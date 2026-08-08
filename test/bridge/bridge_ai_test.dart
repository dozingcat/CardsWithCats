import "dart:math";

import "package:cards_with_cats/bridge/bridge_ai.dart";
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
    final rng = Random(17); // Seeded: unseeded runs occasionally misplay.
    final result =
        chooseCardMonteCarlo(req, mcParams, chooseCardToMaximizeTricks, rng);
    expect(result.bestCard, c("QS")[0]);
  });

  test("mcdd finds the finesse", () {
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
    final result =
        chooseCardMonteCarloDD(req, Random(17), maxRounds: 20);
    expect(result.bestCard, c("QS")[0]);
  });

  test("bidding filter constrains sampled deals", () {
    // Seat 0 opened a 15-17 1NT and everyone passed. From the opening
    // leader's view, sampled deals should give seat 0 a hand consistent
    // with that.
    final req = CardToPlayRequest(
      hand: c("KS QS 8S 3S 2S 7H 4H 3H 8D 6D 3D 9C 2C"),
      previousTricks: [],
      currentTrick: TrickInProgress(1),
      bidHistory: [
        PlayerBid(0, BidAction.noTrump(1)),
        PlayerBid(1, BidAction.pass()),
        PlayerBid(2, BidAction.pass()),
        PlayerBid(3, BidAction.pass()),
      ],
      vulnerability: Vulnerability.neither,
    );
    final filter = BiddingDealFilter.fromRequest(req);
    expect(filter, isNotNull);
    final distReq = makeCardDistributionRequest(req);
    final rng = Random(31);
    // Rejection sampling falls back to a best-effort deal when nothing
    // qualifies within the attempt budget, so allow rare misses.
    int inRange = 0;
    for (int i = 0; i < 20; i++) {
      final round = possibleRound(req, distReq, rng, filter: filter)!;
      final openerHcp = round.players[0].hand
          .map((card) => max(0, card.rank.index - Rank.ten.index))
          .fold(0, (a, b) => a + b);
      if (openerHcp >= 15 && openerHcp <= 17) inRange++;
      expect(round.players[1].hand, req.hand);
    }
    expect(inRange, greaterThanOrEqualTo(17));
  });
}
