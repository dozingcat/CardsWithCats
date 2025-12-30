import "dart:math";

import "package:cards_with_cats/cards/rollout.dart";
import "package:cards_with_cats/cards/trick.dart";
import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/spades/spades.dart";
import "package:cards_with_cats/spades/spades_ai.dart";

const c = PlayingCard.cardsFromString;

void main() {
  group("Bidding", () {
    test("High spades", () {
      final req = BidRequest(
        hand: c("AS KS QS 5H 4H 3H 2H 4D 3D 2D 4C 3C 2C"),
        otherBids: [],
        scoresBeforeRound: [0, 0],
        rules: SpadesRuleSet(),
      );
      expect(chooseBid(req), 3);
    });

    test("High and low spades", () {
      final req = BidRequest(
        hand: c("AS KS 2S 5H 4H 3H 2H 4D 3D 2D 4C 3C 2C"),
        otherBids: [],
        scoresBeforeRound: [0, 0],
        rules: SpadesRuleSet(),
      );
      expect(chooseBid(req), 2);
    });

    test("Low spades", () {
      final req = BidRequest(
        hand: c("4S 3S 2S 5H 4H 3H 2H 4D 3D 2D 4C 3C 2C"),
        otherBids: [],
        scoresBeforeRound: [0, 0],
        rules: SpadesRuleSet(),
      );
      expect(chooseBid(req), 0);
    });

    test("Many low spades", () {
      final req = BidRequest(
        hand: c("6S 5S 4S 3S 2S 3H 2H 4D 3D 2D 4C 3C 2C"),
        otherBids: [],
        scoresBeforeRound: [0, 0],
        rules: SpadesRuleSet(),
      );
      expect(chooseBid(req), greaterThan(0));
    });

    test("High non-spades", () {
      final req = BidRequest(
        hand: c("4S 3S 2S AH KH QH JH 4D 3D 2D 4C 3C 2C"),
        otherBids: [],
        scoresBeforeRound: [0, 0],
        rules: SpadesRuleSet(),
      );
      expect(chooseBid(req), 2);
    });
  });

  group("Choosing whether to overtake partner", () {
    // S: A983 KQJ9 J8 AK8
    // W: Q765 AT5 64 QT97
    // N: T2 8764 T9753 63
    // E: KJ4 32 AKQ2 J542
    // In the play to compute, South has AS 9S and partner is winning with TS.
    final hand = c("AS 9S");
    final previousTricks = [
      Trick(0, c("KH AH 8H 2H"), 1),
      Trick(1, c("4D 3D AD 8D"), 3),
      Trick(3, c("KD JD 6D 5D"), 3),
      Trick(3, c("QD 3S 7S 9D"), 1),
      Trick(1, c("7C 6C JC AC"), 0),
      Trick(0, c("KC TC 3C 5C"), 0),
      Trick(0, c("QH 5H 7H 3H"), 0),
      Trick(0, c("JH TH 6H JS"), 3),
      Trick(3, c("2C 8C QC 4H"), 1),
      Trick(1, c("9S 2S KS 6S"), 3),
      Trick(3, c("4C 9H 9C 7D"), 1),
    ];
    final currentTrick = TrickInProgress(1, c("6S TS 4S"));

    test("Make contract", () {
      final req = CardToPlayRequest(
        rules: SpadesRuleSet(),
        scoresBeforeRound: [0, 0],
        hand: hand,
        previousTricks: previousTricks,
        currentTrick: currentTrick,
        bids: [4, 3, 1, 4],
      );
      // Let partner win, and take the last trick with AS to make the bid.
      expect(req.currentPlayerIndex(), 0);
      final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardRandom, Random(17)).bestCard;
      expect(mcCard, isIn(c("9S")));
    });

    test("Avoid bags", () {
      final req = CardToPlayRequest(
        rules: SpadesRuleSet(),
        scoresBeforeRound: [0, 0],
        hand: hand,
        previousTricks: previousTricks,
        currentTrick: currentTrick,
        bids: [3, 3, 1, 4],
      );
      // Play AS to make bid exactly and avoid bags.
      expect(req.currentPlayerIndex(), 0);
      final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardRandom, Random(17)).bestCard;
      expect(mcCard, isIn(c("AS")));
    });

    test("Make opponents fail contract", () {
      final req = CardToPlayRequest(
        rules: SpadesRuleSet(),
        scoresBeforeRound: [0, 0],
        hand: hand,
        previousTricks: previousTricks,
        currentTrick: currentTrick,
        bids: [3, 4, 1, 5],
      );
      // Play 9S to limit opponents to 8 tricks so they fail their bid.
      expect(req.currentPlayerIndex(), 0);
      final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardRandom, Random(17)).bestCard;
      expect(mcCard, isIn(c("9S")));
    });

    test("Cover partner nil bid", () {
      final req = CardToPlayRequest(
          rules: SpadesRuleSet(),
          scoresBeforeRound: [0, 0],
          hand: hand,
          previousTricks: previousTricks,
          currentTrick: currentTrick,
          bids: [5, 3, 0, 4],
      );
      // Partner bid nil so we should cover with AS, even though this will
      // result in losing the last trick and not making our bid.
      expect(req.currentPlayerIndex(), 0);
      final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardRandom, Random(17)).bestCard;
      expect(mcCard, isIn(c("AS")));
    });
  });
}

MonteCarloParams makeMCParams(int hands, int rollouts) =>
    MonteCarloParams(maxRounds: hands, rolloutsPerRound: rollouts);
