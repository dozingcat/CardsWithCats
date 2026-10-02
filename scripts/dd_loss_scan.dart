/// Ranks self-play deals by how many IMPs the engine's auction loses
/// against a simplified double-dummy par, printing the worst deals with
/// every call's stated meaning so the responsible rule is easy to spot.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/dd_loss_scan.dart \
///       [--deals N] [--seed N] [--start N] [--top N]
///
/// Scoring is non-vulnerable, against the double-dummy par in
/// dd_scoring.dart (sacrifices included). A large loss can still be a slam
/// no system would reach; read the auctions rather than trusting the
/// totals. Recurring rule descriptions among the worst deals are the
/// useful signal.
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dd_scoring.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

String _strainName(Suit? s) =>
    s == null ? "NT" : s.name.substring(0, 1).toUpperCase();

void main(List<String> args) {
  int deals = 1000, seed = 2026, start = 0, top = 60;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--start":
        start = int.parse(args[++i]);
      case "--top":
        top = int.parse(args[++i]);
    }
  }
  final dds = DdsBackend.instance;
  if (dds == null) {
    print("DDS backend unavailable; set DDS_LIB (cpp/build_libdds.sh)");
    exit(1);
  }
  final strains = [null, ...Suit.values];
  final rows = <(int, String)>[];
  for (int index = start; index < start + deals; index++) {
    final hands = dealHands(seed, index);
    final history = runDeal(hands).history;

    // tricks[declarer][strain], double dummy.
    final tricks = [
      for (int d = 0; d < 4; d++)
        {
          for (final s in strains)
            s: () {
              final ns = dds.solve(hands, s, (d + 1) % 4, const [])!;
              return d % 2 == 0 ? ns : 13 - ns;
            }()
        }
    ];
    int sideTricks(int side, Suit? s) =>
        [tricks[side][s]!, tricks[side + 2][s]!].reduce((a, b) => a > b ? a : b);
    final bySide = [
      for (int side = 0; side < 2; side++)
        {for (final s in strains) s: sideTricks(side, s)}
    ];
    final nsBest = bestMakingScore(bySide[0]);
    final ewBest = bestMakingScore(bySide[1]);
    final par = parScoreNs(bySide); // North-South view

    int actual = 0;
    String contract = "passed out";
    final result = FinalContract.of(history);
    if (result != null) {
      final bid = result.bid;
      final t = tricks[result.declarer][bid.trump]!;
      final score = nonVulnerableScore(bid, t, doubled: result.doubled);
      actual = result.side == 0 ? score : -score;
      contract = "${bid.count}${_strainName(bid.trump)}"
          "${switch (result.doubled) {
            DoubledType.none => '',
            DoubledType.doubled => 'X',
            DoubledType.redoubled => 'XX',
          }} by ${"NESW"[result.declarer]} makes $t";
    }
    final loss = impsForScoreDifference(actual - par);

    final calls = <String>[];
    for (int j = 0; j < history.length; j++) {
      if (history[j].bidType == BidType.pass) continue;
      final meaning =
          selectSaycBid(hands[j % 4], history.sublist(0, j)).meaning;
      calls.add("${"NESW"[j % 4]} ${history[j]}: ${meaning.description}");
    }
    final handText = [
      for (int s = 0; s < 4; s++)
        "${"NESW"[s]} ${handGroupString(hands[s])} "
            "(${HandAnalysis(hands[s]).hcp})"
    ].join("  ");
    final nsTricks = [
      for (final s in strains) "${_strainName(s)}:${sideTricks(0, s)}"
    ].join(" ");
    rows.add((
      loss.abs(),
      "deal $index  loss ${loss.abs()} IMPs "
          "(${loss < 0 ? 'NS' : 'EW'} lost)  $contract  "
          "[par $par; best NS $nsBest / EW $ewBest]  NS tricks $nsTricks\n"
          "  $handText\n  ${history.join(' ')}\n"
          "    ${calls.join('\n    ')}"
    ));
    if ((index + 1) % 100 == 0) stderr.write(".");
  }
  stderr.write("\n");
  rows.sort((a, b) => b.$1.compareTo(a.$1));
  final histogram = <int, int>{};
  for (final r in rows) {
    histogram[r.$1] = (histogram[r.$1] ?? 0) + 1;
  }
  final keys = histogram.keys.toList()..sort();
  print("IMP loss histogram (seed $seed, deals $start-${start + deals - 1}): "
      "${keys.map((k) => '$k:${histogram[k]}').join(' ')}");
  for (final r in rows.take(top)) {
    print(r.$2);
  }
}
