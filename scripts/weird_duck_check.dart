/// Reproduces two reported oddities in the same 4S deal:
///   declarer: KQJT76 AQT QT AK   dummy: A852 J7 K64 Q543
/// Trick 1: W leads AD, dummy low, E low — declarer drops the QD from QT.
/// Trick 2: W continues a low diamond — dummy ducks with K6, losing to
/// East's jack.
/// Prints MCDD candidate equities at both decision points.
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';

const c = PlayingCard.cardsFromString;

final bids = [
  PlayerBid(2, BidAction.fromString("2C")),
  PlayerBid(3, BidAction.pass()),
  PlayerBid(0, BidAction.fromString("2D")),
  PlayerBid(1, BidAction.pass()),
  PlayerBid(2, BidAction.fromString("2S")),
  PlayerBid(3, BidAction.pass()),
  PlayerBid(0, BidAction.fromString("3S")),
  PlayerBid(1, BidAction.pass()),
  PlayerBid(2, BidAction.fromString("4S")),
  PlayerBid(3, BidAction.pass()),
  PlayerBid(0, BidAction.pass()),
  PlayerBid(1, BidAction.pass()),
];

void printEquities(String label, MonteCarloResult result) {
  final entries = result.cardEquities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print("$label best=${result.bestCard}: ${entries.map((e) =>
      '${e.key}=${e.value.toStringAsFixed(1)}').join(' ')}");
}

void main() {
  // Declarer (seat 2) fourth to trick 1: AD led, dummy played the 4, E
  // the 2. Declarer holds QT of diamonds.
  final reqA = CardToPlayRequest(
    hand: c("KS QS JS TS 7S 6S AH QH TH QD TD AC KC"),
    dummyHand: c("AS 8S 5S 2S JH 7H KD 6D QC 5C 4C 3C"),
    previousTricks: [],
    currentTrick: TrickInProgress(3, c("AD 4D 2D")),
    bidHistory: bids,
    vulnerability: Vulnerability.neither,
  );
  for (final rounds in [20, 100]) {
    printEquities("trick1 declarer rounds=$rounds",
        chooseCardMonteCarloDD(reqA, Random(3), maxRounds: rounds,
            ddTricksLimit: 7));
  }

  // Dummy (seat 0) second to trick 2: W won the ace and continues the 3.
  // Dummy holds K6 of diamonds; East's JD is still out.
  final reqB = CardToPlayRequest(
    hand: c("AS 8S 5S 2S JH 7H KD 6D QC 5C 4C 3C"),
    declarerHand: c("KS QS JS TS 7S 6S AH QH TH TD AC KC"),
    previousTricks: [
      Trick(3, c("AD 4D 2D QD"), 3),
    ],
    currentTrick: TrickInProgress(3, c("3D")),
    bidHistory: bids,
    vulnerability: Vulnerability.neither,
  );
  for (final rounds in [20, 100]) {
    printEquities("trick2 dummy   rounds=$rounds",
        chooseCardMonteCarloDD(reqB, Random(3), maxRounds: rounds,
            ddTricksLimit: 7));
  }

  // Per-layout audit of the trick-2 duck: sample deals consistent with
  // the position and compare double-dummy declarer tricks after ducking
  // (6D) vs winning (KD).
  final distReq = makeCardDistributionRequest(reqB);
  final filter = BiddingDealFilter.fromRequest(reqB);
  final rng = Random(9);
  final diffCounts = <int, int>{};
  for (int i = 0; i < 40; i++) {
    final hypo = possibleRound(reqB, distReq, rng, filter: filter);
    if (hypo == null) break;
    final tricks = <int>[];
    for (final play in c("6D KD")) {
      final round = hypo.copy();
      round.playCard(play);
      final hands = [for (final p in round.players) p.hand];
      final solver = DDSolver.fromHands(
          hands, Suit.spades, round.currentTrick.leader);
      for (final tc in round.currentTrick.cards) {
        solver.addTrickCard(tc);
      }
      // Declarer is seat 2 (NS side); solver counts the in-progress trick.
      tricks.add(round.numTricksWonByDeclarer() + solver.solve());
    }
    final diff = tricks[0] - tricks[1]; // duck minus win
    diffCounts[diff] = (diffCounts[diff] ?? 0) + 1;
  }
  print("duck-vs-win declarer trick diff distribution: "
      "${(diffCounts.keys.toList()..sort()).map((k) => '$k:${diffCounts[k]}').join(' ')}");
}
