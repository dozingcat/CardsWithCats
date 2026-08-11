/// Probes DdsBackend behavior across isolates (see dds_ffi threading note).
library;

import 'dart:isolate';

import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/cards/card.dart';

const c = PlayingCard.cardsFromString;

int? solveOnce() {
  final hands = [c("AS KS QS JS"), c("8H 7H 6H 5H"), c("8D 7D 6D 5D"), c("8C 7C 6C 5C")];
  return DdsBackend.instance?.solve(hands, null, 0, []);
}

void main() async {
  print("main isolate: ${solveOnce()}");
  print("worker 1: ${await Isolate.run(solveOnce)}");
  print("worker 2: ${await Isolate.run(solveOnce)}");
  print("main again: ${solveOnce()}");
}
