import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:cards_with_cats/five_hundred/five_hundred.dart';
import 'package:cards_with_cats/five_hundred/five_hundred_ai.dart';
import 'package:cards_with_cats/five_hundred_ui.dart';
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

// Shows a match where the human player bids first. Returns a function that
// gets the current match, since it's replaced when a new match starts.
Future<FiveHundredMatch Function()> pumpFiveHundredMatch(
    WidgetTester tester, Random rng, FiveHundredAiFunctions aiFunctions,
    {void Function(FiveHundredRound)? setUpRound}) async {
  tester.view.physicalSize = const Size(1000, 750);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late FiveHundredMatch match;
  FiveHundredMatch createMatch() {
    match = FiveHundredMatch(FiveHundredRuleSet(), rng);
    match.dealer = 3;
    match.currentRound = FiveHundredRound.deal(rules: match.rules, scores: [0, 0], dealer: 3, rng: rng);
    setUpRound?.call(match.currentRound);
    return match;
  }

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [
    Container(color: const Color.fromRGBO(0, 128, 0, 1.0)),
    ...[1, 2, 3].map((i) => Builder(builder: (context) => AiPlayerImage(layout: computeLayout(context), playerIndex: i, catImageIndex: i))),
    FiveHundredMatchDisplay(
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
      aiFunctions: aiFunctions,
    ),
  ]))));
  return () => match;
}

// Plays the rest of the round, with the human always choosing the first legal
// card (and hearts if leading the joker in no trump).
Future<void> playOutRound(WidgetTester tester, FiveHundredRound round) async {
  for (int steps = 0; steps < 2000 && !round.isOver(); steps++) {
    if (round.currentPlayerIndex() == 0 && round.currentTrick.cards.length < 4) {
      final card = round.legalPlaysForCurrentPlayer().first;
      await tapHandCard(tester, card);
      if (round.needsJokerLeadSuit(card)) {
        await tester.tap(find.widgetWithText(ElevatedButton, "♥"));
        await tester.pump();
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(round.isOver(), true);
}

void giveHumanTheJoker(FiveHundredRound round) {
  final hand = round.players[0].hand;
  if (hand.contains(joker)) {
    return;
  }
  for (int p = 1; p < numPlayers; p++) {
    final i = round.players[p].hand.indexOf(joker);
    if (i >= 0) {
      round.players[p].hand[i] = hand[0];
      hand[0] = joker;
      return;
    }
  }
  final k = round.initialKitty.indexOf(joker);
  round.initialKitty = List.of(round.initialKitty)..[k] = hand[0];
  hand[0] = joker;
}

void main() {
  testWidgets("Pass out, bid no trump, discard, lead the joker", (tester) async {
    final rng = Random(42);
    final getMatch = await pumpFiveHundredMatch(tester, rng, FiveHundredAiFunctions(
      chooseBid: (args) => null,
      chooseDiscards: (round) => chooseDiscards(round, rng),
      chooseCard: (round) => chooseCardRandom(round, rng),
      runInIsolate: false,
    ));
    await tester.pump();

    // Passed out round: human passes, AIs pass, redeal.
    expect(find.text("Bid 6♠ (40)"), findsOneWidget);
    expect(find.text("?"), findsOneWidget);
    await tester.tap(find.text("Pass"));
    await pumpFor(tester, 3500);
    expect(getMatch().currentRound.isPassedOut(), true);
    expect(find.text("Pass"), findsNWidgets(4));
    expect(find.text("Everyone passed. The cards will be redealt."), findsOneWidget);
    await tester.tap(find.text("Redeal"));
    await tester.pump();
    expect(getMatch().currentRound.bidHistory, isEmpty);
    giveHumanTheJoker(getMatch().currentRound);
    await tester.pump();

    // Choose 7 no trump, then go back down to 6.
    await tester.tap(find.text("+"));
    await tester.pump();
    await tester.tap(find.text("NT"));
    await tester.pump();
    expect(find.text("Bid 7NT (220)"), findsOneWidget);
    await tester.tap(find.text("–"));
    await tester.pump();
    await tester.tap(find.text("Bid 6NT (120)"));
    await pumpFor(tester, 3500);
    final round = getMatch().currentRound;
    expect(round.status, FiveHundredRoundStatus.declarerDiscarding);
    expect(find.textContaining("You won the bid at 6NT"), findsOneWidget);

    // Discard 3 cards other than the joker.
    final discards = round.declarerAvailableCards().where((c) => c != joker).take(3).toList();
    for (final c in discards.take(2)) {
      await tapHandCard(tester, c);
    }
    expect(find.text("Select 1 more"), findsOneWidget);
    await tapHandCard(tester, discards.last);
    await tester.tap(find.text("Start round"));
    await tester.pump();
    expect(round.status, FiveHundredRoundStatus.playing);
    expect(round.contract!.bid, const FiveHundredBid(6, null));
    expect(round.discards.toSet(), discards.toSet());
    expect(round.players[0].hand, contains(joker));

    // Lead the joker, cancel, then lead it again and choose hearts.
    expect(round.currentPlayerIndex(), 0);
    await tapHandCard(tester, joker);
    expect(find.text("Choose the suit that other players must follow."), findsOneWidget);
    await tester.tap(find.text("Cancel"));
    await tester.pump();
    expect(round.currentTrick.cards, isEmpty);
    await tapHandCard(tester, joker);
    await tester.tap(find.widgetWithText(ElevatedButton, "♥"));
    await tester.pump();
    expect(round.currentTrick.cards, [joker]);
    expect(round.currentJokerLeadSuit(), Suit.hearts);
    await pumpFor(tester, 300);
    expect(find.text("Joker led as "), findsNothing);
    expect(find.textContaining("Joker led as", findRichText: true), findsOneWidget);

    await playOutRound(tester, round);
    expect(round.previousTricks.first.winner, 0);
    await pumpFor(tester, 2500);
    expect(find.text("Tricks taken"), findsOneWidget);
    await tester.tap(find.text("Continue"));
    await tester.pump();
    expect(getMatch().previousRounds.length, 1);
    expect(getMatch().currentRound.dealer, 0);
    // Let the AI players bid, so no timers are pending when the test ends.
    await pumpFor(tester, 3500);
  });

  testWidgets("AI player wins the bid and discards", (tester) async {
    final rng = Random(5);
    // AI players bid 6 hearts if nobody has bid, and otherwise pass.
    final getMatch = await pumpFiveHundredMatch(tester, rng, FiveHundredAiFunctions(
      chooseBid: (args) => args.$1.bidHistory.every((b) => b.isPass) ? const FiveHundredBid(6, Suit.hearts) : null,
      chooseDiscards: (round) => chooseDiscards(round, rng),
      chooseCard: (round) => chooseCardRandom(round, rng),
      runInIsolate: false,
    ));
    await tester.pump();
    await tester.tap(find.text("Pass"));
    // P1 bids 6♥, P2 and P3 pass, then P1 discards.
    await pumpFor(tester, 4500);
    final round = getMatch().currentRound;
    expect(round.status, FiveHundredRoundStatus.playing);
    expect(round.contract!.declarer, 1);
    expect(find.textContaining("won the bid at 6♥"), findsOneWidget);
    // Nobody plays until the dialog is dismissed.
    await pumpFor(tester, 2000);
    expect(round.currentTrick.cards, isEmpty);
    await tester.tap(find.text("Start round"));
    await tester.pump();

    await playOutRound(tester, round);
    await pumpFor(tester, 2500);
    expect(find.text("Round score"), findsOneWidget);
    await tester.tap(find.text("Continue"));
    await tester.pump();
    // Let the AI players bid, so no timers are pending when the test ends.
    await pumpFor(tester, 4000);
  });

  testWidgets("Defenders are happy on the trick that sets the contract", (tester) async {
    final rng = Random(7);
    final getMatch = await pumpFiveHundredMatch(tester, rng, FiveHundredAiFunctions(
      chooseBid: (args) => null,
      chooseDiscards: (round) => chooseDiscards(round, rng),
      chooseCard: (round) => chooseCardRandom(round, rng),
      runInIsolate: false,
    ));
    await tester.pump();
    // Bid 10 tricks, so the first trick the defenders take sets the contract.
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.text("+"));
      await tester.pump();
    }
    await tester.tap(find.text("Bid 10♠ (440)"));
    await pumpFor(tester, 3500);
    final round = getMatch().currentRound;
    for (final c in round.declarerAvailableCards().take(3)) {
      await tapHandCard(tester, c);
    }
    await tester.tap(find.text("Start round"));
    await tester.pump();

    bool sawSet = false;
    for (int steps = 0; steps < 2000 && !round.isOver() && !sawSet; steps++) {
      if (round.currentPlayerIndex() == 0 && round.currentTrick.cards.length < 4) {
        await tapHandCard(tester, round.legalPlaysForCurrentPlayer().first);
      }
      await tester.pump(const Duration(milliseconds: 50));
      if (round.tricksTakenByTeam()[1] == 1) {
        sawSet = true;
        // Moods are shown after the last card of the trick is animated.
        await pumpFor(tester, 300);
        Finder mood(int player, Mood m) =>
            find.byWidgetPredicate((w) => w is MoodBubble && w.playerIndex == player && w.mood == m);
        expect(mood(1, Mood.happy), findsOneWidget);
        expect(mood(3, Mood.happy), findsOneWidget);
        expect(mood(2, Mood.mad), findsOneWidget);
      }
    }
    expect(sawSet, true);
    await playOutRound(tester, round);
    await pumpFor(tester, 2500);
    await tester.tap(find.text("Continue"));
    await tester.pump();
    await pumpFor(tester, 3500);
  });
}
