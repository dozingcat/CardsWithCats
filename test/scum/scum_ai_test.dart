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
