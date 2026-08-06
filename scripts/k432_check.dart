/// Checks the reported blunder: a defender leading the king from K432
/// into dummy's AQ5. Compares the old MC strategy with the new MCDD one
/// and prints per-card equities.
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';

const c = PlayingCard.cardsFromString;

void main() {
  // 3NT by South (seat 2); dummy is North (seat 0), visible, and plays
  // LAST on West's (seat 1) lead. West won trick one with the club ace
  // and now holds K432 of spades under dummy's AQ5.
  final req = CardToPlayRequest(
    hand: c("KS 4S 3S 2S 9H 7H 2H 8D 7D 5D 6C 5C"),
    dummyHand: c("AS QS 5S TH 8H 6H QD JD TD 9D QC JC"),
    previousTricks: [
      Trick(3, c("3C 2C AC 4C"), 1),
    ],
    currentTrick: TrickInProgress(1),
    bidHistory: [
      PlayerBid(2, BidAction.fromString("3NT")),
      PlayerBid(3, BidAction.pass()),
      PlayerBid(0, BidAction.pass()),
      PlayerBid(1, BidAction.pass()),
    ],
    vulnerability: Vulnerability.neither,
  );

  final rng = Random(7);
  final old = chooseCardMonteCarlo(
      req, MonteCarloParams(maxRounds: 30, rolloutsPerRound: 30),
      chooseCardRandom, rng);
  print("old MC:  best ${old.bestCard}");
  _printTop(old.cardEquities);

  final dd = chooseCardMonteCarloDD(req, Random(7),
      maxRounds: 20, ddTricksLimit: 8);
  print("mcdd:    best ${dd.bestCard} (${dd.elapsedMillis}ms)");
  _printTop(dd.cardEquities);
}

void _printTop(Map<PlayingCard, double> equities) {
  final entries = equities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in entries) {
    print("  ${e.key}: ${e.value.toStringAsFixed(1)}");
  }
}
