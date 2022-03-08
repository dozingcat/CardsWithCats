import "dart:math";

import 'package:cards_with_cats/cards/trick.dart';
import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/rollout.dart";

void main() {
  const c = PlayingCard.cardFromString;
  const cs = PlayingCard.cardsFromString;

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
    final cards = cs("2C 2D 2H 2S 3C 3D 3H 3S 4C 4D 4H 4S");
    final constraints = List.generate(4, (i) => CardDistributionConstraint(numCards: 3));
    constraints[0].voidedSuits.add(Suit.spades);
    constraints[2].voidedSuits.addAll([Suit.spades, Suit.hearts, Suit.diamonds]);
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: cards, constraints: constraints), rng)!;

    expect(dist.length, 4);
    expect(dist[0].where((c) => c.suit == Suit.spades).isEmpty, true);
    expect(dist[2].where((c) => c.suit == Suit.clubs).length, 3);
    Set<PlayingCard> allCards = {};
    for (int i = 0; i < 4; i++) {
      expect(dist[i].length, 3);
      allCards.addAll(dist[i]);
    }
    expect(allCards, cards.toSet());
  });

  test("Distribution with fixed cards", () {
    final rng = Random(23);
    final cards = cs("2C 2D 2H 2S 3C 3D 3H 3S 4C 4D 4H 4S");
    final constraints = List.generate(4, (i) => CardDistributionConstraint(numCards: 3));
    constraints[1].fixedCards.add(c("2H"));
    constraints[3].fixedCards.addAll(cs("3D 4D AD"));
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: cards, constraints: constraints), rng)!;

    expect(dist[1].contains(c("2H")), true);
    expect(dist[3].contains(c("3D")), true);
    expect(dist[3].contains(c("4D")), true);
    expect(dist[3].contains(c("AD")), false);
    Set<PlayingCard> allCards = {};
    for (int i = 0; i < 4; i++) {
      expect(dist[i].length, 3);
      allCards.addAll(dist[i]);
    }
    expect(allCards, cards.toSet());
  });

  test("Distribution combination", () {
    final rng = Random(23);
    final cards = cs("AS KS QS JS TS 9S AH KH QH");
    final constraints = List.generate(3, (i) => CardDistributionConstraint(numCards: 3));
    constraints[1].voidedSuits.add(Suit.hearts);
    constraints[2].voidedSuits.add(Suit.hearts);
    final dist = possibleCardDistribution(
        CardDistributionRequest(cardsToAssign: cards, constraints: constraints), rng)!;

    // Players 1 and 2 have no hearts, so player 0 must have them all.
    expect(dist[0].contains(c("AH")), true);
    expect(dist[0].contains(c("KH")), true);
    expect(dist[0].contains(c("QH")), true);
  });

  test("Grouping no-ops", () {
    expect(groupsOfEffectivelyIdenticalCards([], []), []);
    expect(groupsOfEffectivelyIdenticalCards(cs("AS"), []), [cs("AS")]);
  });

  test("Grouping adjacent cards", () {
    final groups = groupsOfEffectivelyIdenticalCards(cs("AC 3C KC 4C 5H 2C"), []);
    expect(groups.toSet(), {
      cs("AC KC"),
      cs("4C 3C 2C"),
      cs("5H"),
    });
  });

  test("Grouping adjacent cards with previous tricks", () {
    final previousTricks = [
      Trick(0, cs("2C 8C 9C AC"), 3),
      Trick(3, cs("3D TH 9D 7D"), 2),
    ];
    final cards = cs("2D 3D 5D 6D 8D KD TD 4C 7C TC JC");
    final groups = groupsOfEffectivelyIdenticalCards(cards, previousTricks);
    expect(groups.toSet(), {
      cs("3D 2D"),
      cs("TD 8D 6D 5D"),
      cs("KD"),
      cs("4C"),
      cs("JC TC 7C"),
    });
  });
}
