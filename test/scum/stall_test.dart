import 'dart:math';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum/scum_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("stress: UI-equivalent turn loop never throws", () {
    var failures = 0;
    for (int g = 0; g < 400; g++) {
      final match = ScumMatch(ScumRuleSet(), Random(g * 7919 + 13));
      var rounds = 0;
      while (!match.isMatchOver() && rounds < 12 && failures < 3) {
        var guard = 0;
        while (!match.currentRound.isOver() && guard < 5000) {
          guard++;
          final round = match.currentRound;
          try {
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
            final p = round.currentPlayerIndex();
            // Mirror the UI: humans with legal options pause for input.
            if (p == 0 && round.legalPlaysForCurrentPlayer().isNotEmpty) {
              // Simulate the human tapping Play on the pre-selected/first option.
              round.playCards(round.legalPlaysForCurrentPlayer().first);
              continue;
            }
            if (p == 0) {
              round.pass();
              continue;
            }
            final req = ScumPlayRequest.fromRound(round, p);
            final cards = chooseScumPlay(req, Random(g * 31 + guard));
            if (cards.isEmpty) {
              round.pass();
            } else {
              round.playCards(cards);
            }
          } catch (e, st) {
            failures++;
            print("FAILURE game=$g guard=$guard: $e");
            print(match.currentRound.toJson());
            print(st);
            rethrow; // Surface loudly on first occurrence.
          }
        }
        expect(guard, lessThan(5000), reason: "game $g stalled");
        match.finishRound();
        rounds++;
      }
    }
  });
}
