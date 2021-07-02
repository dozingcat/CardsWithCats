import 'dart:math';

import 'package:hearts/cards/card.dart';
import 'package:hearts/cards/trick.dart';
import 'package:hearts/hearts/hearts.dart';

class CardsToPassRequest {
  final HeartsRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final int direction;
  final int numCards;

  CardsToPassRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.direction,
    required this.numCards,
  });
}

class CardToPlayRequest {
  final HeartsRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final int passDirection;
  final List<PlayingCard> passedCards;
  final List<PlayingCard> receivedCards;

  CardToPlayRequest({
    required HeartsRuleSet rules_,
    required List<int> scoresBeforeRound_,
    required List<PlayingCard> hand_,
    required this.passDirection,
    required List<PlayingCard> passedCards_,
    required List<PlayingCard> receivedCards_,
  }) :
      rules = rules_.copy(),
      scoresBeforeRound = List.from(scoresBeforeRound_),
      hand = List.from(hand_),
      passedCards = List.from(passedCards_),
      receivedCards = List.from(receivedCards_);
}

// Returns the estimated probability of the player at `player_index` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int maxScore, int playerIndex) {
  if (scores.length < 2) {
    throw Exception("Length of `scores` must be at least 2");
  }
  if (scores.any((s) => s >= maxScore)) {
    final minScore = scores.reduce(min);
    if (scores[playerIndex] > minScore) {
      return 0;
    }
    // An N-way tie for first has an equity of 1/N.
    int numWinners = scores.where((s) => s == minScore).fold(0, (n, _) => n + 1);
    return 1.0 / numWinners;
  }
  // Approximate the probability as (player distance to max) / (sum of all distances to max).
  int totalDist = 0;
  for (int s in scores) {
    totalDist += (maxScore - s);
  }
  return (maxScore - scores[playerIndex]) / totalDist;
}

int dangerForCard(PlayingCard card, List<Rank> suitRanks, CardsToPassRequest req) {
  int cardVal = card.rank.numericValue;
  int lowestValInSuit = suitRanks.last.numericValue;
  switch (card.suit) {
    case Suit.spades:
      if (card.rank.index < Rank.queen.index) {
        return 0;
      }
      // Assuming 4 or more spades are safe, not necessarily true for something like AKxx.
      if (suitRanks.length >= 4) {
        return 0;
      }
      // Always pass QS.
      if (card.rank == Rank.queen) {
        return 100;
      }
      // If we're passing the queen right, it's ok to keep AS and KS
      // because we'll be able to safely play them (as long as we
      // have a lower spade).
      bool passingRight = req.direction == req.rules.numPlayers - 1;
      bool hasQueen = suitRanks.contains(Rank.queen);
      bool hasLowSpade = suitRanks.last.index < Rank.queen.index;
      return (passingRight && hasQueen && hasLowSpade) ? cardVal - 5 : 100;

    case Suit.hearts:
    case Suit.diamonds:
      return cardVal + lowestValInSuit;

    case Suit.clubs:
      // 2C is "higher" than AC for purposes of passing.
      // TODO: We probably want to pass AC less often because winning
      // the first trick can be helpful and doesn't risk points.
      int adjustedVal = (cardVal == 2) ? 14 : cardVal - 1;
      if (lowestValInSuit == 2) {
        // Probably pass 2C.
        if (cardVal == 2) {
          return 50;
        }
        int secondLowestClubVal = suitRanks[suitRanks.length - 2].numericValue;
        return adjustedVal + secondLowestClubVal;
      }
      else {
        return adjustedVal + lowestValInSuit - 1;
      }
  }
}

List<PlayingCard> chooseCardsToPass(CardsToPassRequest req) {
  Map<Suit, List<Rank>> ranksBySuit = {};
  for (Suit suit in Suit.values) {
    ranksBySuit[suit] = ranksForSuit(req.hand, suit);
  }
  Map<PlayingCard, int> cardDanger = {};
  for (PlayingCard c in req.hand) {
    cardDanger[c] = dangerForCard(c, ranksBySuit[c.suit]!, req);
  }
  final sortedHand = List.of(req.hand);
  sortedHand.sort((c1, c2) => cardDanger[c2]! - cardDanger[c1]!);
  return sortedHand.sublist(0, req.numCards);
}