/// Validates the FFI binding (lib/bridge/dds_ffi.dart) against our
/// DDSolver on random positions — this checks struct layout and score
/// mapping, on top of the solver-vs-solver agreement already established
/// via the driver harness.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/dds_compare/dds_ffi_check.dart \
///       [--trials N] [--mindepth N] [--maxdepth N] [--seed N]
library;

import 'dart:io';
import 'dart:math';

import 'package:cards_with_cats/bridge/dd_solver.dart';
import 'package:cards_with_cats/bridge/dds_ffi.dart';

import 'dds_check.dart' show Position, randomPosition;

void main(List<String> args) {
  int trials = 2000;
  int seed = 42;
  int minDepth = 2;
  int maxDepth = 8;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
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
  final dds = DdsBackend.instance;
  if (dds == null) {
    print("DDS backend unavailable; set DDS_LIB to the built library "
        "(cpp/build_libdds.sh)");
    exit(1);
  }

  final rng = Random(seed);
  int mismatches = 0;
  final ourWatch = Stopwatch();
  final ddsWatch = Stopwatch();
  for (int i = 0; i < trials; i++) {
    final Position p = randomPosition(rng, minDepth, maxDepth);
    ourWatch.start();
    final solver = DDSolver.fromHands(p.hands, p.trump, p.leader);
    for (final c in p.trickCards) {
      solver.addTrickCard(c);
    }
    final ours = solver.solve();
    ourWatch.stop();
    ddsWatch.start();
    final ffi = dds.solve(p.hands, p.trump, p.leader, p.trickCards);
    ddsWatch.stop();
    if (ffi != ours) {
      mismatches++;
      print("MISMATCH: ours=$ours ffi=$ffi\n  $p");
    }
  }
  print("$trials positions (depth $minDepth-$maxDepth), "
      "$mismatches mismatches");
  print("time: ours ${ourWatch.elapsedMilliseconds}ms, "
      "dds-ffi ${ddsWatch.elapsedMilliseconds}ms "
      "(dds nodes ${dds.nodesSearched})");
  exit(mismatches == 0 ? 0 : 1);
}
