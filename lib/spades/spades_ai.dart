import 'dart:math';

import 'package:hearts/cards/card.dart';
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

  CardToPlayRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.previousTricks,
    required this.currentTrick,
  });

  static CardToPlayRequest fromRound(final SpadesRound round) =>
      CardToPlayRequest(
        rules: round.rules.copy(),
        scoresBeforeRound: List.from(round.initialScores),
        hand: List.from(round.currentPlayer().hand),
        previousTricks: Trick.copyAll(round.previousTricks),
        currentTrick: round.currentTrick.copy(),
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