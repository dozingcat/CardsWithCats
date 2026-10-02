// Failing cases from an adversarial audit of the SAYC bidding engine
// (2026-10). Every case is an AI-only auction: the engine bids all four
// seats of a full deal, so each bad call is reachable in real play rather
// than relying on a human making a convention the engine doesn't model.
//
// Deals were found with scripts/complete_deal.dart (or come from
// self-play, cited by seed and deal index). Each test first checks that the
// engine still produces the auction leading up to the bad call: if a fix
// elsewhere changes an earlier call, the test fails with a "setup" reason
// and the deal needs to be re-found rather than the fix being credited.
//
// The cases are marked knownFailure until fixed: they pass while the
// engine still makes the bad call and fail ("now passes") once it doesn't,
// so a fix turns the case back into a plain test.
import "package:cards_with_cats/bridge/bridge.dart";
import "package:cards_with_cats/bridge/sayc/sayc_bidding.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:flutter_test/flutter_test.dart";

List<BidAction> _calls(String s) => s.trim().isEmpty
    ? []
    : s.trim().split(RegExp(r"\s+")).map(BidAction.fromString).toList();

bool _auctionOver(List<BidAction> h) =>
    h.length >= 4 &&
    h.sublist(h.length - 3).every((c) => c.bidType == BidType.pass);

/// The engine's call for the next seat after [prefix] on [hands] (dealer
/// first), after checking that the engine itself makes every call in
/// [prefix].
String engineCallAfter(List<String> hands, String prefix) {
  final deal = hands.map(parseHand).toList();
  final history = _calls(prefix);
  for (int i = 0; i < history.length; i++) {
    final call = selectSaycBid(deal[i % 4], history.sublist(0, i)).action;
    expect(call, history[i],
        reason: "setup: the engine no longer bids the auction prefix "
            "'$prefix' (call $i is $call); re-find the deal");
  }
  return selectSaycBid(deal[history.length % 4], history).action.toString();
}

/// The full engine auction on [hands], checked against [expectedPrefix].
List<BidAction> engineAuction(List<String> hands, String expectedPrefix) {
  final deal = hands.map(parseHand).toList();
  final history = <BidAction>[];
  while (!_auctionOver(history) && history.length < 60) {
    history.add(selectSaycBid(deal[history.length % 4], history).action);
  }
  final prefix = _calls(expectedPrefix);
  expect(history.take(prefix.length).toList(), prefix,
      reason: "setup: the engine no longer bids the auction prefix "
          "'$expectedPrefix' (got '${history.join(' ')}'); re-find the deal");
  return history;
}

/// A test for a known engine flaw: it passes while [body] fails and fails
/// once [body] passes, so a fix is noticed and the case turned back into a
/// plain test. A setup failure (the engine no longer reaches the position)
/// is never treated as the known failure.
void knownFailure(String description, dynamic Function() body) {
  test("$description [known failure]", () async {
    try {
      await body();
    } on TestFailure catch (e) {
      if (e.message?.contains("setup:") ?? false) rethrow;
      return;
    }
    fail("now passes: change knownFailure(...) back to test(...)");
  });
}

ContractBid? finalContract(List<BidAction> history) {
  for (final call in history.reversed) {
    if (call.bidType == BidType.contract) return call.contractBid;
  }
  return null;
}

void main() {
  group("audit: Blackwood", () {
    test("contested Blackwood: the asker places the contract", () {
      // Uncontested (1S-2S-4NT-5H) this hand bids 6S; after the 2C
      // overcall the placement falls to the fallback bidder, which treats
      // the artificial 5H answer as "game reached" and passes it.
      final call = engineCallAfter([
        "AKQJ432 AKJ2 K2 -",
        "- Q4 QJ4 KQJT7542",
        "T876 653 A965 A3",
        "95 T987 T873 986",
      ], "1S 2C 2S pass 4NT pass 5H pass");
      expect(call, "6S");
    });

    test("contested Blackwood: the responder answers 4NT", () {
      // Self-play seed 2026 deal 252: the opener passes partner's 4NT
      // ("game already reached") because the third call is fallback
      // territory after an overcall.
      final call = engineCallAfter([
        "84 T87 J86 QJT84",
        "AKQJ753 9 92 A76",
        "T9 AKQJ6543 75 5",
        "62 2 AKQT43 K932",
      ], "pass 1S 2H 3D pass 4S pass 4NT pass");
      expect(call, "5H"); // two aces
    });

    knownFailure("minor-suit Blackwood doesn't bid slam missing two aces", () {
      // 1S-2C-3C-4NT-5D: the asker holds one ace and nothing gates the ask
      // on controls; the 5D answer (one ace) is above five clubs, so the
      // placement forces 6C with the ace of diamonds and ace of clubs
      // both missing.
      final history = engineAuction([
        "KQJ32 A32 Q T987",
        "T987 JT98 AJT9 A",
        "A4 KQ5 K5 KQJ654",
        "65 764 876432 32",
      ], "1S pass 2C pass 3C pass");
      expect(finalContract(history)!.count, lessThan(6),
          reason: "auction: ${history.join(' ')}");
    });

    test("Blackwood with no fit doesn't land in opener's suit", () {
      // Self-play seed 2024 deal 2865: responder with eight solid hearts
      // and a singleton spade asks over 1S-2H-3S and then bids 6S on a
      // 6-1 fit.
      final history = engineAuction([
        "J87532 2 AK AQ52",
        "AT94 643 863 K86",
        "K AKQT9875 T T73",
        "Q6 J QJ97542 J94",
      ], "1S pass 2H pass 3S pass");
      // Responder plays its own eight solid hearts.
      expect(finalContract(history), ContractBid(4, Suit.hearts),
          reason: "auction: ${history.join(' ')}");
    });
  });

  group("audit: passing with game or slam values", () {
    test("a 2C opener doesn't sell out when the overcall is passed back", () {
      final call = engineCallAfter([
        "- AKQJ32 AKQ2 AK2",
        "AKQT92 8 865 Q74",
        "74 T9764 93 J953",
        "J8653 5 JT74 T86",
      ], "2C 2S pass pass");
      expect(call, "3H");
    });

    knownFailure("responder doesn't pass opener's 18-19 3NT rebid with 18 HCP", () {
      // Self-play seed 99 deal 780: 36+ combined HCP.
      final call = engineCallAfter([
        "T9762 872 AT965 -",
        "AK543 KJT K3 AT2",
        "8 943 8742 98763",
        "QJ AQ65 QJ KQJ54",
      ], "pass 1S pass 2C pass 3NT pass");
      expect(call, isNot("Pass"));
    });

    knownFailure("Stayman finds a fit and a 20-count responder looks for slam", () {
      // 35-37 combined HCP with a 4-4 spade fit stops in 4S.
      final history = engineAuction([
        "KJ54 Q32 AK3 Q32",
        "976 J9854 J72 76",
        "AQ32 AK7 Q4 AK54",
        "T8 T6 T9865 JT98",
      ], "1NT pass 2C pass 2S pass");
      expect(finalContract(history)!.count, greaterThanOrEqualTo(6),
          reason: "auction: ${history.join(' ')}");
    });

    knownFailure("2C-2D-2S: a raise with values doesn't stop in game", () {
      // 35 HCP and a nine-card fit: responder's jump to 4S is the same
      // call with 1 HCP or 11, and opener always passes it.
      final history = engineAuction([
        "AKQJT2 KQ2 AQ2 A",
        "976 JT9 JT9 QJT9",
        "8543 A543 K543 K",
        "- 876 876 8765432",
      ], "2C pass 2D pass 2S pass");
      expect(finalContract(history)!.count, greaterThanOrEqualTo(6),
          reason: "auction: ${history.join(' ')}");
    });

    test("opener rebids after RHO bids over partner's response", () {
      // 1H-P-1S-(2C) is fallback territory, which passes 18 HCP and six
      // solid hearts (and 5-5 hands, and 3-card spade support).
      final call = engineCallAfter([
        "K2 AKQJ87 AQ4 52",
        "865 654 JT752 96",
        "JT74 32 K93 QT73",
        "AQ93 T9 86 AKJ84",
      ], "1H pass 1S 2C");
      expect(call, "4H");
    });

    knownFailure("a strong takeout doubler acts again after a raise", () {
      final call = engineCallAfter([
        "T3 AJ4 KJ976 KT9",
        "AKQJ52 K87 AQ4 2",
        "876 2 8532 AQ753",
        "94 QT9653 T J864",
      ], "1D X 2D pass pass");
      expect(call, isNot("Pass"));
    });

    knownFailure("responder raises partner's weak two to game over an overcall", () {
      // The same hand bids 4S over 2S-P and 2S-X; over 2S-(3H) the
      // fallback only competes to 3S.
      final call = engineCallAfter([
        "K98765 84 T5 QJ6",
        "J KJT96 KQJ97 A9",
        "AQ2 AQ2 A432 432",
        "T43 753 86 KT875",
      ], "2S 3H");
      expect(call, "4S");
    });

    knownFailure("advancer acts opposite a weak jump overcall with a fit and 14", () {
      // Raises opposite a weak jump stop at 12 points and game needs 17,
      // so 13-16 with a fit (here an 11-card fit) passes.
      final call = engineCallAfter([
        "A7 QJ9742 J8 QJT",
        "QJT9643 K3 K7 43",
        "- T65 QT532 A9876",
        "K852 A8 A964 K52",
      ], "1H 2S pass");
      expect(call, isNot("Pass"));
    });

    test("responder acts over 1NT-(2C) with 10 HCP and both majors", () {
      // No rules for interference over our 1NT: the fallback passes
      // without a club stopper, missing game with 27 combined.
      final call = engineCallAfter([
        "AT7 Q86 AK98 A76",
        "5 KT4 Q65 KQT985",
        "KQ32 AJ32 32 432",
        "J9864 975 JT74 J",
      ], "1NT 2C");
      expect(call, "3C"); // cue bid: Stayman, game forcing
    });

    knownFailure("a nine-card solid suit does more than a simple overcall", () {
      // Self-play seed 2026 deal 368: 3D over 3C with AKQJ98654 and 15
      // HCP is passed out; 5D makes 12 tricks.
      final call = engineCallAfter([
        "T73 KT8 73 AKT73",
        "J AQJ52 - J986542",
        "K94 - AKQJ98654 Q",
        "AQ8652 97643 T2 -",
      ], "pass 3C");
      expect(call, isNot("3D"));
    });

    knownFailure("opener's reopening rebid shows a strong hand", () {
      // The reopening table has a single cheapest-level suit rebid, so 19
      // HCP with seven solid spades bids the same 2S as a minimum.
      final call = engineCallAfter([
        "AKQJ987 AKQ 32 2",
        "- JT97643 AQJ AK5",
        "2 85 8765 QJ7643",
        "T6543 2 KT94 T98",
      ], "1S 2H pass pass");
      expect(call, isNot("2S"));
    });
  });

  group("audit: misread or misjudged competitive calls", () {
    test("a natural 2H over 1NT-(2C) isn't completed as a transfer", () {
      // Responder's fallback bids 2H as a natural six-card suit; opener
      // treats it as Jacoby and bids 2S, and responder passes 2S with Qxx.
      final call = engineCallAfter([
        "AK3 Q32 KJ4 Q432",
        "J94 A T75 AKT875",
        "Q32 KJ9876 432 2",
        "T875 T54 AQ986 9",
      ], "1NT 2C 2H pass");
      expect(call, "Pass");
    });

    test("no penalty double of a competitive raise without trump tricks", () {
      // The fallback's "doubling their preempt on combined strength"
      // treats any 3-level contract as a preempt: here a singleton heart,
      // with an eight-card spade fit. This rule was behind 15 of the 150
      // largest double-dummy losses over 3000 self-play deals.
      final call = engineCallAfter([
        "AKJ52 82 AQ64 Q2",
        "7 AKJ974 T5 Q843",
        "863 T5 K973 AT95",
        "QT94 Q63 J82 J76",
      ], "1S 2H 2S 3H");
      expect(call, "Pass");
    });

    test("no five-level raise of an overcall with three trumps", () {
      // 1S-(2H)-4S: an eight-card fit and defensive values; the four-level
      // raise gate also admits the five level.
      final call = engineCallAfter([
        "KJ974 84 QJ8 AQ9",
        "6 AQJT653 75 KJT",
        "AT32 9 KT32 7643",
        "Q85 K72 A964 852",
      ], "1S 2H 4S");
      expect(call, "Pass");
    });

    test("responder converts opener's reopening double with a trump stack",
        () {
      // KJT97 sitting over the overcaller's hearts: the penalty-pass rule
      // wants 5+ HCP in trumps, so this bids 3C instead.
      final call = engineCallAfter([
        "AJ8764 8 AKT3 86",
        "KT9 AQ642 5 AQ73",
        "Q2 KJT97 864 K52",
        "53 53 QJ972 JT94",
      ], "1S 2H pass pass X pass");
      expect(call, "Pass");
    });

    test("a double of a four-level preempt can be left in", () {
      // The doubler is void in hearts; KJT9 of trumps still pulls to 5C.
      final call = engineCallAfter([
        "4 AQ765432 86 96",
        "AJT975 - A75 AKJT",
        "KQ86 8 KQT43 874",
        "32 KJT9 J92 Q532",
      ], "4H X pass");
      expect(call, "Pass");
    });

    test("the doubler corrects a forced 5C advance to a solid major", () {
      // Partner's 5C was a forced 0-11 advance, not a game decision; the
      // doubler holds seven solid spades and a singleton club.
      final call = engineCallAfter([
        "653 QJT98765 Q7 -",
        "AKQJ987 A2 K32 2",
        "2 K43 A85 AQJ963",
        "T4 - JT964 KT8754",
      ], "4H X pass 5C pass");
      expect(call, "5S");
    });

    test("advancer runs from our doubled 1NT overcall with six hearts", () {
      final call = engineCallAfter([
        "94 - AJ876 AJ9875",
        "AT8 JT KQT95 KQT",
        "KQJ765 A9765 - 64",
        "32 KQ8432 432 32",
      ], "1C 1NT X");
      expect(call, "2H");
    });
  });

  group("audit: notrump games with a long suit or a void", () {
    knownFailure("seven solid spades play in 4S, not 3NT, opposite a singleton",
        () {
      // The same hand bids 4S over a 1NT rebid.
      final call = engineCallAfter([
        "4 AK9765 T97 AT7",
        "65 JT84 QJ4 K865",
        "AKQJ987 2 K32 32",
        "T32 Q3 A865 QJ94",
      ], "1H pass 1S pass 2H pass");
      expect(call, "4S");
    });

    knownFailure("no 3NT with a void in opener's suit and a fit for the second", () {
      // Self-play seed 2026 deal 99: responder is void in hearts with
      // four clubs opposite opener's 3C; NS make 13 tricks in clubs.
      final call = engineCallAfter([
        "K7 AQJT2 A KJ652",
        "Q6543 864 QJ T98",
        "AJT2 - K9852 AQ74",
        "98 K9753 T7643 3",
      ], "1H pass 2D pass 3C pass");
      expect(call, isNot("3NT"));
    });
  });
}
