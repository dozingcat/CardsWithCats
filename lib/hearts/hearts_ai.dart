import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/hearts/hearts.dart';
import 'package:cards_with_cats/hearts/hearts.dart' as hearts;

const debugOutput = false;

void printd(String msg) {
  if (debugOutput) print(msg);
}

class CardsToPassRequest {
  final HeartsRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final int direction;
  final int numCards;

  CardsToPassRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.direction,
    required this.numCards,
  });
}

class CardToPlayRequest {
  final HeartsRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final List<Trick> previousTricks;
  final TrickInProgress currentTrick;
  final int passDirection;
  final List<PlayingCard> passedCards;
  final List<PlayingCard> receivedCards;

  CardToPlayRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.previousTricks,
    required this.currentTrick,
    required this.passDirection,
    required this.passedCards,
    required this.receivedCards,
  });

  static CardToPlayRequest fromRound(final HeartsRound round) => CardToPlayRequest(
        rules: round.rules.copy(),
        scoresBeforeRound: List.from(round.initialScores),
        hand: List.from(round.currentPlayer().hand),
        previousTricks: Trick.copyAll(round.previousTricks),
        currentTrick: round.currentTrick.copy(),
        passDirection: round.passDirection,
        passedCards: List.from(round.currentPlayer().passedCards),
        receivedCards: List.from(round.currentPlayer().receivedCards),
      );

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  List<PlayingCard> legalPlays() {
    return hearts.legalPlays(hand, currentTrick, previousTricks, rules);
  }
}

// Returns the estimated probability of the player at `player_index` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int maxScore, int playerIndex) {
  if (scores.length < 2) {
    throw Exception("Length of `scores` must be at least 2");
  }
  if (scores.any((s) => s >= maxScore)) {
    final minScore = scores.reduce(min);
    if (scores[playerIndex] > minScore) {
      return 0;
    }
    // An N-way tie for first has an equity of 1/N.
    int numWinners = scores.where((s) => s == minScore).length;
    return 1.0 / numWinners;
  }
  // Approximate the probability as (player distance to max) / (sum of all distances to max).
  int totalDist = 0;
  for (int s in scores) {
    totalDist += (maxScore - s);
  }
  return (maxScore - scores[playerIndex]) / totalDist;
}

int dangerForCard(PlayingCard card, List<Rank> suitRanks, CardsToPassRequest req) {
  int cardVal = card.rank.numericValue;
  int lowestValInSuit = suitRanks.last.numericValue;
  switch (card.suit) {
    case Suit.spades:
      if (card.rank.index < Rank.queen.index) {
        return 0;
      }
      // Assuming 4 or more spades are safe, not necessarily true for something like AKxx.
      if (suitRanks.length >= 4) {
        return 0;
      }
      // Always pass QS.
      if (card.rank == Rank.queen) {
        return 100;
      }
      // If we're passing the queen right, it's ok to keep AS and KS
      // because we'll be able to safely play them (as long as we
      // have a lower spade).
      bool passingRight = req.direction == req.rules.numPlayers - 1;
      bool hasQueen = suitRanks.contains(Rank.queen);
      bool hasLowSpade = suitRanks.last.index < Rank.queen.index;
      return (passingRight && hasQueen && hasLowSpade) ? cardVal - 5 : 100;

    case Suit.hearts:
    case Suit.diamonds:
      return cardVal + lowestValInSuit;

    case Suit.clubs:
      // 2C is "higher" than AC for purposes of passing.
      // TODO: We probably want to pass AC less often because winning
      // the first trick can be helpful and doesn't risk points.
      int adjustedVal = (cardVal == 2) ? 14 : cardVal - 1;
      if (lowestValInSuit == 2) {
        // Probably pass 2C.
        if (cardVal == 2) {
          return 50;
        }
        int secondLowestClubVal = suitRanks[suitRanks.length - 2].numericValue;
        return adjustedVal + secondLowestClubVal;
      } else {
        return adjustedVal + lowestValInSuit - 1;
      }
  }
}

List<PlayingCard> chooseCardsToPass(CardsToPassRequest req) {
  Map<Suit, List<Rank>> ranksBySuit = {};
  for (Suit suit in Suit.values) {
    ranksBySuit[suit] = sortedRanksInSuit(req.hand, suit);
  }
  Map<PlayingCard, int> cardDanger = {};
  for (PlayingCard c in req.hand) {
    cardDanger[c] = dangerForCard(c, ranksBySuit[c.suit]!, req);
  }
  final sortedHand = List.of(req.hand);
  sortedHand.sort((c1, c2) => cardDanger[c2]! - cardDanger[c1]!);
  return sortedHand.sublist(0, req.numCards);
}

PlayingCard chooseCardRandom(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  return legalPlays[rng.nextInt(legalPlays.length)];
}

PlayingCard chooseCardAvoidingPoints(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  if (legalPlays.length == 1) {
    return legalPlays[0];
  }
  // Sort by descending rank independent of suit, which is useful in several cases below.
  legalPlays.sort((c1, c2) => c2.rank.index - c1.rank.index);
  final legalSuits = legalPlays.map((c) => c.suit).toSet();
  // If leading, play the lowest card in a random suit.
  // If last in a trick and following suit, play high if there are no points.
  // Otherwise play low if following suit, discard highest otherwise (favoring QS).
  // TODO: Favor leading spades if QS hasn't been played and it's safe?
  final trick = req.currentTrick;
  if (trick.cards.isEmpty) {
    // Pick a suit and lead the lowest card, but not QS.
    final suit = legalSuits.toList()[rng.nextInt(legalSuits.length)];
    return legalPlays.reversed.firstWhere((c) => c.suit == suit && c != queenOfSpades,
        orElse: () => legalPlays.reversed.firstWhere((c) => c != queenOfSpades));
  }
  final trickSuit = trick.cards[0].suit;
  final isFollowingSuit = legalSuits.contains(trickSuit);
  final hasQS = legalPlays.contains(queenOfSpades);
  final hasJD = req.rules.jdMinus10 && legalPlays.contains(jackOfDiamonds);
  if (isFollowingSuit) {
    assert(legalSuits.length == 1);
    // Play high on first trick if no points allowed.
    if (req.previousTricks.isEmpty && !req.rules.pointsOnFirstTrick) {
      return legalPlays[0];
    }
    final highCard = highestCardInTrick(trick.cards);
    // Dump QS if possible.
    if (hasQS && highCard.rank.index > Rank.queen.index) {
      return queenOfSpades;
    }
    final isLastPlay = trick.cards.length == req.rules.numPlayers - 1;
    if (isLastPlay) {
      final trickPoints = pointsForCards(trick.cards, req.rules);
      // Win with JD if possible (and no QS).
      if (hasJD && trickPoints < 10 && highCard.rank.index < Rank.jack.index) {
        return jackOfDiamonds;
      }
      // Win without taking points if possible.
      if (trickPoints <= 0) {
        return _firstInSuitNotQS(legalPlays, trickSuit);
      }
      // Avoid taking the trick if we can; if we can't play highest.
      // If playing with JD rule, don't play it under a higher diamond.
      // TODO: Win with AS or KS if it helps to avoid the queen.
      return legalPlays.where((c) => !(hasJD && c == jackOfDiamonds)).firstWhere(
          (c) => c.rank.index < highCard.rank.index,
          orElse: () => _firstInSuitNotQS(legalPlays, trickSuit));
    } else {
      // Play just under the winner if possible (but not JD if it's -10 points).
      // If we can't, play the lowest (other than QS).
      return legalPlays.where((c) => !(hasJD && c == jackOfDiamonds)).firstWhere(
          (c) => c.rank.index < highCard.rank.index,
          orElse: () => _firstInSuitNotQS(legalPlays.reversed, trickSuit));
    }
  } else {
    // Ditch QS if possible, otherwise highest heart, otherwise highest other card.
    if (hasQS) {
      return queenOfSpades;
    }
    if (legalSuits.contains(Suit.hearts)) {
      return legalPlays.firstWhere((c) => c.suit == Suit.hearts);
    }
    return legalPlays.firstWhere((c) => !(hasJD && c == jackOfDiamonds));
  }
}

PlayingCard _firstInSuitNotQS(final Iterable<PlayingCard> cards, Suit suit) {
  return cards.firstWhere((c) => c.suit == suit && c != queenOfSpades);
}

typedef ChooseCardFn = PlayingCard Function(CardToPlayRequest req, Random rng);

ChooseCardFn makeMixedRandomOrAvoidPoints(double randomProb) {
  return (CardToPlayRequest req, Random rng) {
    final chooseFn = rng.nextDouble() < randomProb ? chooseCardRandom : chooseCardAvoidingPoints;
    return chooseFn(req, rng);
  };
}

CardDistributionRequest makeCardDistributionRequest(final CardToPlayRequest req) {
  final numPlayers = req.rules.numPlayers;
  final seenCards = Set.from(req.hand);
  final voidedSuits = List.generate(numPlayers, (_n) => <Suit>{});

  var heartsBroken = false;

  void processTrick(List<PlayingCard> cards, int leader) {
    final trickSuit = cards[0].suit;
    if (!heartsBroken && trickSuit == Suit.hearts) {
      // Led hearts when they weren't broken, so must have had no other choice.
      heartsBroken = true;
      voidedSuits[leader].addAll([Suit.spades, Suit.diamonds, Suit.clubs]);
    }
    seenCards.add(cards[0]);
    for (int i = 1; i < cards.length; i++) {
      final c = cards[i];
      seenCards.add(c);
      if (c.suit != trickSuit) {
        voidedSuits[(leader + i) % numPlayers].add(trickSuit);
      }
      if (c.suit == Suit.hearts || (req.rules.queenBreaksHearts && c == queenOfSpades)) {
        heartsBroken = true;
      }
    }
  }

  for (final t in req.previousTricks) {
    processTrick(t.cards, t.leader);
  }
  if (req.currentTrick.cards.isNotEmpty) {
    processTrick(req.currentTrick.cards, req.currentTrick.leader);
  }

  final baseNumCards = req.rules.numberOfCardsPerPlayer - req.previousTricks.length;
  final cardCounts = List.generate(numPlayers, (_n) => baseNumCards);
  for (int i = 0; i < req.currentTrick.cards.length; i++) {
    final pi = (req.currentTrick.leader + i) % numPlayers;
    cardCounts[pi] -= 1;
  }
  cardCounts[req.currentPlayerIndex()] = 0;

  final constraints = List.generate(
      numPlayers,
      (pnum) => CardDistributionConstraint(
            numCards: cardCounts[pnum],
            voidedSuits: voidedSuits[pnum].toList(),
            fixedCards: [],
          ));
  if (req.rules.numPassedCards > 0) {
    final passedTo = (req.currentPlayerIndex() + req.passDirection) % numPlayers;
    constraints[passedTo].fixedCards.addAll(req.passedCards);
  }

  final Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  cardsToAssign.removeAll(seenCards);
  cardsToAssign.removeAll(req.rules.removedCards);
  return CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
}

HeartsRound? possibleRound(CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng) {
  final dist = possibleCardDistribution(distReq, rng);
  if (dist == null) {
    return null;
  }
  final currentPlayer = cardReq.currentPlayerIndex();
  final resultPlayers = List.generate(
      cardReq.rules.numPlayers, (i) => HeartsPlayer(i == currentPlayer ? cardReq.hand : dist[i]));
  return HeartsRound()
    ..rules = cardReq.rules.copy()
    ..players = resultPlayers
    ..initialScores = List.of(cardReq.scoresBeforeRound)
    ..currentTrick = cardReq.currentTrick.copy()
    ..previousTricks = Trick.copyAll(cardReq.previousTricks)
    ..status = HeartsRoundStatus.playing
    // Ignore passed cards. TODO: Incorporate the fact that we know what cards were passed
    // to the current player.
    ..passDirection = 0;
}

List<PlayingCard> cardsToConsiderPlaying(CardToPlayRequest req, Random rng) {
  // For testing with and without this feature.
  // It seems to slightly improve the AI with rounds=20, rollouts=50;
  // with players 1 and 3 using this path and 0 and 2 not, "victory points"
  // (12 points for win, 12/n for n-way tie) after 1000 matches:
  // [2712, 3174, 2910, 3204]
  // if (req.currentPlayerIndex() % 2 == 0) return req.legalPlays();

  final legalPlays = req.legalPlays();
  // Always handle the queen of spades individually; if you have both the king
  // and queen they're equivalent in terms of winning tricks, but obviously not
  // in terms of scoring. Jack of diamonds if enabled as well.
  List<PlayingCard> result = [];
  final cardsToGroup = List.of(legalPlays);
  if (cardsToGroup.contains(queenOfSpades)) {
    result.add(queenOfSpades);
    cardsToGroup.remove(queenOfSpades);
  }
  if (req.rules.jdMinus10 && cardsToGroup.contains(jackOfDiamonds)) {
    result.add(jackOfDiamonds);
    cardsToGroup.remove(jackOfDiamonds);
  }
  // Choose one card at random from each group of identical cards.
  final groups = groupsOfEffectivelyIdenticalCards(cardsToGroup, req.previousTricks);
  result.addAll(groups.map((g) => g[rng.nextInt(g.length)]));
  if (legalPlays.length != result.length) {
    printd("Reduced ${legalPlays.length} choices to ${result.length}");
  }
  return result;
}

MonteCarloResult chooseCardMonteCarlo(
    CardToPlayRequest cardReq, MonteCarloParams mcParams, ChooseCardFn rolloutChooseFn, Random rng,
    {int Function()? timeFn}) {
  timeFn ??= () => DateTime.now().millisecondsSinceEpoch;
  final startTime = timeFn();
  final legalPlays = cardsToConsiderPlaying(cardReq, rng);
  assert(legalPlays.isNotEmpty);
  if (legalPlays.length == 1) {
    return MonteCarloResult.rolloutNotNeeded(bestCard: legalPlays[0]);
  }
  final pnum = cardReq.currentPlayerIndex();
  final playEquities = List.filled(legalPlays.length, 0.0);
  final distReq = makeCardDistributionRequest(cardReq);
  int numRounds = 0;
  int numRollouts = 0;
  int numRolloutCardsPlayed = 0;
  final cardsPerRollout =
      52 - (4 * cardReq.previousTricks.length + cardReq.currentTrick.cards.length);
  for (int i = 0; i < mcParams.maxRounds; i++) {
    final hypoRound = possibleRound(cardReq, distReq, rng);
    if (hypoRound == null) {
      print("MC failed to generate round, falling back to avoiding points");
      final bestCard = chooseCardAvoidingPoints(cardReq, rng);
      final normalizedEquities =
          playEquities.map((e) => e / numRollouts * legalPlays.length).toList();
      return MonteCarloResult.rolloutFailed(
        bestCard: bestCard,
        cardEquities: Map.fromIterables(legalPlays, normalizedEquities),
        numRounds: numRounds,
        numRollouts: numRollouts,
        numRolloutCardsPlayed: numRolloutCardsPlayed,
        elapsedMillis: timeFn() - startTime,
      );
    }
    for (int ci = 0; ci < legalPlays.length; ci++) {
      for (int r = 0; r < mcParams.rolloutsPerRound; r++) {
        final rolloutRound = hypoRound.copy();
        rolloutRound.playCard(legalPlays[ci]);
        doRollout(rolloutRound, rolloutChooseFn, rng);
        final pointsForRound = rolloutRound.pointsTaken();
        final scoresAfterRound = List.generate(
            pointsForRound.length, (p) => pointsForRound[p] + cardReq.scoresBeforeRound[p]);
        playEquities[ci] += matchEquityForScores(scoresAfterRound, cardReq.rules.pointLimit, pnum);
        numRollouts += 1;
        numRolloutCardsPlayed += cardsPerRollout;
      }
    }
    numRounds += 1;
    if (mcParams.maxTimeMillis != null && timeFn() - startTime >= mcParams.maxTimeMillis!) {
      break;
    }
  }
  final normalizedEquities = playEquities.map((e) => e / numRollouts * legalPlays.length).toList();
  return MonteCarloResult.rolloutSuccess(
    cardEquities: Map.fromIterables(legalPlays, normalizedEquities),
    numRounds: numRounds,
    numRollouts: numRollouts,
    numRolloutCardsPlayed: numRolloutCardsPlayed,
    elapsedMillis: timeFn() - startTime,
  );
}

void doRollout(HeartsRound round, ChooseCardFn chooseFn, Random rng) {
  while (!round.isOver()) {
    final legalPlays = round.legalPlaysForCurrentPlayer();
    if (legalPlays.isEmpty) {
      final msg = "No legal plays for ${round.currentPlayerIndex()}";
      throw Exception(msg);
    }
    // CardToPlayRequest.fromRound makes deep copies of HeartsRound fields,
    // which is safe but expensive. Here we can just copy the references,
    // because we know the round won't be modified during the lifetime of `req`.
    // This is around a 2x speedup.
    final req = CardToPlayRequest(
      rules: round.rules,
      scoresBeforeRound: round.initialScores,
      hand: round.currentPlayer().hand,
      previousTricks: round.previousTricks,
      currentTrick: round.currentTrick,
      passDirection: round.passDirection,
      passedCards: round.currentPlayer().passedCards,
      receivedCards: round.currentPlayer().receivedCards,
    );
    final cardToPlay = chooseFn(req, rng);
    round.playCard(cardToPlay);
  }
}
