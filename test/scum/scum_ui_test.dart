import 'dart:math';

import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum_ui.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Builds a match whose previous round finished with player 0 last, so the
  // human is Scum in the new round: their mandatory trade is pre-selected and
  // the exchange can start immediately.
  ScumMatch matchWithHumanAsScum() {
    final match = ScumMatch(ScumRuleSet(), Random(9));
    final order = [1, 2, 3, 0];
    for (int position = 0; position < order.length; position++) {
      final player = match.currentRound.players[order[position]];
      player.hand.clear();
      player.finishPosition = position;
    }
    match.finishRound();
    return match;
  }

  Widget makeDisplay(ScumMatch match) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          ScumMatchDisplay(
            initialMatchFn: () => match,
            createMatchFn: () => ScumMatch(ScumRuleSet(), Random()),
            saveMatchFn: (_) {},
            mainMenuFn: () {},
            dialogVisible: false,
            catImageIndices: const [0, 1, 2, 3],
            matchUpdateStream: const Stream.empty(),
            soundPlayer: SoundEffectPlayer(),
          ),
        ]),
      ),
    );
  }

  testWidgets("renders hand and role badges in the trading phase",
      (tester) async {
    final match = matchWithHumanAsScum();
    await tester.pumpWidget(makeDisplay(match));
    await tester.pump();

    expect(find.textContaining("You're Scum"), findsOneWidget);
    expect(find.text("Exchange cards"), findsOneWidget);
  });

  testWidgets("exchange starts play and reaches the human's turn",
      (tester) async {
    final match = matchWithHumanAsScum();
    await tester.pumpWidget(makeDisplay(match));
    await tester.pump();

    await tester.tap(find.text("Exchange cards"));
    await tester.pump();

    // The AI cats take their turns (650 ms apart) until it is the human's
    // turn and the action buttons appear.
    Finder actionButton() =>
        find.widgetWithText(ElevatedButton, "Pass").evaluate().isNotEmpty
            ? find.widgetWithText(ElevatedButton, "Pass")
            : find.widgetWithText(ElevatedButton, "Play");

    var found = false;
    for (int i = 0; i < 12 && !found; i++) {
      await tester.pump(const Duration(milliseconds: 700));
      found = actionButton().evaluate().isNotEmpty;
    }
    expect(found, isTrue,
        reason: "Human turn controls never appeared after exchanging");
  });
}
