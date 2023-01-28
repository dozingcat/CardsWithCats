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
  final List<PlayingCard> hand;

  BidRequest(
      {required this.rules,
        required this.scoresBeforeRound,
        required this.otherBids,
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
int chooseBid(BidRequest req) {
  // TODO
  return (req.hand.length / 4.0).round();
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
