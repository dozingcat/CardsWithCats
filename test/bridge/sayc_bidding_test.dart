import "package:cards_with_cats/bridge/bridge.dart";
import "package:cards_with_cats/bridge/hand_estimate.dart";
import "package:cards_with_cats/bridge/sayc/sayc_bidding.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:flutter_test/flutter_test.dart";

const exampleHandString = "AS QS 3S 2S KH 6H AD 4D 3D 2D 4C 3C 2C";

List<PlayingCard> hand(String spades, String hearts, String diamonds, String clubs) {
  return parseHand("$spades $hearts $diamonds $clubs");
}

/// The opening bid for a hand given in suit-group parts ('-' for a void).
String openingBid(String spades, String hearts, String diamonds, String clubs,
    {List<String> history = const []}) {
  final result = selectSaycBid(
    hand(spades, hearts, diamonds, clubs),
    history.map(BidAction.fromString).toList(),
  );
  return result!.action.toString();
}

void main() {
  group("hand parsing", () {
    test("card list and suit groups parse identically", () {
      final a = parseHand(exampleHandString);
      final b = parseHand("AQ32 K6 A432 432");
      expect(a.toSet(), b.toSet());
    });

    test("void parses as dash", () {
      final h = parseHand("AKQJT98765432 - - -");
      expect(h.length, 13);
      expect(h.every((c) => c.suit == Suit.spades), true);
    });

    test("group string round trip", () {
      expect(handGroupString(parseHand("AQ32 K6 A432 432")), "AQ32 K6 A432 432");
      expect(handGroupString(parseHand("AKQJT98765432 - - -")),
          "AKQJT98765432 - - -");
    });

    test("wrong card count rejected", () {
      expect(() => HandAnalysis(parseHand("AS KS QS")), throwsArgumentError);
    });

    test("duplicate cards rejected", () {
      expect(
          () => HandAnalysis(
              parseHand("AS AS QS JS TS 9S 8S 7S 6S 5S 4S 3S 2S")),
          throwsArgumentError);
    });
  });

  group("hand evaluation", () {
    test("high card points", () {
      expect(HandAnalysis(parseHand(exampleHandString)).hcp, 13);
    });

    test("total points add length", () {
      final h = HandAnalysis(hand("AQJ432", "A32", "32", "32"));
      expect(h.hcp, 11);
      expect(h.totalPoints, 13);
    });

    test("balanced shapes", () {
      expect(HandAnalysis(hand("AQ3", "KJ4", "QJ32", "K74")).isBalanced, true);
      expect(HandAnalysis(hand("AQ32", "KJ32", "A32", "32")).isBalanced, true);
      expect(HandAnalysis(hand("AQJ32", "KJ4", "QJ3", "K7")).isBalanced, true);
      expect(HandAnalysis(hand("AKJ43", "A432", "K32", "2")).isBalanced, false);
      expect(HandAnalysis(hand("32", "AKJ43", "K432", "A3")).isBalanced, false);
    });

    test("stoppers", () {
      final withStoppers = HandAnalysis(hand("A2", "K32", "Q432", "J432"));
      expect(withStoppers.hasStopper(Suit.spades), true); // A
      expect(withStoppers.hasStopper(Suit.hearts), true); // Kxx
      expect(withStoppers.hasStopper(Suit.diamonds), true); // Qxxx
      expect(withStoppers.hasStopper(Suit.clubs), true); // Jxxx
      final without = HandAnalysis(hand("432", "Q2", "J32", "87654"));
      expect(without.hasStopper(Suit.spades), false);
      expect(without.hasStopper(Suit.hearts), false); // Qx too short
      expect(without.hasStopper(Suit.diamonds), false); // Jxx too short
      expect(without.hasStopper(Suit.clubs), false);
    });

    test("aces", () {
      expect(HandAnalysis(hand("A2", "AKJT", "Q32", "9876")).aces, 2);
    });
  });

  group("notrump openings", () {
    test("1NT with 15-17 balanced", () {
      expect(openingBid("AQ3", "KJ4", "QJ32", "K74"), "1NT"); // 16
      expect(openingBid("AQ3", "KJ4", "QJ32", "Q74"), "1NT"); // 15
      expect(openingBid("AQ3", "KJ4", "QJ32", "A74"), "1NT"); // 17
    });

    test("1NT allowed with a 5-card major", () {
      expect(openingBid("AQJ32", "KJ4", "QJ3", "K7"), "1NT"); // 17, 5-3-3-2
    });

    test("14 balanced opens a suit", () {
      expect(openingBid("AQ3", "KJ4", "QJ32", "J74"), "1D");
    });

    test("18-19 balanced opens a suit", () {
      expect(openingBid("AQ3", "KJ4", "QJ32", "KQ4"), "1D"); // 18
    });

    test("2NT with 20-21", () {
      expect(openingBid("AQ3", "KJ4", "AQ32", "KJ4"), "2NT"); // 20
      expect(openingBid("AQ3", "KJ4", "AQ32", "KQ4"), "2NT"); // 21
    });
  });

  group("strong two clubs", () {
    test("22 balanced opens 2C, not 2NT", () {
      expect(openingBid("AKJ4", "AQ3", "KQ3", "K32"), "2C"); // 22
    });

    test("strong unbalanced opens 2C", () {
      expect(openingBid("AKQJ32", "AKQ", "A32", "2"), "2C"); // 23
    });
  });

  group("one-level suit openings", () {
    test("1S with five spades", () {
      expect(openingBid("AKJ43", "A432", "K32", "2"), "1S"); // 15
    });

    test("1H with five hearts", () {
      expect(openingBid("32", "AKJ43", "K432", "A3"), "1H"); // 15, 2-5-4-2
    });

    test("five-five majors opens spades", () {
      expect(openingBid("AKJ43", "KQ432", "32", "2"), "1S");
    });

    test("longer major wins", () {
      expect(openingBid("AKJ43", "KQJ432", "2", "2"), "1H");
    });

    test("light opening with length points", () {
      expect(openingBid("AQJ432", "A32", "32", "32"), "1S"); // 11 HCP + 2
    });

    test("longer minor", () {
      expect(openingBid("A2", "K32", "AQJ32", "432"), "1D");
      expect(openingBid("A32", "K3", "432", "AQJ32"), "1C");
    });

    test("four-four minors opens 1D, three-three opens 1C", () {
      expect(openingBid("A32", "K3", "QJ32", "QJ32"), "1D");
      expect(openingBid("AJ32", "KQ3", "432", "K32"), "1C");
    });

    test("4=4=3=2 opens 1D with three", () {
      expect(openingBid("AQ32", "KJ32", "A32", "32"), "1D"); // 14
    });

    test("example hand opens 1D", () {
      final result = selectSaycBid(parseHand(exampleHandString), []);
      expect(result!.action.toString(), "1D");
    });
  });

  group("preempts", () {
    test("weak twos", () {
      expect(openingBid("KQJ432", "32", "432", "32"), "2S"); // 6
      expect(openingBid("32", "AKJ432", "432", "32"), "2H"); // 8
      expect(openingBid("32", "432", "AQJ432", "32"), "2D"); // 7
    });

    test("no weak two clubs", () {
      expect(openingBid("32", "432", "32", "KQJ432"), "Pass");
    });

    test("three level with a seven-card suit", () {
      expect(openingBid("2", "32", "KQJ6543", "432"), "3D"); // 6
    });

    test("preempt beats light opening", () {
      // 10 HCP + 3 length = 13 total, but 5-10 HCP preempts first.
      expect(openingBid("2", "32", "AKJ6543", "Q32"), "3D");
      expect(openingBid("2", "32", "AKQ6543", "Q32"), "1D"); // 11 HCP
    });

    test("four level with an eight-card suit", () {
      expect(openingBid("KQJ65432", "32", "32", "2"), "4S"); // 6
    });

    test("weak hand with a five-card suit passes", () {
      expect(openingBid("KQJ43", "432", "432", "32"), "Pass");
    });

    test("too weak to preempt", () {
      expect(openingBid("2", "32", "J865432", "432"), "Pass");
    });
  });

  group("pass as opener", () {
    test("weak flat hand passes", () {
      expect(openingBid("Q32", "J432", "Q32", "432"), "Pass"); // 5
    });

    test("twelve balanced passes", () {
      expect(openingBid("K32", "QJ32", "K32", "K32"), "Pass"); // 12
    });

    test("opens in later seats after passes", () {
      expect(
          openingBid("AKJ43", "A432", "K32", "2", history: ["pass"]), "1S");
      expect(
          openingBid("AKJ43", "A432", "K32", "2",
              history: ["pass", "pass", "pass"]),
          "1S");
    });
  });

  group("auction dispatch", () {
    test("completed auction rejected", () {
      expect(
          () => selectSaycBid(
              parseHand(exampleHandString),
              ["pass", "pass", "pass", "pass"]
                  .map(BidAction.fromString)
                  .toList()),
          throwsStateError);
    });

    test("unported positions return null", () {
      expect(
          selectSaycBid(parseHand(exampleHandString),
              [BidAction.fromString("1D"), BidAction.pass()]),
          null);
    });
  });

  group("describe and explain", () {
    test("describe 1NT opening", () {
      final meaning = describeSaycCall([], BidAction.noTrump(1));
      expect(meaning!.hcp, const Range(low: 15, high: 17));
      expect(meaning.balanced, true);
    });

    test("describe weak two", () {
      final meaning = describeSaycCall([], BidAction.fromString("2H"));
      expect(meaning!.hcp, const Range(low: 5, high: 10));
      expect(meaning.suitLengths[Suit.hearts], const Range(low: 6, high: 6));
    });

    test("describe pass as dealer", () {
      final meaning = describeSaycCall([], BidAction.pass());
      expect(meaning!.totalPoints, const Range(high: 12));
    });

    test("describe call with no meaning returns null", () {
      expect(describeSaycCall([], BidAction.fromString("5C")), null);
    });

    test("explain covers openings and accumulates seats", () {
      final ex = explainSaycAuction(
          ["pass", "1S"].map(BidAction.fromString).toList());
      expect(ex.calls[0].meaning!.totalPoints, const Range(high: 12));
      expect(ex.calls[1].meaning!.suitLengths[Suit.spades],
          const Range(low: 5));
      expect(ex.players[1]!.totalPoints, const Range(low: 13, high: 21));
    });
  });
}
