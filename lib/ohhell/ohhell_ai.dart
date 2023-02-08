import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/ohhell/ohhell.dart';
import 'package:cards_with_cats/ohhell/ohhell.dart' as ohhell;

class BidRequest {
  final OhHellRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<int> otherBids;
  final PlayingCard trumpCard;
  final bool dealerHasTrumpCard;
  final List<PlayingCard> hand;

  BidRequest(
      {required this.rules,
        required this.scoresBeforeRound,
        required this.otherBids,
        required this.trumpCard,
        required this.dealerHasTrumpCard,
        required this.hand});
}

class CardToPlayRequest {
  final OhHellRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final List<Trick> previousTricks;
  final TrickInProgress currentTrick;
  final List<int> bids;
  final PlayingCard trumpCard;
  final bool dealerHasTrumpCard;

  CardToPlayRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.previousTricks,
    required this.currentTrick,
    required this.bids,
    required this.trumpCard,
    required this.dealerHasTrumpCard,
  });

  static CardToPlayRequest fromRound(final OhHellRound round) => CardToPlayRequest(
    rules: round.rules.copy(),
    scoresBeforeRound: List.from(round.initialScores),
    hand: List.from(round.currentPlayer().hand),
    previousTricks: Trick.copyAll(round.previousTricks),
    currentTrick: round.currentTrick.copy(),
    bids: [...round.players.map((p) => p.bid!)],
    trumpCard: round.trumpCard,
    dealerHasTrumpCard: round.dealerHasTrumpCard(),
  );
  
  static CardToPlayRequest fromRoundWithSharedReferences(final OhHellRound round) => CardToPlayRequest(
    rules: round.rules,
    scoresBeforeRound: round.initialScores,
    hand: round.currentPlayer().hand,
    previousTricks: round.previousTricks,
    currentTrick: round.currentTrick,
    bids: [...round.players.map((p) => p.bid!)],
    trumpCard: round.trumpCard,
    dealerHasTrumpCard: round.dealerHasTrumpCard(),
  );

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  int dealerIndex() {
    // The player immediately following the dealer leads the first trick.
    int firstLeader = previousTricks.isNotEmpty ? previousTricks.first.leader : currentTrick.leader;
    return (firstLeader == 0) ? rules.numPlayers - 1 : firstLeader - 1;
  }

  int numInitialCards() => previousTricks.length + hand.length;

  List<PlayingCard> legalPlays() {
    return ohhell.legalPlays(hand, currentTrick, previousTricks, rules);
  }

  bool hasCardBeenPlayed(final PlayingCard card) {
    if (currentTrick.cards.contains(card)) {
      return true;
    }
    for (final t in previousTricks) {
      if (t.cards.contains(card)) {
        return true;
      }
    }
    return false;
  }

  bool isCardKnown(final PlayingCard card) {
    return hand.contains(card) || hasCardBeenPlayed(card) || card == trumpCard;
  }
}

// match equity, bidding, playing.
int chooseBidFixed(BidRequest req) {
  // TODO
  return (req.hand.length / 4.0).round();
}

OhHellRound _possibleRoundForBiddingRollout(final BidRequest req, Random rng) {
  // Run rollouts with everyone playing random cards, pick the average number of tricks won.
  Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  // Create a fake round with dealer at N-1, so the bidder index is the number of previous bids.
  int dealerIndex = req.rules.numPlayers - 1;
  int bidderIndex = req.otherBids.length;
  final constraints = List.generate(
      req.rules.numPlayers,
          (pnum) => CardDistributionConstraint(
        numCards: req.hand.length,
        voidedSuits: [],
        fixedCards: pnum == bidderIndex ? req.hand : [],
      ));
  if (req.dealerHasTrumpCard && bidderIndex != dealerIndex) {
    constraints[dealerIndex].fixedCards.add(req.trumpCard);
  }

  final distReq = CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
  final cardDist = possibleCardDistribution(distReq, rng)!;
  final resultPlayers = List.generate(
      req.rules.numPlayers, (i) => OhHellPlayer(cardDist[i]));
  if (resultPlayers[bidderIndex].hand.where((c) => !req.hand.contains(c)).isNotEmpty) {
    print("req.hand: ${req.hand}");
    print("result hand: ${cardDist[bidderIndex]}");
    throw Exception("Bad hand");
  }
  // Player 0 leads the first trick because the dealer is N-1.
  final firstTrick = TrickInProgress(0, []);
  return OhHellRound()
      ..rules = req.rules
      ..status = OhHellRoundStatus.playing
      ..players = resultPlayers
      ..numCardsPerPlayer = req.hand.length
      ..initialScores = List.generate(req.rules.numPlayers, (i) => 0)
      ..dealer = dealerIndex
      ..trumpCard = req.trumpCard
      ..currentTrick = firstTrick
      ..previousTricks = []
      ;
}

int chooseBid(BidRequest req, Random rng) {
  const numPossibleDeals = 20;
  const numRolloutsPerDeal = 20;
  const numRounds = numPossibleDeals * numRolloutsPerDeal;
  final bidderIndex = req.otherBids.length;
  int totalTricksWon = 0;
  for (int i = 0; i < numPossibleDeals; i++) {
    final hypoRound = _possibleRoundForBiddingRollout(req, rng);
    for (int j = 0; j < numRolloutsPerDeal; j++) {
      final r = hypoRound.copy();
      while (!r.isOver()) {
        final legalPlays = r.legalPlaysForCurrentPlayer();
        final selectedCard = legalPlays[rng.nextInt(legalPlays.length)];
        r.playCard(selectedCard);
      }
      totalTricksWon += r.previousTricks.where((t) => t.winner == bidderIndex).length;
    }
  }
  final avgTricksWon = 1.0 * totalTricksWon / numRounds;
  return avgTricksWon.round();
}

// Returns the estimated probability of the player at `playerIndex` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int playerIndex, OhHellRuleSet rules) {
  // TODO
  int totalScores = scores.reduce((a, b) => a + b);
  return (1.0 * scores[playerIndex]) / totalScores;
}

List<PlayingCard> cardsToConsiderPlaying(CardToPlayRequest req, Random rng) {
  // For testing with and without this feature.
  // if (req.currentPlayerIndex() % 2 == 0) return req.legalPlays();
  final legalPlays = req.legalPlays();
  List<PlayingCard> result = [];
  // Choose one card at random from each group of identical cards.
  final groups = groupsOfEffectivelyIdenticalCards(legalPlays, req.previousTricks);
  result.addAll(groups.map((g) => g[rng.nextInt(g.length)]));
  return result;
}

typedef ChooseCardFn = PlayingCard Function(CardToPlayRequest req, Random rng);

PlayingCard chooseCardRandom(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  return legalPlays[rng.nextInt(legalPlays.length)];
}

CardDistributionRequest makeCardDistributionRequest(final CardToPlayRequest req) {
  final numPlayers = req.rules.numPlayers;
  final seenCards = <PlayingCard>{};
  final voidedSuits = List.generate(numPlayers, (i) => <Suit>{});

  // Record when a player is out of a suit.
  void processTrick(List<PlayingCard> cards, int leader) {
    final trickSuit = cards[0].suit;
    seenCards.add(cards[0]);
    for (int i = 1; i < cards.length; i++) {
      final c = cards[i];
      seenCards.add(c);
      if (c.suit != trickSuit) {
        voidedSuits[(leader + i) % numPlayers].add(trickSuit);
      }
    }
  }

  for (final t in req.previousTricks) {
    processTrick(t.cards, t.leader);
  }
  if (req.currentTrick.cards.isNotEmpty) {
    processTrick(req.currentTrick.cards, req.currentTrick.leader);
  }

  final baseNumCards = req.hand.length;
  final cardCounts = List.generate(numPlayers, (_n) => baseNumCards);
  for (int i = 0; i < req.currentTrick.cards.length; i++) {
    final pi = (req.currentTrick.leader + i) % numPlayers;
    cardCounts[pi] -= 1;
  }

  int currentPlayerIndex = req.currentPlayerIndex();
  final constraints = List.generate(
      numPlayers,
          (pnum) => CardDistributionConstraint(
        numCards: cardCounts[pnum],
        voidedSuits: voidedSuits[pnum].toList(),
            fixedCards: pnum == currentPlayerIndex ? req.hand : [],
      ));
  if (req.dealerHasTrumpCard && !seenCards.contains(req.trumpCard) && req.dealerIndex() != req.currentPlayerIndex()) {
    constraints[req.dealerIndex()].fixedCards.add(req.trumpCard);
  }

  final Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  cardsToAssign.removeAll(seenCards);
  return CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
}

OhHellRound? possibleRound(CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng) {
  final dist = possibleCardDistribution(distReq, rng);
  if (dist == null) {
    return null;
  }
  final resultPlayers = List.generate(dist.length, (pnum) => OhHellPlayer(dist[pnum], bid: cardReq.bids[pnum]!));
  return OhHellRound()
    ..rules = cardReq.rules.copy()
    ..status = OhHellRoundStatus.playing
    ..players = resultPlayers
    ..numCardsPerPlayer = cardReq.numInitialCards()
    ..initialScores = List.of(cardReq.scoresBeforeRound)
    ..dealer = cardReq.dealerIndex()
    ..trumpCard = cardReq.trumpCard
    ..currentTrick = cardReq.currentTrick.copy()
    ..previousTricks = Trick.copyAll(cardReq.previousTricks)
    ;
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
      print("MC failed to generate round, falling back to random");
      final bestCard = chooseCardRandom(cardReq, rng);
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
            pointsForRound.length, (p) => pointsForRound[p].totalRoundPoints + cardReq.scoresBeforeRound[p]);
        playEquities[ci] += matchEquityForScores(scoresAfterRound, pnum, cardReq.rules);
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

void doRollout(OhHellRound round, ChooseCardFn chooseFn, Random rng) {
  while (!round.isOver()) {
    final legalPlays = round.legalPlaysForCurrentPlayer();
    if (legalPlays.isEmpty) {
      final msg = "No legal plays for ${round.currentPlayerIndex()}";
      throw Exception(msg);
    }
    final req = CardToPlayRequest.fromRoundWithSharedReferences(round);
    final cardToPlay = chooseFn(req, rng);
    round.playCard(cardToPlay);
  }
}
