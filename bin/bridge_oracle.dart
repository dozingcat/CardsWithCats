/// Generates bidding positions for cross-validation against the Python
/// reference engine. Deals seeded random hands, runs each seat through the
/// ported SAYC engine for as long as positions are covered, and emits one
/// TSV line per call:
///
///   <hand in suit groups> \t <history or '-'> \t <chosen call>
///
/// Check against the reference with:
///   dart run bin/bridge_oracle.dart --deals 500 --seed 3 \
///     | python3 ~/tmp/bridge_bidding/oracle_check.py
///
/// Usage: dart run bin/bridge_oracle.dart [--deals N] [--seed S]
library;

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/cards/card.dart';

void main(List<String> args) {
  int deals = 200;
  int seed = 1;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == "--deals") deals = int.parse(args[++i]);
    if (args[i] == "--seed") seed = int.parse(args[++i]);
  }

  int positions = 0;
  for (int index = 0; index < deals; index++) {
    final rng = Random(seed * 100003 + index);
    final deck = standardDeckCards()..shuffle(rng);
    final hands =
        List.generate(4, (i) => deck.sublist(i * 13, (i + 1) * 13));

    final history = <BidAction>[];
    while (true) {
      final seat = history.length % 4;
      if (history.length >= 4 &&
          history
              .sublist(history.length - 3)
              .every((c) => c.bidType == BidType.pass)) {
        break;
      }
      final result = selectSaycBid(hands[seat], history);
      if (result == null) break; // position not ported yet
      final historyString = history.isEmpty
          ? "-"
          : history.map((c) => c.toString()).join(" ");
      print("${handGroupString(hands[seat])}\t$historyString"
          "\t${result.action}");
      positions++;
      history.add(result.action);
    }
  }
  // Summary on stderr so stdout stays a clean TSV stream.
  stderr.writeln("$deals deals, $positions covered positions emitted");
}
