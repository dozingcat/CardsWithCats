import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';

import 'five_hundred.dart';

// Placeholder AI: rough bidding from trump length and aces, simple discards,
// and random legal plays.

// The card to play, and the suit to choose if it's the joker led in no trump.
typedef CardChoice = (PlayingCard card, Suit? jokerLeadSuit);

CardChoice chooseCardRandom(FiveHundredRound round, Random rng) {
  final plays = round.legalPlaysForCurrentPlayer();
  final card = plays[rng.nextInt(plays.length)];
  final suit = round.needsJokerLeadSuit(card) ? Suit.values[rng.nextInt(Suit.values.length)] : null;
  return (card, suit);
}

// Tricks the player expects their team to take with `trump`: most of their
// trumps, their side aces, and two tricks from partner.
double estimatedTricks(List<PlayingCard> hand, Suit trump) {
  final numTrumps = hand.where((c) => effectiveSuit(c, trump) == trump).length;
  final sideAces = hand.where((c) => c is SuitedCard && c.rank == .ace && effectiveSuit(c, trump) != trump).length;
  return 0.75 * numTrumps + sideAces + 2;
}

// Bids the cheapest bid in the best suit that beats the current high bid, if
// the estimate supports it. Never bids no trump or outbids partner.
FiveHundredBid? chooseBid(FiveHundredRound round, int player, Random rng) {
  final high = highBid(round.bidHistory);
  if (high != null && high.player % numTeams == player % numTeams) {
    return null;
  }
  final hand = round.cardsForPlayer(player);
  final suit = Suit.values.reduce((a, b) => estimatedTricks(hand, a) >= estimatedTricks(hand, b) ? a : b);
  final maxTricks = estimatedTricks(hand, suit).floor();
  for (int tricks = minimumBidTricks; tricks <= min(maxTricks, maximumBidTricks); tricks++) {
    final bid = FiveHundredBid(tricks, suit);
    if (round.canCurrentBidderMakeBid(bid)) {
      return bid;
    }
  }
  return null;
}

// Discards the lowest non-trump cards.
Set<PlayingCard> chooseDiscards(FiveHundredRound round, Random rng) {
  final trump = round.winningBid().bid!.trump;
  int keepValue(PlayingCard c) {
    if (c is JokerCard) return 1000;
    final isTrump = trump != null && effectiveSuit(c, trump) == trump;
    return (isTrump ? 100 : 0) + cardRankValue(c, trump);
  }
  final cards = round.declarerAvailableCards()..sort((a, b) => keepValue(a) - keepValue(b));
  return cards.take(numKittyCards).toSet();
}
