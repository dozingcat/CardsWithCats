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

  Trick copy() => Trick(leader, List.of(cards), winner);
}

class TrickInProgress {
  final int leader;
  final List<PlayingCard> cards;

  TrickInProgress(this.leader, [List<PlayingCard>? _cards]) :
        cards=_cards ?? [];

  TrickInProgress copy() => TrickInProgress(leader, List.of(cards));

  Trick finish({Suit? trump}) {
    int winnerRelIndex = trickWinnerIndex(cards, trump: trump);
    int winner = (leader + winnerRelIndex) % cards.length;
    return Trick(leader, cards, winner);
  }
}
