/// Scans self-play auctions that end in five of a minor and compares them,
/// double dummy, with 3NT by the same side. Reports how often 3NT would
/// have made when 5m failed (and the reverse), grouped by the rule that
/// chose five of the minor, with examples of the 3NT-better cases.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/minor_game_scan.dart \
///       [--deals N] [--seed N] [--examples N]
library;

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

void main(List<String> args) {
  int deals = 4000;
  int seed = 1;
  int maxExamples = 10;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--examples":
        maxExamples = int.parse(args[++i]);
    }
  }
  final dds = DdsBackend.instance;
  if (dds == null) {
    print("DDS backend unavailable; set DDS_LIB (cpp/build_libdds.sh)");
    exit(1);
  }

  // Outcome counts keyed by the description of the call that bid 5m.
  final byRule = <String, List<int>>{}; // [total, ntOnly, both, minorOnly]
  final examples = <String, List<String>>{};
  int total = 0, ntOnly = 0, both = 0, minorOnly = 0, neither = 0;

  for (int d = 0; d < deals; d++) {
    final hands = dealHands(seed, d);
    final history = runDeal(hands).history;
    int? last;
    for (int j = history.length - 1; j >= 0; j--) {
      if (history[j].bidType == BidType.contract) {
        last = j;
        break;
      }
    }
    if (last == null) continue;
    final contract = history[last].contractBid!;
    if (contract.count != 5 ||
        contract.trump == null ||
        isMajorSuit(contract.trump!)) {
      continue;
    }
    if (history.sublist(last + 1).any((c) => c.bidType != BidType.pass)) {
      continue; // doubled: may be a sacrifice
    }
    final side = last % 2;
    final minor = contract.trump!;
    // The declarer is whoever on the side first bid the minor.
    int declarer = last % 4;
    for (int j = side; j <= last; j += 2) {
      if (history[j].bidType == BidType.contract &&
          history[j].contractBid!.trump == minor) {
        declarer = j % 4;
        break;
      }
    }
    int tricks(int decl, Suit? trump) {
      final ns = dds.solve(hands, trump, (decl + 1) % 4, const [])!;
      return decl % 2 == 0 ? ns : 13 - ns;
    }

    final minorTricks = tricks(declarer, minor);
    final ntTricks = [tricks(side, null), tricks(side + 2, null)]
        .reduce((a, b) => a > b ? a : b);
    final minorMakes = minorTricks >= 11;
    final ntMakes = ntTricks >= 9;

    final chooser = last % 4;
    final why = selectSaycBid(hands[chooser], history.sublist(0, last))
        .meaning
        .description;
    final row = byRule.putIfAbsent(why, () => [0, 0, 0, 0]);
    row[0]++;
    total++;
    if (ntMakes && !minorMakes) {
      ntOnly++;
      row[1]++;
      final ex = examples.putIfAbsent(why, () => []);
      if (ex.length < maxExamples) {
        ex.add("deal $d: ${history.join(' ')}  "
            "(5${minor.asciiChar}: $minorTricks tricks, 3NT: $ntTricks)\n"
            "      ${[
          for (int s = 0; s < 4; s++)
            "seat $s: ${PlayingCard.stringFromCards(hands[s])}"
        ].join('\n      ')}");
      }
    } else if (ntMakes && minorMakes) {
      both++;
      row[2]++;
    } else if (minorMakes) {
      minorOnly++;
      row[3]++;
    } else {
      neither++;
    }
    if ((d + 1) % 200 == 0) stderr.write(".");
  }
  stderr.write("\n");

  print("$total undoubled 5m contracts over $deals deals (seed $seed):");
  print("  3NT makes, 5m fails: $ntOnly");
  print("  both make:           $both");
  print("  5m makes, 3NT fails: $minorOnly");
  print("  neither makes:       $neither");
  print("");
  print("by the rule that bid 5m (total / 3NT-only / both / 5m-only):");
  final keys = byRule.keys.toList()
    ..sort((a, b) => byRule[b]![0].compareTo(byRule[a]![0]));
  for (final k in keys) {
    final r = byRule[k]!;
    print("  ${r[0]} / ${r[1]} / ${r[2]} / ${r[3]}  $k");
  }
  for (final k in keys) {
    final ex = examples[k];
    if (ex == null) continue;
    print("");
    print("== 3NT better: $k");
    for (final e in ex) {
      print("  $e");
    }
  }
}
