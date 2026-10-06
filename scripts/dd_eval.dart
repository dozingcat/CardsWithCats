/// Scores self-play bidding against double-dummy par using trick tables
/// cached by dd_tables.dart, so a bidding change can be measured over
/// thousands of deals in seconds. Losses are split into categories from the
/// losing side's point of view, and auctions can be saved and compared
/// against an earlier run deal by deal.
///
///   dart run scripts/dd_eval.dart --tables FILE [--deals N]
///       [--save FILE] [--compare FILE] [--show CATEGORY] [--top N] [--hcp]
///
/// --save writes each deal's auction and IMP loss; --compare reads such a
/// file and reports the deals whose auction changed, with the net IMPs
/// gained or lost and the largest swings (with hands and stated meanings).
/// --show prints the worst --top deals of one category (a prefix of the
/// category name is enough). --hcp breaks each category's IMPs down by the
/// losing side's combined HCP.
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dd_scoring.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

final _strains = <Suit?>[null, ...Suit.values];

class _Deal {
  final int index;
  final List<List<PlayingCard>> hands;
  final List<Map<Suit?, int>> byDeclarer;
  _Deal(this.index, this.hands, this.byDeclarer);

  List<Map<Suit?, int>> get bySide => [
        for (int side = 0; side < 2; side++)
          {
            for (final s in _strains)
              s: [byDeclarer[side][s]!, byDeclarer[side + 2][s]!]
                  .reduce((a, b) => a > b ? a : b)
          }
      ];
}

class _Result {
  final _Deal deal;
  final List<BidAction> history;
  final int actualNs, parNs;
  final String contract;
  final String category;
  _Result(this.deal, this.history, this.actualNs, this.parNs, this.contract,
      this.category);

  int get loss => impsForScoreDifference((actualNs - parNs).abs());
}

String _strainName(Suit? s) => s == null ? "NT" : s.asciiChar;

_Result _evaluate(_Deal deal) {
  final history = runDeal(deal.hands).history;
  final bySide = deal.bySide;
  final parNs = parScoreNs(bySide);
  final result = FinalContract.of(history);
  int actualNs = 0;
  String contract = "passed out";
  if (result != null) {
    final t = deal.byDeclarer[result.declarer][result.bid.trump]!;
    final score = nonVulnerableScore(result.bid, t, doubled: result.doubled);
    actualNs = result.side == 0 ? score : -score;
    contract = "${result.bid.count}${_strainName(result.bid.trump)}"
        "${switch (result.doubled) {
          DoubledType.none => '',
          DoubledType.doubled => 'X',
          DoubledType.redoubled => 'XX',
        }} by ${"NESW"[result.declarer]} (${t - 6 - result.bid.count >= 0 ? '+' : ''}${t - 6 - result.bid.count})";
  }

  String category;
  if (actualNs == parNs) {
    category = "at-par";
  } else {
    final loser = actualNs < parNs ? 0 : 1;
    final sidesBidding = {
      for (int i = 0; i < history.length; i++)
        if (history[i].bidType == BidType.contract) i % 2
    };
    final contested = sidesBidding.length == 2 ? "contested" : "uncontested";
    if (result == null) {
      category = "passed-out";
    } else {
      final t = deal.byDeclarer[result.declarer][result.bid.trump]!;
      final makes = t >= 6 + result.bid.count;
      final doubled = result.doubled != DoubledType.none;
      if (result.side == loser) {
        if (!makes) {
          category = doubled ? "declared-down-doubled" : "declared-down";
        } else {
          final best = bySide[loser];
          final gameMakes = _strains.any((s) =>
              best[s]! >= 6 + (s == null ? 3 : (isMajorSuit(s) ? 4 : 5)));
          final slamMakes = _strains.any((s) => best[s]! >= 12);
          final level = result.bid.count;
          final isGame = level >=
              (result.bid.trump == null
                  ? 3
                  : (isMajorSuit(result.bid.trump!) ? 4 : 5));
          category = slamMakes && level < 6
              ? "made-missed-slam"
              : gameMakes && !isGame
                  ? "made-missed-game"
                  : "made-wrong-contract";
        }
      } else {
        category = makes
            ? (doubled ? "they-made-doubled" : "they-made")
            : (doubled ? "they-down-doubled" : "they-down-undoubled");
      }
    }
    category = "$category/$contested";
  }
  return _Result(deal, history, actualNs, parNs, contract, category);
}

String _describe(_Result r) {
  final hands = r.deal.hands;
  final calls = <String>[];
  for (int j = 0; j < r.history.length; j++) {
    if (r.history[j].bidType == BidType.pass) continue;
    final meaning = selectSaycBid(hands[j % 4], r.history.sublist(0, j)).meaning;
    calls.add("${"NESW"[j % 4]} ${r.history[j]}: ${meaning.description}");
  }
  final handText = [
    for (int s = 0; s < 4; s++)
      "${"NESW"[s]} ${handGroupString(hands[s])} (${HandAnalysis(hands[s]).hcp})"
  ].join("  ");
  final bySide = r.deal.bySide;
  String tricks(int side) =>
      [for (final s in _strains) "${_strainName(s)}${bySide[side][s]}"]
          .join(" ");
  return "deal ${r.deal.index}  ${r.category}  loss ${r.loss}  "
      "${r.contract}  NS ${r.actualNs} vs par ${r.parNs}\n"
      "  $handText\n  NS [${tricks(0)}] EW [${tricks(1)}]\n"
      "  ${r.history.join(' ')}\n    ${calls.join('\n    ')}";
}

void main(List<String> args) {
  String? tablesPath, savePath, comparePath, show;
  bool hcpBreakdown = false;
  int? limit;
  int top = 20;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--tables":
        tablesPath = args[++i];
      case "--deals":
        limit = int.parse(args[++i]);
      case "--save":
        savePath = args[++i];
      case "--compare":
        comparePath = args[++i];
      case "--show":
        show = args[++i];
      case "--hcp":
        hcpBreakdown = true;
      case "--top":
        top = int.parse(args[++i]);
    }
  }
  if (tablesPath == null) {
    print("--tables FILE is required (see dd_tables.dart)");
    exit(1);
  }
  final lines = File(tablesPath).readAsLinesSync();
  final seed = int.parse(lines.first.split(" ").last);
  final deals = <_Deal>[];
  for (final line in lines.skip(1)) {
    if (limit != null && deals.length >= limit) break;
    final v = line.split(" ").map(int.parse).toList();
    deals.add(_Deal(v[0], dealHands(seed, v[0]), [
      for (int d = 0; d < 4; d++)
        {for (int s = 0; s < 5; s++) _strains[s]: v[1 + d * 5 + s]}
    ]));
  }

  final results = deals.map(_evaluate).toList();
  final total = results.fold(0, (a, r) => a + r.loss);
  final atPar = results.where((r) => r.loss == 0).length;
  print("seed $seed, ${results.length} deals: "
      "${(total / results.length).toStringAsFixed(3)} IMPs/deal lost, "
      "$atPar at par");
  final byCategory = <String, List<_Result>>{};
  for (final r in results) {
    if (r.loss > 0) (byCategory[r.category] ??= []).add(r);
  }
  final cats = byCategory.keys.toList()
    ..sort((a, b) => byCategory[b]!
        .fold(0, (x, r) => x + r.loss)
        .compareTo(byCategory[a]!.fold(0, (x, r) => x + r.loss)));
  for (final c in cats) {
    final rs = byCategory[c]!;
    final imps = rs.fold(0, (x, r) => x + r.loss);
    print("  ${c.padRight(42)} ${rs.length.toString().padLeft(5)} deals "
        "${imps.toString().padLeft(6)} IMPs "
        "(${(imps / results.length).toStringAsFixed(3)}/deal)");
    if (hcpBreakdown) {
      // IMPs by the losing side's combined HCP.
      final byHcp = <String, int>{};
      for (final r in rs) {
        final loser = r.actualNs < r.parNs ? 0 : 1;
        final hcp = HandAnalysis(r.deal.hands[loser]).hcp +
            HandAnalysis(r.deal.hands[loser + 2]).hcp;
        final band = hcp < 20
            ? "<20"
            : hcp >= 33
                ? "33+"
                : "${hcp - hcp % 3}-${hcp - hcp % 3 + 2}";
        byHcp[band] = (byHcp[band] ?? 0) + r.loss;
      }
      final bands = byHcp.keys.toList()..sort();
      print("      by loser HCP: "
          "${bands.map((b) => '$b:${byHcp[b]}').join('  ')}");
    }
  }

  if (show != null) {
    final rs = [
      for (final c in cats)
        if (c.startsWith(show)) ...byCategory[c]!
    ]..sort((a, b) => b.loss.compareTo(a.loss));
    for (final r in rs.take(top)) {
      print("");
      print(_describe(r));
    }
  }

  if (savePath != null) {
    File(savePath).writeAsStringSync([
      for (final r in results) "${r.deal.index} ${r.loss} ${r.history.join(' ')}"
    ].join("\n"));
  }
  if (comparePath != null) {
    final base = <int, (int, String)>{};
    for (final line in File(comparePath).readAsLinesSync()) {
      final parts = line.split(" ");
      base[int.parse(parts[0])] = (int.parse(parts[1]), parts.skip(2).join(" "));
    }
    final changed = <(_Result, int)>[];
    for (final r in results) {
      final b = base[r.deal.index];
      if (b == null || b.$2 == r.history.join(" ")) continue;
      changed.add((r, b.$1 - r.loss));
    }
    final net = changed.fold(0, (a, c) => a + c.$2);
    final better = changed.where((c) => c.$2 > 0).length;
    final worse = changed.where((c) => c.$2 < 0).length;
    print("\ncompared with $comparePath: ${changed.length} auctions changed, "
        "$better better, $worse worse, net ${net >= 0 ? '+' : ''}$net IMPs "
        "(${(net / results.length).toStringAsFixed(3)}/deal)");
    changed.sort((a, b) => a.$2.compareTo(b.$2));
    void list(String title, Iterable<(_Result, int)> cs) {
      if (cs.isEmpty) return;
      print("\n== $title");
      for (final c in cs) {
        final before = base[c.$1.deal.index]!.$2;
        print("\n${c.$2 >= 0 ? '+' : ''}${c.$2} IMPs; before: $before");
        print(_describe(c.$1));
      }
    }

    list("largest losses", changed.where((c) => c.$2 < 0).take(top));
    list("largest gains",
        changed.reversed.where((c) => c.$2 > 0).take(top));
  }
}
