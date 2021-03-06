import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

class CardDistributionConstraint {
  int numCards;
  List<Suit> voidedSuits;
  List<PlayingCard> fixedCards;

  CardDistributionConstraint({
    required this.numCards,
    List<Suit>? voidedSuits,
    List<PlayingCard>? fixedCards,
  })  : voidedSuits = voidedSuits ?? [],
        fixedCards = fixedCards ?? [];
}

class CardDistributionRequest {
  final List<PlayingCard> cardsToAssign;
  final List<CardDistributionConstraint> constraints;

  CardDistributionRequest({required this.cardsToAssign, required this.constraints});
}

class MonteCarloParams {
  int maxRounds;
  int rolloutsPerRound;
  int? maxTimeMillis;

  MonteCarloParams({required this.maxRounds, required this.rolloutsPerRound, this.maxTimeMillis});
}

enum MonteCarloResultType { rollout_not_needed, rollout_failed, rollout_success }

class MonteCarloResult {
  MonteCarloResultType resultType;
  PlayingCard bestCard;
  Map<PlayingCard, double> cardEquities;
  int numRounds;
  int numRollouts;
  int numRolloutCardsPlayed;
  int elapsedMillis;

  MonteCarloResult({
    required this.resultType,
    required this.bestCard,
    this.cardEquities = const {},
    this.numRounds = 0,
    this.numRollouts = 0,
    this.numRolloutCardsPlayed = 0,
    this.elapsedMillis = 0,
  });

  @override
  String toString() {
    switch (resultType) {
      case MonteCarloResultType.rollout_not_needed:
        return "<${bestCard.toString()}; no rollouts>";
      case MonteCarloResultType.rollout_failed:
        return "<${bestCard.toString()}; rollouts failed; time=${elapsedMillis}ms>";
      case MonteCarloResultType.rollout_success:
        return "<${bestCard.toString()}; equity=${cardEquities[bestCard]!.toStringAsFixed(4)}; time=${elapsedMillis}ms, rounds=$numRounds, rollouts=$numRollouts, cards=$numRolloutCardsPlayed>";
    }
  }

  static MonteCarloResult rolloutNotNeeded({required PlayingCard bestCard}) => MonteCarloResult(
        resultType: MonteCarloResultType.rollout_not_needed,
        bestCard: bestCard,
      );

  static MonteCarloResult rolloutFailed({
    required PlayingCard bestCard,
    required Map<PlayingCard, double> cardEquities,
    required int numRounds,
    required int numRollouts,
    required int numRolloutCardsPlayed,
    required int elapsedMillis,
  }) =>
      MonteCarloResult(
        resultType: MonteCarloResultType.rollout_failed,
        bestCard: bestCard,
        cardEquities: cardEquities,
        numRounds: numRounds,
        numRollouts: numRollouts,
        numRolloutCardsPlayed: numRolloutCardsPlayed,
        elapsedMillis: elapsedMillis,
      );

  static MonteCarloResult rolloutSuccess({
    required Map<PlayingCard, double> cardEquities,
    required int numRounds,
    required int numRollouts,
    required int numRolloutCardsPlayed,
    required int elapsedMillis,
  }) {
    PlayingCard? bestCard;
    double bestEquity = 0.0;
    for (final e in cardEquities.entries) {
      if (bestCard == null || e.value > bestEquity) {
        bestCard = e.key;
        bestEquity = e.value;
      }
    }
    return MonteCarloResult(
      resultType: MonteCarloResultType.rollout_success,
      bestCard: bestCard!,
      cardEquities: cardEquities,
      numRounds: numRounds,
      numRollouts: numRollouts,
      numRolloutCardsPlayed: numRolloutCardsPlayed,
      elapsedMillis: elapsedMillis,
    );
  }
}

List<List<PlayingCard>>? _possibleCardDistribution(CardDistributionRequest req, Random rng) {
  final numPlayers = req.constraints.length;
  List<List<PlayingCard>> result = List.generate(numPlayers, (index) => []);
  List<List<PlayingCard>> legalCards = List.generate(numPlayers, (index) => []);
  for (int i = 0; i < numPlayers; i++) {
    final cs = req.constraints[i];
    // Add cards in suits that the player isn't known to be out of.
    for (final c in req.cardsToAssign) {
      if (!cs.voidedSuits.contains(c.suit)) {
        legalCards[i].add(c);
      }
    }
    // Assign fixed cards.
    for (var fc in cs.fixedCards) {
      if (req.cardsToAssign.contains(fc)) {
        result[i].add(fc);
        legalCards[i].remove(fc);
      }
    }
    // Remove cards that are fixed to other players.
    for (int j = 0; j < numPlayers; j++) {
      if (i != j) {
        legalCards[i].removeWhere((card) => req.constraints[j].fixedCards.contains(card));
      }
    }
  }
  // Assign cards randomly according to constraints.
  while (true) {
    bool tookAll = false;
    // If any player's remaining cards are forced, take them all.
    for (int i = 0; i < numPlayers; i++) {
      final numToFill = req.constraints[i].numCards - result[i].length;
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
      final numToFill = req.constraints[i].numCards - result[i].length;
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

List<List<PlayingCard>>? possibleCardDistribution(CardDistributionRequest req, Random rng) {
  for (int i = 0; i < 1000; i++) {
    final result = _possibleCardDistribution(req, rng);
    if (result != null) {
      return result;
    }
  }
  return null;
}

// Splits `cards` into groups that are "identical" for purposes of taking tricks.
// For example, if `cards` contains both the king and queen of hearts, those are
// identical because anytime playing the king would win a trick, the queen would
// as well. Similarly, the 10 and 8 of spades are identical if the 9 of spades
// was played in a previous trick. This can reduce the work needed by the
// Monte Carlo strategy; there's no need to do rollouts for more than one card
// in each group of identical cards.
//
// Each list in the returned value will contain one or more cards of a single
// suit, sorted descending by rank.
List<List<PlayingCard>> groupsOfEffectivelyIdenticalCards(
    List<PlayingCard> cards, Iterable<Trick> previousTricks) {
  if (cards.isEmpty) return [];
  if (cards.length == 1) return [cards.toList()];
  List<List<PlayingCard>> groups = [];
  final remainingCards = Set.of(cards);
  final seenCards = <PlayingCard>{};
  for (final t in previousTricks) {
    seenCards.addAll(t.cards);
  }
  while (remainingCards.isNotEmpty) {
    final start = remainingCards.first;
    final currentGroup = [start];
    remainingCards.remove(start);
    // Go up, then down.
    var rank = start.rank;
    while (rank.isLowerThan(Rank.ace)) {
      rank = rank.nextHigherRank();
      final c = PlayingCard(rank, start.suit);
      if (remainingCards.contains(c)) {
        // `c` is adjacent to and thus identical to a card in `currentGroup`.
        remainingCards.remove(c);
        currentGroup.add(c);
      } else if (!seenCards.contains(c)) {
        break;
      }
      // If here, the card was in a previous trick so we can keep going.
    }
    rank = start.rank;
    while (rank.isHigherThan(Rank.two)) {
      rank = rank.nextLowerRank();
      final c = PlayingCard(rank, start.suit);
      if (remainingCards.contains(c)) {
        remainingCards.remove(c);
        currentGroup.add(c);
      } else if (!seenCards.contains(c)) {
        break;
      }
    }
    groups.add(sortedCardsInSuit(currentGroup, start.suit));
  }
  return groups;
}
