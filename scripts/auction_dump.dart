/// Prints the engine's call and stated meaning at every position of every
/// self-play auction, one line per position, as a fingerprint of the
/// bidding engine's behavior. Comparing the output before and after a
/// refactor (it is deterministic) shows whether any call or explanation
/// changed. With --chaos P, random calls are injected as in
/// bidding_audit.dart, which reaches positions normal bidding never does.
///
///   dart run scripts/auction_dump.dart [--deals N] [--seed N] [--chaos P]
library;

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';

void main(List<String> args) {
  int deals = 1000;
  int seed = 1;
  double chaos = 0;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--chaos":
        chaos = double.parse(args[++i]);
    }
  }
  for (int d = 0; d < deals; d++) {
    final hands = dealHands(seed, d);
    final history = runDeal(hands,
            chaosRng: chaos > 0 ? Random(seed * 31 + d) : null,
            chaosProbability: chaos)
        .history;
    for (int i = 0; i < history.length; i++) {
      final bid = selectSaycBid(hands[i % 4], history.sublist(0, i));
      print("$d.$i ${history.sublist(0, i).join(' ')} -> "
          "${bid.action} | ${bid.meaning.description}");
    }
  }
}
