/// Quick DD solver probe: one deal, increasing depths, prints timing as it
/// goes so slowness is visible immediately.
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/bridge/heuristic_play.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

void main(List<String> args) {
  final seed = args.isEmpty ? 42 : int.parse(args[0]);
  for (int tricksLeft = 3; tricksLeft <= 13; tricksLeft++) {
    final rng = Random(seed);
    final round = BridgeRound.deal(0, rng);
    round.bidHistory = [
      PlayerBid(2, BidAction.fromString("4H")),
      for (int i = 3; i < 6; i++) PlayerBid(i % 4, BidAction.pass()),
    ];
    round.contract = Contract(
        bid: ContractBid.fromString("4H"), isVulnerable: false, declarer: 2);
    round.status = BridgeRoundStatus.playing;
    round.currentTrick = TrickInProgress(3);
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
    print("depth $tricksLeft: ${watch.elapsedMilliseconds}ms, NS $tricks");
  }
}
