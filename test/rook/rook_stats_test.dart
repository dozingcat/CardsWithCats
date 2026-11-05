import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/rook/rook.dart';
import 'package:cards_with_cats/rook/rook_stats.dart';
import 'package:flutter_test/flutter_test.dart';

List<PlayingCard> c(String s) => PlayingCard.cardsFromString(s);

// A finished round where the declaring team captures `declarerCards` and the
// defenders capture `defenderCards`. Defenders win the last trick, unless
// `nest` is set, which goes to the declaring team.
RookRound finishedRound({
  required int declarer,
  required int bid,
  required String declarerCards,
  required String defenderCards,
  String nest = "",
  List<int> initialScores = const [0, 0],
}) {
  final defender = (declarer + 1) % numPlayers;
  return RookRound()
    ..status = RookRoundStatus.playing
    ..rules = RookRuleSet()
    ..players = List.generate(numPlayers, (_) => RookPlayer([]))
    ..dealer = declarer
    ..initialScores = initialScores
    ..bidHistory = [PlayerBid(declarer, bid)]
    ..currentTrick = TrickInProgress(0)
    ..finalNest = c(nest)
    ..previousTricks = [
      Trick(0, c(defenderCards), defender),
      Trick(0, c(declarerCards), nest.isEmpty ? declarer : (declarer + 2) % numPlayers),
    ]
    ..contract = Contract(declarer: declarer, bid: bid, trump: Suit.spades);
}

void main() {
  test("Player's team made contract", () {
    final round = finishedRound(declarer: 2, bid: 70, declarerCards: "AS AH AD AC 10S 10H 10D", defenderCards: "5S");
    final stats = RookStats.empty().updateFromRound(round);
    expect(stats.numContractsMade, 1);
    expect(stats.numContracts, 1);
    expect(stats.numOpponentContractsMade, 0);
    expect(stats.numOpponentContracts, 0);
  });

  test("Nest counts toward making the contract", () {
    final round = finishedRound(declarer: 0, bid: 70, declarerCards: "AS AH AD AC 10S 10H", defenderCards: "5S", nest: "10D");
    expect(RookStats.empty().updateFromRound(round).numContractsMade, 1);
  });

  test("Player's team failed contract", () {
    final round = finishedRound(declarer: 0, bid: 70, declarerCards: "AS 5H", defenderCards: "AH");
    final stats = RookStats.empty().updateFromRound(round);
    expect(stats.numContractsMade, 0);
    expect(stats.numContracts, 1);
  });

  test("Opponent contracts", () {
    final made = finishedRound(declarer: 1, bid: 70, declarerCards: "AS AH AD AC 10S 10H 10D", defenderCards: "5S");
    final failed = finishedRound(declarer: 3, bid: 70, declarerCards: "AS", defenderCards: "AH");
    final stats = RookStats.empty().updateFromRound(made).updateFromRound(failed);
    expect(stats.numOpponentContractsMade, 1);
    expect(stats.numOpponentContracts, 2);
    expect(stats.numContractsMade, 0);
    expect(stats.numContracts, 0);
  });

  test("Passed out round isn't counted", () {
    final round = RookRound()
      ..status = RookRoundStatus.bidding
      ..bidHistory = [for (int p = 0; p < numPlayers; p++) PlayerBid(p, null)];
    final stats = RookStats.empty().updateFromRound(round);
    expect(stats.toJson(), RookStats.empty().toJson());
  });

  test("Unfinished round and match are errors", () {
    final match = RookMatch(RookRuleSet(), Random(1));
    expect(() => RookStats.empty().updateFromRound(match.currentRound), throwsException);
    expect(() => RookStats.empty().updateFromMatch(match), throwsException);
  });

  test("Match update records win and total points", () {
    final match = RookMatch(RookRuleSet(), Random(1));
    match.currentRound = finishedRound(
        declarer: 0, bid: 70, declarerCards: "AS AH AD AC 10S 10H 10D", defenderCards: "5S", initialScores: [240, 100]);
    var stats = RookStats.empty().updateFromMatch(match);
    expect(stats.numMatches, 1);
    expect(stats.matchesWon, 1);
    expect(stats.totalMatchPoints, 310);
    expect(stats.totalOpponentMatchPoints, 105);

    // Negative totals are possible for the losing team.
    match.currentRound = finishedRound(
        declarer: 0, bid: 70, declarerCards: "AS", defenderCards: "AH", initialScores: [-20, 295]);
    stats = stats.updateFromMatch(match);
    expect(stats.numMatches, 2);
    expect(stats.matchesWon, 1);
    expect(stats.totalMatchPoints, 310 - 90);
    expect(stats.totalOpponentMatchPoints, 105 + 305);
  });

  test("JSON roundtrip", () {
    final stats = RookStats(
      numMatches: 1,
      matchesWon: 2,
      totalMatchPoints: 3,
      numContracts: 5,
      numContractsMade: 4,
      totalOpponentMatchPoints: 6,
      numOpponentContracts: 8,
      numOpponentContractsMade: 7,
    );
    expect(RookStats.fromJson(stats.toJson()).toJson(), stats.toJson());
  });
}
