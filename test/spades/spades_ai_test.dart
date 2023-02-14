import 'dart:math';

import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
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
}
