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

Layout testLayout() => Layout()
  ..displaySize = const Size(800, 600)
  ..playerHeight = 75
  ..padding = EdgeInsets.zero;

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets("details dialog shows bidding table with seat letters",
      (tester) async {
    final round = playedOutRound(Random(17));
    await tester.pumpWidget(wrap(DuplicateRoundDetailsDialog(
        layout: testLayout(), round: round, onClose: () {})));

    for (final seat in ["S", "W", "N", "E"]) {
      expect(find.text(seat), findsOneWidget);
    }
    // The auction: one contract bid and three passes.
    expect(find.text(BidAction.contract(1, Suit.clubs).symbolString()),
        findsOneWidget);
    expect(find.text(BidAction.pass().symbolString()), findsNWidgets(3));
  });

  testWidgets("play tab navigates tricks and highlights the winner",
      (tester) async {
    final round = playedOutRound(Random(17));
    await tester.pumpWidget(wrap(DuplicateRoundDetailsDialog(
        layout: testLayout(), round: round, onClose: () {})));

    await tester.tap(find.text("Play"));
    await tester.pump();
    expect(find.text("Trick 1 of 13"), findsOneWidget);

    bool hasWinnerBorder(Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        ((w.decoration as BoxDecoration).border as Border?)?.top.color ==
            Colors.amber;
    expect(find.byWidgetPredicate(hasWinnerBorder), findsOneWidget);

    // Back arrow is disabled on the first trick.
    final leftButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(leftButton.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text("Trick 2 of 13"), findsOneWidget);
    expect(find.byWidgetPredicate(hasWinnerBorder), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text("Trick 1 of 13"), findsOneWidget);
  });

  testWidgets("back button invokes onClose", (tester) async {
    final round = playedOutRound(Random(17));
    bool closed = false;
    await tester.pumpWidget(wrap(DuplicateRoundDetailsDialog(
        layout: testLayout(), round: round, onClose: () => closed = true)));

    await tester.tap(find.text("Back"));
    expect(closed, isTrue);
  });
}
