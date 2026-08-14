import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge_ui.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BridgeRound playedOutRound(Random rng) {
  final match = BridgeMatch(rng);
  final round = match.currentRound;
  round.addBid(
      PlayerBid(round.currentBidder(), BidAction.contract(1, Suit.clubs)));
  for (int i = 0; i < 3; i++) {
    round.addBid(PlayerBid(round.currentBidder(), BidAction.pass()));
  }
  while (!round.isOver()) {
    final legal = round.legalPlaysForCurrentPlayer();
    round.playCard(legal[rng.nextInt(legal.length)]);
  }
  return round;
}

BridgeRound passedOutRound(Random rng) {
  final round = BridgeMatch(rng).currentRound;
  for (int i = 0; i < 4; i++) {
    round.addBid(PlayerBid(round.currentBidder(), BidAction.pass()));
  }
  return round;
}

// shortestSide of 350 gives dialogScale() of 1.0, so the dialog fits the
// test surface and its controls are tappable.
Layout testLayout() => Layout()
  ..displaySize = const Size(350, 350)
  ..playerHeight = 44
  ..padding = EdgeInsets.zero;

Widget wrapDialog(BridgeRound round, BridgeRound duplicateRound,
        {Function()? onClose}) =>
    MaterialApp(
        home: Scaffold(
            body: RoundDetailsDialog(
                layout: testLayout(),
                round: round,
                duplicateRound: duplicateRound,
                onClose: onClose ?? () {})));

void main() {
  testWidgets("details dialog shows bidding table with seat letters",
      (tester) async {
    final round = playedOutRound(Random(17));
    await tester.pumpWidget(wrapDialog(round, passedOutRound(Random(17))));

    for (final seat in ["S", "W", "N", "E"]) {
      expect(find.text(seat), findsOneWidget);
    }
    // The auction: one contract bid and three passes.
    expect(find.text(BidAction.contract(1, Suit.clubs).symbolString()),
        findsOneWidget);
    expect(find.text(BidAction.pass().symbolString()), findsNWidgets(3));
    // The contract result for the player's round shows below the toggle.
    expect(find.text(roundResultDescription(round)), findsOneWidget);
  });

  testWidgets("play tab navigates tricks and highlights the winner",
      (tester) async {
    final round = playedOutRound(Random(17));
    await tester.pumpWidget(wrapDialog(round, passedOutRound(Random(17))));

    await tester.tap(find.text("Play"));
    await tester.pump();
    expect(find.text("Trick 1 of 13"), findsOneWidget);

    bool hasWinnerBorder(Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).border as Border?)?.top.color ==
            Colors.amber;
    expect(find.byWidgetPredicate(hasWinnerBorder), findsOneWidget);

    // The center arrow points at the trick leader's card position.
    int arrowQuarterTurns() => tester
        .widget<RotatedBox>(find.ancestor(
            of: find.byIcon(Icons.arrow_upward),
            matching: find.byType(RotatedBox)))
        .quarterTurns;
    expect(arrowQuarterTurns(), (round.previousTricks[0].leader + 2) % 4);

    // Back arrow is disabled on the first trick.
    final leftButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(leftButton.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text("Trick 2 of 13"), findsOneWidget);
    expect(find.byWidgetPredicate(hasWinnerBorder), findsOneWidget);
    expect(arrowQuarterTurns(), (round.previousTricks[1].leader + 2) % 4);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text("Trick 1 of 13"), findsOneWidget);
  });

  testWidgets("round toggle switches to the duplicate round", (tester) async {
    final round = playedOutRound(Random(17));
    await tester.pumpWidget(wrapDialog(round, passedOutRound(Random(17))));

    // Advance into the player's round so we can verify the trick position
    // resets when switching rounds.
    await tester.tap(find.text("Play"));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text("Trick 2 of 13"), findsOneWidget);

    await tester.tap(find.text("Duplicate"));
    await tester.pump();
    expect(find.text("Passed out"), findsOneWidget);
    expect(find.text("No cards were played."), findsOneWidget);

    // Bidding tab for the duplicate round shows its four passes.
    await tester.tap(find.text("Bidding"));
    await tester.pump();
    expect(find.text(BidAction.pass().symbolString()), findsNWidgets(4));

    // Back on the player's round, the trick position starts over.
    await tester.tap(find.text("Your round"));
    await tester.pump();
    await tester.tap(find.text("Play"));
    await tester.pump();
    expect(find.text("Trick 1 of 13"), findsOneWidget);
  });

  testWidgets("back button invokes onClose", (tester) async {
    final round = playedOutRound(Random(17));
    bool closed = false;
    await tester.pumpWidget(wrapDialog(round, passedOutRound(Random(17)),
        onClose: () => closed = true));

    await tester.tap(find.text("Back"));
    expect(closed, isTrue);
  });
}
