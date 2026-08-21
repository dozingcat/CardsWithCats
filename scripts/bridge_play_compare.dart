/// Duplicate-table comparison of bridge card-play strategies.
///
/// Each board is dealt randomly and bid once by the SAYC engine (all four
/// seats). The play then happens twice with identical cards and auction:
/// in the open room strategy A holds North-South, in the closed room the
/// sides are swapped. The score difference is converted to IMPs credited
/// to strategy A, exactly as in a team-of-four match. Boards that are
/// passed out are skipped (bidding is identical in both rooms, so they
/// can never produce a difference).
///
/// Boards are played in parallel across isolates. All randomness is
/// seeded per board, so results are identical regardless of --jobs.
///
/// Usage:
///   dart run scripts/bridge_play_compare.dart [options] <specA> <specB>
///     --deals N     boards to play (default 100)
///     --seed N      RNG seed (default 42)
///     --jobs N      worker isolates (default: cores - 2)
///     --quiet       suppress per-board output
/// Strategy specs are described in lib/bridge/play_strategies.dart.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/bridge/play_strategies.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';

class StrategyStats {
  int cardsPlayed = 0;
  int elapsedMicros = 0;
  int maxMicros = 0;

  double get avgMillisPerPlay =>
      cardsPlayed == 0 ? 0 : elapsedMicros / cardsPlayed / 1000;

  double get maxMillisPerPlay => maxMicros / 1000;

  void merge(int cards, int micros, int maxM) {
    cardsPlayed += cards;
    elapsedMicros += micros;
    if (maxM > maxMicros) maxMicros = maxM;
  }
}

/// Plays out `round` (bidding already complete). Seats in `teamASeats` use
/// strategy A; the others use B. Returns nothing; mutates the round.
void playRound(BridgeRound round, PlayStrategy a, PlayStrategy b,
    Set<int> teamASeats, Random rng, StrategyStats statsA, StrategyStats statsB) {
  final watch = Stopwatch();
  while (!round.isOver()) {
    final seat = round.currentPlayerIndex();
    final isTeamA = teamASeats.contains(seat);
    final strategy = isTeamA ? a : b;
    final req = CardToPlayRequest.fromRound(round);
    watch
      ..reset()
      ..start();
    final card = strategy.chooseCard(req, rng);
    watch.stop();
    final stats = isTeamA ? statsA : statsB;
    stats.cardsPlayed += 1;
    stats.elapsedMicros += watch.elapsedMicroseconds;
    if (watch.elapsedMicroseconds > stats.maxMicros) {
      stats.maxMicros = watch.elapsedMicroseconds;
    }
    round.playCard(card);
  }
}

/// Bids the round with the SAYC engine for all seats. Returns false if the
/// auction failed (engine exception or illegal call).
bool bidRound(BridgeRound round) {
  while (round.status == BridgeRoundStatus.bidding) {
    final seat = round.currentBidder();
    final history = [for (final b in round.bidHistory) b.action];
    BidAction call;
    try {
      call = selectSaycBid(round.players[seat].hand, history,
              vulnerability: round.vulnerability)
          .action;
    } catch (e) {
      return false;
    }
    if (!isLegalCall(call, history)) {
      return false;
    }
    round.addBid(PlayerBid(seat, call));
  }
  return true;
}

BridgeRound _dealAndBid(int seed, int board) {
  final dealRng = Random(seed * 1000003 + board);
  final round = BridgeRound.deal(board % 4, dealRng)
    ..vulnerability = vulnerabilityForRoundIndex(board);
  return round;
}

/// One played board's outcome, sendable across isolates.
typedef BoardResult = ({
  int board,
  int imps,
  int scoreDiff,
  String description,
  int aCards,
  int aMicros,
  int aMaxMicros,
  int bCards,
  int bMicros,
  int bMaxMicros,
});

BoardResult _playBoard(String specA, String specB, int seed, int board) {
  final a = makeStrategy(specA);
  final b = makeStrategy(specB);
  final open = _dealAndBid(seed, board);
  bidRound(open);
  final closed = open.copyAndReset();
  for (final bid in open.bidHistory) {
    closed.addBid(bid);
  }
  final statsA = StrategyStats();
  final statsB = StrategyStats();
  // Open room: A holds N-S. Closed room: A holds E-W. Both rooms use the
  // same RNG seed (common random numbers): identical strategies then play
  // identically and score zero, and the shared noise cancels in the
  // difference for similar strategies.
  playRound(open, a, b, {0, 2}, Random(seed * 7 + board), statsA, statsB);
  playRound(closed, b, a, {0, 2}, Random(seed * 7 + board), statsB, statsA);
  final scoreDiff =
      open.contractScoreForPlayer(0) - closed.contractScoreForPlayer(0);
  final c = open.contract!;
  final made = open.tricksTakenByDeclarerOverContract();
  final madeClosed = closed.tricksTakenByDeclarerOverContract();
  final description = "${c.bid} by ${"NESW"[c.declarer]}"
      "${c.doubled != DoubledType.none ? 'X' : ''} "
      "open ${made >= 0 ? '+' : ''}$made closed "
      "${madeClosed >= 0 ? '+' : ''}$madeClosed";
  return (
    board: board,
    imps: impsForScoreDifference(scoreDiff),
    scoreDiff: scoreDiff,
    description: description,
    aCards: statsA.cardsPlayed,
    aMicros: statsA.elapsedMicros,
    aMaxMicros: statsA.maxMicros,
    bCards: statsB.cardsPlayed,
    bMicros: statsB.elapsedMicros,
    bMaxMicros: statsB.maxMicros,
  );
}

void main(List<String> args) async {
  int numDeals = 100;
  int seed = 42;
  int jobs = max(1, Platform.numberOfProcessors - 2);
  bool quiet = false;
  final specs = <String>[];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        numDeals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--jobs":
        jobs = max(1, int.parse(args[++i]));
      case "--quiet":
        quiet = true;
      default:
        specs.add(args[i]);
    }
  }
  if (specs.length != 2) {
    print("Expected exactly two strategy specs, got $specs");
    exit(1);
  }
  // Instantiate here to fail fast on bad specs.
  print("A: ${makeStrategy(specs[0]).name}");
  print("B: ${makeStrategy(specs[1]).name}");

  final overallWatch = Stopwatch()..start();

  // Bidding is cheap; pre-scan sequentially for the boards the play phase
  // will use, so results match a sequential run exactly.
  final playable = <int>[];
  int passedOut = 0;
  int biddingFailed = 0;
  for (int board = 0; playable.length < numDeals; board++) {
    final round = _dealAndBid(seed, board);
    if (!bidRound(round)) {
      biddingFailed++;
    } else if (round.isPassedOut()) {
      passedOut++;
    } else {
      playable.add(board);
    }
  }

  // Fan boards out across worker isolates.
  final results = List<BoardResult?>.filled(playable.length, null);
  int nextIndex = 0;
  Future<void> worker() async {
    while (true) {
      final i = nextIndex++;
      if (i >= playable.length) return;
      final board = playable[i];
      results[i] = await Isolate.run(
          () => _playBoard(specs[0], specs[1], seed, board));
    }
  }

  await Future.wait([for (int w = 0; w < jobs; w++) worker()]);
  overallWatch.stop();

  final statsA = StrategyStats();
  final statsB = StrategyStats();
  final impResults = <int>[];
  int totalPointDiff = 0;
  int boardsWonByA = 0, boardsWonByB = 0, boardsTied = 0;
  for (final r in results) {
    if (r == null) continue;
    impResults.add(r.imps);
    totalPointDiff += r.scoreDiff;
    if (r.imps > 0) {
      boardsWonByA++;
    } else if (r.imps < 0) {
      boardsWonByB++;
    } else {
      boardsTied++;
    }
    statsA.merge(r.aCards, r.aMicros, r.aMaxMicros);
    statsB.merge(r.bCards, r.bMicros, r.bMaxMicros);
    if (!quiet) {
      print("board ${impResults.length}: ${r.description} -> "
          "${r.imps >= 0 ? '+' : ''}${r.imps} IMPs to A");
    }
  }

  final n = impResults.length;
  final mean = impResults.fold(0, (s, x) => s + x) / n;
  final variance =
      impResults.fold(0.0, (s, x) => s + (x - mean) * (x - mean)) /
          max(1, n - 1);
  final stderr = sqrt(variance / n);
  print("");
  print("boards: $n (skipped: $passedOut passed out, "
      "$biddingFailed bidding failures)");
  print("IMPs to A per board: ${mean.toStringAsFixed(3)} "
      "+/- ${stderr.toStringAsFixed(3)}");
  print("total point diff to A: $totalPointDiff");
  print("boards won A/B/tied: $boardsWonByA/$boardsWonByB/$boardsTied");
  print("avg ms/play: A ${statsA.avgMillisPerPlay.toStringAsFixed(2)} "
      "(max ${statsA.maxMillisPerPlay.toStringAsFixed(0)}, "
      "${statsA.cardsPlayed} plays), "
      "B ${statsB.avgMillisPerPlay.toStringAsFixed(2)} "
      "(max ${statsB.maxMillisPerPlay.toStringAsFixed(0)}, "
      "${statsB.cardsPlayed} plays)");
  print("elapsed: ${(overallWatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s "
      "($jobs jobs)");
}
