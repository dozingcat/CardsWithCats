/// Benchmarks the double-dummy solver on random deals at various depths.
///
/// Usage: dart run scripts/dd_bench.dart [--deals N] [--seed N]
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/bridge/heuristic_play.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

void main(List<String> args) {
  int numDeals = 20;
  int seed = 42;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        numDeals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
    }
  }

  for (final tricksLeft in [6, 8, 10, 13]) {
    final times = <int>[];
    int totalTricks = 0;
    for (int d = 0; d < numDeals; d++) {
      final rng = Random(seed + d);
      final round = BridgeRound.deal(0, rng);
      // Fixed 4H contract by South (seat 2) so hands are unconstrained.
      round.bidHistory = [
        PlayerBid(2, BidAction.fromString("4H")),
        for (int i = 3; i < 6; i++) PlayerBid(i % 4, BidAction.pass()),
      ];
      round.contract = Contract(
          bid: ContractBid.fromString("4H"),
          isVulnerable: false,
          declarer: 2);
      round.status = BridgeRoundStatus.playing;
      round.currentTrick = TrickInProgress(3);
      // Play down to the target depth with the heuristic policy.
      while (round.players[0].hand.length > tricksLeft ||
          round.currentTrick.cards.isNotEmpty) {
        final req = CardToPlayRequest.fromRoundWithSharedReferences(round);
        round.playCard(chooseCardHeuristic(req, rng));
      }
      final hands = [for (final p in round.players) p.hand];
      final solver =
          DDSolver.fromHands(hands, Suit.hearts, round.currentTrick.leader);
      final watch = Stopwatch()..start();
      final tricks = solver.solve();
      watch.stop();
      times.add(watch.elapsedMicroseconds);
      totalTricks += tricks;
    }
    times.sort();
    final total = times.fold(0, (a, b) => a + b);
    print("depth $tricksLeft: avg ${(total / numDeals / 1000).toStringAsFixed(1)}ms "
        "median ${(times[numDeals ~/ 2] / 1000).toStringAsFixed(1)}ms "
        "max ${(times.last / 1000).toStringAsFixed(1)}ms "
        "(avg NS tricks ${(totalTricks / numDeals).toStringAsFixed(1)})");
  }
}
