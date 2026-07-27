import "package:cards_with_cats/bridge/bridge.dart";
import "package:cards_with_cats/bridge/hand_estimate.dart";
import "package:cards_with_cats/bridge/sayc/sayc_bidding.dart";
import "package:cards_with_cats/bridge/sayc/selfplay.dart";
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
  return result.action.toString();
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
      expect(result.action.toString(), "1D");
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
      expect(result.action.toString(), "2S");
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
      expect(result.action.toString(), "2NT");
      expect(result.meaning.artificial, true);
      expect(result.meaning.suitLengths[Suit.spades], const Range(low: 4));
    });

    test("splinter 3S over 1H", () {
      final result = selectSaycBid(hand("2", "AK32", "A432", "K432"),
          [BidAction.fromString("1H"), BidAction.pass()]);
      expect(result.action.toString(), "3S");
      expect(result.meaning.artificial, true);
      expect(result.meaning.suitLengths[Suit.hearts], const Range(low: 4));
      expect(result.meaning.suitLengths[Suit.spades], const Range(high: 1));
      expect(result.meaning.totalPoints, const Range(low: 12, high: 15));
    });

    test("splinter 4C over 1S", () {
      final result = selectSaycBid(hand("K432", "AK32", "A5432", "-"),
          [BidAction.fromString("1S"), BidAction.pass()]);
      expect(result.action.toString(), "4C");
      expect(result.meaning.artificial, true);
      expect(result.meaning.suitLengths[Suit.spades], const Range(low: 4));
      expect(result.meaning.suitLengths[Suit.clubs], const Range(high: 1));
      expect(result.meaning.totalPoints, const Range(low: 12, high: 15));
    });

    test("opener continues correctly after a splinter", () {
      final splintered = ["1H", "pass", "3S", "pass"];
      // Minimum: sign off in game (not a "raise" of the singleton!).
      expect(openingBid("Q432", "AKJ43", "K2", "32", history: splintered),
          "4H"); // 15
      // Slam interest opposite the shortness: Blackwood.
      expect(openingBid("32", "AKJ43", "AK32", "K2", history: splintered),
          "4NT"); // 19
    });

    test("splinter Blackwood sequence completes", () {
      // Responder answers aces...
      expect(
          openingBid("2", "AK32", "A432", "K432",
              history: ["1H", "pass", "3S", "pass", "4NT", "pass"]),
          "5H"); // 2 aces
      // ...and opener places the contract.
      expect(
          openingBid("32", "AKJ43", "AK32", "K2", history: [
            "1H", "pass", "3S", "pass", "4NT", "pass", "5H", "pass"
          ]),
          "6H"); // 2 + 2 aces
      expect(
          openingBid("32", "KQJ43", "AK32", "K2", history: [
            "1H", "pass", "3S", "pass", "4NT", "pass", "5D", "pass"
          ]),
          "5H"); // 1 + 1 aces: sign off
    });

    test("contested three-level free bid is not a splinter", () {
      // 1H (3C) 3S is a natural free bid; opener raises real spades.
      expect(
          openingBid("Q432", "AKJ43", "K2", "32",
              history: ["1H", "3C", "3S", "pass"]),
          "4S");
    });

    test("16+ with shortness prefers Jacoby 2NT to a splinter", () {
      expect(openingBid("2", "AK32", "AK32", "KQ32", history: ["1H", "pass"]),
          "2NT"); // 18: above the splinter cap
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
      expect(result.action.toString(), "1NT");
      expect(result.meaning.suitLengths[Suit.spades], const Range(high: 2));
    });

    test("two hearts over one spade shows five", () {
      final result = selectSaycBid(hand("32", "AKJ32", "432", "Q32"),
          [BidAction.fromString("1S"), BidAction.pass()]);
      expect(result.action.toString(), "2H");
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
      expect(result.action.toString(), "2C");
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
      expect(result.action.toString(), "2D");
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

    test("Stayman and transfers over 2NT", () {
      final nt2 = ["2NT", "pass"];
      // Stayman with a 4-card major and 5+ HCP.
      expect(openingBid("K432", "Q32", "J432", "J2", history: nt2), "3C");
      // Transfers with any 5-card major, any strength.
      expect(openingBid("KQ432", "32", "432", "432", history: nt2), "3H");
      expect(openingBid("32", "KQ432", "432", "432", history: nt2), "3D");
      expect(openingBid("KQ432", "K432", "32", "32", history: nt2), "3H");
      // Too weak for Stayman: pass.
      expect(openingBid("J432", "Q32", "J432", "42", history: nt2), "Pass");
    });

    test("opener answers Stayman and transfers over 2NT", () {
      expect(
          openingBid("AQ32", "KQJ2", "AQ2", "K2",
              history: ["2NT", "pass", "3C", "pass"]),
          "3H"); // hearts first with both majors
      expect(
          openingBid("AQ3", "KQ2", "AQ32", "K32",
              history: ["2NT", "pass", "3C", "pass"]),
          "3D"); // no 4-card major
      expect(
          openingBid("AQ3", "KQ2", "AQ32", "K32",
              history: ["2NT", "pass", "3D", "pass"]),
          "3H");
      expect(
          openingBid("AQ3", "KQ2", "AQ32", "K32",
              history: ["2NT", "pass", "3H", "pass"]),
          "3S");
    });

    test("responder continues after Stayman over 2NT", () {
      expect(
          openingBid("K432", "Q432", "J32", "32",
              history: ["2NT", "pass", "3C", "pass", "3H", "pass"]),
          "4H"); // fit found
      expect(
          openingBid("32", "Q432", "K432", "J32",
              history: ["2NT", "pass", "3C", "pass", "3S", "pass"]),
          "3NT"); // wrong major
      expect(
          openingBid("K432", "Q32", "J432", "J2",
              history: ["2NT", "pass", "3C", "pass", "3D", "pass"]),
          "3NT"); // no major
    });

    test("responder continues after a transfer over 2NT", () {
      final completed = ["2NT", "pass", "3D", "pass", "3H", "pass"];
      expect(openingBid("32", "J65432", "432", "32", history: completed),
          "Pass"); // bust
      expect(openingBid("K2", "Q5432", "J432", "32", history: completed),
          "3NT"); // exactly five: choice of games
      expect(openingBid("32", "Q65432", "K32", "J2", history: completed),
          "4H"); // six trumps
    });

    test("opener's choice of games after 2NT structures", () {
      final choice = ["2NT", "pass", "3D", "pass", "3H", "pass", "3NT", "pass"];
      expect(openingBid("AQ3", "KQ2", "AQ32", "K32", history: choice),
          "4H"); // 3-card fit
      expect(openingBid("AQ32", "K2", "AQJ2", "KQ2", history: choice),
          "Pass"); // doubleton
      expect(
          openingBid("AQ32", "KQJ2", "AQ2", "K2", history: [
            "2NT", "pass", "3C", "pass", "3H", "pass", "3NT", "pass"
          ]),
          "4S"); // correcting to the 4-4 spade fit
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
      expect(result.action.toString(), "2S");
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
                  h.map(BidAction.fromString).toList())
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

    test("rules_for still returns null for uncovered positions", () {
      // select_bid falls back, but the explicit-rules API keeps signalling.
      expect(
          saycRulesForAuction(["1D", "1H", "1S", "2H", "X", "pass"]
              .map(BidAction.fromString)
              .toList()),
          null);
    });
  });

  group("direct actions over their opening", () {
    test("overcalls", () {
      expect(openingBid("AKJ32", "432", "32", "432", history: ["1D"]), "1S");
      expect(openingBid("K32", "432", "32", "AKJ43", history: ["1H"]), "2C");
      expect(openingBid("A32", "KJ4", "AQ32", "Q74", history: ["1H"]), "1NT");
      expect(openingBid("KQJ432", "32", "32", "432", history: ["1D"]), "2S");
      expect(openingBid("KJ4", "A32", "AQ32", "Q74", history: ["2S"]), "2NT");
      expect(openingBid("KQJ432", "A2", "432", "32", history: ["1NT"]), "2S");
    });

    test("takeout doubles", () {
      expect(openingBid("KQ32", "2", "AJ32", "K432", history: ["1H"]), "Double");
      expect(openingBid("AQ32", "432", "AKJ2", "A2", history: ["1H"]), "Double");
      expect(openingBid("KQ32", "2", "AJ32", "K432", history: ["2H"]), "Double");
    });

    test("standard treatment of trump stacks", () {
      const stack = "A2 AKJT Q32 9876";
      expect(selectSaycBid(parseHand(stack), [BidAction.fromString("1H")])
          .action.toString(), "Pass"); // trap pass
      expect(selectSaycBid(parseHand(stack), [BidAction.fromString("3H")])
          .action.toString(), "Pass");
      expect(selectSaycBid(parseHand(stack), [BidAction.fromString("4H")])
          .action.toString(), "Double"); // optional double at the 4 level
      expect(
          selectSaycBid(parseHand(stack),
                  ["1H", "pass", "pass", "X", "pass"]
                      .map(BidAction.fromString)
                      .toList())
              .action
              .toString(),
          "Pass"); // converting the reopening double
    });

    test("pass without a suitable action", () {
      expect(openingBid("Q432", "J32", "32", "Q432", history: ["1D"]), "Pass");
    });
  });

  group("responses over interference", () {
    test("negative doubles", () {
      final result = selectSaycBid(hand("432", "KQ32", "Q32", "J32"),
          ["1D", "1S"].map(BidAction.fromString).toList());
      expect(result.action.toString(), "Double");
      expect(result.meaning.artificial, true);
      expect(result.meaning.suitLengths[Suit.hearts], const Range(low: 4));
      expect(openingBid("432", "KQ432", "Q32", "32", history: ["1D", "1S"]),
          "Double"); // five hearts, too weak to bid freely
      expect(openingBid("432", "AKQ32", "Q32", "32", history: ["1D", "1S"]),
          "2H"); // strong enough to bid the suit
      expect(openingBid("KQ32", "KJ32", "432", "32", history: ["1D", "2C"]),
          "Double"); // both majors
      expect(openingBid("KQ32", "432", "Q32", "J32", history: ["1C", "1H"]),
          "Double"); // exactly four spades
      expect(openingBid("KQ432", "432", "Q32", "32", history: ["1C", "1H"]),
          "1S"); // five spades
    });

    test("raises keep their meanings", () {
      expect(openingBid("432", "K32", "KQ32", "432", history: ["1H", "1S"]),
          "2H");
      expect(openingBid("K32", "K32", "KQ32", "432", history: ["1H", "2C"]),
          "3H");
      expect(openingBid("32", "K432", "AK32", "K32", history: ["1H", "1S"]),
          "4H");
    });

    test("three-level free bids with 12+", () {
      expect(openingBid("Q", "QJ9874", "AT3", "AQ4", history: ["1D", "2S"]),
          "3H");
    });

    test("notrump with a stopper", () {
      expect(openingBid("K32", "KJ3", "J32", "Q432", history: ["1D", "1H"]),
          "1NT");
      expect(openingBid("K32", "432", "J32", "Q543", history: ["1D", "1H"]),
          "Pass");
      expect(
          selectSaycBid(parseHand(exampleHandString),
                  ["1H", "1S"].map(BidAction.fromString).toList())
              .action
              .toString(),
          "3NT"); // 13 with a spade stopper
    });

    test("over RHO's takeout double", () {
      expect(openingBid("KQ32", "2", "KJ32", "Q432", history: ["1H", "X"]),
          "Redouble");
      expect(openingBid("432", "K32", "KQ32", "432", history: ["1H", "X"]),
          "2H"); // systems on
    });
  });

  group("advances", () {
    test("of a takeout double", () {
      expect(openingBid("Q432", "J432", "432", "32", history: ["1D", "X", "pass"]),
          "1H"); // forced, up the line
      expect(openingBid("K432", "KQ32", "Q32", "32", history: ["1D", "X", "pass"]),
          "2H"); // 9-11 jump
      expect(openingBid("K432", "KQ32", "A32", "32", history: ["1D", "X", "pass"]),
          "4H"); // 12+
    });

    test("never jumps past game", () {
      expect(openingBid("65", "Q76", "KJ", "QJT876", history: ["4S", "X", "pass"]),
          "5C");
    });

    test("of an overcall", () {
      expect(openingBid("K32", "Q432", "432", "Q32", history: ["1D", "1S", "pass"]),
          "2S");
      expect(openingBid("Q2", "K432", "KJ32", "J32", history: ["1D", "1S", "pass"]),
          "1NT");
      expect(openingBid("KQ432", "32", "432", "432", history: ["1D", "1NT", "pass"]),
          "2H"); // systems on over partner's 1NT overcall
      expect(openingBid("K32", "Q432", "432", "Q32", history: ["1D", "1S", "2D"]),
          "2S"); // free advance over their raise
    });

    test("free advances are not forced", () {
      expect(openingBid("KQ32", "432", "K432", "32", history: ["1H", "X", "2H"]),
          "2S");
      expect(openingBid("Q432", "432", "J432", "32", history: ["1H", "X", "2H"]),
          "Pass");
    });
  });

  group("competitive continuations", () {
    test("opener after partner's negative double", () {
      final h = ["1D", "1S", "X", "pass"];
      expect(openingBid("432", "KQ32", "AKJ32", "2", history: h), "2H");
      expect(openingBid("32", "KQ32", "AKQJ32", "2", history: h), "3H");
      expect(openingBid("K32", "K32", "AQJ32", "32", history: h), "1NT");
      expect(openingBid("32", "432", "AKJ432", "A2", history: h), "2D");
    });

    test("reopening seat", () {
      final h = ["1D", "1S", "pass", "pass"];
      expect(openingBid("2", "K432", "AQ432", "K32", history: h), "Double");
      expect(openingBid("432", "K4", "AKJ432", "Q2", history: h), "2D");
      expect(openingBid("A32", "K32", "AQJ32", "A2", history: h), "1NT");
      expect(openingBid("KQ32", "K32", "AQ432", "2", history: h), "Pass");
    });

    test("sandwich seat", () {
      expect(openingBid("KQ32", "2", "AJ32", "K432", history: ["1H", "pass", "2H"]),
          "Double");
      expect(openingBid("AKJ32", "32", "K32", "K32", history: ["1H", "pass", "2H"]),
          "2S");
      final twoSuits = selectSaycBid(hand("2", "KQ32", "A32", "AQ432"),
          ["1D", "pass", "1S"].map(BidAction.fromString).toList());
      expect(twoSuits.action.toString(), "Double");
      expect(twoSuits.meaning.suitLengths[Suit.hearts], const Range(low: 4));
      expect(openingBid("K32", "K32", "Q432", "Q32", history: ["1D", "pass", "1S"]),
          "Pass");
    });

    test("responder's second call after a negative double", () {
      final h = ["1D", "1S", "X", "pass", "2H", "pass"];
      expect(openingBid("432", "KQ32", "Q32", "J32", history: h), "Pass");
      expect(openingBid("432", "KQ32", "QJ2", "QJ2", history: h), "3H");
      expect(openingBid("A32", "KQ32", "QJ2", "J32", history: h), "4H");
      expect(
          openingBid("432", "KQ32", "Q32", "J32",
              history: ["1D", "1S", "X", "pass", "3H", "pass"]),
          "4H"); // accepting the jump
    });

    test("competing when partner passes", () {
      final h = ["1S", "2C", "2S", "3C", "pass", "pass"];
      expect(openingBid("K432", "Q32", "K32", "432", history: h), "3S");
      expect(openingBid("K32", "Q432", "K32", "432", history: h), "Pass");
    });

    test("penalty pass of a reopening double", () {
      final h = ["1D", "1S", "pass", "pass", "X", "pass"];
      expect(openingBid("AKJ32", "432", "32", "432", history: h), "Pass");
      expect(openingBid("432", "K432", "Q32", "432", history: h), "2H");
    });
  });

  group("fallback bidder", () {
    test("passes when game is reached", () {
      final result = selectSaycBid(
          hand("A432", "QJ32", "QJ2", "32"),
          ["1NT", "pass", "2C", "pass", "2H", "pass", "3NT", "pass", "4S", "pass"]
              .map(BidAction.fromString)
              .toList());
      expect(result.action.toString(), "Pass");
      expect(result.meaning.description, contains("Fallback"));
    });

    test("competes to the level of combined trumps", () {
      expect(openingBid("AKJ432", "32", "32", "432",
              history: ["1D", "1S", "2D", "2S", "3D"]),
          "3S");
      expect(openingBid("AKQJ32", "A2", "K2", "432",
              history: ["1D", "1S", "2D", "2S", "3D"]),
          "4S");
    });

    test("respects partner's shown weakness", () {
      expect(openingBid("KQ32", "2", "AJ32", "K432",
              history: ["1H", "X", "2H", "pass", "pass"]),
          "Pass");
    });

    test("penalty doubles with a trump stack", () {
      expect(
          selectSaycBid(parseHand("A2 AKJT Q32 9876"),
                  ["2H", "X", "3H", "pass", "pass"]
                      .map(BidAction.fromString)
                      .toList())
              .action
              .toString(),
          "Double");
      // Never doubles an already-doubled contract.
      expect(
          selectSaycBid(parseHand("A2 AKJT Q32 9876"),
                  ["1D", "1H", "1S", "2H", "X", "pass"]
                      .map(BidAction.fromString)
                      .toList())
              .action
              .toString(),
          isNot("Double"));
    });

    test("doubles their preempt on combined strength", () {
      expect(openingBid("AKQ32", "32", "AK32", "32",
              history: ["1S", "pass", "2S", "4H"]),
          "Double");
    });
  });

  group("parity: parsing and summaries", () {
    test("ten parses as T or 10", () {
      final a = parseHand("AS KS QS JS 10S 9S 8S 7S 6S 5S 4S 3S 2S");
      final b = parseHand("AS KS QS JS TS 9S 8S 7S 6S 5S 4S 3S 2S");
      expect(a.toSet(), b.toSet());
    });

    test("invalid token rejected", () {
      expect(() => parseHand("AS KS QS JS TS 9S 8S 7S 6S 5S 4S 3S 1S"),
          throwsFormatException);
    });

    test("meaning summaries", () {
      final nt = describeSaycCall([], BidAction.noTrump(1))!.summary();
      expect(nt, contains("15-17 HCP"));
      expect(nt, contains("balanced"));
      final spade = describeSaycCall([], BidAction.fromString("1S"))!.summary();
      expect(spade, contains("5+ spades"));
      expect(spade, contains("13-21 total points"));
      final weakTwo = describeSaycCall([], BidAction.fromString("2S"))!.summary();
      expect(weakTwo, contains("6 spades"));
      expect(weakTwo, contains("5-10 HCP"));
    });

    test("vulnerability parameter is accepted", () {
      final result = selectSaycBid(parseHand(exampleHandString), [],
          vulnerability: Vulnerability.both);
      expect(result.action.toString(), "1D");
    });
  });

  group("parity: opener rebids", () {
    test("raise responder's major after a minor opening", () {
      expect(
          openingBid("K32", "KQ32", "32", "AQ32",
              history: ["1C", "pass", "1H", "pass"]),
          "2H");
    });

    test("2NT rebid over a two-over-one", () {
      expect(
          openingBid("AKJ32", "K32", "32", "Q32",
              history: ["1S", "pass", "2C", "pass"]),
          "2NT");
    });

    test("game after a single raise with 19+", () {
      expect(
          openingBid("AKJ32", "AK2", "KJ2", "32",
              history: ["1S", "pass", "2S", "pass"]),
          "4S");
    });

    test("natural 2NT over a minor raised to game", () {
      expect(
          openingBid("K32", "K32", "AQ32", "J32",
              history: ["1D", "pass", "2NT", "pass"]),
          "3NT");
    });

    test("rebids after a 1NT response", () {
      final nt = ["1S", "pass", "1NT", "pass"];
      expect(openingBid("AKJ432", "32", "K32", "Q2", history: nt), "2S");
      expect(openingBid("AKJ32", "32", "32", "KQ32", history: nt), "2C");
      expect(openingBid("AKJ32", "K32", "Q32", "32", history: nt), "Pass");
    });

    test("weak two opener passes the raise", () {
      expect(
          openingBid("KQJ432", "32", "432", "32",
              history: ["2S", "pass", "3S", "pass"]),
          "Pass");
    });

    test("completes the transfer to spades", () {
      expect(
          openingBid("K32", "A32", "AQ32", "KJ2",
              history: ["1NT", "pass", "2H", "pass"]),
          "2S");
    });
  });

  group("parity: responder rebids", () {
    test("2NT after a Stayman denial", () {
      expect(
          openingBid("K432", "Q432", "QJ2", "32",
              history: ["1NT", "pass", "2C", "pass", "2D", "pass"]),
          "2NT");
    });

    test("4S after a spade transfer", () {
      expect(
          openingBid("KQJ432", "32", "K32", "K2",
              history: ["1NT", "pass", "2H", "pass", "2S", "pass"]),
          "4S");
    });

    test("game-try decisions", () {
      final tryH = ["1S", "pass", "2S", "pass", "3S", "pass"];
      expect(openingBid("K32", "Q432", "K32", "Q32", history: tryH), "4S");
      expect(openingBid("K32", "Q432", "Q32", "432", history: tryH), "Pass");
    });

    test("Jacoby continuations without slam values", () {
      expect(
          openingBid("K432", "A432", "AK2", "32",
              history: ["1S", "pass", "2NT", "pass", "4S", "pass"]),
          "Pass");
      expect(
          openingBid("K432", "A432", "AK2", "32",
              history: ["1S", "pass", "2NT", "pass", "3S", "pass"]),
          "4S");
    });

    test("after opener's jump raise", () {
      final jump = ["1D", "pass", "1S", "pass", "3S", "pass"];
      expect(openingBid("KQ32", "432", "Q32", "J32", history: jump), "4S");
      expect(openingBid("Q432", "K32", "432", "J32", history: jump), "Pass");
    });

    test("over opener's 2NT jump rebid", () {
      final jump = ["1D", "pass", "1S", "pass", "2NT", "pass"];
      expect(openingBid("KQ32", "432", "Q32", "J32", history: jump), "3NT");
      expect(openingBid("KQJ432", "32", "Q32", "32", history: jump), "4S");
    });

    test("2NT invite over a second suit", () {
      expect(
          openingBid("KQ32", "K32", "K32", "J32",
              history: ["1D", "pass", "1S", "pass", "2C", "pass"]),
          "2NT");
    });

    test("raising opener's second-suit major", () {
      final h = ["1C", "pass", "1D", "pass", "1H", "pass"];
      expect(openingBid("432", "K432", "AQ43", "32", history: h), "2H");
      expect(openingBid("432", "K432", "AQJ432", "-", history: h), "3H");
      expect(openingBid("432", "32", "AQ432", "J32", history: h), "1NT");
    });

    test("continuations after our 1NT response", () {
      expect(
          openingBid("32", "KQ432", "Q432", "32",
              history: ["1S", "pass", "1NT", "pass", "2C", "pass"]),
          "2S"); // preference
      expect(
          openingBid("32", "K432", "Q432", "K32",
              history: ["1S", "pass", "1NT", "pass", "2C", "pass"]),
          "Pass");
      expect(
          openingBid("32", "K432", "Q432", "K32",
              history: ["1S", "pass", "1NT", "pass", "2S", "pass"]),
          "Pass");
      expect(
          openingBid("32", "K432", "Q432", "K32",
              history: ["1S", "pass", "1NT", "pass", "3S", "pass"]),
          "4S");
      expect(
          openingBid("32", "K432", "Q432", "K32",
              history: ["1S", "pass", "1NT", "pass", "2NT", "pass"]),
          "3NT");
    });

    test("pass a 2NT rebid after a minimum two-over-one", () {
      expect(
          openingBid("K32", "432", "32", "KQJ43",
              history: ["1S", "pass", "2C", "pass", "2NT", "pass"]),
          "Pass");
    });
  });

  group("parity: competitive", () {
    test("balancing seat treated as direct", () {
      expect(
          openingBid("AKJ32", "432", "32", "432",
              history: ["1H", "pass", "pass"]),
          "1S");
    });

    test("raise beats negative double after a major opening", () {
      expect(openingBid("KQ32", "K32", "J432", "32", history: ["1H", "2C"]),
          "2H");
    });

    test("penalty double of their 1NT overcall", () {
      expect(openingBid("KQ32", "2", "KJ32", "Q432", history: ["1H", "1NT"]),
          "Double");
    });

    test("no optional double without trump quality", () {
      expect(
          selectSaycBid(parseHand("A2 5432 KQ32 A32"),
                  [BidAction.fromString("4H")])
              .action
              .toString(),
          "Pass");
    });

    test("negative-double continuations over notrump and suit rebids", () {
      expect(
          openingBid("KQ32", "432", "Q32", "J32",
              history: ["1C", "1H", "X", "pass", "1NT", "pass"]),
          "Pass");
      expect(
          openingBid("KQ32", "432", "QJ3", "KJ2",
              history: ["1C", "1H", "X", "pass", "1NT", "pass"]),
          "2NT");
      expect(
          openingBid("432", "KQ32", "Q32", "J32",
              history: ["1D", "1S", "X", "pass", "2D", "pass"]),
          "Pass");
      expect(
          openingBid("432", "KQ32", "QJ2", "QJ2",
              history: ["1D", "1S", "X", "pass", "2D", "pass"]),
          "3D");
      expect(
          openingBid("432", "KQ32", "QJ32", "32",
              history: ["1D", "1S", "X", "pass", "2C", "pass"]),
          "2D"); // preference
      expect(
          openingBid("432", "KQ32", "Q32", "J32",
              history: ["1D", "1S", "X", "pass", "2C", "pass"]),
          "Pass");
    });

    test("game after a raise with an LHO overcall", () {
      expect(
          openingBid("KQ32", "A32", "K32", "J32",
              history: ["1D", "pass", "1S", "2C", "2S", "pass"]),
          "4S");
    });

    test("pass 3NT after our natural 2NT in competition", () {
      expect(
          openingBid("K32", "KJ3", "QJ32", "Q32",
              history: ["1D", "1H", "2NT", "pass", "3NT", "pass"]),
          "Pass");
    });

    test("compete with a six-card suit when partner passes", () {
      expect(
          openingBid("KQJ432", "32", "432", "32",
              history: ["1D", "1H", "1S", "2H", "pass", "pass"]),
          "2S");
    });
  });

  group("parity: slam and third calls", () {
    test("2NT opener accepts quantitative with 21", () {
      expect(
          openingBid("AK2", "KQ2", "KQ32", "KJ2",
              history: ["2NT", "pass", "4NT", "pass"]),
          "6NT");
    });

    test("opener passes responder's signoff", () {
      expect(
          openingBid("K32", "KJ2", "AQ32", "J32",
              history: ["1D", "pass", "1S", "pass", "1NT", "pass", "2S", "pass"]),
          "Pass");
    });

    test("transfer invitation decisions", () {
      final invite = ["1NT", "pass", "2D", "pass", "2H", "pass", "2NT", "pass"];
      expect(openingBid("K32", "A32", "AQ32", "KJ2", history: invite), "4H");
      expect(openingBid("K32", "A32", "AQ32", "Q32", history: invite), "Pass");
    });
  });

  group("parity: missed-game fixes", () {
    test("game over a jump rebid after a two-over-one", () {
      expect(
          openingBid("-", "QJ876", "AKT74", "842",
              history: ["1S", "pass", "2H", "pass", "3S", "pass"]),
          "3NT");
    });

    test("responder bids game over a jump shift after 1NT", () {
      expect(
          openingBid("32", "Q432", "KJ32", "Q32",
              history: ["1S", "pass", "1NT", "pass", "3H", "pass"]),
          "4H");
    });

    test("advancer bids 3NT over a strong overcall", () {
      expect(openingBid("KQ32", "32", "A432", "K32", history: ["2S", "3H", "pass"]),
          "3NT");
    });

    test("opener invites over 1NT with 17+", () {
      expect(
          openingBid("AQ32", "AKJ2", "2", "KJ32",
              history: ["1C", "pass", "1D", "pass", "1H", "pass", "1NT", "pass"]),
          "2NT");
    });
  });

  group("parity: fallback", () {
    test("raises partner to game in a deep auction", () {
      expect(
          openingBid("KQ32", "A32", "K32", "J32", history: [
            "1D", "pass", "1S", "pass", "2C", "pass", "2D", "pass",
            "2S", "pass"
          ]),
          "4S");
    });

    test("3NT with a stopper and combined strength", () {
      expect(
          selectSaycBid(parseHand(exampleHandString),
                  ["1D", "1H", "1S", "2H", "X", "pass"]
                      .map(BidAction.fromString)
                      .toList())
              .action
              .toString(),
          "3NT");
    });

    test("passes without values in an unknown position", () {
      expect(
          selectSaycBid(parseHand(exampleHandString),
                  ["1C", "pass", "1H", "pass", "1S"]
                      .map(BidAction.fromString)
                      .toList())
              .action
              .toString(),
          "Pass");
    });
  });

  group("parity: dispatch", () {
    test("completed auction rejected even where the fallback would apply", () {
      expect(
          () => selectSaycBid(
              parseHand(exampleHandString),
              ["1S", "pass", "2S", "pass", "pass", "pass"]
                  .map(BidAction.fromString)
                  .toList()),
          throwsStateError);
    });

    test("passed hand still responds", () {
      expect(
          openingBid("K32", "Q432", "K32", "432",
              history: ["pass", "pass", "1S", "pass"]),
          "2S");
    });
  });

  group("parity: describe and explain", () {
    test("describe 2C opening", () {
      expect(describeSaycCall([], BidAction.fromString("2C"))!.hcp,
          const Range(low: 22));
    });

    test("describe a single raise", () {
      final meaning = describeSaycCall(
          ["1S", "pass"].map(BidAction.fromString).toList(),
          BidAction.fromString("2S"))!;
      expect(meaning.totalPoints, const Range(low: 6, high: 10));
      expect(meaning.suitLengths[Suit.spades], const Range(low: 3));
    });

    test("describe Jacoby 2NT", () {
      final meaning = describeSaycCall(
          ["1H", "pass"].map(BidAction.fromString).toList(),
          BidAction.noTrump(2))!;
      expect(meaning.artificial, true);
      expect(meaning.suitLengths[Suit.hearts], const Range(low: 4));
      expect(meaning.totalPoints, const Range(low: 13));
    });

    test("describe Stayman and transfers", () {
      final nt1 = ["1NT", "pass"].map(BidAction.fromString).toList();
      final stayman = describeSaycCall(nt1, BidAction.fromString("2C"))!;
      expect(stayman.artificial, true);
      expect(stayman.hcp, const Range(low: 8));
      final transfer = describeSaycCall(nt1, BidAction.fromString("2D"))!;
      expect(transfer.artificial, true);
      expect(transfer.suitLengths[Suit.hearts], const Range(low: 5));
    });

    test("describe a negative double", () {
      final meaning = describeSaycCall(
          ["1D", "1S"].map(BidAction.fromString).toList(),
          BidAction.double())!;
      expect(meaning.artificial, true);
      expect(meaning.suitLengths[Suit.hearts], const Range(low: 4));
    });

    test("describe an overcall", () {
      final meaning = describeSaycCall(
          [BidAction.fromString("1H")], BidAction.fromString("1S"))!;
      expect(meaning.hcp, const Range(low: 8, high: 16));
      expect(meaning.suitLengths[Suit.spades], const Range(low: 5));
    });

    test("describe opener's raise of the response", () {
      final meaning = describeSaycCall(
          ["1D", "pass", "1S", "pass"].map(BidAction.fromString).toList(),
          BidAction.fromString("2S"))!;
      expect(meaning.totalPoints, const Range(low: 13, high: 15));
      expect(meaning.suitLengths[Suit.spades], const Range(low: 4));
    });

    test("describe merges weak and strong meanings", () {
      final meaning = describeSaycCall(
          ["1H", "pass"].map(BidAction.fromString).toList(),
          BidAction.fromString("1S"))!;
      expect(meaning.suitLengths[Suit.spades], const Range(low: 4));
      expect(meaning.totalPoints, const Range(low: 6));
    });

    test("describe returns null for uncovered positions", () {
      expect(
          describeSaycCall(
              ["1D", "1H", "1S", "2H", "X", "pass"]
                  .map(BidAction.fromString)
                  .toList(),
              BidAction.fromString("3S")),
          null);
    });

    test("explain intersects a player's calls", () {
      final ex = explainSaycAuction(["1S", "pass", "2S", "pass", "3S", "pass"]
          .map(BidAction.fromString)
          .toList());
      expect(ex.players[0]!.totalPoints, const Range(low: 16, high: 18));
      expect(ex.players[0]!.suitLengths[Suit.spades], const Range(low: 5));
      expect(ex.players[2]!.totalPoints, const Range(low: 6, high: 10));
    });

    test("explain marks meaningless calls as null", () {
      final ex = explainSaycAuction(
          ["1NT", "pass", "5C", "pass"].map(BidAction.fromString).toList());
      expect(ex.calls[2].meaning, null);
      expect(ex.calls[1].meaning, isNotNull);
    });
  });

  group("self-play invariants", () {
    test("no hard failures over random deals", () {
      for (int index = 0; index < 150; index++) {
        final hands = dealHands(1, index);
        final result = runDeal(hands);
        final failures = result.findings
            .where((f) => hardFailureCategories.contains(f.category))
            .toList();
        expect(failures, isEmpty,
            reason: "deal $index (seed 1): $failures; "
                "auction: ${result.history.map((c) => '$c').join(' ')}");
      }
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
