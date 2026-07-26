/// Self-play over random deals: reports hard engine failures and heuristic
/// bidding-quality findings. Every deal is reproducible from (seed, index).
///
/// Usage: dart run bin/bridge_selfplay.dart [--deals N] [--seed S]
///          [--examples K] [--category NAME]
library;

// ignore_for_file: avoid_print

import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';

void main(List<String> args) {
  int deals = 200;
  int seed = 1;
  int maxExamples = 3;
  String? category;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == "--deals") deals = int.parse(args[++i]);
    if (args[i] == "--seed") seed = int.parse(args[++i]);
    if (args[i] == "--examples") maxExamples = int.parse(args[++i]);
    if (args[i] == "--category") category = args[++i];
  }

  final counts = <String, int>{};
  final examples = <String, List<String>>{};
  int clean = 0;
  for (int index = 0; index < deals; index++) {
    final hands = dealHands(seed, index);
    final result = runDeal(hands);
    var findings = result.findings;
    if (category != null) {
      findings = findings.where((f) => f.category == category).toList();
    }
    if (findings.isEmpty) clean++;
    for (final finding in findings) {
      counts[finding.category] = (counts[finding.category] ?? 0) + 1;
      final list = examples.putIfAbsent(finding.category, () => []);
      if (list.length < maxExamples) {
        final dealDesc = [
          for (int i = 0; i < 4; i++)
            "      seat $i: ${handGroupString(hands[i])} "
                "(${HandAnalysis(hands[i]).hcp} HCP, "
                "${HandAnalysis(hands[i]).totalPoints} total)"
        ].join("\n");
        list.add("  deal $index (seed $seed): ${finding.message}\n"
            "    auction: ${result.history.map((c) => '$c').join(' ')}\n"
            "$dealDesc");
      }
    }
  }

  print("$deals deals, $clean clean");
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted) {
    print("\n== ${entry.key}: ${entry.value}");
    for (final example in examples[entry.key] ?? []) {
      print(example);
    }
  }
}
