import 'dart:math';

import '../cards/card.dart';

int pointsForCard(PlayingCard card) {
  switch (card.rank) {
    case Rank.ace:
      return 4;
    case Rank.king:
      return 3;
    case Rank.queen:
      return 2;
    case Rank.jack:
      return 1;
    default:
      return 0;
  }
}

int highCardPoints(final List<PlayingCard> hand) {
  return hand.map(pointsForCard).reduce((a, b) => a + b);
}

int lengthPoints(final List<PlayingCard> hand) {
  int points = 0;
  points += max(0, hand.where((c) => c.suit == Suit.spades).length - 4);
  points += max(0, hand.where((c) => c.suit == Suit.hearts).length - 4);
  points += max(0, hand.where((c) => c.suit == Suit.diamonds).length - 4);
  points += max(0, hand.where((c) => c.suit == Suit.clubs).length - 4);
  return points;
}

int lengthPointsForSuitCounts(final Map<Suit, int> suitCounts) {
  int points = 0;
  for (final entry in suitCounts.entries) {
    points += max(0, entry.value - 4);
  }
  return points;
}
