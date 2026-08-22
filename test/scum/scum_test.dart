import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:flutter_test/flutter_test.dart';

PlayingCard card(String s) => PlayingCard.cardFromString(s);

ScumRound roundInPlay({Random? rng}) {
  final match = ScumMatch(ScumRuleSet(), rng ?? Random(1));
  return match.currentRound;
}

/// Finishes the current round instantly with the given finish order
/// (player indices, best first).
void forceFinishRound(ScumMatch match, List<int> order) {
  for (int position = 0; position < order.length; position++) {
    final player = match.currentRound.players[order[position]];
    player.hand.clear();
    player.finishPosition = position;
  }
}

void main() {
  test("Deal gives every player 13 cards", () {
    final round = roundInPlay();
    expect(round.players.length, 4);
    for (final p in round.players) {
      expect(p.hand.length, 13);
    }
    // All cards unique.
    final allCards = [for (final p in round.players) ...p.hand];
    expect(Set.of(allCards).length, 52);
  });

  test("First round: everyone is a Citizen and no trading occurs", () {
    final round = roundInPlay();
    expect(round.firstRound, isTrue);
    expect(round.status, ScumRoundStatus.playing);
    for (int i = 0; i < 4; i++) {
      expect(round.displayNameForPlayer(i), "Citizen");
      expect(round.numCardsToSelectForTrade(i), 0);
    }
    expect(round.readyToExchange(), isFalse);
  });

  test("Later rounds assign rank names by finish order", () {
    final match = ScumMatch(ScumRuleSet(), Random(21));
    forceFinishRound(match, [2, 0, 3, 1]);
    match.finishRound();
    final round = match.currentRound;
    expect(round.firstRound, isFalse);
    expect(round.displayNameForPlayer(2), "President");
    expect(round.displayNameForPlayer(0), "Vice President");
    expect(round.displayNameForPlayer(3), "Vice Scum");
    expect(round.displayNameForPlayer(1), "Scum");
  });

  test("First round starts playing immediately with a random leader", () {
    final round = roundInPlay();
    expect(round.status, ScumRoundStatus.playing);
    expect(round.currentPlayerIndex(), round.seatOrder[0]);
  });

  test("Leader must play; followers may pass", () {
    final round = roundInPlay();
    expect(round.canCurrentPlayerPass(), isFalse);
    expect(() => round.pass(), throwsException);
    // Play a single.
    round.playCards([round.players[round.currentPlayerIndex()].hand.last]);
    expect(round.canCurrentPlayerPass(), isTrue);
  });

  test("Followers must play same count with higher rank", () {
    final round = roundInPlay();
    final leaderIndex = round.currentPlayerIndex();
    final leaderHand = round.players[leaderIndex].hand;
    leaderHand.sort((a, b) => a.rank.index - b.rank.index);
    final lowCard = leaderHand.first;
    round.playCards([lowCard]);

    // Invalid: a card lower than the lead rank (when the follower has one).
    final follower = round.players[round.currentPlayerIndex()];
    follower.hand.sort((a, b) => a.rank.index - b.rank.index);
    final lowerCards =
        follower.hand.where((c) => c.rank.index < lowCard.rank.index).toList();
    if (lowerCards.isNotEmpty) {
      expect(isValidPlay(follower.hand, [lowerCards.first], round.currentTrick),
          isFalse);
    }
    // Invalid: wrong count (a pair when a single was led).
    if (follower.hand.length >= 2 &&
        follower.hand[0].rank == follower.hand[1].rank &&
        follower.hand[0].rank.index > lowCard.rank.index) {
      expect(isValidPlay(follower.hand, follower.hand.sublist(0, 2), round.currentTrick),
          isFalse);
    }
    // Valid: any card higher than the lead rank as a single.
    PlayingCard? higher;
    for (final c in follower.hand) {
      if (c.rank.index > lowCard.rank.index) {
        higher = c;
        break;
      }
    }
    expect(higher, isNotNull);
    expect(isValidPlay(follower.hand, [higher!], round.currentTrick), isTrue);
  });

  test("Playing an ace immediately completes the trick (issue #3)", () {
    final round = roundInPlay();
    final leader = round.currentPlayerIndex();
    final ace = round.players[leader].hand.firstWhere((c) => c.rank == Rank.ace);
    round.playCards([ace]);
    // No passes are collected: the trick is over and the ace player leads.
    expect(round.currentTrick.actions, isEmpty);
    expect(round.currentTrick.leader, leader);
  });

  test("Sets of the same rank may be led and beaten by bigger sets", () {
    final hand = [
      card("2H"), card("2D"),
      card("3S"), card("3C"), card("3D"),
      card("AC"), card("AH"), card("AD"), card("AS"),
      card("KS"), card("KH"), card("KD"),
      card("JC"),
    ];
    // Leading: pairs, triples, quads available.
    final leads = legalSetsForHand(hand, null);
    expect(leads.where((s) => s.length == 2).length, greaterThanOrEqualTo(1));
    expect(leads.where((s) => s.length == 3).length, greaterThanOrEqualTo(1));
    expect(leads.where((s) => s.length == 4).length, 1);

    // A pair of threes can be beaten only by a higher pair.
    final trick = ScumTrick(0)
      ..actions.add(ScumTrickAction(0, [card("3S"), card("3C")]));
    final legal = legalSetsForHand(hand, trick);
    expect(legal.map((s) => s.length), everyElement(2));
    expect(legal.any((s) => s[0].rank == Rank.ace), isTrue);
    expect(legal.any((s) => s[0].rank == Rank.king), isTrue);
    expect(legal.any((s) => s[0].rank == Rank.two), isFalse);
  });

  test("Trick completes when everyone else passes; winner leads next", () {
    final round = roundInPlay();
    int leader = round.currentPlayerIndex();
    round.playCards([round.players[leader].hand.last]);
    // Everyone else passes.
    while (!round.isOver() && round.currentTrick.actions.isNotEmpty &&
        round.currentPlayerIndex() != -1) {
      if (round.currentPlayerIndex() == leader && round.currentTrick.plays.isNotEmpty) {
        break;
      }
      if (round.canCurrentPlayerPass() && round.currentPlayerIndex() != leader) {
        round.pass();
      } else {
        break;
      }
    }
    // The best action's player should now be the new leader.
    expect(round.currentTrick.leader, leader);
    expect(round.currentTrick.actions, isEmpty);
  });

  test("Player who empties their hand finishes; last player is scum position",
      () {
    final round = roundInPlay(rng: Random(7));
    // Force a full game driven by simple AI-less logic: always play lowest
    // single if possible, else pass.
    var guard = 0;
    while (!round.isOver() && guard < 10000) {
      guard++;
      final player = round.currentPlayerIndex();
      final hand = round.players[player].hand;
      final legal = round.legalPlaysForCurrentPlayer();
      if (legal.isEmpty) {
        round.pass();
      } else {
        // Play the set that empties the hand if possible, else lowest set.
        final emptying = legal.where((s) => s.length == hand.length).toList();
        emptying.isNotEmpty
            ? round.playCards(emptying.first)
            : round.playCards(legal.reduce((a, b) =>
                a[0].rank.index <= b[0].rank.index ? a : b));
      }
    }
    expect(round.isOver(), isTrue);
    final order = round.finishOrder();
    expect(order.toSet().length, 4);
    expect(order.length, 4);
    final points = round.pointsTaken();
    expect(points[order[0]], 3);
    expect(points[order[1]], 2);
    expect(points[order[2]], 1);
    expect(points[order[3]], 0);
  });

  test("Trading pre-selects mandatory highest cards from scum players", () {
    final match = ScumMatch(ScumRuleSet(), Random(11));
    forceFinishRound(match, [0, 1, 2, 3]);
    match.finishRound();
    final round = match.currentRound;
    expect(round.status, ScumRoundStatus.trading);

    final scumSeat = round.seatOrder[3];
    final viceScumSeat = round.seatOrder[2];
    expect(round.tradeSelections[scumSeat].length, 2);
    expect(round.tradeSelections[viceScumSeat].length, 1);
    // The selections are the highest cards.
    final scumSorted = highestCards(round.players[scumSeat].hand, 2);
    expect(round.tradeSelections[scumSeat][0].rank.index,
        scumSorted[0].rank.index);
    // President/VP start unselected.
    expect(round.numCardsToSelectForTrade(round.seatOrder[0]), 2);
    expect(round.numCardsToSelectForTrade(round.seatOrder[1]), 1);
  });

  test("Exchange moves cards between roles and president leads", () {
    final match = ScumMatch(ScumRuleSet(), Random(3));
    forceFinishRound(match, [0, 1, 2, 3]);
    match.finishRound();
    final round = match.currentRound;
    // Player 0 finished first, so they are President.
    expect(round.roleForPlayer(0), ScumRole.president);
    round.setTradeSelection(round.seatOrder[0],
        highestCards(round.players[round.seatOrder[0]].hand.reversed.toList(), 2));
    round.setTradeSelection(round.seatOrder[1],
        [round.players[round.seatOrder[1]].hand.last]);
    final scumBefore = round.players[round.seatOrder[3]].hand.length;
    final presidentBefore = round.players[round.seatOrder[0]].hand.length;
    round.exchangeCards();

    expect(round.status, ScumRoundStatus.playing);
    expect(round.currentTrick.leader, round.seatOrder[0]);
    // Net hand sizes are unchanged.
    expect(round.players[round.seatOrder[3]].hand.length, scumBefore);
    expect(round.players[round.seatOrder[0]].hand.length, presidentBefore);
    // Scum received two cards from the president.
    expect(round.players[round.seatOrder[3]].receivedCards.length, 2);
    expect(round.players[round.seatOrder[0]].receivedCards.length, 2);
    expect(round.players[round.seatOrder[2]].receivedCards.length, 1);
  });

  test("Match ends after numRounds rounds and reports winners", () {
    final match = ScumMatch(ScumRuleSet(), Random(42));
    int rounds = 0;
    while (!match.isMatchOver() && rounds < 20) {
      rounds++;
      // Finish the round instantly with a random order.
      final remaining = [for (int i = 0; i < 4; i++) i]..shuffle(match.rng);
      forceFinishRound(match, remaining);
      match.finishRound();
    }
    expect(match.isMatchOver(), isTrue);
    expect(match.roundsCompleted, 8);
    expect(match.winningPlayers(), isNotEmpty);
    final totalScore = match.scores.reduce((a, b) => a + b);
    // Each round awards 6 points total.
    expect(totalScore, 6 * 8);
  });

  test("JSON serialization round-trips a match", () {
    final match = ScumMatch(ScumRuleSet(), Random(5));
    forceFinishRound(match, [2, 0, 3, 1]);
    match.finishRound();
    match.currentRound.setTradeSelection(match.currentRound.seatOrder[0],
        highestCards(match.currentRound.players[match.currentRound.seatOrder[0]].hand, 2));
    match.currentRound.setTradeSelection(match.currentRound.seatOrder[1],
        [match.currentRound.players[match.currentRound.seatOrder[1]].hand.first]);
    match.currentRound.exchangeCards();
    match.currentRound.playCards(
        [match.currentRound.players[match.currentRound.currentPlayerIndex()].hand.last]);

    final json = match.toJson();
    final restored = ScumMatch.fromJson(json, Random(5));
    expect(restored.scores, match.scores);
    expect(restored.previousRounds.length, match.previousRounds.length);
    expect(restored.currentRound.toJson(), match.currentRound.toJson());
  });
}
