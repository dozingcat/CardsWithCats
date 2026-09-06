// Regression test for issue #12: the cats keep a reserve of high cards in
// proportion to the low cards they still have to shed, instead of spending
// aces on tricks that didn't need them.
//
// Plays seeded rounds with two cautious cats against two reckless ones,
// rotating the policy across seats so seat and role advantages cancel out.
// tool/scum_ai_bench.dart runs the same comparison at higher volume.
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum/scum_ai.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mean finish position per policy (0 = President, 3 = Scum; lower is better).
Map<String, double> _meanFinishByPolicy(int numRounds) {
  final finishSum = {"cautious": 0, "reckless": 0};
  final counts = {"cautious": 0, "reckless": 0};

  for (int g = 0; g < numRounds; g++) {
    final rng = Random(g * 7919 + 13);
    final rules = ScumRuleSet();
    final policies = <ScumAiOptions>[];
    final names = <String>[];
    for (int seat = 0; seat < rules.numPlayers; seat++) {
      final isCautious = ((seat + g) % 2) == 0;
      policies.add(isCautious ? ScumAiOptions.standard : ScumAiOptions.reckless);
      names.add(isCautious ? "cautious" : "reckless");
    }

    final round =
        ScumRound.deal(rules, List.filled(rules.numPlayers, 0), null, rng);
    var guard = 0;
    while (!round.isOver() && guard < 5000) {
      guard++;
      if (round.status == ScumRoundStatus.trading) {
        for (int i = 0; i < rules.numPlayers; i++) {
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
      if (p < 0) break;
      final cards = chooseScumPlay(ScumPlayRequest.fromRound(round, p), rng,
          options: policies[p]);
      if (cards.isEmpty) {
        round.pass();
      } else {
        round.playCards(cards);
      }
    }
    expect(guard, lessThan(5000), reason: "round $g stalled");

    final order = round.finishOrder();
    for (int seat = 0; seat < rules.numPlayers; seat++) {
      final position = order.indexOf(seat);
      if (position < 0) continue;
      finishSum[names[seat]] = finishSum[names[seat]]! + position;
      counts[names[seat]] = counts[names[seat]]! + 1;
    }
  }
  return {
    for (final k in finishSum.keys) k: finishSum[k]! / counts[k]!,
  };
}

void main() {
  test("keeping a high-card reserve finishes ahead of spending it", () {
    final means = _meanFinishByPolicy(1500);
    // Measured over 12000 rounds the gap is about 1.459 vs 1.542; asserting a
    // smaller margin keeps the test stable at this sample size while still
    // failing if the reserve stops paying for itself.
    expect(means["cautious"]!, lessThan(means["reckless"]! - 0.03),
        reason: "cautious=${means["cautious"]} reckless=${means["reckless"]}");
  });

  test("the reserve only discounts plays that actually spend high cards", () {
    const c = PlayingCard.cardsFromString;
    final trashHeavyHand = c("AS KH 7D 6C 5S 4H 3D");
    // Playing a low card never looks worse for control reasons.
    expect(controlDeficit(trashHeavyHand, c("3D")), 0);
    // Spending both high cards leaves nothing to buy the leads the five low
    // cards still need.
    expect(controlDeficit(trashHeavyHand, c("AS")), greaterThan(0));

    // A hand with little left to shed has no reserve to protect.
    final shortHand = c("AS KH 3D");
    expect(controlDeficit(shortHand, c("AS")), 0);
  });
}
