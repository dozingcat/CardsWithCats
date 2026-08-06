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
/// Usage:
///   dart run scripts/bridge_play_compare.dart [options] <specA> <specB>
///     --deals N     boards to play (default 100)
///     --seed N      RNG seed (default 42)
///     --quiet       suppress per-board output
/// Strategy specs are described in lib/bridge/play_strategies.dart.
library;

import 'dart:io';
import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/bridge/play_strategies.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart' show isLegalCall;

class StrategyStats {
  int cardsPlayed = 0;
  int elapsedMicros = 0;

  double get avgMillisPerPlay =>
      cardsPlayed == 0 ? 0 : elapsedMicros / cardsPlayed / 1000;
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

void main(List<String> args) {
  int numDeals = 100;
  int seed = 42;
  bool quiet = false;
  final specs = <String>[];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        numDeals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
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
  final a = makeStrategy(specs[0]);
  final b = makeStrategy(specs[1]);
  print("A: ${a.name}");
  print("B: ${b.name}");

  final statsA = StrategyStats();
  final statsB = StrategyStats();
  final impResults = <int>[];
  int totalPointDiff = 0;
  int passedOut = 0;
  int biddingFailed = 0;
  int boardsWonByA = 0, boardsWonByB = 0, boardsTied = 0;
  final overallWatch = Stopwatch()..start();

  for (int board = 0; impResults.length < numDeals; board++) {
    final dealRng = Random(seed * 1000003 + board);
    final open = BridgeRound.deal(board % 4, dealRng)
      ..vulnerability = vulnerabilityForRoundIndex(board);
    if (!bidRound(open)) {
      biddingFailed++;
      continue;
    }
    if (open.isPassedOut()) {
      passedOut++;
      continue;
    }
    final closed = open.copyAndReset();
    for (final bid in open.bidHistory) {
      closed.addBid(bid);
    }
    // Open room: A holds N-S. Closed room: A holds E-W. Both rooms use the
    // same RNG seed (common random numbers): identical strategies then play
    // identically and score zero, and the shared noise cancels in the
    // difference for similar strategies.
    playRound(open, a, b, {0, 2}, Random(seed * 7 + board), statsA, statsB);
    playRound(closed, b, a, {0, 2}, Random(seed * 7 + board), statsB, statsA);
    final scoreDiff =
        open.contractScoreForPlayer(0) - closed.contractScoreForPlayer(0);
    final imps = impsForScoreDifference(scoreDiff);
    impResults.add(imps);
    totalPointDiff += scoreDiff;
    if (imps > 0) {
      boardsWonByA++;
    } else if (imps < 0) {
      boardsWonByB++;
    } else {
      boardsTied++;
    }
    if (!quiet) {
      final c = open.contract!;
      final made = open.tricksTakenByDeclarerOverContract();
      final madeClosed = closed.tricksTakenByDeclarerOverContract();
      print("board ${impResults.length}: ${c.bid} by ${"NESW"[c.declarer]}"
          "${c.doubled != DoubledType.none ? 'X' : ''} "
          "open ${made >= 0 ? '+' : ''}$made closed "
          "${madeClosed >= 0 ? '+' : ''}$madeClosed -> "
          "${imps >= 0 ? '+' : ''}$imps IMPs to A");
    }
  }
  overallWatch.stop();

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
      "(${statsA.cardsPlayed} plays), "
      "B ${statsB.avgMillisPerPlay.toStringAsFixed(2)} "
      "(${statsB.cardsPlayed} plays)");
  print("elapsed: ${(overallWatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s");
}
