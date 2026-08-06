import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/bridge/dd_solver.dart';

const c = PlayingCard.cardsFromString;

void main() {
  test("cashes established winners", () {
    // North holds all the top spades and is on lead.
    final hands = [
      c("AS KS QS JS"),
      c("8H 7H 6H 5H"),
      c("8D 7D 6D 5D"),
      c("8C 7C 6C 5C"),
    ];
    expect(DDSolver.fromHands(hands, null, 0).solve(), 4);
  });

  test("finesse works when the king is onside", () {
    // South leads low toward North's AQ; West holds the king.
    final hands = [
      c("AS QS"), // North
      c("8H 7H"), // East
      c("3S 2S"), // South
      c("KS 5S"), // West
    ];
    expect(DDSolver.fromHands(hands, null, 2).solve(), 2);
  });

  test("finesse fails when the king is offside", () {
    final hands = [
      c("AS QS"), // North
      c("KS 8S"), // East
      c("3S 2S"), // South
      c("8H 7H"), // West
    ];
    expect(DDSolver.fromHands(hands, null, 2).solve(), 1);
  });

  test("trumps beat aces", () {
    final hands = [
      c("AS 2S"), // North
      c("3H 2H"), // East: only trumps
      c("4S 3S"), // South
      c("6D 5D"), // West
    ];
    // In notrump North-South cash spades.
    expect(DDSolver.fromHands(hands, null, 0).solve(), 2);
    // With hearts trump East ruffs everything.
    expect(DDSolver.fromHands(hands, Suit.hearts, 0).solve(), 0);
  });

  test("partial trick in progress", () {
    // South led the 2, West played the king: now the finesse is free.
    final hands = [
      c("AS QS"), // North
      c("8H 7H"), // East
      c("3S"), // South (already played the 2)
      c("5S"), // West (already played the king)
    ];
    final solver = DDSolver.fromHands(hands, null, 2);
    solver.addTrickCard(c("2S")[0]);
    solver.addTrickCard(c("KS")[0]);
    expect(solver.solve(), 2);
  });

  test("agrees with brute-force reference on random endings", () {
    final rng = Random(99);
    final deck = standardDeckCards();
    // Endings are capped at 5 cards per hand: the unpruned reference is
    // exponential and 6-card endings already take minutes.
    for (int trial = 0; trial < 150; trial++) {
      final cardsPer = 3 + trial % 3; // 3-5 card endings
      final cards = List.of(deck)..shuffle(rng);
      final hands = [
        for (int p = 0; p < 4; p++)
          cards.sublist(p * cardsPer, (p + 1) * cardsPer)
      ];
      final trump = switch (trial % 5) {
        0 => null,
        1 => Suit.clubs,
        2 => Suit.diamonds,
        3 => Suit.hearts,
        _ => Suit.spades,
      };
      final leader = trial % 4;
      final fast = DDSolver.fromHands(hands, trump, leader).solve();
      final reference =
          DDReferenceSolver.fromHands(hands, trump, leader).solve();
      expect(fast, reference,
          reason: "trial $trial trump $trump leader $leader hands $hands");
    }
  });

  test("leads win when nobody can follow at notrump", () {
    // South's spade honors crash under the ace; North's low hearts then
    // win because no other hand holds hearts.
    final hands = [
      c("AS 2H 3H"), // North
      c("9D 8D 7D"), // East
      c("KS QS JS"), // South
      c("9C 8C 7C"), // West
    ];
    expect(DDSolver.fromHands(hands, null, 0).solve(), 3);
  });
}
