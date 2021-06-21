import 'dart:math';

import "./card.dart" show Suit, PlayingCard;

class CardDistributionConstraint {
  int numCards;
  List<Suit> voidedSuits;
  List<PlayingCard> fixedCards;

  CardDistributionConstraint({
    required this.numCards, List<Suit>? voidedSuits, List<PlayingCard>? fixedCards,
  }) : voidedSuits = voidedSuits ?? [],
       fixedCards = fixedCards ?? [];
}

class CardDistributionException implements Exception {
  String msg;
  CardDistributionException(this.msg);
}

List<List<PlayingCard>>? _possibleCardDistribution(
    List<PlayingCard> cards,
    List<CardDistributionConstraint> constraints,
    Random rng) {
  final numPlayers = constraints.length;
  List<List<PlayingCard>> result = List.generate(numPlayers, (index) => []);
  List<List<PlayingCard>> legalCards = List.generate(numPlayers, (index) => []);
  for (int i = 0; i < numPlayers; i++) {
    final cs = constraints[i];
    // Add cards in suits that the player isn't known to be out of.
    for (final c in cards) {
      if (!cs.voidedSuits.contains(c.suit)) {
        legalCards[i].add(c);
      }
    }
    // Assign fixed cards.
    for (var fc in cs.fixedCards) {
      if (cards.contains(fc)) {
        result[i].add(fc);
        legalCards[i].remove(fc);
      }
    }
    // Remove cards that are fixed to other players.
    for (int j = 0; j < numPlayers; j++) {
      if (i != j) {
        legalCards[i].removeWhere((card) => constraints[j].fixedCards.contains(card));
      }
    }
  }
  // Assign cards randomly according to constraints.
  while (true) {
    bool tookAll = false;
    // If any player's remaining cards are forced, take them all.
    for (int i = 0; i < numPlayers; i++) {
      final numToFill = constraints[i].numCards - result[i].length;
      if (numToFill > 0) {
        final numLegal = legalCards[i].length;
        if (numToFill > numLegal) {
          return null;
        }
        if (numLegal == numToFill) {
          // print("Assigning ${legalCards[i]} to player $i");
          result[i].addAll(legalCards[i]);
          for (int j = 0; j < numPlayers; j++) {
            if (i != j) {
              legalCards[j].removeWhere((card) => legalCards[i].contains(card));
            }
          }
          legalCards[i].clear();
          tookAll = true;
          break;
        }
      }
    }
    if (tookAll) {
      continue;
    }
    // Nobody had a forced pick, choose one card for one player.
    bool choseCard = false;
    for (int i = 0; i < numPlayers; i++) {
      final numToFill = constraints[i].numCards - result[i].length;
      if (numToFill > 0) {
        // print("Choosing card for player $i from ${legalCards[i]}");
        final cardIndex = rng.nextInt(legalCards[i].length);
        final card = legalCards[i][cardIndex];
        // print("Assigning $card to player $i");
        result[i].add(card);
        for (var lc in legalCards) {
          lc.remove(card);
        }
        choseCard = true;
        break;
      }
    }
    if (!choseCard) {
      break;
    }
  }
  return result;
}

List<List<PlayingCard>> possibleCardDistribution(
    List<PlayingCard> cards,
    List<CardDistributionConstraint> constraints,
    Random rng) {
  for (int i = 0; i < 1000; i++) {
    final result = _possibleCardDistribution(cards, constraints, rng);
    if (result != null) {
      return result;
    }
  }
  throw CardDistributionException("Can't satisfy constraints");
}
