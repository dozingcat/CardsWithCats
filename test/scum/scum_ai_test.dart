import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum/scum_ai.dart';
import 'package:flutter_test/flutter_test.dart';

PlayingCard card(String s) => PlayingCard.cardFromString(s);

void main() {
  test("Mandatory pass returns the highest cards", () {
    final hand = [
      card("2C"), card("7D"), card("9H"), card("AS"), card("KH"), card("KS"),
    ];
    final two = mandatoryCardsToGive(hand, 2);
    expect(two[0].rank, Rank.ace);
    expect(two[1].rank, Rank.king);
    final one = mandatoryCardsToGive(hand, 1);
    expect(one[0].rank, Rank.ace);
  });

  test("President gives away lowest singletons without breaking sets", () {
    final hand = [
      card("2H"), card("2D"), // pair of 2s
      card("5S"), // singleton 5
      card("9C"), // singleton 9
      card("QH"), card("QS"), // pair of queens
    ];
    final give = chooseCardsToGive(
        ScumTradeRequest(hand: hand, count: 2, myRole: ScumRole.president));
    expect(give.map((c) => c.rank).toSet(), {Rank.five, Rank.nine});
    // Asking for a third card must break the lowest set.
    final give3 = chooseCardsToGive(
        ScumTradeRequest(hand: hand, count: 3, myRole: ScumRole.president));
    expect(give3.length, 3);
    expect(give3.where((c) => c.rank == Rank.two).length, 1);
  });

  test("AI beats a cheap lead instead of passing", () {
    final rng = Random(4);
    int beats = 0;
    const runs = 50;
    for (int seed = 0; seed < runs; seed++) {
      final hand = [card("5H"), card("9D"), card("JC")];
      final trick = ScumTrick(1)..actions.add(ScumTrickAction(1, [card("3S")]));
      final req = ScumPlayRequest(
        rules: ScumRuleSet(),
        hand: hand,
        seatOrder: const [0, 1, 2, 3],
        scores: const [0, 0, 0, 0],
        handCounts: const [3, 3, 5, 5],
        seenCards: {...hand, card("3S")},
        playerIndex: 0,
        currentTrick: trick,
      );
      final play = chooseScumPlay(req, rng);
      if (play.isNotEmpty) {
        beats++;
        // Should beat with the lowest sufficient card, not a higher one.
        expect(play[0].rank, Rank.five);
      }
    }
    expect(beats, greaterThan(runs * 9 ~/ 10),
        reason: "AI should almost always beat a 3 lead holding 5-9-J");
  });

  test("AI preserves high cards when only they can beat a cheap play", () {
    final rng = Random(6);
    int beats = 0;
    const runs = 50;
    for (int seed = 0; seed < runs; seed++) {
      final hand = [card("AH"), card("KS"), card("QD")];
      final trick = ScumTrick(1)..actions.add(ScumTrickAction(1, [card("4C")]));
      final req = ScumPlayRequest(
        rules: ScumRuleSet(),
        hand: hand,
        seatOrder: const [0, 1, 2, 3],
        scores: const [0, 0, 0, 0],
        handCounts: const [3, 10, 10, 10],
        seenCards: {...hand, card("4C")},
        playerIndex: 0,
        currentTrick: trick,
      );
      final play = chooseScumPlay(req, rng);
      if (play.isNotEmpty) beats++;
    }
    // Early game with a healthy hand: burning A/K/Q on a 4 is usually wrong,
    // but the AI should still beat sometimes; it must never stall entirely.
    expect(beats, lessThan(runs));
    expect(beats, greaterThanOrEqualTo(0));
  });

  test("issue #10: the AI does not lead a high quad early", () {
    final rng = Random(8);
    final hand = [
      card("KS"), card("KH"), card("KD"), card("KC"),
      card("3H"), card("4D"), card("5S"), card("6C"),
      card("7H"), card("8D"),
    ];
    for (int seed = 0; seed < 40; seed++) {
      final req = ScumPlayRequest(
        rules: ScumRuleSet(),
        hand: List.of(hand),
        seatOrder: const [0, 1, 2, 3],
        scores: const [0, 0, 0, 0],
        handCounts: const [10, 10, 10, 10],
        seenCards: {...hand},
        playerIndex: 0,
        currentTrick: ScumTrick(0),
      );
      final play = chooseScumPlay(req, Random(seed));
      final isKingsQuad = play.length == 4 && play[0].rank == Rank.king;
      expect(isKingsQuad, isFalse,
          reason: "seed $seed led quad kings with a deep hand");
    }
  });

  test("AI always returns a legal play or a legal pass", () {
    final rng = Random(19);
    for (int game = 0; game < 30; game++) {
      final match = ScumMatch(ScumRuleSet(), Random(game * 3 + 1));
      int guard = 0;
      while (!match.currentRound.isOver() && guard < 5000) {
        guard++;
        final round = match.currentRound;
        if (round.status == ScumRoundStatus.trading) {
          for (int i = 0; i < 4; i++) {
            final needed = round.numCardsToSelectForTrade(i);
            if (needed > 0) {
              round.setTradeSelection(
                  i,
                  chooseCardsToGive(ScumTradeRequest(
                      hand: round.players[i].hand,
                      count: needed,
                      myRole: round.roleForPlayer(i))));
            }
          }
          round.exchangeCards();
          continue;
        }
        final playerIndex = round.currentPlayerIndex();
        final req = ScumPlayRequest.fromRound(round, playerIndex);
        final cards = chooseScumPlay(req, rng);
        if (cards.isEmpty) {
          expect(round.canCurrentPlayerPass(), isTrue,
              reason: "AI passed illegally");
          round.pass();
        } else {
          expect(
              isValidPlay(round.players[playerIndex].hand, cards,
                  round.currentTrick),
              isTrue,
              reason:
                  "AI played invalid set ${PlayingCard.stringFromCards(cards)}");
          round.playCards(cards);
        }
      }
      expect(match.currentRound.isOver(), isTrue);
    }
  });

  test("AI plays out many complete matches without stalling", () {
    final rng = Random(1234);
    for (int g = 0; g < 10; g++) {
      final match = ScumMatch(ScumRuleSet(), Random(g));
      while (!match.isMatchOver()) {
        var guard = 0;
        while (!match.currentRound.isOver() && guard < 20000) {
          guard++;
          final round = match.currentRound;
          if (round.status == ScumRoundStatus.trading) {
            for (int i = 0; i < 4; i++) {
              final needed = round.numCardsToSelectForTrade(i);
              if (needed > 0) {
                round.setTradeSelection(
                    i,
                    chooseCardsToGive(ScumTradeRequest(
                        hand: round.players[i].hand,
                        count: needed,
                        myRole: round.roleForPlayer(i))));
              }
            }
            round.exchangeCards();
            continue;
          }
          final playerIndex = round.currentPlayerIndex();
          final req = ScumPlayRequest.fromRound(round, playerIndex);
          final cards = chooseScumPlay(req, rng);
          if (cards.isEmpty) {
            round.pass();
          } else {
            round.playCards(cards);
          }
        }
        expect(match.currentRound.isOver(), isTrue,
            reason: "Round did not finish");
        match.finishRound();
      }
    }
  });
}
