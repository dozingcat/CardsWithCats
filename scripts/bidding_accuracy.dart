/// Measures bidding accuracy against double-dummy truth: runs self-play
/// auctions over random deals, solves each deal double dummy, and reports
/// precision (of games/slams bid, how many make) and recall (of makeable
/// games/slams, how many were bid) per declaring side. Precision and recall
/// leave doubled contracts out, so it also scores every deal (doubled ones
/// included, non-vulnerable) against double-dummy par, and classifies the
/// doubled contracts that went down as good or bad sacrifices.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/bidding_accuracy.dart \
///       [--deals N] [--seed N] [--show N]
///
/// --show N prints the first N deals' auction, result, par, and trick table.
library;

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

int gameLevel(Suit? trump) =>
    trump == null ? 3 : (isMajorSuit(trump) ? 4 : 5);

final allBids = [
  for (int level = 1; level <= 7; level++)
    for (final trump in [...Suit.values, null]) ContractBid(level, trump)
];

/// Non-vulnerable duplicate score for the declaring side of [bid] taking
/// [tricks] (self-play bids without vulnerability).
int scoreFor(ContractBid bid, int tricks,
        {DoubledType doubled = DoubledType.none}) =>
    Contract(bid: bid, isVulnerable: false, declarer: 0, doubled: doubled)
        .scoreForTricksTaken(tricks);

/// Double-dummy par for N-S, from each side's best tricks per strain: the
/// sides take turns outbidding (a making contract, or a doubled sacrifice
/// when it costs less than defending) until neither improves. The side with
/// the better makeable contract bids first.
int parScoreNs(List<Map<Suit?, int>> maxTricks) {
  int result(int side, ContractBid bid) {
    final t = maxTricks[side][bid.trump]!;
    return t >= bid.numTricksRequired
        ? scoreFor(bid, t)
        : scoreFor(bid, t, doubled: DoubledType.doubled);
  }

  int bestMaking(int side) => allBids
      .where((b) => maxTricks[side][b.trump]! >= b.numTricksRequired)
      .map((b) => scoreFor(b, maxTricks[side][b.trump]!))
      .fold(0, (a, b) => a > b ? a : b);

  ContractBid? current;
  int owner = -1;
  int side = bestMaking(0) >= bestMaking(1) ? 0 : 1;
  int passes = 0;
  while (passes < 2) {
    final defend = current == null
        ? 0
        : (owner == side ? result(owner, current) : -result(owner, current));
    ContractBid? best;
    int bestScore = defend;
    for (final b in allBids) {
      if (current != null && !b.isHigherThan(current)) continue;
      final r = result(side, b);
      if (r > bestScore) {
        best = b;
        bestScore = r;
      }
    }
    if (best != null && owner != side) {
      current = best;
      owner = side;
      passes = 0;
    } else {
      passes++;
    }
    side = 1 - side;
  }
  if (current == null) return 0;
  final score = result(owner, current);
  return owner == 0 ? score : -score;
}

void main(List<String> args) {
  int deals = 400;
  int seed = 1;
  int show = 0;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--show":
        show = int.parse(args[++i]);
    }
  }
  final dds = DdsBackend.instance;
  if (dds == null) {
    print("DDS backend unavailable; set DDS_LIB (cpp/build_libdds.sh)");
    exit(1);
  }

  // Confusion counts for games (game-or-higher by a side) and slams.
  int gamesBid = 0, gamesBidMakeable = 0;
  int gameChances = 0, gameChancesBid = 0;
  int slamsBid = 0, slamsBidMakeable = 0;
  int slamChances = 0, slamChancesBid = 0;
  int contractsBid = 0, doubledExcluded = 0;
  // Score against par, and sacrifices (doubled contracts that went down).
  int impsLost = 0, atPar = 0;
  int doubledMade = 0;
  int goodSacrifices = 0, goodSaved = 0;
  int badSacrifices = 0, badCost = 0;

  final strains = [null, ...Suit.values];
  for (int i = 0; i < deals; i++) {
    final hands = dealHands(seed, i);
    final history = runDeal(hands).history;

    // Double-dummy max tricks for each side in each strain (best declarer).
    int tricksFor(int declarer, Suit? trump) {
      final ns = dds.solve(hands, trump, (declarer + 1) % 4, const [])!;
      return declarer % 2 == 0 ? ns : 13 - ns;
    }

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

    int? lastBidIndex;
    for (int j = history.length - 1; j >= 0; j--) {
      if (history[j].bidType == BidType.contract) {
        lastBidIndex = j;
        break;
      }
    }
    final contract = lastBidIndex == null
        ? null
        : history[lastBidIndex].contractBid!;
    final declSide = lastBidIndex == null ? null : lastBidIndex % 2;
    final doubled = lastBidIndex != null &&
        history.sublist(lastBidIndex + 1).any((c) =>
            c.bidType == BidType.double || c.bidType == BidType.redouble);

    // Actual result: the declarer is whoever on the side first bid the
    // final strain; doubled contracts count here too.
    int actualNs = 0;
    if (contract != null) {
      int declarer = lastBidIndex! % 4;
      for (int j = declSide!; j <= lastBidIndex; j += 2) {
        if (history[j].bidType == BidType.contract &&
            history[j].contractBid!.trump == contract.trump) {
          declarer = j % 4;
          break;
        }
      }
      final after = history.sublist(lastBidIndex + 1);
      final dbl = after.any((c) => c.bidType == BidType.redouble)
          ? DoubledType.redoubled
          : after.any((c) => c.bidType == BidType.double)
              ? DoubledType.doubled
              : DoubledType.none;
      final tricks = tricksFor(declarer, contract.trump);
      final score = scoreFor(contract, tricks, doubled: dbl);
      actualNs = declSide == 0 ? score : -score;
      if (dbl != DoubledType.none) {
        if (score >= 0) {
          doubledMade++;
        } else {
          // Compare the penalty with what the opponents could have scored
          // in their best makeable contract.
          int oppBest = 0;
          for (final b in allBids) {
            final t = maxTricks[1 - declSide][b.trump]!;
            if (t >= b.numTricksRequired) {
              final s = scoreFor(b, t);
              if (s > oppBest) oppBest = s;
            }
          }
          if (-score < oppBest) {
            goodSacrifices++;
            goodSaved += oppBest + score;
          } else {
            badSacrifices++;
            badCost += -score - oppBest;
          }
        }
      }
    }
    final parNs = parScoreNs(maxTricks);
    final imps = impsForScoreDifference((actualNs - parNs).abs());
    if (i < show) {
      String table(int side) => [
            for (final st in strains)
              "${st == null ? 'N' : st.asciiChar}${maxTricks[side][st]}"
          ].join(" ");
      print("deal $i: ${history.join(' ')}\n"
          "  N-S $actualNs, par $parNs ($imps IMPs); "
          "tricks N-S [${table(0)}] E-W [${table(1)}]");
    }
    impsLost += imps;
    if (imps == 0) atPar++;

    final bidGame = contract != null &&
        contract.count >= gameLevel(contract.trump);
    final bidSlam = contract != null && contract.count >= 6;

    // Precision: does the contract actually make double dummy? Doubled
    // contracts are excluded (they may be sensible sacrifices).
    if (bidGame && !doubled) {
      contractsBid++;
      final makes =
          maxTricks[declSide!][contract!.trump]! >= 6 + contract.count;
      gamesBid++;
      if (makes) gamesBidMakeable++;
      if (bidSlam) {
        slamsBid++;
        if (makes) slamsBidMakeable++;
      }
    } else if (bidGame && doubled) {
      doubledExcluded++;
    }

    // Recall: for each side with a double-dummy game/slam available, did
    // that side bid it?
    for (int side = 0; side < 2; side++) {
      if (sideHasGame(side)) {
        gameChances++;
        if (bidGame && declSide == side) gameChancesBid++;
      }
      if (sideHasSlam(side)) {
        slamChances++;
        if (bidSlam && declSide == side) slamChancesBid++;
      }
    }
    if ((i + 1) % 100 == 0) stderr.write(".");
  }
  stderr.write("\n");

  String pct(int a, int b) =>
      b == 0 ? "n/a" : "${(100 * a / b).toStringAsFixed(1)}%";
  print("over $deals deals (double-dummy truth):");
  print("games+ bid (undoubled): $gamesBid, DD-makeable $gamesBidMakeable "
      "(precision ${pct(gamesBidMakeable, gamesBid)}); "
      "$doubledExcluded doubled excluded");
  print("game chances: $gameChances, bid by that side $gameChancesBid "
      "(recall ${pct(gameChancesBid, gameChances)})");
  print("slams bid: $slamsBid, DD-makeable $slamsBidMakeable "
      "(precision ${pct(slamsBidMakeable, slamsBid)})");
  print("slam chances: $slamChances, bid by that side $slamChancesBid "
      "(recall ${pct(slamChancesBid, slamChances)})");
  print("score vs double-dummy par (non-vulnerable, doubled contracts "
      "included): ${(impsLost / deals).toStringAsFixed(3)} IMPs/deal lost, "
      "$atPar deals (${pct(atPar, deals)}) within 10 points of par");
  print("doubled contracts made: $doubledMade; went down: "
      "${goodSacrifices + badSacrifices} (good sacrifices $goodSacrifices "
      "saving $goodSaved points, bad $badSacrifices costing $badCost)");
}
