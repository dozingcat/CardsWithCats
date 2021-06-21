import './card.dart' show PlayingCard, Suit, Rank, RankExtension;

int trickWinnerIndex(final List<PlayingCard> cards, {Suit? trump}) {
  Suit leadSuit = cards[0].suit;
  Rank topRank = cards[0].rank;
  Suit? effectiveTrump = (leadSuit == trump) ? null : trump;
  bool hasTrump = false;
  int topIndex = 0;
  for (int i = 1; i < cards.length; i++) {
    Suit cs = cards[i].suit;
    Rank cr = cards[i].rank;
    if (hasTrump) {
      if (cs == effectiveTrump && cr.isHigherThan(topRank)) {
        topIndex = i;
        topRank = cr;
      }
    }
    else {
      if (cs == effectiveTrump) {
        hasTrump = true;
        topIndex = i;
        topRank = cr;
      }
      else if (cs == leadSuit && cr.isHigherThan(topRank)) {
        topIndex = i;
        topRank = cr;
      }
    }
  }
  return topIndex;
}

class Trick {
  final int leader;
  final List<PlayingCard> cards;
  final int winner;

  Trick(this.leader, this.cards, this.winner);
}

class TrickInProgress {
  final int leader;
  final List<PlayingCard> cards = [];

  TrickInProgress(this.leader);

  Trick finish({Suit? trump}) {
    int winnerRelIndex = trickWinnerIndex(this.cards, trump: trump);
    int winner = (this.leader + winnerRelIndex) % this.cards.length;
    return Trick(this.leader, this.cards, winner);
  }
}
