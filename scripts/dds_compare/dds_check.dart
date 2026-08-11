/// Cross-checks lib/bridge/dd_solver.dart against the established
/// dds-bridge/dds solver on randomly generated positions. Double dummy is
/// a perfect-information problem, so any two correct solvers must agree
/// exactly on every position.
///
/// Build the driver first (see dds_driver.cpp), then:
///   dart run scripts/dds_compare/dds_check.dart --driver <path> \
///       [--trials N] [--mindepth N] [--maxdepth N] [--seed N]
///
/// Positions get random trumps and leaders, and ~40% include a partial
/// trick of 1-3 legal cards. DDS reports tricks for the side of the
/// player to move; ours reports North-South tricks including the trick
/// in progress. Both are normalized to North-South for comparison.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/cards/card.dart';

int ddsSuit(Suit s) => 3 - s.index; // DDS: 0=S 1=H 2=D 3=C
int ddsRank(Rank r) => r.index + 2; // DDS: 2..14

class Position {
  final List<List<PlayingCard>> hands; // remaining, after trick cards
  final Suit? trump;
  final int leader;
  final List<PlayingCard> trickCards;

  Position(this.hands, this.trump, this.leader, this.trickCards);

  int get depth =>
      (hands.fold(0, (n, h) => n + h.length) + trickCards.length) ~/ 4;

  String toDriverLine() {
    final parts = <int>[
      trump == null ? 4 : ddsSuit(trump!),
      leader,
      trickCards.length,
      for (final c in trickCards) ...[ddsSuit(c.suit), ddsRank(c.rank)],
    ];
    for (int h = 0; h < 4; h++) {
      for (int s = 0; s < 4; s++) {
        final suit = Suit.values[3 - s];
        int mask = 0;
        for (final c in hands[h]) {
          if (c.suit == suit) mask |= 1 << ddsRank(c.rank);
        }
        parts.add(mask);
      }
    }
    return parts.join(" ");
  }

  @override
  String toString() {
    final handStr = [
      for (int h = 0; h < 4; h++)
        "${"NESW"[h]}: ${PlayingCard.stringFromCards(hands[h])}"
    ].join("  ");
    return "trump=${trump?.asciiChar ?? 'NT'} leader=${"NESW"[leader]} "
        "trick=[${PlayingCard.stringFromCards(trickCards)}] $handStr";
  }
}

Position randomPosition(Random rng, int minDepth, int maxDepth) {
  final depth = minDepth + rng.nextInt(maxDepth - minDepth + 1);
  final deck = List.of(standardDeckCards())..shuffle(rng);
  final hands = [
    for (int h = 0; h < 4; h++) deck.sublist(h * depth, (h + 1) * depth)
  ];
  final trumpChoice = rng.nextInt(5);
  final trump = trumpChoice == 4 ? null : Suit.values[trumpChoice];
  final leader = rng.nextInt(4);
  final trickCards = <PlayingCard>[];
  if (rng.nextDouble() < 0.4) {
    final numTrickCards = 1 + rng.nextInt(3);
    for (int i = 0; i < numTrickCards; i++) {
      final seat = (leader + i) % 4;
      final hand = hands[seat];
      List<PlayingCard> legal = hand;
      if (trickCards.isNotEmpty) {
        final ledSuit = trickCards[0].suit;
        final following = hand.where((c) => c.suit == ledSuit).toList();
        if (following.isNotEmpty) legal = following;
      }
      final card = legal[rng.nextInt(legal.length)];
      hand.remove(card);
      trickCards.add(card);
    }
  }
  return Position(hands, trump, leader, trickCards);
}

void main(List<String> args) async {
  String? driverPath;
  int trials = 2000;
  int seed = 42;
  int minDepth = 2;
  int maxDepth = 8;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--driver":
        driverPath = args[++i];
      case "--trials":
        trials = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--mindepth":
        minDepth = int.parse(args[++i]);
      case "--maxdepth":
        maxDepth = int.parse(args[++i]);
    }
  }
  if (driverPath == null) {
    print("--driver <path to dds_driver binary> is required "
        "(see dds_driver.cpp for build instructions)");
    exit(1);
  }

  final rng = Random(seed);
  final positions = [
    for (int i = 0; i < trials; i++) randomPosition(rng, minDepth, maxDepth)
  ];

  // Solve ours.
  final ourNs = <int>[];
  int ourNodes = 0;
  final ourWatch = Stopwatch()..start();
  for (final p in positions) {
    final solver = DDSolver.fromHands(p.hands, p.trump, p.leader);
    for (final c in p.trickCards) {
      solver.addTrickCard(c);
    }
    ourNs.add(solver.solve());
    ourNodes += solver.nodesSearched;
  }
  ourWatch.stop();

  // Solve with DDS via the driver.
  final ddsWatch = Stopwatch()..start();
  final proc = await Process.start(driverPath, []);
  final outLines = proc.stdout
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter())
      .toList();
  for (final p in positions) {
    proc.stdin.writeln(p.toDriverLine());
  }
  await proc.stdin.close();
  final ddsOut = await outLines;
  ddsWatch.stop();
  if (ddsOut.length != positions.length) {
    print("DDS driver returned ${ddsOut.length} lines for "
        "${positions.length} positions");
    exit(1);
  }

  int mismatches = 0;
  int ddsNodes = 0;
  for (int i = 0; i < positions.length; i++) {
    final p = positions[i];
    if (ddsOut[i].startsWith("ERR")) {
      print("DDS error on position $i: ${ddsOut[i]}\n  $p");
      mismatches++;
      continue;
    }
    final ddsParts = ddsOut[i].split(" ");
    final score = int.parse(ddsParts[0]);
    ddsNodes += int.parse(ddsParts[1]);
    final mover = (p.leader + p.trickCards.length) % 4;
    final ddsNs = mover % 2 == 0 ? score : p.depth - score;
    if (ddsNs != ourNs[i]) {
      mismatches++;
      print("MISMATCH position $i: ours=${ourNs[i]} dds=$ddsNs");
      print("  $p");
      print("  driver line: ${p.toDriverLine()}");
    }
  }
  print("$trials positions (depth $minDepth-$maxDepth), "
      "$mismatches mismatches");
  print("time: ours ${ourWatch.elapsedMilliseconds}ms, "
      "dds ${ddsWatch.elapsedMilliseconds}ms");
  print("nodes: ours $ourNodes, dds $ddsNodes "
      "(ratio ${(ourNodes / max(1, ddsNodes)).toStringAsFixed(1)}x); "
      "ns/node: ours ${(ourWatch.elapsedMicroseconds * 1000 / max(1, ourNodes)).toStringAsFixed(0)}, "
      "dds ${(ddsWatch.elapsedMicroseconds * 1000 / max(1, ddsNodes)).toStringAsFixed(0)}");
  exit(mismatches == 0 ? 0 : 1);
}
