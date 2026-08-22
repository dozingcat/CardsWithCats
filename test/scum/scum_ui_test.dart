import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum_ui.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finishes the current round instantly with `order` (player indices, best
/// first) and advances the match into the next round's trading phase.
ScumMatch matchWithFinishOrder(List<int> order, [int seed = 9]) {
  final match = ScumMatch(ScumRuleSet(), Random(seed));
  for (int position = 0; position < order.length; position++) {
    final player = match.currentRound.players[order[position]];
    player.hand.clear();
    player.finishPosition = position;
  }
  match.finishRound();
  return match;
}

void main() {
  // Builds a match whose previous round finished with player 0 last, so the
  // human is Scum in the new round: their mandatory trade is pre-selected and
  // the exchange can start immediately.
  ScumMatch matchWithHumanAsScum() => matchWithFinishOrder([1, 2, 3, 0]);

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
    for (int i = 0; i < 40 && !found; i++) {
      await tester.pump(const Duration(milliseconds: 700));
      found = actionButton().evaluate().isNotEmpty;
    }
    expect(found, isTrue,
        reason: "Human turn controls never appeared after exchanging");
  });

  testWidgets("issue #2: president can select cards to give away",
    (tester) async {
  final match = matchWithFinishOrder([0, 1, 2, 3], 31);
  expect(match.currentRound.roleForPlayer(0), ScumRole.president);

  await tester.pumpWidget(makeDisplay(match));
  await tester.pump();

  expect(find.textContaining("You're President"), findsOneWidget);
  expect(find.text("Select 2 more"), findsOneWidget);

  final handCardFinders = find.byWidgetPredicate((w) => w is PositionedCard);
  expect(handCardFinders.evaluate().length, 13);

  final firstCard = tester.widget<PositionedCard>(handCardFinders.first).card;
  await tester.tap(handCardFinders.first);
  await tester.pump();
  expect(find.text("Select 1 more"), findsOneWidget);

  final secondFinder = find.byWidgetPredicate(
      (w) => w is PositionedCard && w.card != firstCard).first;
  await tester.tap(secondFinder);
  await tester.pump();
  expect(find.text("Exchange cards"), findsOneWidget);

  await tester.tap(find.text("Exchange cards"));
  await tester.pump();
  expect(find.text("Exchange cards"), findsNothing);

  // Let the turn scheduler reach its quiescent state (the human leads).
  await tester.pump(const Duration(milliseconds: 450));
  expect(find.widgetWithText(ElevatedButton, "Play"),
      findsOneWidget);
});

testWidgets("issue #4: tapping a card selects every copy of that rank",
    (tester) async {
  final match = ScumMatch(ScumRuleSet(), Random(5));
  final round = match.currentRound;

  // Deterministic setup: the human leads with a known pair of sevens.
  final pair = [
    PlayingCard(Rank.seven, Suit.spades),
    PlayingCard(Rank.seven, Suit.hearts),
  ];
  final deck = standardDeckCards()..shuffle(Random(77));
  deck.removeWhere(pair.contains);
  round.players[0].hand
    ..clear()
    ..addAll(pair)
    ..addAll([deck.removeAt(0), deck.removeAt(0), deck.removeAt(0)]);
  for (int i = 1; i < 4; i++) {
    round.players[i].hand
      ..clear()
      ..addAll([deck.removeAt(0), deck.removeAt(0)]);
  }
  round.seatOrder = [0, 1, 2, 3];
  round.currentTrick = ScumTrick(0);

  await tester.pumpWidget(makeDisplay(match));
  await tester.pump();
  // Flush the initial turn-scheduler delay so the action buttons appear.
  await tester.pump(const Duration(milliseconds: 700));

  // Tapping one seven selects both.
  final sevenOfSpades =
      find.byWidgetPredicate((w) => w is PositionedCard && w.card == pair[0]);
  expect(sevenOfSpades, findsOneWidget);
  await tester.tap(sevenOfSpades);
  await tester.pump();

  final playButton =
      find.widgetWithText(ElevatedButton, "Play");
  expect(playButton, findsOneWidget);
  await tester.tap(playButton);
  await tester.pump();

  // Both sevens are now on the table.
  final playedSevens = find.byWidgetPredicate((w) =>
      w is PositionedCard &&
      w.card.rank == Rank.seven &&
      !round.players[0].hand.contains(w.card));
  expect(playedSevens, findsNWidgets(2));

  // Drain the remaining turn timers so the widget tree is disposed quietly.
  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 700));
  }
});

testWidgets("issue #3: a forced pass happens without user input",
    (tester) async {
  final match = ScumMatch(ScumRuleSet(), Random(11));
  final round = match.currentRound;

  // The human holds only the 2♣, which can never legally beat anything,
  // so every turn they take must be an automatic pass.
  final deck = standardDeckCards()..shuffle(Random(3));
  deck.remove(PlayingCard(Rank.two, Suit.clubs));
  round.players[0].hand
    ..clear()
    ..add(PlayingCard(Rank.two, Suit.clubs));
  for (int i = 1; i < 4; i++) {
    round.players[i].hand
      ..clear()
      ..addAll([deck.removeAt(0), deck.removeAt(0)]);
  }
  round.seatOrder = [1, 2, 3, 0];
  round.currentTrick = ScumTrick(1);

  await tester.pumpWidget(makeDisplay(match));
  await tester.pump();

  var passed = false;
  for (int i = 0; i < 12 && !passed; i++) {
    await tester.pump(const Duration(milliseconds: 700));
    passed = round.currentTrick.actions
        .any((a) => a.player == 0 && a.isPass);
    expect(find.text("Pass"), findsNothing,
        reason: "forced passes should be automatic, no Pass button");
  }
  expect(passed, isTrue,
      reason: "human with no legal plays was not auto-passed");

  // Drain the remaining turn timers so the tree disposes quietly.
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 700));
    if (find.text("Continue").evaluate().isNotEmpty) {
      await tester.tap(find.text("Continue"));
    }
  }
});
}
