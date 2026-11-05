import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/five_hundred/five_hundred.dart';
import 'package:cards_with_cats/five_hundred/five_hundred_stats.dart';
import 'package:flutter_test/flutter_test.dart';

// A finished round where the declaring team takes `declarerTricks` tricks.
// Tricks carry only winners, which is all the scoring reads.
FiveHundredRound finishedRound({
  required int declarer,
  required int tricks,
  required int declarerTricks,
  Suit? trump = Suit.hearts,
  List<int> initialScores = const [0, 0],
}) {
  final bid = FiveHundredBid(tricks, trump);
  return FiveHundredRound()
    ..status = FiveHundredRoundStatus.playing
    ..rules = FiveHundredRuleSet()
    ..players = List.generate(numPlayers, (_) => FiveHundredPlayer([]))
    ..dealer = declarer
    ..initialScores = initialScores
    ..bidHistory = [PlayerBid(declarer, bid)]
    ..currentTrick = TrickInProgress(0)
    ..previousTricks = [
      for (int i = 0; i < numTricksPerRound; i++)
        Trick(0, const [], i < declarerTricks ? declarer : (declarer + 1) % numPlayers),
    ]
    ..contract = Contract(declarer: declarer, bid: bid);
}

void main() {
  test("Player's team made contract", () {
    final round = finishedRound(declarer: 2, tricks: 7, declarerTricks: 8);
    final stats = FiveHundredStats.empty().updateFromRound(round);
    expect(stats.numContractsMade, 1);
    expect(stats.numContracts, 1);
    expect(stats.numSlams, 0);
    expect(stats.numOpponentContractsMade, 0);
    expect(stats.numOpponentContracts, 0);
  });

  test("Player's team failed contract", () {
    final round = finishedRound(declarer: 0, tricks: 8, declarerTricks: 7);
    final stats = FiveHundredStats.empty().updateFromRound(round);
    expect(stats.numContractsMade, 0);
    expect(stats.numContracts, 1);
  });

  test("Opponent contracts", () {
    final made = finishedRound(declarer: 1, tricks: 7, declarerTricks: 7);
    final failed = finishedRound(declarer: 3, tricks: 7, declarerTricks: 6);
    final stats = FiveHundredStats.empty().updateFromRound(made).updateFromRound(failed);
    expect(stats.numOpponentContractsMade, 1);
    expect(stats.numOpponentContracts, 2);
    expect(stats.numContractsMade, 0);
    expect(stats.numContracts, 0);
  });

  test("Slams count all 10 tricks whatever the bid", () {
    var stats = FiveHundredStats.empty();
    stats = stats.updateFromRound(finishedRound(declarer: 0, tricks: 7, declarerTricks: 10));
    stats = stats.updateFromRound(finishedRound(declarer: 2, tricks: 10, declarerTricks: 10, trump: null));
    stats = stats.updateFromRound(finishedRound(declarer: 1, tricks: 6, declarerTricks: 10));
    expect(stats.numSlams, 2);
    expect(stats.numOpponentSlams, 1);
    // A failed 10 bid, or defenders taking every trick, isn't a slam.
    stats = stats.updateFromRound(finishedRound(declarer: 0, tricks: 10, declarerTricks: 9));
    stats = stats.updateFromRound(finishedRound(declarer: 1, tricks: 6, declarerTricks: 0));
    expect(stats.numSlams, 2);
    expect(stats.numOpponentSlams, 1);
    expect(stats.numContracts, 3);
    expect(stats.numContractsMade, 2);
    expect(stats.numOpponentContracts, 2);
    expect(stats.numOpponentContractsMade, 1);
  });

  test("Passed out round isn't counted", () {
    final round = FiveHundredRound()
      ..status = FiveHundredRoundStatus.bidding
      ..bidHistory = [for (int p = 0; p < numPlayers; p++) PlayerBid(p, null)];
    final stats = FiveHundredStats.empty().updateFromRound(round);
    expect(stats.toJson(), FiveHundredStats.empty().toJson());
  });

  test("Unfinished round and match are errors", () {
    final match = FiveHundredMatch(FiveHundredRuleSet(), Random(1));
    expect(() => FiveHundredStats.empty().updateFromRound(match.currentRound), throwsException);
    expect(() => FiveHundredStats.empty().updateFromMatch(match), throwsException);
  });

  test("Match update records win and total points", () {
    final match = FiveHundredMatch(FiveHundredRuleSet(), Random(1));
    // 7♥ is worth 200; the defenders take 2 tricks.
    match.currentRound = finishedRound(declarer: 0, tricks: 7, declarerTricks: 8, initialScores: [350, 100]);
    var stats = FiveHundredStats.empty().updateFromMatch(match);
    expect(stats.numMatches, 1);
    expect(stats.matchesWon, 1);
    expect(stats.totalMatchPoints, 550);
    expect(stats.totalOpponentMatchPoints, 120);

    // Losing by falling to the negative limit.
    match.currentRound = finishedRound(declarer: 0, tricks: 7, declarerTricks: 6, initialScores: [-400, 100]);
    stats = stats.updateFromMatch(match);
    expect(stats.numMatches, 2);
    expect(stats.matchesWon, 1);
    expect(stats.totalMatchPoints, 550 - 600);
    expect(stats.totalOpponentMatchPoints, 120 + 140);
  });

  test("JSON roundtrip", () {
    final stats = FiveHundredStats(
      numMatches: 1,
      matchesWon: 2,
      totalMatchPoints: 3,
      numContracts: 5,
      numContractsMade: 4,
      numSlams: 6,
      totalOpponentMatchPoints: 7,
      numOpponentContracts: 9,
      numOpponentContractsMade: 8,
      numOpponentSlams: 10,
    );
    expect(FiveHundredStats.fromJson(stats.toJson()).toJson(), stats.toJson());
  });
}
