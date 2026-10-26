import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:cards_with_cats/rook/rook.dart';
import 'package:cards_with_cats/rook_ui.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpFor(WidgetTester tester, int millis) async {
  for (int t = 0; t < millis; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Taps the visible top left corner of a card in the human player's hand.
Future<void> tapHandCard(WidgetTester tester, PlayingCard card) async {
  final finder = find.byWidgetPredicate((w) => w is PositionedCard && w.card == card && w.onCardClicked != null);
  expect(finder, findsOneWidget, reason: "card $card");
  final rect = tester.getRect(finder);
  await tester.tapAt(rect.topLeft + const Offset(6, 10));
  await tester.pump();
}

void main() {
  testWidgets("Pass out, bid, discard, play a round", (tester) async {
    tester.view.physicalSize = const Size(1000, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rng = Random(42);
    late RookMatch match;
    RookMatch createMatch() {
      match = RookMatch(RookRuleSet(), rng);
      // Human bids first.
      match.dealer = 3;
      match.currentRound = RookRound.deal(rules: match.rules, scores: [0, 0], dealer: 3, rng: rng);
      return match;
    }

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [
      Container(color: const Color.fromRGBO(0, 128, 0, 1.0)),
      ...[1, 2, 3].map((i) => Builder(builder: (context) => AiPlayerImage(layout: computeLayout(context), playerIndex: i, catImageIndex: i))),
      RookMatchDisplay(
        initialMatchFn: createMatch,
        createMatchFn: createMatch,
        saveMatchFn: (m) {},
        mainMenuFn: () {},
        dialogVisible: false,
        catImageIndices: const [0, 1, 2, 3],
        tintTrumpCards: true,
        matchUpdateStream: StreamController.broadcast().stream,
        soundPlayer: SoundEffectPlayer(),
        statsStore: InMemoryStatsStore(),
        cardImageSet: defaultCardImageSet,
      ),
    ]))));
    await tester.pump();

    // Passed out round: human passes, AIs pass, redeal.
    expect(find.text("Bid 70"), findsOneWidget);
    expect(find.text("70"), findsOneWidget);
    // The bid table shows "?" for the current bidder.
    expect(find.text("?"), findsOneWidget);
    await tester.tap(find.text("Pass"));
    await pumpFor(tester, 1100);
    // The human's pass is in the table, and the bid controls are gone.
    expect(find.text("Pass"), findsNWidgets(2));
    expect(find.text("Bid 70"), findsNothing);
    await pumpFor(tester, 2500);
    expect(match.currentRound.isPassedOut(), true);
    expect(find.text("Pass"), findsNWidgets(4));
    expect(find.text("?"), findsNothing);
    expect(find.text("Everyone passed. The cards will be redealt."), findsOneWidget);
    await tester.tap(find.text("Redeal"));
    await tester.pump();
    expect(match.currentRound.bidHistory, isEmpty);
    expect(find.text("Bid 70"), findsOneWidget);
    expect(find.text("Pass"), findsOneWidget);

    // Bid 80, AIs pass.
    await tester.tap(find.text("+"));
    await tester.pump();
    await tester.tap(find.text("+"));
    await tester.pump();
    expect(find.text("Bid 80"), findsOneWidget);
    await tester.tap(find.text("–"));
    await tester.tap(find.text("+"));
    await tester.pump();
    await tester.tap(find.text("Bid 80"));
    await pumpFor(tester, 1100);
    // Controls are disabled while others bid, and the next minimum is 85.
    expect(find.text("80"), findsOneWidget);
    expect(find.text("Bid 85"), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, "Bid 85")).onPressed, isNull);
    await pumpFor(tester, 2400);
    final round = match.currentRound;
    expect(round.status, RookRoundStatus.declarerChoosingCardsAndTrump);
    expect(find.textContaining("You won the bid at 80"), findsOneWidget);

    // Choose 5 non-point cards (works with either discard rule).
    final discards = round.declarerAvailableCards()
        .where((c) => pointsForCard(c, round.rules) == 0).take(5).toList();
    for (final c in discards.take(3)) {
      await tapHandCard(tester, c);
    }
    expect(find.text("Select 2 more"), findsOneWidget);
    for (final c in discards.skip(3)) {
      await tapHandCard(tester, c);
    }
    expect(find.text("Choose trump"), findsOneWidget);
    await tester.tap(find.text("♥"));
    await tester.pump();
    await tester.tap(find.text("Start round"));
    await tester.pump();
    expect(round.status, RookRoundStatus.playing);
    expect(round.contract!.trump, Suit.hearts);
    expect(round.finalNest.toSet(), discards.toSet());
    expect(round.players[0].hand.length, 9);

    // Play the round, always choosing the first legal card.
    for (int steps = 0; steps < 2000 && !round.isOver(); steps++) {
      if (round.currentPlayerIndex() == 0 && round.currentTrick.cards.length < 4) {
        await tapHandCard(tester, round.legalPlaysForCurrentPlayer().first);
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(round.isOver(), true);
    await pumpFor(tester, 2500);
    expect(find.text("Round score"), findsOneWidget);
    await tester.tap(find.text("Continue"));
    await tester.pump();
    expect(match.previousRounds.length, 1);
    expect(match.currentRound.dealer, 0);
    // Let the AI players bid, so no timers are pending when the test ends.
    await pumpFor(tester, 3500);
    expect(find.text("Bid 70"), findsOneWidget);
    expect(find.text("Pass"), findsNWidgets(4));
  });

  testWidgets("Bid table skips players who passed", (tester) async {
    // P0 and P1 keep bidding after P2 and P3 pass.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: BidTable(
      headerCells: const [Text("P0"), Text("P1"), Text("P2"), Text("P3")],
      entries: const [
        BidTableEntry(1, "70"),
        BidTableEntry(2, "Pass"),
        BidTableEntry(3, "75"),
        BidTableEntry(0, "Pass"),
        BidTableEntry(1, "80"),
        BidTableEntry(3, "85"),
      ],
      firstBidder: 1,
      nextBidder: 1,
    )))));

    Offset at(String text, {int index = 0}) => tester.getCenter(find.text(text).at(index));
    // Columns match headers.
    expect(at("70").dx, at("P1").dx);
    expect(at("75").dx, at("P3").dx);
    expect(at("Pass", index: 1).dx, at("P0").dx);
    expect(at("80").dx, at("P1").dx);
    expect(at("85").dx, at("P3").dx);
    expect(at("?").dx, at("P1").dx);
    // Rows: P0's pass wraps to the second row, 80 and 85 are on that row, and
    // the next bid for P1 wraps to a third row.
    expect(at("70").dy, at("75").dy);
    expect(at("Pass", index: 1).dy, greaterThan(at("70").dy));
    expect(at("80").dy, at("Pass", index: 1).dy);
    expect(at("85").dy, at("80").dy);
    expect(at("?").dy, greaterThan(at("85").dy));
  });
}
