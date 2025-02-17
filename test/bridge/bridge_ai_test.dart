import "dart:math";

import "package:cards_with_cats/bridge/bridge_ai.dart";
import "package:cards_with_cats/bridge/bridge_bidding.dart";
import "package:cards_with_cats/cards/rollout.dart";
import "package:cards_with_cats/cards/trick.dart";
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
  return chooseBid(req);
}

void main() {
  test("finesse", () {
    final req = CardToPlayRequest(
      declarerHand: c("3S 2S AH KH QH JH TH AD KD QD AC KC QC"),
      hand: c("AS QS 6S 5S 4S 3H 2H 4D 3D 2D 4C 3C 2C"),
      previousTricks: [],
      currentTrick: TrickInProgress(1, c("7S")),
      bidHistory: [
        PlayerBid.contract(0, ContractBid.noTrump(3)),
        PlayerBid.pass(1),
        PlayerBid.pass(2),
        PlayerBid.pass(3),
      ],
      vulnerability: Vulnerability.neither,
    );

    expect(req.contract.bid.count, 3);
    expect(req.contract.bid.trump, null);
    expect(req.contract.declarer, 0);
    expect(req.contract.dummy, 2);
    expect(req.currentPlayerIndex(), 2);

    expect(req.legalPlays().length, 5);

    final mcParams = MonteCarloParams(maxRounds: 20, rolloutsPerRound: 50);
    final rng = Random();
    final result = chooseCardMonteCarlo(req, mcParams, chooseCardToMaximizeTricks, rng);
    expect(result.bestCard, c("QS")[0]);
  });

  test("opening bids", () {
    expect(getOpeningBid(c("AS KS QS 4S 3S TH 4H 2H 4D 3D 2D 7C 2C")).bidType, BidType.pass);
    expect(getOpeningBid(c("AS KS QS 4S 3S TH 4H 2H 4D 3D 2D AC 2C")).contractBid, cb("1S"));
  });
}