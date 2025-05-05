import "dart:math";

import "package:cards_with_cats/bridge/bridge_ai.dart";
import "package:cards_with_cats/bridge/bridge_bidding.dart";
import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/bridge/bridge.dart";

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

PlayerBid getResponseToPartnerOpening(List<PlayingCard> hand, ContractBid parterOpeningBid) {
  final req = BidRequest(
    playerIndex: 0,
    hand: hand,
    bidHistory: [
      PlayerBid(0, BidAction.withBid(parterOpeningBid)),
      PlayerBid(1, BidAction.pass()),
    ],
  );
  return chooseBid(req);
}

void main() {
  test("opening bids", () {
    expect(
        getOpeningBid(c("AS KS QS 4S 3S TH 4H 2H 4D 3D 2D 7C 2C")).action,
        BidAction.pass());
    expect(
        getOpeningBid(c("AS KS QS 4S 3S TH 4H 2H 4D 3D 2D AC 2C")).action,
        BidAction.contract(1, Suit.spades));
  });

  group("Response to partner opening", () {
    test("Raises major with minimum hand", () {
      final hand = c("AS KS 8S 4S 4H 3H 2H 4D 3D 2S 4C 3C 2C");
      expect(
          getResponseToPartnerOpening(hand, cb("1H")).action,
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
        print(descriptionWithSuitGroups(hand));
        // With 13+ points, response should never be in spades (too strong for
        // a limit raise or 4S) and should never pass or bid 1NT.
        final responseTo1S = getResponseToPartnerOpening(hand, cb("1S"));
        print("1S / ${responseTo1S.action.contractBid}");
        expect(responseTo1S.action.bidType, BidType.contract);
        final bidAfter1S = responseTo1S.action.contractBid!;
        expect(bidAfter1S.count == 1, false);
        expect(bidAfter1S.trump == Suit.spades, false);

        // 1S is allowed as response to 1H.
        final responseTo1H = getResponseToPartnerOpening(hand, cb("1H"));
        print("1H / ${responseTo1H.action.contractBid}");
        expect(responseTo1H.action.bidType, BidType.contract);
        final bidAfter1H = responseTo1H.action.contractBid!;
        expect(bidAfter1H.count == 1 && bidAfter1H.trump == null, false);
        expect(bidAfter1H.trump == Suit.hearts, false);

        numBids += 1;
      }
    });
  });
}
