/// Measures bidding accuracy against double-dummy truth: runs self-play
/// auctions over random deals, solves each deal double dummy, and reports
/// precision (of games/slams bid, how many make) and recall (of makeable
/// games/slams, how many were bid) per declaring side. Precision and recall
/// leave doubled contracts out, so it also scores every deal (doubled ones
/// included, non-vulnerable) against double-dummy par, and classifies the
/// doubled contracts that went down as good or bad sacrifices.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/bidding_accuracy.dart \
///       [--deals N] [--seed N] [--show N] [--workers N]
///
/// --show N prints the first N deals' auction, result, par, and trick table.
/// --workers N splits the deals across N isolates (results are identical to
/// a single worker; DDS allows up to min(cores, 16) concurrent solves).
library;

import 'dart:io';
import 'dart:isolate';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dd_scoring.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

int gameLevel(Suit? trump) =>
    trump == null ? 3 : (isMajorSuit(trump) ? 4 : 5);

/// Counts over a range of deals; ranges are summed with [add].
class _Stats {
  // Confusion counts for games (game-or-higher by a side) and slams.
  int gamesBid = 0, gamesBidMakeable = 0;
  int gameChances = 0, gameChancesBid = 0;
  int slamsBid = 0, slamsBidMakeable = 0;
  int slamChances = 0, slamChancesBid = 0;
  int doubledExcluded = 0;
  // Score against par, and sacrifices (doubled contracts that went down).
  int impsLost = 0, atPar = 0;
  int doubledMade = 0;
  int goodSacrifices = 0, goodSaved = 0;
  int badSacrifices = 0, badCost = 0;
  // --show output for deals in this range, in order.
  final shown = <String>[];

  void add(_Stats o) {
    gamesBid += o.gamesBid;
    gamesBidMakeable += o.gamesBidMakeable;
    gameChances += o.gameChances;
    gameChancesBid += o.gameChancesBid;
    slamsBid += o.slamsBid;
    slamsBidMakeable += o.slamsBidMakeable;
    slamChances += o.slamChances;
    slamChancesBid += o.slamChancesBid;
    doubledExcluded += o.doubledExcluded;
    impsLost += o.impsLost;
    atPar += o.atPar;
    doubledMade += o.doubledMade;
    goodSacrifices += o.goodSacrifices;
    goodSaved += o.goodSaved;
    badSacrifices += o.badSacrifices;
    badCost += o.badCost;
    shown.addAll(o.shown);
  }
}

/// Analyzes deals [start, end) of [seed], showing those below [show]. Runs
/// in its own isolate when there are several workers, so it loads DDS
/// itself.
_Stats _analyze(int seed, int start, int end, int show) {
  final dds = DdsBackend.instance!;
  final st = _Stats();
  final strains = [null, ...Suit.values];
  for (int i = start; i < end; i++) {
    final hands = dealHands(seed, i);
    final history = runDeal(hands).history;

    // Double-dummy tricks for a declarer; null means every DDS thread slot
    // was busy (more workers than slots), so wait for one.
    int tricksFor(int declarer, Suit? trump) {
      while (true) {
        final ns = dds.solve(hands, trump, (declarer + 1) % 4, const []);
        if (ns != null) return declarer % 2 == 0 ? ns : 13 - ns;
        sleep(const Duration(milliseconds: 1));
      }
    }

    // Max tricks for each side in each strain (best declarer).
    final maxTricks = List.generate(
        2,
        (side) => {
              for (final s in strains)
                s: [tricksFor(side, s), tricksFor(side + 2, s)]
                    .reduce((a, b) => a > b ? a : b)
            });
    bool sideHasGame(int side) => strains.any(
        (s) => maxTricks[side][s]! >= 6 + gameLevel(s));
    bool sideHasSlam(int side) =>
        strains.any((s) => maxTricks[side][s]! >= 12);

    // Actual result, doubled contracts included.
    final result = FinalContract.of(history);
    int actualNs = 0;
    if (result != null) {
      final tricks = tricksFor(result.declarer, result.bid.trump);
      final score =
          nonVulnerableScore(result.bid, tricks, doubled: result.doubled);
      actualNs = result.side == 0 ? score : -score;
      if (result.doubled != DoubledType.none) {
        if (score >= 0) {
          st.doubledMade++;
        } else {
          // Compare the penalty with what the opponents could have scored
          // in their best makeable contract.
          final oppBest = bestMakingScore(maxTricks[1 - result.side]);
          if (-score < oppBest) {
            st.goodSacrifices++;
            st.goodSaved += oppBest + score;
          } else {
            st.badSacrifices++;
            st.badCost += -score - oppBest;
          }
        }
      }
    }
    final parNs = parScoreNs(maxTricks);
    final imps = impsForScoreDifference((actualNs - parNs).abs());
    if (i < show) {
      String table(int side) => [
            for (final s in strains)
              "${s == null ? 'N' : s.asciiChar}${maxTricks[side][s]}"
          ].join(" ");
      st.shown.add("deal $i: ${history.join(' ')}\n"
          "  N-S $actualNs, par $parNs ($imps IMPs); "
          "tricks N-S [${table(0)}] E-W [${table(1)}]");
    }
    st.impsLost += imps;
    if (imps == 0) st.atPar++;

    final contract = result?.bid;
    final declSide = result?.side;
    final doubled = result != null && result.doubled != DoubledType.none;
    final bidGame =
        contract != null && contract.count >= gameLevel(contract.trump);
    final bidSlam = contract != null && contract.count >= 6;

    // Precision: does the contract actually make double dummy? Doubled
    // contracts are excluded (they may be sensible sacrifices).
    if (bidGame && !doubled) {
      final makes = maxTricks[declSide!][contract.trump]! >= 6 + contract.count;
      st.gamesBid++;
      if (makes) st.gamesBidMakeable++;
      if (bidSlam) {
        st.slamsBid++;
        if (makes) st.slamsBidMakeable++;
      }
    } else if (bidGame && doubled) {
      st.doubledExcluded++;
    }

    // Recall: for each side with a double-dummy game/slam available, did
    // that side bid it?
    for (int side = 0; side < 2; side++) {
      if (sideHasGame(side)) {
        st.gameChances++;
        if (bidGame && declSide == side) st.gameChancesBid++;
      }
      if (sideHasSlam(side)) {
        st.slamChances++;
        if (bidSlam && declSide == side) st.slamChancesBid++;
      }
    }
    if ((i + 1) % 100 == 0) stderr.write(".");
  }
  return st;
}

Future<void> main(List<String> args) async {
  int deals = 400;
  int seed = 1;
  int show = 0;
  int workers = 1;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--show":
        show = int.parse(args[++i]);
      case "--workers":
        workers = int.parse(args[++i]);
    }
  }
  if (DdsBackend.instance == null) {
    print("DDS backend unavailable; set DDS_LIB (cpp/build_libdds.sh)");
    exit(1);
  }

  final st = _Stats();
  if (workers <= 1) {
    st.add(_analyze(seed, 0, deals, show));
  } else {
    // Contiguous ranges, merged in order so --show output stays ordered.
    final bounds = [for (int w = 0; w <= workers; w++) deals * w ~/ workers];
    final parts = await Future.wait([
      for (int w = 0; w < workers; w++)
        Isolate.run(() => _analyze(seed, bounds[w], bounds[w + 1], show)),
    ]);
    parts.forEach(st.add);
  }
  stderr.write("\n");
  st.shown.forEach(print);

  String pct(int a, int b) =>
      b == 0 ? "n/a" : "${(100 * a / b).toStringAsFixed(1)}%";
  print("over $deals deals (double-dummy truth):");
  print("games+ bid (undoubled): ${st.gamesBid}, DD-makeable "
      "${st.gamesBidMakeable} (precision "
      "${pct(st.gamesBidMakeable, st.gamesBid)}); "
      "${st.doubledExcluded} doubled excluded");
  print("game chances: ${st.gameChances}, bid by that side "
      "${st.gameChancesBid} (recall "
      "${pct(st.gameChancesBid, st.gameChances)})");
  print("slams bid: ${st.slamsBid}, DD-makeable ${st.slamsBidMakeable} "
      "(precision ${pct(st.slamsBidMakeable, st.slamsBid)})");
  print("slam chances: ${st.slamChances}, bid by that side "
      "${st.slamChancesBid} (recall "
      "${pct(st.slamChancesBid, st.slamChances)})");
  print("score vs double-dummy par (non-vulnerable, doubled contracts "
      "included): ${(st.impsLost / deals).toStringAsFixed(3)} IMPs/deal "
      "lost, ${st.atPar} deals (${pct(st.atPar, deals)}) within 10 points "
      "of par");
  print("doubled contracts made: ${st.doubledMade}; went down: "
      "${st.goodSacrifices + st.badSacrifices} (good sacrifices "
      "${st.goodSacrifices} saving ${st.goodSaved} points, bad "
      "${st.badSacrifices} costing ${st.badCost})");
}
