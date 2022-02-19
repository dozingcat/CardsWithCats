import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/rollout.dart";

void main() {
  test("Distribution with no constraints", () {
    final rng = Random(23);
    final cs = List.generate(4, (i) => CardDistributionConstraint(numCards: 13));
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: standardDeckCards(), constraints: cs), rng)!;

    expect(dist.length, 4);
    Set<PlayingCard> allCards = {};
    for (int i = 0; i < 4; i++) {
      expect(dist[i].length, 13);
      allCards.addAll(dist[i]);
    }
    expect(allCards.length, 52);
  });
  
  test("Distribution with voided suits", () {
    final rng = Random(23);
    final cards = PlayingCard.cardsFromString("2C 2D 2H 2S 3C 3D 3H 3S 4C 4D 4H 4S");
    final constraints = List.generate(4, (i) => CardDistributionConstraint(numCards: 3));
    constraints[0].voidedSuits.add(Suit.spades);
    constraints[2].voidedSuits.addAll([Suit.spades, Suit.hearts, Suit.diamonds]);
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: cards, constraints: constraints), rng)!;

    expect(dist.length, 4);
    expect(dist[0].where((c) => c.suit == Suit.spades).toList(), []);
    expect(dist[2].where((c) => c.suit == Suit.clubs).toList().length, 3);
    Set<PlayingCard> allCards = {};
    for (int i = 0; i < 4; i++) {
      expect(dist[i].length, 3);
      allCards.addAll(dist[i]);
    }
    expect(allCards, cards.toSet());
  });

  test("Distribution with fixed cards", () {
    final rng = Random(23);
    final cards = PlayingCard.cardsFromString("2C 2D 2H 2S 3C 3D 3H 3S 4C 4D 4H 4S");
    final constraints = List.generate(4, (i) => CardDistributionConstraint(numCards: 3));
    constraints[1].fixedCards.add(PlayingCard.cardFromString("2H"));
    constraints[3].fixedCards.addAll(PlayingCard.cardsFromString("3D 4D AD"));
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: cards, constraints: constraints), rng)!;

    expect(dist[1].contains(PlayingCard.cardFromString("2H")), true);
    expect(dist[3].contains(PlayingCard.cardFromString("3D")), true);
    expect(dist[3].contains(PlayingCard.cardFromString("4D")), true);
    expect(dist[3].contains(PlayingCard.cardFromString("AD")), false);
    Set<PlayingCard> allCards = {};
    for (int i = 0; i < 4; i++) {
      expect(dist[i].length, 3);
      allCards.addAll(dist[i]);
    }
    expect(allCards, cards.toSet());
  });

  test("Distribution combination", () {
    final rng = Random(23);
    final cards = PlayingCard.cardsFromString("AS KS QS JS TS 9S AH KH QH");
    final constraints = List.generate(3, (i) => CardDistributionConstraint(numCards: 3));
    constraints[1].voidedSuits.add(Suit.hearts);
    constraints[2].voidedSuits.add(Suit.hearts);
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: cards, constraints: constraints), rng)!;

    // Players 1 and 2 have no hearts, so player 0 must have them all.
    expect(dist[0].contains(PlayingCard.cardFromString("AH")), true);
    expect(dist[0].contains(PlayingCard.cardFromString("KH")), true);
    expect(dist[0].contains(PlayingCard.cardFromString("QH")), true);
  });
}
