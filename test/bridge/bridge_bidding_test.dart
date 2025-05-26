import "dart:math";

import "package:cards_with_cats/bridge/bridge_bidding.dart";
import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/bridge/bridge.dart";
import "package:cards_with_cats/bridge/utils.dart";

const c = PlayingCard.cardsFromString;
const cb = ContractBid.fromString;

PlayerBid getOpeningBid(List<PlayingCard> hand) {
  final req = BidRequest(
    playerIndex: 0,
    hand: hand,
    bidHistory: [],
  );
  print("getOpeningBid: $hand");
  return chooseBid(req);
}

BidAction getResponseToBidSequence(
    List<PlayingCard> hand, List<BidAction> bids) {
  int playerIndex = bids.length % 4;
  print("playerIndex: $playerIndex");
  final bidHistory =
      List.generate(bids.length, (n) => PlayerBid(n % 4, bids[n]));
  final req = BidRequest(
    playerIndex: playerIndex,
    hand: hand,
    bidHistory: bidHistory,
  );
  return chooseBid(req).action;
}

BidAction getResponseToPartnerOpening(
    List<PlayingCard> hand, ContractBid partnerOpeningBid) {
  return getResponseToBidSequence(hand, [
    BidAction.withBid(partnerOpeningBid),
    BidAction.pass(),
  ]);
}

void main() {
  test("opening bids", () {
    expect(getOpeningBid(c("AS KS QS 4S 3S TH 4H 2H 4D 3D 2D 7C 2C")).action,
        BidAction.pass());
    expect(getOpeningBid(c("AS KS QS 4S 3S TH 4H 2H 4D 3D 2D AC 2C")).action,
        BidAction.contract(1, Suit.spades));
  });

  group("Response to partner opening", () {
    test("Raises major with minimum hand", () {
      final hand = c("AS KS 8S 4S 4H 3H 2H 4D 3D 2S 4C 3C 2C");
      expect(getResponseToPartnerOpening(hand, cb("1H")),
          BidAction.contract(2, Suit.hearts));
    });

    test("Never makes invalid response to major opening with 13+ points", () {
      final rng = Random(17);
      final deck = standardDeckCards();
      int numBids = 0;
      while (numBids < 100) {
        deck.shuffle(rng);
        final hand = deck.sublist(0, 13);
        final points = highCardPoints(hand);
        if (points < 13) {
          continue;
        }
        // print(descriptionWithSuitGroups(hand));
        // With 13+ points, response should never be in spades (too strong for
        // a limit raise or 4S) and should never pass or bid 1NT.
        final responseTo1S = getResponseToPartnerOpening(hand, cb("1S"));
        // print("1S / ${responseTo1S.contractBid}");
        expect(responseTo1S.bidType, BidType.contract);
        final bidAfter1S = responseTo1S.contractBid!;
        expect(bidAfter1S.count == 1, false);
        expect(bidAfter1S.trump == Suit.spades, false);

        // 1S is allowed as response to 1H.
        final responseTo1H = getResponseToPartnerOpening(hand, cb("1H"));
        // print("1H / ${responseTo1H.contractBid}");
        expect(responseTo1H.bidType, BidType.contract);
        final bidAfter1H = responseTo1H.contractBid!;
        expect(bidAfter1H.count == 1 && bidAfter1H.trump == null, false);
        expect(bidAfter1H.trump == Suit.hearts, false);

        numBids += 1;
      }
    });
  });

  group("Overcalls", () {
    test("Overcalls at 1-level with minimum hand", () {
      final response = getResponseToBidSequence(
        c("AS KS QS 3S 2S TH 2H TD 9D JC 8C 7C 5C"),
        [
          BidAction.withBid(cb("1C")),
        ],
      );
      expect(response.contractBid, cb("1S"));
    });

    test("Overcalls at 2-level with minimum hand", () {
      final response = getResponseToBidSequence(
        c("AS KS QS 3S 2S TH 2H TD 9D JC 8C 7C 5C"),
        [
          BidAction.withBid(cb("1C")),
        ],
      );
      expect(response.contractBid, cb("1S"));
    });
  });

  group("Multi-step partner responses", () {
    test("Raises partner's major response with minimum hand", () {
      final response = getResponseToBidSequence(
        // 13 points, minimum opener
        c("AS KS QS 2S AH 2H TD 9D 9C 8C 7C 5C 3C"),
        [
          BidAction.withBid(cb("1C")),
          BidAction.pass(),
          BidAction.withBid(cb("1S")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("2S"));
    });
  });

  group("NT responses", () {
    test("Responds to Stayman after 1NT opening with a major", () {
      final response = getResponseToBidSequence(
          c("AS KS 3S 2S AH KH QH 4D 3D 2D 4C 3C 2C"), [
        BidAction.noTrump(1),
        BidAction.pass(),
        BidAction.withBid(cb("2C")),
        BidAction.pass(),
      ]);
      expect(response.contractBid, cb("2S"));
    });

    test("Responds to Jacoby transfer", () {
      final response = getResponseToBidSequence(
          c("AS KS 3S 2S AH KH QH 4D 3D 2D 4C 3C 2C"), [
        BidAction.noTrump(1),
        BidAction.pass(),
        BidAction.withBid(cb("2D")),
        BidAction.pass(),
      ]);
      expect(response.contractBid, cb("2H"));
    });

    test("Super-accept Jacoby transfer", () {
      final response = getResponseToBidSequence(
        c("AS KS JS 2S AH KH QH 4D 3D 2D 4C 3C 2C"),
        [
          BidAction.noTrump(1),
          BidAction.pass(),
          BidAction.withBid(cb("2H")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("3S"));
    });
  });

  group("Game and invitational bids", () {
    test("Raises partner major response to game with maximum hand", () {
      final response = getResponseToBidSequence(
        // 19 points
        c("AS KS QS 2S AH 2H TD 9D AC QC 7C 5C 3C"),
        [
          BidAction.withBid(cb("1C")),
          BidAction.pass(),
          BidAction.withBid(cb("1S")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("4S"));
    });

    test("Makes invitational bid after partner major response", () {
      final response = getResponseToBidSequence(
        // 17 points
        c("AS KS QS 2S AH 2H TD 9D AC 9C 7C 5C 3C"),
        [
          BidAction.withBid(cb("1C")),
          BidAction.pass(),
          BidAction.withBid(cb("1S")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("3S"));
    });

    test("Makes invitational bid after partner's 1NT response", () {
      final response = getResponseToBidSequence(
        c("AS KS 7S 3S 2S AH 2H KD 9D QC JC 7C 5C"),
        [
          BidAction.withBid(cb("1S")),
          BidAction.pass(),
          BidAction.withBid(cb("1NT")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("2NT"));
    });

    test("Accepts partner's invitational bid with strong hand", () {
      final response = getResponseToBidSequence(
        c("AS KS QS 2S AH QH TD 9D TC 9C 7C 5C 3C"),
        [
          BidAction.withBid(cb("1C")),
          BidAction.pass(),
          BidAction.withBid(cb("1S")),
          BidAction.pass(),
          BidAction.withBid(cb("2S")),
          BidAction.pass(),
          BidAction.withBid(cb("3S")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("4S"));
    });

    test("Declines partner's invitational bid with weak hand", () {
      final response = getResponseToBidSequence(
        c("AS QS 3S 2S AH QH TD 9D TC 9C 7C 5C 3C"),
        [
          BidAction.withBid(cb("1C")),
          BidAction.pass(),
          BidAction.withBid(cb("1S")),
          BidAction.pass(),
          BidAction.withBid(cb("2S")),
          BidAction.pass(),
          BidAction.withBid(cb("3S")),
          BidAction.pass(),
        ],
      );
      expect(response.bidType, BidType.pass);
    });

    test("Raises to major game after partner's 1NT open and Stayman response",
        () {
      final response = getResponseToBidSequence(
        c("AS 4S 3S 2S AH 4H 3H 2H TD AC 7C 5C 3C"),
        [
          BidAction.withBid(cb("1NT")),
          BidAction.pass(),
          BidAction.withBid(cb("2C")),
          BidAction.pass(),
          BidAction.withBid(cb("2H")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("4H"));
    });

    test("Raises to NT game after partner's 1NT open and Stayman response", () {
      final response = getResponseToBidSequence(
        c("AS 4S 3S AH 4H 3H 2H TD 2D AC 7C 5C 3C"),
        [
          BidAction.withBid(cb("1NT")),
          BidAction.pass(),
          BidAction.withBid(cb("2C")),
          BidAction.pass(),
          BidAction.withBid(cb("2S")),
          BidAction.pass(),
        ],
      );
      expect(response.contractBid, cb("3NT"));
    });
  });
}
