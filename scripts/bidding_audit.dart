/// Runs self-play auctions over many random deals and reports findings
/// grouped by category and rule, for auditing bidding-rule consistency
/// (e.g. rules whose hand requirements don't match their advertised
/// meaning ranges).
///
///   dart run scripts/bidding_audit.dart [--deals N] [--seed N] [--category X]
library;

import 'package:cards_with_cats/bridge/sayc/selfplay.dart';

void main(List<String> args) {
  int deals = 2000;
  int seed = 1;
  String? category;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        deals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--category":
        category = args[++i];
    }
  }
  final counts = <String, int>{};
  final examples = <String, List<String>>{};
  for (int i = 0; i < deals; i++) {
    final result = runDeal(dealHands(seed, i));
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
      "over $deals deals");
}
