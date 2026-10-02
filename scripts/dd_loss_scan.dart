/// Ranks self-play deals by how many IMPs the engine's auction loses
/// against a simplified double-dummy par, printing the worst deals with
/// every call's stated meaning so the responsible rule is easy to spot.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/dd_loss_scan.dart \
///       [--deals N] [--seed N] [--start N] [--top N]
///
/// Scoring is non-vulnerable. Par is each side's best makeable contract
/// (the higher-scoring side wins), ignoring sacrifices, so a large loss
/// can also be a slam no system would reach; read the auctions rather
/// than trusting the totals. Recurring rule descriptions among the worst
/// deals are the useful signal.
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

const _impTable = [
  20, 50, 90, 130, 170, 220, 270, 320, 370, 430, 500, 600, 750, 900, //
  1100, 1300, 1500, 1750, 2000, 2250, 2500, 3000, 3500, 4000,
];

int imps(int diff) {
  final a = diff.abs();
  int i = 0;
  while (i < _impTable.length && a >= _impTable[i]) {
    i++;
  }
  return diff < 0 ? -i : i;
}

int _trickValue(Suit? trump) =>
    trump == null || isMajorSuit(trump) ? 30 : 20;

/// Non-vulnerable score for declarer; [doubled] is 0, 1 (X) or 2 (XX).
int contractScore(int level, Suit? trump, int doubled, int tricks) {
  final need = level + 6;
  if (tricks < need) {
    final down = need - tricks;
    if (doubled == 0) return -50 * down;
    int penalty = 0;
    for (int i = 1; i <= down; i++) {
      penalty += i == 1 ? 100 : (i <= 3 ? 200 : 300);
    }
    return -(doubled == 2 ? penalty * 2 : penalty);
  }
  final per = _trickValue(trump);
  final base =
      (per * level + (trump == null ? 10 : 0)) * (doubled == 0 ? 1 : 2 * doubled);
  int score = base + (base >= 100 ? 300 : 50);
  if (level == 6) score += 500;
  if (level == 7) score += 1000;
  score += 50 * doubled;
  final overtricks = tricks - need;
  score += doubled == 0 ? overtricks * per : overtricks * 100 * doubled;
  return score;
}

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
    int bestScore(int side) {
      int best = 0;
      for (final s in strains) {
        final t = sideTricks(side, s);
        for (int level = 1; level <= t - 6; level++) {
          final score = contractScore(level, s, 0, t);
          if (score > best) best = score;
        }
      }
      return best;
    }

    final nsBest = bestScore(0), ewBest = bestScore(1);
    final par = nsBest >= ewBest ? nsBest : -ewBest; // North-South view

    int? lastIndex;
    for (int j = history.length - 1; j >= 0; j--) {
      if (history[j].bidType == BidType.contract) {
        lastIndex = j;
        break;
      }
    }
    int actual = 0;
    String contract = "passed out";
    if (lastIndex != null) {
      final bid = history[lastIndex].contractBid!;
      int doubled = 0;
      for (final c in history.sublist(lastIndex + 1)) {
        if (c.bidType == BidType.double) doubled = 1;
        if (c.bidType == BidType.redouble) doubled = 2;
      }
      // Declarer: the first of the declaring side to name the strain.
      final side = lastIndex % 2;
      int declarer = lastIndex % 4;
      for (int j = 0; j < history.length; j++) {
        if (j % 2 == side &&
            history[j].bidType == BidType.contract &&
            history[j].contractBid!.trump == bid.trump) {
          declarer = j % 4;
          break;
        }
      }
      final t = tricks[declarer][bid.trump]!;
      final score = contractScore(bid.count, bid.trump, doubled, t);
      actual = declarer % 2 == 0 ? score : -score;
      contract = "${bid.count}${_strainName(bid.trump)}"
          "${doubled == 1 ? 'X' : doubled == 2 ? 'XX' : ''} "
          "by ${"NESW"[declarer]} makes $t";
    }
    final loss = imps(actual - par);

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
          "[best NS $nsBest / EW $ewBest]  NS tricks $nsTricks\n"
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
