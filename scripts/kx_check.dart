/// Reproduces a scanned blunder: East (seat 1), defending 3D by North,
/// leads the king from K2 of spades into dummy's visible AQ9876. Prints
/// MCDD candidate equities at increasing sample counts.
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

const c = PlayingCard.cardsFromString;

void main() {
  final req = CardToPlayRequest(
    hand: c("KS 2S 7H 6H 5H 3H 9C 7C"),
    dummyHand: c("AS QS 9S 8S 7S 6S 7D JC"),
    previousTricks: [
      Trick(1, c("TS 5S 3S JS"), 0),
      Trick(0, c("KC 4C 8C AC"), 3),
      Trick(3, c("3D 2D KD 5D"), 1),
      Trick(1, c("QH 2H 4H AH"), 0),
      Trick(0, c("8H KH JH 2C"), 1),
    ],
    currentTrick: TrickInProgress(1),
    bidHistory: [
      PlayerBid(1, BidAction.fromString("1H")),
      PlayerBid(2, BidAction.fromString("2S")),
      PlayerBid(3, BidAction.pass()),
      PlayerBid(0, BidAction.fromString("3D")),
      PlayerBid(1, BidAction.pass()),
      PlayerBid(2, BidAction.pass()),
      PlayerBid(3, BidAction.pass()),
    ],
    vulnerability: Vulnerability.nsOnly,
  );
  for (final rounds in [10, 50, 200]) {
    final result = chooseCardMonteCarloDD(req, Random(48),
        maxRounds: rounds, ddTricksLimit: 7);
    final entries = result.cardEquities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print("rounds=$rounds best=${result.bestCard}: ${entries.map((e) =>
        '${e.key}=${e.value.toStringAsFixed(1)}').join(' ')}");
  }
}
