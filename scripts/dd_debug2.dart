/// Compares candidate-move sets between the tuned and simple generators
/// over random playouts of the failing deal.
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/cards/card.dart';

const c = PlayingCard.cardsFromString;

void main() {
  final rng = Random(5);
  for (int trial = 0; trial < 500; trial++) {
    final hands = [
      c("AC KS 2C"),
      c("7S QH 5S"),
      c("6C 6S 7H"),
      c("5D 2S 5H"),
    ];
    final fancy = DDSolver.fromHands(hands, Suit.hearts, 3)
      ..debugNoEquivalenceClasses = true
      ..debugNoLastSeatReduction = true;
    final simple = DDSolver.fromHands(hands, Suit.hearts, 3)
      ..debugSimpleMovegen = true;
    for (int step = 0; step < 12; step++) {
      final player = (fancy.leader + fancy.trickCount) % 4;
      final a = fancy.debugCandidateMoves(player).toSet();
      final b = simple.debugCandidateMoves(player).toSet();
      if (a.length != a.toList().length) {}
      if (!(a.containsAll(b) && b.containsAll(a))) {
        print("MISMATCH trial $trial step $step player $player");
        print("  fancy:  ${a.toList()..sort()}");
        print("  simple: ${b.toList()..sort()}");
        return;
      }
      final move = b.toList()[rng.nextInt(b.length)];
      fancy.debugPlay(move >> 4, move & 15);
      simple.debugPlay(move >> 4, move & 15);
    }
  }
  print("no mismatches");
}
