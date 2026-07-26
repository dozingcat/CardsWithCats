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

  group("responses to major openings", () {
    test("single raise with three trumps", () {
      final result = selectSaycBid(hand("K32", "Q432", "K32", "432"),
          [BidAction.fromString("1S"), BidAction.pass()]);
      expect(result!.action.toString(), "2S");
      expect(result.meaning.totalPoints, const Range(low: 6, high: 10));
      expect(result.meaning.suitLengths[Suit.spades], const Range(low: 3));
    });

    test("raise preferred over new suit", () {
      expect(openingBid("KQ32", "K32", "Q432", "32", history: ["1H", "pass"]),
          "2H");
    });

    test("limit raise", () {
      expect(openingBid("K32", "K432", "KJ32", "Q2", history: ["1S", "pass"]),
          "3S");
    });

    test("Jacoby 2NT", () {
      final result = selectSaycBid(hand("K432", "A432", "AK2", "32"),
          [BidAction.fromString("1S"), BidAction.pass()]);
      expect(result!.action.toString(), "2NT");
      expect(result.meaning.artificial, true);
      expect(result.meaning.suitLengths[Suit.spades], const Range(low: 4));
    });

    test("game-forcing hand with three trumps bids new suit", () {
      expect(openingBid("K32", "AQ32", "A432", "32", history: ["1S", "pass"]),
          "2D");
    });

    test("one spade over one heart", () {
      expect(openingBid("KQ32", "32", "Q432", "J32", history: ["1H", "pass"]),
          "1S");
    });

    test("1NT response with no fit", () {
      final result = selectSaycBid(hand("32", "K432", "Q432", "K32"),
          [BidAction.fromString("1S"), BidAction.pass()]);
      expect(result!.action.toString(), "1NT");
      expect(result.meaning.suitLengths[Suit.spades], const Range(high: 2));
    });

    test("two hearts over one spade shows five", () {
      final result = selectSaycBid(hand("32", "AKJ32", "432", "Q32"),
          [BidAction.fromString("1S"), BidAction.pass()]);
      expect(result!.action.toString(), "2H");
      expect(result.meaning.suitLengths[Suit.hearts], const Range(low: 5));
    });

    test("two clubs over one heart", () {
      expect(openingBid("K32", "32", "A32", "KQ432", history: ["1H", "pass"]),
          "2C");
    });

    test("pass with a weak hand", () {
      expect(openingBid("432", "5432", "432", "432", history: ["1S", "pass"]),
          "Pass");
    });
  });

  group("responses to minor openings", () {
    test("four-four majors up the line", () {
      expect(openingBid("K432", "A432", "32", "Q32", history: ["1C", "pass"]),
          "1H");
    });

    test("longer major first", () {
      expect(openingBid("KQ432", "A432", "32", "32", history: ["1D", "pass"]),
          "1S");
    });

    test("five-five majors bids spades", () {
      expect(openingBid("KQ432", "A5432", "2", "32", history: ["1D", "pass"]),
          "1S");
    });

    test("one diamond over one club", () {
      expect(openingBid("432", "432", "AQ432", "K2", history: ["1C", "pass"]),
          "1D");
    });

    test("raises of a minor", () {
      expect(openingBid("432", "32", "KQ432", "Q32", history: ["1D", "pass"]),
          "2D");
      expect(openingBid("K32", "2", "KQ432", "Q432", history: ["1D", "pass"]),
          "3D");
    });

    test("notrump ladder", () {
      expect(openingBid("K32", "Q32", "J32", "Q432", history: ["1D", "pass"]),
          "1NT");
      expect(openingBid("K32", "QJ2", "J32", "AK32", history: ["1D", "pass"]),
          "2NT");
      expect(openingBid("AK2", "QJ2", "J32", "AK32", history: ["1D", "pass"]),
          "3NT");
    });

    test("two-over-one in the other minor", () {
      expect(openingBid("32", "K32", "432", "AQJ32", history: ["1D", "pass"]),
          "2C");
    });
  });

  group("responses to 1NT", () {
    List<String> nt1 = ["1NT", "pass"];

    test("Stayman with a four-card major", () {
      final result = selectSaycBid(hand("KQ32", "K432", "432", "32"),
          nt1.map(BidAction.fromString).toList());
      expect(result!.action.toString(), "2C");
      expect(result.meaning.artificial, true);
    });

    test("transfers", () {
      expect(openingBid("32", "KQ432", "432", "432", history: nt1), "2D");
      expect(openingBid("KQ432", "32", "432", "432", history: nt1), "2H");
      // A 5-card major always transfers, even with Stayman values.
      expect(openingBid("KQ432", "K432", "32", "32", history: nt1), "2H");
    });

    test("no Stayman below eight points", () {
      expect(openingBid("K432", "Q32", "J432", "J2", history: nt1), "Pass");
    });

    test("notrump ladder", () {
      expect(openingBid("J32", "Q32", "J432", "432", history: nt1), "Pass");
      expect(openingBid("K32", "Q32", "K432", "J32", history: nt1), "2NT");
      expect(openingBid("K32", "Q32", "KQ32", "Q32", history: nt1), "3NT");
      expect(openingBid("AK2", "KQ2", "KJ32", "J32", history: nt1), "4NT");
      expect(openingBid("AK2", "KQ2", "KQ32", "Q32", history: nt1), "4C");
    });
  });

  group("responses to two-level and preempt openings", () {
    test("2D waiting over 2C", () {
      final result = selectSaycBid(hand("K32", "Q432", "432", "432"),
          [BidAction.fromString("2C"), BidAction.pass()]);
      expect(result!.action.toString(), "2D");
      expect(result.meaning.artificial, true);
    });

    test("raises of a weak two", () {
      expect(openingBid("K32", "432", "Q432", "432", history: ["2S", "pass"]),
          "3S");
      expect(openingBid("K32", "AK2", "A432", "K32", history: ["2S", "pass"]),
          "4S");
    });

    test("pass a weak two without support", () {
      expect(openingBid("K432", "2", "Q432", "K432", history: ["2H", "pass"]),
          "Pass");
    });

    test("3NT over a weak two with 16+ and no fit", () {
      expect(openingBid("K2", "AQ32", "AQ32", "K32", history: ["2S", "pass"]),
          "3NT");
    });

    test("raise partner's preempt to game", () {
      expect(openingBid("K32", "AK2", "A432", "K32", history: ["3S", "pass"]),
          "4S");
    });

    test("3NT over a minor preempt with 16+", () {
      expect(openingBid("K2", "AQ32", "AQ32", "K32", history: ["3C", "pass"]),
          "3NT");
    });

    test("ladders over 2NT opening", () {
      expect(openingBid("K32", "Q32", "KQ32", "J32", history: ["2NT", "pass"]),
          "4NT");
      expect(openingBid("AK2", "Q32", "KQ32", "J32", history: ["2NT", "pass"]),
          "4C");
      expect(openingBid("K32", "Q32", "Q432", "432", history: ["2NT", "pass"]),
          "3NT");
    });
  });

  group("opener rebids", () {
    test("original example: raise responder's major with four", () {
      final result = selectSaycBid(parseHand(exampleHandString),
          ["1D", "pass", "1S", "pass"].map(BidAction.fromString).toList());
      expect(result!.action.toString(), "2S");
      expect(result.meaning.totalPoints, const Range(low: 13, high: 15));
      expect(result.meaning.suitLengths[Suit.spades], const Range(low: 4));
    });

    test("jump raise and game raise", () {
      expect(
          openingBid("AQ32", "K6", "AKJ32", "32",
              history: ["1D", "pass", "1S", "pass"]),
          "3S"); // 18 total
      expect(
          openingBid("AQ32", "6", "AKQJ32", "Q2",
              history: ["1D", "pass", "1S", "pass"]),
          "4S"); // 20 total
    });

    test("notrump rebids", () {
      expect(
          openingBid("K32", "K32", "AQ32", "J32",
              history: ["1D", "pass", "1S", "pass"]),
          "1NT"); // 13
      expect(
          openingBid("K32", "KQ2", "AQ32", "A32",
              history: ["1D", "pass", "1S", "pass"]),
          "2NT"); // 18
    });

    test("six-card suit rebids", () {
      expect(
          openingBid("32", "K2", "AKJ432", "Q32",
              history: ["1D", "pass", "1S", "pass"]),
          "2D"); // 15 total
      expect(
          openingBid("32", "K2", "AKQJ32", "Q32",
              history: ["1D", "pass", "1S", "pass"]),
          "3D"); // 17 total
    });

    test("reverses require 17+", () {
      expect(
          openingBid("K2", "AQ32", "AKQ32", "32",
              history: ["1D", "pass", "1S", "pass"]),
          "2H"); // 19 total
      expect(
          openingBid("K2", "KQ32", "AQJ32", "32",
              history: ["1D", "pass", "1S", "pass"]),
          "2D"); // 16 total: no reverse
    });

    test("jump shift with 18+", () {
      expect(
          openingBid("K2", "2", "AKQ32", "AQJ43",
              history: ["1D", "pass", "1S", "pass"]),
          "3C"); // 21 total
      expect(
          openingBid("AKJ32", "2", "K2", "AQJ43",
              history: ["1S", "pass", "1NT", "pass"]),
          "3C"); // 20 total
    });

    test("new major before raising a minor response", () {
      expect(
          openingBid("K32", "KQ32", "2", "AQ432",
              history: ["1C", "pass", "1D", "pass"]),
          "1H");
    });

    test("after a single raise", () {
      expect(
          openingBid("AKJ32", "K32", "Q32", "32",
              history: ["1S", "pass", "2S", "pass"]),
          "Pass"); // 14
      expect(
          openingBid("AKJ32", "AK2", "Q32", "32",
              history: ["1S", "pass", "2S", "pass"]),
          "3S"); // 18
    });

    test("accepts a limit raise with 14", () {
      expect(
          openingBid("AKJ32", "K32", "Q32", "32",
              history: ["1S", "pass", "3S", "pass"]),
          "4S"); // 14
      expect(
          openingBid("AKJ32", "Q32", "Q32", "32",
              history: ["1S", "pass", "3S", "pass"]),
          "Pass"); // 13
    });

    test("Jacoby 2NT rebids", () {
      expect(
          openingBid("AKJ32", "K32", "Q32", "32",
              history: ["1S", "pass", "2NT", "pass"]),
          "4S"); // minimum
      expect(
          openingBid("AKJ32", "AK2", "Q32", "32",
              history: ["1S", "pass", "2NT", "pass"]),
          "3S"); // extras
    });

    test("Stayman answers and transfer completions", () {
      final stayman = ["1NT", "pass", "2C", "pass"];
      expect(openingBid("K432", "AQ32", "A32", "K2", history: stayman), "2H");
      expect(openingBid("AQ32", "K32", "A32", "KJ2", history: stayman), "2S");
      expect(openingBid("K32", "A32", "AQ32", "KJ2", history: stayman), "2D");
      expect(
          openingBid("K32", "A32", "AQ32", "KJ2",
              history: ["1NT", "pass", "2D", "pass"]),
          "2H");
    });

    test("1NT opener invitation decisions", () {
      final invite = ["1NT", "pass", "2NT", "pass"];
      expect(openingBid("K32", "A32", "AQ32", "Q32", history: invite), "Pass");
      expect(openingBid("K32", "A32", "AQ32", "KJ2", history: invite), "3NT");
    });

    test("2C rebids", () {
      final after2d = ["2C", "pass", "2D", "pass"];
      expect(openingBid("AKJ4", "AQ3", "KQ3", "K32", history: after2d), "2NT");
      expect(
          openingBid("AKQJ32", "AKQ", "A32", "2", history: after2d), "2S");
    });
  });

  group("responder rebids", () {
    test("Stayman continuations", () {
      final h2 = ["1NT", "pass", "2C", "pass", "2H", "pass"];
      expect(openingBid("K432", "Q432", "QJ2", "32", history: h2), "3H"); // 8
      expect(openingBid("A432", "QJ32", "QJ2", "32", history: h2), "4H"); // 10
      final s2 = ["1NT", "pass", "2C", "pass", "2S", "pass"];
      expect(openingBid("32", "QJ32", "A432", "Q32", history: s2), "2NT"); // 9
      expect(openingBid("32", "QJ32", "A432", "K32", history: s2), "3NT"); // 10
    });

    test("transfer continuations", () {
      final t = ["1NT", "pass", "2D", "pass", "2H", "pass"];
      expect(openingBid("32", "KQ432", "432", "432", history: t), "Pass");
      expect(openingBid("32", "KQ432", "K32", "J32", history: t), "2NT");
      expect(openingBid("32", "KQJ432", "Q32", "32", history: t), "3H");
      expect(openingBid("K2", "KQ432", "K32", "Q32", history: t), "3NT");
      expect(openingBid("32", "KQJ432", "K32", "K2", history: t), "4H");
    });

    test("after opener raises our suit", () {
      final raised = ["1D", "pass", "1S", "pass", "2S", "pass"];
      expect(openingBid("KQ32", "432", "Q32", "J32", history: raised), "Pass");
      expect(openingBid("KQ32", "432", "K32", "KJ2", history: raised), "3S");
      expect(openingBid("KQ32", "A32", "K32", "J32", history: raised), "4S");
    });

    test("after opener's 1NT rebid", () {
      final nt = ["1D", "pass", "1S", "pass", "1NT", "pass"];
      expect(openingBid("KQ32", "432", "Q32", "J32", history: nt), "Pass");
      expect(openingBid("KQ32", "432", "K32", "KJ2", history: nt), "2NT");
      expect(openingBid("KQ32", "A32", "K32", "J32", history: nt), "3NT");
      expect(openingBid("KQJ432", "32", "Q32", "32", history: nt), "2S");
      expect(openingBid("KQJ432", "A2", "K32", "32", history: nt), "4S");
    });

    test("after opener rebids its own suit", () {
      final own = ["1D", "pass", "1S", "pass", "2D", "pass"];
      expect(openingBid("KQ32", "432", "Q32", "J32", history: own), "Pass");
      expect(openingBid("KQ32", "K432", "32", "KJ2", history: own), "2NT");
      expect(openingBid("KQ32", "A432", "32", "KJ2", history: own), "3NT");
      expect(openingBid("KQJ432", "432", "32", "32", history: own), "2S");
    });

    test("preference after a second suit", () {
      final second = ["1D", "pass", "1S", "pass", "2C", "pass"];
      expect(openingBid("KQ32", "432", "Q32", "J32", history: second), "2D");
      expect(openingBid("KQ32", "432", "32", "J432", history: second), "Pass");
      expect(openingBid("KQ32", "A32", "K32", "J32", history: second), "3NT");
    });

    test("moves toward game over a reverse", () {
      expect(
          openingBid("432", "AQJ32", "Q32", "32",
              history: ["1D", "pass", "1H", "pass", "2S", "pass"]),
          "3NT"); // 9 opposite 17+
    });

    test("two-over-one continuations", () {
      final raised = ["1S", "pass", "2C", "pass", "2S", "pass"];
      expect(openingBid("K32", "A32", "K2", "KQ432", history: raised), "4S");
      expect(openingBid("K32", "432", "32", "KQJ43", history: raised), "Pass");
      final nt = ["1S", "pass", "2C", "pass", "2NT", "pass"];
      expect(openingBid("K32", "A32", "K2", "KQ432", history: nt), "3NT");
    });

    test("2C auction continuations", () {
      final after2nt = ["2C", "pass", "2D", "pass", "2NT", "pass"];
      expect(openingBid("Q32", "J432", "Q32", "432", history: after2nt), "3NT");
      expect(openingBid("432", "5432", "J32", "432", history: after2nt), "Pass");
      final after2s = ["2C", "pass", "2D", "pass", "2S", "pass"];
      expect(openingBid("Q32", "5432", "J32", "432", history: after2s), "4S");
      expect(openingBid("32", "J5432", "J32", "432", history: after2s), "2NT");
    });
  });

  group("slam conventions", () {
    test("Jacoby sequences launch Blackwood", () {
      expect(
          openingBid("K432", "A432", "AK2", "K2",
              history: ["1S", "pass", "2NT", "pass", "3S", "pass"]),
          "4NT"); // 17
    });

    test("Blackwood answers", () {
      final ask = ["1S", "pass", "2NT", "pass", "3S", "pass", "4NT", "pass"];
      expect(openingBid("AKJ32", "A32", "K32", "32", history: ask), "5H");
      expect(openingBid("AKJ32", "432", "K32", "K2", history: ask), "5D");
    });

    test("Blackwood placement", () {
      expect(
          openingBid("K432", "A432", "AK2", "K2", history: [
            "1S", "pass", "2NT", "pass", "3S", "pass", "4NT", "pass",
            "5H", "pass"
          ]),
          "6S"); // two aces + two shown
      expect(
          openingBid("K432", "KQ32", "KQ2", "K2", history: [
            "1S", "pass", "2NT", "pass", "3S", "pass", "4NT", "pass",
            "5D", "pass"
          ]),
          "5S"); // zero aces + one shown
    });

    test("Gerber answers and continuation", () {
      final ask = ["1NT", "pass", "4C", "pass"];
      expect(openingBid("K32", "A32", "AQ32", "KJ2", history: ask), "4S");
      expect(openingBid("K32", "KQ2", "KQ32", "KJ2", history: ask), "4D");
      expect(
          openingBid("AK2", "KQ2", "AQ32", "Q32",
              history: ["1NT", "pass", "4C", "pass", "4S", "pass"]),
          "6NT"); // 2 + 2 aces
      expect(
          openingBid("KQ2", "KQ2", "KQ32", "QJ2",
              history: ["1NT", "pass", "4C", "pass", "4H", "pass"]),
          "4NT"); // 0 + 1 aces
    });
  });

  group("opener's third call", () {
    test("invitation decisions after a 1NT rebid", () {
      final h = ["1D", "pass", "1S", "pass", "1NT", "pass", "2NT", "pass"];
      expect(openingBid("K32", "KJ2", "AQ32", "J32", history: h), "3NT"); // 14
      expect(openingBid("K32", "QJ2", "AQ32", "432", history: h), "Pass"); // 12
    });

    test("invitation decisions after a raise", () {
      final h = ["1D", "pass", "1S", "pass", "2S", "pass", "3S", "pass"];
      expect(openingBid("AQ32", "K32", "A5432", "2", history: h), "4S"); // 14
      expect(
          selectSaycBid(parseHand(exampleHandString),
                  h.map(BidAction.fromString).toList())!
              .action
              .toString(),
          "Pass"); // 13
    });

    test("minor invite accepted with 3NT", () {
      expect(
          openingBid("32", "K2", "AKJ432", "Q32", history: [
            "1D", "pass", "1S", "pass", "2D", "pass", "3D", "pass"
          ]),
          "3NT"); // 15
    });

    test("corrects Stayman 3NT to the spade fit", () {
      final h = ["1NT", "pass", "2C", "pass", "2H", "pass", "3NT", "pass"];
      expect(openingBid("K432", "AQ32", "A32", "K2", history: h), "4S");
      expect(openingBid("K32", "AQ32", "A32", "K32", history: h), "Pass");
    });

    test("transfer choice of games", () {
      final h = ["1NT", "pass", "2D", "pass", "2H", "pass", "3NT", "pass"];
      expect(openingBid("K32", "A32", "AQ32", "KJ2", history: h), "4H");
      expect(openingBid("K32", "A3", "AQ32", "KJ32", history: h), "Pass");
    });

    test("2C game force is enforced", () {
      expect(
          openingBid("AKQJ32", "AKQ", "A32", "2", history: [
            "2C", "pass", "2D", "pass", "2S", "pass", "2NT", "pass"
          ]),
          "4S");
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
      // Competitive auctions are a later phase.
      expect(
          selectSaycBid(parseHand(exampleHandString),
              [BidAction.fromString("1D"), BidAction.fromString("1S")]),
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
