/// Measures bidding accuracy against double-dummy truth: runs self-play
/// auctions over random deals, solves each deal double dummy, and reports
/// precision (of games/slams bid, how many make) and recall (of makeable
/// games/slams, how many were bid) per declaring side.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/bidding_accuracy.dart \
///       [--deals N] [--seed N]
library;

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

int gameLevel(Suit? trump) =>
    trump == null ? 3 : (isMajorSuit(trump) ? 4 : 5);

void main(List<String> args) {
  int deals = 400;
  int seed = 1;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
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
}
