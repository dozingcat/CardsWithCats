// Tests for the double-dummy "review the play" support: reconstructing the
// position at an earlier point in a completed round, and scoring every legal
// play from that position.
//
// The tests that need the native DDS backend are skipped when it isn't
// loaded; run them with `DDS_LIB=native/libdds.dylib flutter test`
// (see cpp/build_libdds.sh).
import "dart:math";

import "package:cards_with_cats/bridge/bridge.dart";
import "package:cards_with_cats/bridge/bridge_ai.dart";
import "package:cards_with_cats/bridge/dd_solver.dart";
import "package:cards_with_cats/bridge/dds_ffi.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/trick.dart";
import "package:flutter_test/flutter_test.dart";

const c = PlayingCard.cardsFromString;

final ddsAvailable = DdsBackend.instance != null;
const ddsSkipReason =
    "Native DDS backend not loaded; set DDS_LIB (see cpp/build_libdds.sh)";

/// Bids to a contract and then plays random legal cards until the round ends.
BridgeRound playedOutRound(Random rng, {Suit? trump = Suit.spades}) {
  final round = BridgeRound.deal(rng.nextInt(4), rng);
  round.addBid(
      PlayerBid(round.currentBidder(), BidAction.contract(3, trump)));
  for (int i = 0; i < 3; i++) {
    round.addBid(PlayerBid(round.currentBidder(), BidAction.pass()));
  }
  while (!round.isOver()) {
    final legal = round.legalPlaysForCurrentPlayer();
    round.playCard(legal[rng.nextInt(legal.length)]);
  }
  return round;
}

/// A random position with [cardsPerHand] cards each and [cardsInTrick] cards
/// already played to the trick in progress, in the layout the solvers expect:
/// players who have already played hold one card fewer.
({List<List<PlayingCard>> hands, TrickInProgress trick}) randomPosition(
    Random rng, int cardsPerHand, int cardsInTrick) {
  final deck = List.of(standardDeckCards())..shuffle(rng);
  final hands = List.generate(
      4, (p) => deck.sublist(p * cardsPerHand, (p + 1) * cardsPerHand));
  final trick = TrickInProgress(rng.nextInt(4));
  for (int i = 0; i < cardsInTrick; i++) {
    final player = (trick.leader + i) % 4;
    final legal = legalPlays(hands[player], trick);
    final card = legal[rng.nextInt(legal.length)];
    hands[player].remove(card);
    trick.cards.add(card);
  }
  return (hands: hands, trick: trick);
}

/// Tricks taken by the side on play if it plays [card], computed with the
/// pure-Dart solver. Deliberately independent of the single-call DDS path:
/// it removes the card, resolves the trick if the card completes it, and
/// solves the resulting position.
int referenceTricksForSideOnPlay(List<List<PlayingCard>> hands, Suit? trump,
    TrickInProgress trick, PlayingCard card) {
  final mover = (trick.leader + trick.cards.length) % 4;
  final totalTricks = hands[mover].length;
  final handsAfter = [...hands];
  handsAfter[mover] = [...hands[mover]]..remove(card);
  final trickCards = [...trick.cards, card];

  final int nsTricks;
  if (trickCards.length == 4) {
    final winner =
        TrickInProgress(trick.leader, trickCards).finish(trump: trump).winner;
    nsTricks = DDSolver.fromHands(handsAfter, trump, winner).solve() +
        (winner % 2 == 0 ? 1 : 0);
  } else {
    final solver = DDSolver.fromHands(handsAfter, trump, trick.leader);
    for (final tc in trickCards) {
      solver.addTrickCard(tc);
    }
    nsTricks = solver.solve();
  }
  return mover % 2 == 0 ? nsTricks : totalTricks - nsTricks;
}

void main() {
  group("roundStateAtPointInPlay", () {
    test("reconstructs every position in a completed round", () {
      final leadersSeen = <int>{};
      for (int seed = 1; seed <= 5; seed++) {
        final round = playedOutRound(Random(seed));
        for (int ti = 0; ti < round.previousTricks.length; ti++) {
          final trick = round.previousTricks[ti];
          leadersSeen.add(trick.leader);
          // Every card from this trick onwards is either still in a hand or
          // already played to the trick in progress, and appears exactly once.
          final unplayed = <PlayingCard>{};
          for (int later = ti; later < round.previousTricks.length; later++) {
            unplayed.addAll(round.previousTricks[later].cards);
          }
          for (int ci = 0; ci < 4; ci++) {
            final state = roundStateAtPointInPlay(
                round: round, completedTricks: ti, cardsInCurrentTrick: ci);
            final reason = "seed $seed trick $ti leader ${trick.leader} ci $ci";

            expect(state.currentTrick.leader, trick.leader, reason: reason);
            expect(state.currentTrick.cards, trick.cards.sublist(0, ci),
                reason: reason);

            // Players who have already played to this trick hold one card
            // fewer than those who have not.
            final cardsRemaining = round.previousTricks.length - ti;
            for (int p = 0; p < 4; p++) {
              final hasPlayed = (p - trick.leader) % 4 < ci;
              expect(state.hands[p].length,
                  hasPlayed ? cardsRemaining - 1 : cardsRemaining,
                  reason: "$reason player $p");
            }

            final allHeld = [for (final h in state.hands) ...h];
            expect(allHeld.toSet().length, allHeld.length,
                reason: "$reason: a card is held twice");
            expect({...allHeld, ...state.currentTrick.cards}, unplayed,
                reason: reason);

            // The player on play must hold the card they actually played.
            final mover = (trick.leader + ci) % 4;
            expect(state.hands[mover], contains(trick.cards[ci]),
                reason: reason);
          }
        }
      }
      // The bug this guards against only showed up for tricks not led by
      // player 0, so make sure the sample actually covers those.
      expect(leadersSeen, containsAll([0, 1, 2, 3]));
    });

    test("removes cards in the trick in progress from the player who played "
        "them, not from player 0", () {
      // Regression: the removal used `% currentTrick.cards.length` instead of
      // `% 4`, so for a trick not led by player 0 the cards were removed from
      // the wrong hand (usually a no-op), leaving a player holding a card that
      // was also sitting in the trick.
      final round = playedOutRound(Random(11));
      final nonZeroLeaderTricks = [
        for (int ti = 0; ti < round.previousTricks.length; ti++)
          if (round.previousTricks[ti].leader != 0) ti
      ];
      expect(nonZeroLeaderTricks, isNotEmpty);
      for (final ti in nonZeroLeaderTricks) {
        for (int ci = 1; ci < 4; ci++) {
          final state = roundStateAtPointInPlay(
              round: round, completedTricks: ti, cardsInCurrentTrick: ci);
          for (final played in state.currentTrick.cards) {
            for (int p = 0; p < 4; p++) {
              expect(state.hands[p], isNot(contains(played)),
                  reason: "trick $ti ci $ci: $played still held by player $p");
            }
          }
        }
      }
    });

    test("rejects rounds that are not over and out-of-range indexes", () {
      final inProgress = BridgeRound.deal(0, Random(3));
      expect(
          () => roundStateAtPointInPlay(
              round: inProgress, completedTricks: 0, cardsInCurrentTrick: 0),
          throwsA(isA<Exception>()));

      final round = playedOutRound(Random(3));
      expect(
          () => roundStateAtPointInPlay(
              round: round, completedTricks: 13, cardsInCurrentTrick: 0),
          throwsRangeError);
      expect(
          () => roundStateAtPointInPlay(
              round: round, completedTricks: -1, cardsInCurrentTrick: 0),
          throwsRangeError);
      expect(
          () => roundStateAtPointInPlay(
              round: round, completedTricks: 0, cardsInCurrentTrick: 4),
          throwsRangeError);
    });
  });

  group("DdsBackend.solveAllCards", () {
    test("credits the card that wins the trick in progress", () {
      // Notrump. Player 0 led the king of spades and players 1 and 2 have
      // followed, so only their remaining cards are in the hands. Player 3
      // (E/W) is on play: the ace wins this trick and leaves the two of
      // spades good for the next one, while the two of spades loses both.
      final hands = [
        c("2C"), // player 0, N/S, already played the king of spades
        c("3C"), // player 1, E/W
        c("4C"), // player 2, N/S
        c("AS 2S"), // player 3, E/W, on play
      ];
      final result =
          DdsBackend.instance!.solveAllCards(hands, null, 0, c("KS 3S 4S"));
      expect(result, {c("AS")[0]: 2, c("2S")[0]: 0});
    });

    test("scores a lead from the leading side's perspective", () {
      // The same deal one card earlier, with player 0 (N/S) on lead. Leading
      // the king into player 3's ace concedes both tricks; leading the club
      // instead wins that trick for player 2 and holds E/W to one.
      final hands = [
        c("KS 2C"), // player 0, N/S, on lead
        c("3S 3C"), // player 1, E/W
        c("4S 4C"), // player 2, N/S
        c("AS 2S"), // player 3, E/W
      ];
      final result =
          DdsBackend.instance!.solveAllCards(hands, null, 0, const []);
      // Counted for N/S, the side on play, not for a fixed side.
      expect(result, {c("2C")[0]: 1, c("KS")[0]: 0});
    });

    test("covers exactly the legal plays", () {
      final rng = Random(29);
      for (int cardsInTrick = 0; cardsInTrick < 4; cardsInTrick++) {
        for (int i = 0; i < 15; i++) {
          final pos = randomPosition(rng, 5, cardsInTrick);
          final mover = (pos.trick.leader + cardsInTrick) % 4;
          final trump = [null, Suit.spades, Suit.hearts][i % 3];
          final result = DdsBackend.instance!
              .solveAllCards(pos.hands, trump, pos.trick.leader, pos.trick.cards);
          expect(result, isNotNull);
          expect(result!.keys.toSet(),
              legalPlays(pos.hands[mover], pos.trick).toSet(),
              reason: "trump $trump, $cardsInTrick cards in trick");
        }
      }
    });

    test("agrees with the pure-Dart solver on random endings", () {
      final rng = Random(31);
      int checked = 0;
      for (int cardsInTrick = 0; cardsInTrick < 4; cardsInTrick++) {
        for (int i = 0; i < 8; i++) {
          final pos = randomPosition(rng, 4, cardsInTrick);
          final trump = [null, Suit.spades, Suit.diamonds][i % 3];
          final result = DdsBackend.instance!
              .solveAllCards(pos.hands, trump, pos.trick.leader, pos.trick.cards);
          expect(result, isNotNull);
          for (final entry in result!.entries) {
            expect(
                entry.value,
                referenceTricksForSideOnPlay(
                    pos.hands, trump, pos.trick, entry.key),
                reason: "card ${entry.key}, trump $trump, "
                    "leader ${pos.trick.leader}, trick ${pos.trick.cards}");
            checked++;
          }
        }
      }
      expect(checked, greaterThan(50));
    });

    test("rejects a complete trick, which DDS cannot represent", () {
      final hands = [c("KS"), c("3S"), c("4S"), c("AS")];
      expect(
          () => DdsBackend.instance!
              .solveAllCards(hands, null, 0, c("KS 3S 4S AS")),
          throwsArgumentError);
    });
  }, skip: ddsAvailable ? null : ddsSkipReason);

  group("doubleDummyResultForAllCards", () {
    test("orders cards from most tricks to fewest", () {
      final rng = Random(37);
      for (int cardsInTrick = 0; cardsInTrick < 4; cardsInTrick++) {
        for (int i = 0; i < 8; i++) {
          final pos = randomPosition(rng, 5, cardsInTrick);
          final trump = i.isEven ? null : Suit.clubs;
          final result = doubleDummyResultForAllCards(
              currentTrick: pos.trick, hands: pos.hands, trump: trump);
          expect(result, isNotNull);
          final values = result!.values.toList();
          expect(values, orderedEquals([...values]..sort((a, b) => b - a)));
          expect(values.first, values.reduce(max));
        }
      }
    });

    test("agrees with the pure-Dart solver for both sides", () {
      final rng = Random(41);
      final moversSeen = <int>{};
      for (int cardsInTrick = 0; cardsInTrick < 4; cardsInTrick++) {
        for (int i = 0; i < 6; i++) {
          final pos = randomPosition(rng, 4, cardsInTrick);
          final trump = i.isEven ? null : Suit.hearts;
          moversSeen.add((pos.trick.leader + cardsInTrick) % 4);
          final result = doubleDummyResultForAllCards(
              currentTrick: pos.trick, hands: pos.hands, trump: trump);
          expect(result, isNotNull);
          for (final entry in result!.entries) {
            expect(
                entry.value,
                referenceTricksForSideOnPlay(
                    pos.hands, trump, pos.trick, entry.key),
                reason: "card ${entry.key}, trump $trump");
          }
        }
      }
      // Both N/S (even) and E/W (odd) players must be exercised, since their
      // scores come from opposite sides of the solver's convention.
      expect(moversSeen, containsAll([0, 1, 2, 3]));
    });
  }, skip: ddsAvailable ? null : ddsSkipReason);

  group("doubleDummyResultForPreviousPointInRound", () {
    test("evaluates every seat in every trick", () {
      // Regression: only the seat on lead (ci == 0) used to produce a result;
      // the other three returned null because the reconstructed deal was
      // malformed and DDS rejected it.
      final round = playedOutRound(Random(13), trump: Suit.hearts);
      for (int ti = 0; ti < round.previousTricks.length; ti++) {
        final trick = round.previousTricks[ti];
        for (int ci = 0; ci < 4; ci++) {
          final result = doubleDummyResultForPreviousPointInRound(
              round: round, completedTricks: ti, cardsInCurrentTrick: ci);
          final reason = "trick $ti leader ${trick.leader} ci $ci";
          expect(result, isNotNull, reason: reason);
          // The card actually played is always one of the evaluated options.
          expect(result!.keys, contains(trick.cards[ci]), reason: reason);
          final state = roundStateAtPointInPlay(
              round: round, completedTricks: ti, cardsInCurrentTrick: ci);
          final mover = (trick.leader + ci) % 4;
          expect(result.keys.toSet(),
              legalPlays(state.hands[mover], state.currentTrick).toSet(),
              reason: reason);
          // Tricks available to the side on play, so values are in range.
          for (final v in result.values) {
            expect(v, inInclusiveRange(0, state.hands[mover].length),
                reason: reason);
          }
        }
      }
    });

    test("matches evaluating the reconstructed position directly", () {
      for (int seed = 1; seed <= 3; seed++) {
        final round = playedOutRound(Random(seed), trump: null);
        for (final ti in [0, 4, 8, 12]) {
          for (int ci = 0; ci < 4; ci++) {
            final state = roundStateAtPointInPlay(
                round: round, completedTricks: ti, cardsInCurrentTrick: ci);
            final expected = doubleDummyResultForAllCards(
                currentTrick: state.currentTrick,
                hands: state.hands,
                trump: round.trumpSuit());
            final actual = doubleDummyResultForPreviousPointInRound(
                round: round, completedTricks: ti, cardsInCurrentTrick: ci);
            expect(actual, expected, reason: "seed $seed trick $ti ci $ci");
          }
        }
      }
    });

    test("agrees with the pure-Dart solver in the endgame", () {
      // Late tricks leave few enough cards for the pure-Dart solver to act as
      // an independent oracle over the whole reconstruct-and-score path.
      final round = playedOutRound(Random(23), trump: Suit.clubs);
      for (final ti in [9, 10, 11]) {
        for (int ci = 0; ci < 4; ci++) {
          final state = roundStateAtPointInPlay(
              round: round, completedTricks: ti, cardsInCurrentTrick: ci);
          final result = doubleDummyResultForPreviousPointInRound(
              round: round, completedTricks: ti, cardsInCurrentTrick: ci);
          expect(result, isNotNull);
          for (final entry in result!.entries) {
            expect(
                entry.value,
                referenceTricksForSideOnPlay(state.hands, round.trumpSuit(),
                    state.currentTrick, entry.key),
                reason: "trick $ti ci $ci card ${entry.key}");
          }
        }
      }
    });
  }, skip: ddsAvailable ? null : ddsSkipReason);
}
