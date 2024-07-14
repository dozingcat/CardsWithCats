import "package:cards_with_cats/spades/bridge_ai.dart";
import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/bridge/bridge.dart";

const c = PlayingCard.cardsFromString;

void main() {
  test("finesse", () {
    final contract = Contract(
      declarer: 0,
      bid: ContractBid(1, null),
      isVulnerable: false,
    );

    final req = CardToPlayRequest(rules: rules, scoresBeforeRound: scoresBeforeRound, hand: hand, previousTricks: previousTricks, currentTrick: currentTrick, bids: bids)
  });
}