import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_stats.dart';
import 'package:cards_with_cats/cards/trick.dart';

/// A finished round with the given contract and declarer trick count.
/// Hands are empty (the round is over); tricks carry only winners, which
/// is all the stats computations read.
BridgeRound finishedRound({
  required String contract,
  required int declarer,
  required int declarerTricks,
  DoubledType doubled = DoubledType.none,
  bool vulnerable = false,
}) {
  final dummy = (declarer + 2) % 4;
  final defender = (declarer + 1) % 4;
  return BridgeRound()
    ..status = BridgeRoundStatus.playing
    ..players = List.generate(4, (_) => BridgePlayer([]))
    ..dealer = declarer
    ..bidHistory = [
      PlayerBid(declarer, BidAction.fromString(contract)),
      for (int i = 1; i <= 3; i++)
        PlayerBid((declarer + i) % 4, BidAction.pass()),
    ]
    ..currentTrick = TrickInProgress(0)
    ..previousTricks = [
      for (int i = 0; i < 13; i++)
        Trick(0, const [], i < declarerTricks ? (i % 2 == 0 ? declarer : dummy) : defender),
    ]
    ..contract = Contract(
      bid: ContractBid.fromString(contract),
      declarer: declarer,
      doubled: doubled,
      isVulnerable: vulnerable,
    );
}

BridgeRound passedOutRound() {
  return BridgeRound()
    ..status = BridgeRoundStatus.playing
    ..players = List.generate(4, (_) => BridgePlayer([]))
    ..dealer = 0
    ..bidHistory = [
      for (int i = 0; i < 4; i++) PlayerBid(i, BidAction.pass()),
    ]
    ..currentTrick = TrickInProgress(0)
    ..previousTricks = [];
}

void main() {
  test("game contract definition follows scoring", () {
    Contract make(String bid, [DoubledType doubled = DoubledType.none]) =>
        Contract(
            bid: ContractBid.fromString(bid),
            declarer: 0,
            doubled: doubled,
            isVulnerable: false);
    expect(BridgeStats.isGameContract(make("3NT")), true);
    expect(BridgeStats.isGameContract(make("4S")), true);
    expect(BridgeStats.isGameContract(make("5C")), true);
    expect(BridgeStats.isGameContract(make("4C")), false);
    expect(BridgeStats.isGameContract(make("2S")), false);
    expect(BridgeStats.isGameContract(make("2S", DoubledType.doubled)), true);
    expect(BridgeStats.isGameContract(make("1NT", DoubledType.doubled)), false);
  });

  test("player partial made", () {
    final round =
        finishedRound(contract: "2S", declarer: 0, declarerTricks: 8);
    final dup = finishedRound(contract: "2S", declarer: 0, declarerTricks: 8);
    final stats = BridgeStats.empty().updateFromRound(round, dup);
    expect(stats.numRounds, 1);
    expect(stats.netRoundImps, 0);
    expect(stats.numContracts, 1);
    expect(stats.numContractsMade, 1);
    expect(stats.numGameContracts, 0);
    expect(stats.numSlamContracts, 0);
    expect(stats.numOpposingContracts, 0);
  });

  test("partner's game counts for the player's side", () {
    final round =
        finishedRound(contract: "4S", declarer: 2, declarerTricks: 9);
    final dup = finishedRound(contract: "4S", declarer: 2, declarerTricks: 9);
    final stats = BridgeStats.empty().updateFromRound(round, dup);
    expect(stats.numContracts, 1);
    expect(stats.numContractsMade, 0);
    expect(stats.numGameContracts, 1);
    expect(stats.numGameContractsMade, 0);
  });

  test("opposing slam is not counted as an opposing game", () {
    final round =
        finishedRound(contract: "6H", declarer: 1, declarerTricks: 12);
    final dup = finishedRound(contract: "6H", declarer: 1, declarerTricks: 12);
    final stats = BridgeStats.empty().updateFromRound(round, dup);
    expect(stats.numOpposingContracts, 1);
    expect(stats.numOpposingContractsMade, 1);
    expect(stats.numOpposingGameContracts, 0);
    expect(stats.numOpposingSlamContracts, 1);
    expect(stats.numOpposingSlamContractsMade, 1);
    expect(stats.numContracts, 0);
  });

  test("round IMPs come from the duplicate comparison", () {
    // 4S making 10 (+420) vs the replay going down one (-50): +470 -> 10.
    final round =
        finishedRound(contract: "4S", declarer: 0, declarerTricks: 10);
    final dup = finishedRound(contract: "4S", declarer: 0, declarerTricks: 9);
    final stats = BridgeStats.empty().updateFromRound(round, dup);
    expect(stats.netRoundImps, 10);
  });

  test("passed-out round counts only as a round", () {
    final stats =
        BridgeStats.empty().updateFromRound(passedOutRound(), passedOutRound());
    expect(stats.numRounds, 1);
    expect(stats.netRoundImps, 0);
    expect(stats.numContracts, 0);
    expect(stats.numOpposingContracts, 0);
  });

  test("match update records win and net IMPs", () {
    final match = BridgeMatch(Random(1), numRounds: 1);
    match.currentRound =
        finishedRound(contract: "4S", declarer: 0, declarerTricks: 10);
    match.duplicateRound =
        finishedRound(contract: "4S", declarer: 0, declarerTricks: 9);
    match.finishRound();
    expect(match.isMatchOver(), true);
    final stats = BridgeStats.empty().updateFromMatch(match);
    expect(stats.numMatches, 1);
    expect(stats.numMatchesWon, 1);
    expect(stats.numMatchesTied, 0);
    expect(stats.netMatchImps, 10);
  });

  test("json roundtrip", () {
    var stats = BridgeStats.empty();
    final round =
        finishedRound(contract: "6NT", declarer: 0, declarerTricks: 12);
    stats = stats.updateFromRound(round, round);
    stats = stats.copyWith(numMatches: 3, numMatchesWon: 2, netMatchImps: -7);
    final restored = BridgeStats.fromJson(stats.toJson());
    expect(restored.toJson(), stats.toJson());
    expect(restored.numSlamContractsMade, 1);
    expect(restored.netMatchImps, -7);
  });
}
