/// Runs self-play auctions over many random deals and reports findings
/// grouped by category and rule, for auditing bidding-rule consistency
/// (e.g. rules whose hand requirements don't match their advertised
/// meaning ranges).
///
///   dart run scripts/bidding_audit.dart [--deals N] [--seed N] [--category X]
///       [--chaos P]
///
/// With --chaos, each call is replaced by a random legal call with
/// probability P, fuzzing the engine's responses to auctions it would
/// never produce itself.
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/sayc/selfplay.dart';

void main(List<String> args) {
  int deals = 2000;
  int seed = 1;
  double chaos = 0;
  String? category;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--category":
        category = args[++i];
      case "--chaos":
        chaos = double.parse(args[++i]);
    }
  }
  final counts = <String, int>{};
  final examples = <String, List<String>>{};
  int injected = 0;
  for (int i = 0; i < deals; i++) {
    final result = runDeal(dealHands(seed, i),
        chaosRng: chaos > 0 ? Random(seed * 31 + i) : null,
        chaosProbability: chaos);
    injected += result.injectedCalls;
    for (final f in result.findings) {
      if (category != null && f.category != category) continue;
      // Group by category plus the rule description in trailing brackets.
      final m = RegExp(r"\[(.*)\]$").firstMatch(f.message);
      final key = "${f.category}: ${m?.group(1) ?? f.message}";
      counts[key] = (counts[key] ?? 0) + 1;
      (examples[key] ??= []).add("deal $i: ${f.message}");
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  for (final k in keys) {
    print("${counts[k]!.toString().padLeft(5)}  $k");
    for (final e in examples[k]!.take(2)) {
      print("       $e");
    }
  }
  print("\ntotal: ${counts.values.fold(0, (a, b) => a + b)} findings "
      "over $deals deals"
      "${chaos > 0 ? ' ($injected chaos calls injected)' : ''}");
}
