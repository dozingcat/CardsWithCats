/// Reproduces two reported oddities in the same 4S deal:
///   declarer: KQJT76 AQT QT AK   dummy: A852 J7 K64 Q543
/// Trick 1: W leads AD, dummy low, E low — declarer drops the QD from QT.
/// Trick 2: W continues a low diamond — dummy ducks with K6, losing to
/// East's jack.
///
/// Both decision points are evaluated two ways:
///   preroll:   the pre-fix evaluation — play forward with the heuristic
///              policy until 7 tricks remain, then solve exactly. Its
///              preference for the trick-2 duck (~+30 points) was preroll
///              bias: the heuristic misplayed the win-the-K continuations.
///   fullsolve: solve each candidate position exactly from the decision
///              point (the shipped default).
/// A per-layout audit then shows ground truth: for sampled layouts, the
/// exact declarer-trick difference of ducking vs winning.
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

void evaluateBothWays(String label, CardToPlayRequest req) {
  for (final rounds in [20, 100]) {
    printEquities(
        "$label preroll   rounds=$rounds",
        chooseCardMonteCarloDD(req, Random(3),
            maxRounds: rounds, ddTricksLimit: 7, tryFullDepthSolve: false));
    printEquities(
        "$label fullsolve rounds=$rounds",
        chooseCardMonteCarloDD(req, Random(3),
            maxRounds: rounds, ddTricksLimit: 7));
  }
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
  evaluateBothWays("trick1 declarer", reqA);

  // Dummy (seat 0) second to trick 2: W won the ace and continues the 3.
  // Dummy holds K6 of diamonds; East's JD is still out. Two variants:
  // - With QC in dummy, ducking is a legitimate alternative line: if West
  //   holds the jack, declarer's ten scores en passant and the K plus QC
  //   later provide two heart pitches, replacing the heart finesse with a
  //   diamond finesse (near-tied equities, resolving toward the K).
  // - With the QC weakened to 6C (variant due to Brian), only one pitch
  //   exists, the heart finesse is needed in both lines, and ducking is
  //   strictly wrong: it never gains and loses a trick whenever East has
  //   the jack. Full-depth evaluation prefers the K decisively; preroll
  //   evaluation still ducks — a sharp regression case for preroll bias.
  for (final (clubs, label) in [("QC", "QC variant"), ("6C", "6C variant")]) {
    final reqB = CardToPlayRequest(
      hand: c("AS 8S 5S 2S JH 7H KD 6D $clubs 5C 4C 3C"),
      declarerHand: c("KS QS JS TS 7S 6S AH QH TH TD AC KC"),
      previousTricks: [
        Trick(3, c("AD 4D 2D QD"), 3),
      ],
      currentTrick: TrickInProgress(3, c("3D")),
      bidHistory: bids,
      vulnerability: Vulnerability.neither,
    );
    evaluateBothWays("trick2 dummy $label", reqB);

    // Per-layout audit: sample deals consistent with the position and
    // compare double-dummy declarer tricks after ducking (6D) vs winning
    // (KD). Negative diffs mean ducking costs tricks. Split by which
    // defender holds the outstanding JD: with East, ducking tends to
    // cost a trick; with West, it can only help.
    final distReq = makeCardDistributionRequest(reqB);
    final filter = BiddingDealFilter.fromRequest(reqB);
    final rng = Random(9);
    final diffCounts = <int, int>{};
    final diffCountsByJd = {1: <int, int>{}, 3: <int, int>{}};
    for (int i = 0; i < 40; i++) {
      final hypo = possibleRound(reqB, distReq, rng, filter: filter);
      if (hypo == null) break;
      final jd = c("JD")[0];
      final jdHolder = hypo.players[1].hand.contains(jd) ? 1 : 3;
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
        // Declarer is seat 2 (NS side); the solver counts the
        // in-progress trick.
        tricks.add(round.numTricksWonByDeclarer() + solver.solve());
      }
      final diff = tricks[0] - tricks[1]; // duck minus win
      diffCounts[diff] = (diffCounts[diff] ?? 0) + 1;
      diffCountsByJd[jdHolder]![diff] =
          (diffCountsByJd[jdHolder]![diff] ?? 0) + 1;
    }
    String fmt(Map<int, int> m) =>
        (m.keys.toList()..sort()).map((k) => '$k:${m[k]}').join(' ');
    print("$label duck-vs-win trick diff distribution: ${fmt(diffCounts)}");
    print("  when East holds JD: ${fmt(diffCountsByJd[1]!)}");
    print("  when West holds JD: ${fmt(diffCountsByJd[3]!)}");
  }
}
