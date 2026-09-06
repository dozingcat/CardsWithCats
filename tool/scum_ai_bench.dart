// Head-to-head strength benchmark for the Scum cats.
//
// Seats two "cautious" bots (the shipped `ScumAiOptions.standard`, which keeps
// a reserve of high cards) against two "reckless" ones and plays out seeded
// rounds, rotating which seats get which policy so seat and role advantages
// cancel out. Reports mean finish position (lower is better) and points.
//
//   dart run tool/scum_ai_bench.dart [rounds] [controlWeight]
//
// Used to justify the change for issue #12.
import 'dart:math';

import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum/scum_ai.dart';

class Tally {
  int rounds = 0;
  int finishSum = 0;
  int points = 0;
  int firsts = 0;
  int lasts = 0;

  double get meanFinish => finishSum / rounds;
  double get meanPoints => points / rounds;
}

void main(List<String> args) {
  final numRounds = args.isNotEmpty ? int.parse(args[0]) : 4000;
  final weight = args.length > 1 ? double.parse(args[1]) : 3.0;

  final cautious = ScumAiOptions(controlWeight: weight);
  const reckless = ScumAiOptions.reckless;

  final tallies = {"cautious": Tally(), "reckless": Tally()};

  for (int g = 0; g < numRounds; g++) {
    final rng = Random(g * 7919 + 13);
    final rules = ScumRuleSet();
    // Rotate the policy assignment so each policy sees every seat equally.
    final policies = <ScumAiOptions>[];
    final names = <String>[];
    for (int seat = 0; seat < rules.numPlayers; seat++) {
      final isCautious = ((seat + g) % 2) == 0;
      policies.add(isCautious ? cautious : reckless);
      names.add(isCautious ? "cautious" : "reckless");
    }

    final round = ScumRound.deal(rules, List.filled(rules.numPlayers, 0), null, rng);
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
      final req = ScumPlayRequest.fromRound(round, p);
      final cards = chooseScumPlay(req, rng, options: policies[p]);
      if (cards.isEmpty) {
        round.pass();
      } else {
        round.playCards(cards);
      }
    }

    final order = round.finishOrder();
    final points = round.pointsTaken();
    for (int seat = 0; seat < rules.numPlayers; seat++) {
      final t = tallies[names[seat]]!;
      final position = order.indexOf(seat);
      if (position < 0) continue;
      t.rounds++;
      t.finishSum += position;
      t.points += points[seat];
      if (position == 0) t.firsts++;
      if (position == rules.numPlayers - 1) t.lasts++;
    }
  }

  print("rounds=$numRounds controlWeight=$weight");
  for (final name in ["cautious", "reckless"]) {
    final t = tallies[name]!;
    print("${name.padRight(9)} "
        "meanFinish=${t.meanFinish.toStringAsFixed(4)} "
        "meanPoints=${t.meanPoints.toStringAsFixed(4)} "
        "1st=${(100 * t.firsts / t.rounds).toStringAsFixed(2)}% "
        "last=${(100 * t.lasts / t.rounds).toStringAsFixed(2)}%");
  }
}
