import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/rook/rook.dart';

// Placeholder AI so the game is playable: always passes when bidding, and
// plays random legal cards.
// TODO: Real bidding, discarding, and Monte Carlo card play.

// Returns the bid amount, or null to pass.
int? chooseBid(RookRound round, int playerIndex, Random rng) {
  return null;
}

class DiscardsAndTrump {
  final Set<PlayingCard> discards;
  final Suit trump;

  DiscardsAndTrump(this.discards, this.trump);
}

// Chooses the suit with the most cards as trump, and discards the lowest
// cards that aren't trump or point cards.
DiscardsAndTrump chooseDiscardsAndTrump(RookRound round, Random rng) {
  final cards = round.declarerAvailableCards();
  final suitedCards = cards.whereType<SuitedCard>();
  final counts = suitCounts(suitedCards);
  final trump = Suit.values.reduce((a, b) => counts[a]! >= counts[b]! ? a : b);

  // Lowest priority first: non-trump non-point cards by rank, then non-trump
  // point cards, then trumps. If point cards can't be discarded, they're
  // only discarded if there aren't enough other cards.
  int keepPriority(PlayingCard c) {
    final isTrump = effectiveSuit(c, trump) == trump;
    final isPointCard = pointsForCard(c, round.rules) > 0;
    final rankValue = (c is SuitedCard) ? c.rank.index : Rank.values.length;
    return (isPointCard && !round.rules.allowDiscardingPointCards ? 10000 : 0) +
        (isTrump ? 1000 : 0) + (isPointCard ? 100 : 0) + rankValue;
  }
  final sorted = List.of(cards)..sort((a, b) => keepPriority(a) - keepPriority(b));
  final discards = sorted.take(numNestCards).toSet();
  assert(round.isValidDiscardForDeclarer(discards));
  return DiscardsAndTrump(discards, trump);
}

PlayingCard chooseCardRandom(RookRound round, Random rng) {
  final plays = round.legalPlaysForCurrentPlayer();
  return plays[rng.nextInt(plays.length)];
}
