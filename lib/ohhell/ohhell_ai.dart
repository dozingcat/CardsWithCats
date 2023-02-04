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
  final List<PlayingCard> hand;

  BidRequest(
      {required this.rules,
        required this.scoresBeforeRound,
        required this.otherBids,
        required this.trumpCard,
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

  CardToPlayRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.previousTricks,
    required this.currentTrick,
    required this.bids,
    required this.trumpCard,
  });

  static CardToPlayRequest fromRound(final OhHellRound round) => CardToPlayRequest(
    rules: round.rules.copy(),
    scoresBeforeRound: List.from(round.initialScores),
    hand: List.from(round.currentPlayer().hand),
    previousTricks: Trick.copyAll(round.previousTricks),
    currentTrick: round.currentTrick.copy(),
    bids: [...round.players.map((p) => p.bid!)],
    trumpCard: round.trumpCard,
  );

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

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
  cardsToAssign.removeAll(req.hand);
  cardsToAssign.remove(req.trumpCard);
  // Create a fake round with dealer at N-1, so the bidder index is the number of previous bids.
  int dealerIndex = req.rules.numPlayers - 1;
  int bidderIndex = req.otherBids.length;
  final constraints = List.generate(
      req.rules.numPlayers,
          (pnum) => CardDistributionConstraint(
        numCards: req.hand.length,
        voidedSuits: [],
        fixedCards: [],
      ));
  constraints[bidderIndex].numCards = 0;
  constraints[bidderIndex].fixedCards = req.hand;
  if (bidderIndex != dealerIndex && req.rules.trumpMethod == TrumpMethod.dealerLastCard) {
    if (req.hand.length * req.rules.numPlayers < 52) {
      constraints[dealerIndex].numCards -= 1;
      constraints[dealerIndex].fixedCards.add(req.trumpCard);
    }
  }
  final distReq = CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
  final cardDist = possibleCardDistribution(distReq, rng)!;
  final resultPlayers = List.generate(
      req.rules.numPlayers, (i) => OhHellPlayer(cardDist[i]));
  resultPlayers[bidderIndex].hand = req.hand;
  if (resultPlayers[dealerIndex].hand.length != req.hand.length) {
    resultPlayers[bidderIndex].hand.add(req.trumpCard);
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

// Returns the estimated probability of the player at `player_index` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int playerIndex, OhHellRuleSet rules) {
  // TODO
  int totalScores = scores.reduce((a, b) => a + b);
  return (1.0 * scores[playerIndex]) / totalScores;
}

PlayingCard chooseCardRandom(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  return legalPlays[rng.nextInt(legalPlays.length)];
}
