/// Fuzzes the SAYC engine by injecting random legal calls into self-play
/// auctions: whatever nonsense a partner or opponent produces, the engine
/// must respond legally, without exceptions, and only with bids whose
/// advertised meaning its hand actually satisfies.
import "dart:math";

import "package:cards_with_cats/bridge/sayc/selfplay.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("engine stays legal and consistent under injected chaos calls", () {
    int injected = 0;
    for (int i = 0; i < 500; i++) {
      final result = runDeal(dealHands(20260821, i),
          chaosRng: Random(31 * i + 7), chaosProbability: 0.15);
      injected += result.injectedCalls;
      final hard = result.findings
          .where((f) => hardFailureCategories.contains(f.category))
          .toList();
      expect(hard, isEmpty,
          reason: "deal $i, auction: ${result.history.join(' ')}\n"
              "${hard.join('\n')}");
    }
    // The fuzz should actually have exercised unusual auctions.
    expect(injected, greaterThan(500));
  });
}
