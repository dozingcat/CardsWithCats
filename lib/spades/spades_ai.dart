import 'dart:math';

import 'package:hearts/cards/card.dart';
import 'package:hearts/cards/rollout.dart';
import 'package:hearts/cards/trick.dart';
import 'package:hearts/spades/spades.dart';
import 'package:hearts/spades/spades.dart' as spades;

class BidRequest {
  final SpadesRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;

  BidRequest({required this.rules, required this.scoresBeforeRound, required this.hand});
}

class CardToPlayRequest {
  final SpadesRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final List<Trick> previousTricks;
  final TrickInProgress currentTrick;
  final List<int> bids;

  CardToPlayRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.previousTricks,
    required this.currentTrick,
    required this.bids,
  });

  static CardToPlayRequest fromRound(final SpadesRound round) =>
      CardToPlayRequest(
        rules: round.rules.copy(),
        scoresBeforeRound: List.from(round.initialScores),
        hand: List.from(round.currentPlayer().hand),
        previousTricks: Trick.copyAll(round.previousTricks),
        currentTrick: round.currentTrick.copy(),
        bids: [...round.players.map((p) => p.bid!)],
      );

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  List<PlayingCard> legalPlays() {
    return spades.legalPlays(hand, currentTrick, previousTricks, rules);
  }
}

// match equity, bidding, playing.
int chooseBid(BidRequest req) {
  return 3;
}

// Returns the estimated probability of the player at `player_index` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int teamIndex, SpadesRuleSet rules) {
  int maxScore = scores.reduce(max);
  // We're arbitrarily defining the "target" score as the match limit plus 50.
  int target = max(rules.pointLimit, (maxScore ~/ 10) * 10) + 50;
  // equity is 1 - (my distance to target) / (sum of all distances to target)
  // Distance is penalized by number of bags, quadratically. (Going from 1 to 2
  // bags is less bad than going from 7 to 8. Max penalty is 0.5*9*9 = 40.5).
  final distances = scores.map((s) {
    final bags = s % 10;
    return target - (s - bags - 0.5 * bags * bags);
  }).toList();
  final distSum = distances.reduce((a, b) => a + b);
  return 1 - (distances[teamIndex] / distSum);
}

PlayingCard chooseCardRandom(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  return legalPlays[rng.nextInt(legalPlays.length)];
}

PlayingCard chooseCardMaximizingTricks(final CardToPlayRequest req, Random rng) {
  // TODO
  return chooseCardRandom(req, rng);
}

typedef ChooseCardFn = PlayingCard Function(CardToPlayRequest req, Random rng);

CardDistributionRequest makeCardDistributionRequest(final CardToPlayRequest req) {
  final numPlayers = req.rules.numPlayers;
  final seenCards = Set.from(req.hand);
  final voidedSuits = List.generate(numPlayers, (_n) => Set<Suit>());

  var spadesBroken = false;

  void processTrick(List<PlayingCard> cards, int leader) {
    final trickSuit = cards[0].suit;
    if (!spadesBroken && trickSuit == Suit.spades) {
      spadesBroken = true;
      if (req.rules.spadeLeading == SpadeLeading.after_broken) {
        // Led spades when they weren't broken, so must have had no other choice.
        voidedSuits[leader].addAll([Suit.hearts, Suit.diamonds, Suit.clubs]);
      }
    }
    seenCards.add(cards[0]);
    for (int i = 1; i < cards.length; i++) {
      final c = cards[i];
      seenCards.add(c);
      if (c.suit != trickSuit) {
        voidedSuits[(leader + i) % numPlayers].add(trickSuit);
      }
      if (c.suit == Suit.spades) {
        spadesBroken = true;
      }
    }
  }
  for (final t in req.previousTricks) {
    processTrick(t.cards, t.leader);
  }
  if (req.currentTrick.cards.isNotEmpty) {
    processTrick(req.currentTrick.cards, req.currentTrick.leader);
  }

  final baseNumCards = req.rules.numberOfCardsPerPlayer -
      req.previousTricks.length;
  final cardCounts = List.generate(numPlayers, (_n) => baseNumCards);
  for (int i = 0; i < req.currentTrick.cards.length; i++) {
    final pi = (req.currentTrick.leader + i) % numPlayers;
    cardCounts[pi] -= 1;
  }
  cardCounts[req.currentPlayerIndex()] = 0;

  final constraints = List.generate(numPlayers, (pnum) => CardDistributionConstraint(
    numCards: cardCounts[pnum],
    voidedSuits: voidedSuits[pnum].toList(),
    fixedCards: [],
  ));
  final Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  cardsToAssign.removeAll(seenCards);
  cardsToAssign.removeAll(req.rules.removedCards);
  return CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
}

SpadesRound? possibleRound(CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng) {
  final dist = possibleCardDistribution(distReq, rng);
  if (dist == null) {
    return null;
  }
  final currentPlayer = cardReq.currentPlayerIndex();
  final resultPlayers = List.generate(cardReq.rules.numPlayers,
          (i) => SpadesPlayer(i == currentPlayer ? cardReq.hand : dist[i])
            ..bid = cardReq.bids[i]);
  return SpadesRound()
    ..rules = cardReq.rules.copy()
    ..players = resultPlayers
    ..initialScores = List.of(cardReq.scoresBeforeRound)
    ..currentTrick = cardReq.currentTrick.copy()
    ..previousTricks = Trick.copyAll(cardReq.previousTricks)
    ..status = SpadesRoundStatus.playing
    ..dealer = 0;
}

PlayingCard chooseCardMonteCarlo(
    CardToPlayRequest cardReq,
    MonteCarloParams mcParams,
    ChooseCardFn rolloutChooseFn,
    Random rng) {
  final legalPlays = cardReq.legalPlays();
  assert(legalPlays.isNotEmpty);
  if (legalPlays.length == 1) {
    return legalPlays[0];
  }
  final pnum = cardReq.currentPlayerIndex();
  final playEquities = List.generate(legalPlays.length, (_) => 0.0);
  final distReq = makeCardDistributionRequest(cardReq);
  for (int i = 0; i < mcParams.numHands; i++) {
    final hypoRound = possibleRound(cardReq, distReq, rng);
    if (hypoRound == null) {
      print("MC failed to generate round, falling back to default");
      return chooseCardMaximizingTricks(cardReq, rng);
    }
    for (int ci = 0; ci < legalPlays.length; ci++) {
      for (int r = 0; r < mcParams.rolloutsPerHand; r++) {
        final rolloutRound = hypoRound.copy();
        rolloutRound.playCard(legalPlays[ci]);
        doRollout(rolloutRound, rolloutChooseFn, rng);
        final pointsForRound = rolloutRound.pointsTaken();
        final scoresAfterRound = combinePoints(
            cardReq.scoresBeforeRound, pointsForRound, cardReq.rules);
        playEquities[ci] += matchEquityForScores(
            scoresAfterRound, pnum % cardReq.rules.numTeams, cardReq.rules);
      }
    }
  }
  int bestIndex = 0;
  // print("First card: " + legalPlays[0].toString() + " " + playEquities[0].toString());
  for (int i = 1; i < legalPlays.length; i++) {
    if (playEquities[i] > playEquities[bestIndex]) {
      bestIndex = i;
      // print("Better: " + legalPlays[i].toString() + " " + playEquities[i].toString());
    }
    else {
      // print("Worse: " + legalPlays[i].toString() + " " + playEquities[i].toString());
    }
  }
  return legalPlays[bestIndex];
}

void doRollout(SpadesRound round, ChooseCardFn chooseFn, Random rng) {
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
      bids: [...round.players.map((p) => p.bid!)],
    );
    final cardToPlay = chooseFn(req, rng);
    round.playCard(cardToPlay);
  }
}
