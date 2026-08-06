/// Reproduces a fuzz-test failure with feature toggles to isolate the bug.
library;

import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/cards/card.dart';

const c = PlayingCard.cardsFromString;

void main() {
  final hands = [
    c("JS 8C JH 2C TD"),
    c("6C JC JD 8S 4C"),
    c("6D 4D 5D 8D 9S"),
    c("9D QC AD 3C 9C"),
  ];
  DDSolver make() => DDSolver.fromHands(hands, Suit.spades, 1);
  print("full: ${make().solve()}");
  print("simpleMovegen: ${(make()..debugSimpleMovegen = true).solve()}");
  print("noTT: ${(make()..debugDisableTT = true).solve()}");
  print("noReduction: ${(make()..debugNoLastSeatReduction = true).solve()}");
  print("noClasses: ${(make()..debugNoEquivalenceClasses = true).solve()}");
  print("noClassesNoReduction: ${(make()..debugNoEquivalenceClasses = true..debugNoLastSeatReduction = true).solve()}");
  print("clearTT: ${(make()..debugClearTTBetweenPasses = true).solve()}");
  print("reference: ${DDReferenceSolver.fromHands(hands, Suit.spades, 1).solve()}");
}

void extra() {}
