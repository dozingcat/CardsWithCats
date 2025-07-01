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

void main() {
  test("finesse", () {
    final req = CardToPlayRequest(
      declarerHand: c("3S 2S AH KH QH JH TH AD KD QD AC KC QC"),
      hand: c("AS QS 6S 5S 4S 3H 2H 4D 3D 2D 4C 3C 2C"),
      previousTricks: [],
      currentTrick: TrickInProgress(1, c("7S")),
      bidHistory: [
        PlayerBid(0, BidAction.noTrump(3)),
        PlayerBid(1, BidAction.pass()),
        PlayerBid(2, BidAction.pass()),
        PlayerBid(3, BidAction.pass()),
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
    final result =
        chooseCardMonteCarlo(req, mcParams, chooseCardToMaximizeTricks, rng);
    expect(result.bestCard, c("QS")[0]);
  });
}
