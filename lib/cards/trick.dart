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

PlayingCard highestCardInTrick(List<PlayingCard> cards, {Suit? trump}) {
  return cards[trickWinnerIndex(cards, trump: trump)];
}

class Trick {
  final int leader;
  final List<PlayingCard> cards;
  final int winner;

  Trick(this.leader, this.cards, this.winner);

  Trick copy() => Trick(leader, List.of(cards), winner);
  static List<Trick> copyAll(List<Trick> tricks) =>
      List.generate(tricks.length, (i) => tricks[i].copy());

  Map<String, dynamic> toJson() {
    return {
      "leader": leader,
      "cards": PlayingCard.stringFromCards(cards),
      "winner": winner,
    };
  }

  static Trick fromJson(final Map<String, dynamic> json) {
    return Trick(
        json["leader"] as int,
        PlayingCard.cardsFromString(json["cards"] as String),
        json["winner"] as int);
  }
}

class TrickInProgress {
  final int leader;
  final List<PlayingCard> cards;

  TrickInProgress(this.leader, [List<PlayingCard>? _cards]) :
        cards=_cards ?? [];

  TrickInProgress copy() => TrickInProgress(leader, List.of(cards));

  Map<String, dynamic> toJson() {
    return {
      "leader": leader,
      "cards": PlayingCard.stringFromCards(cards),
    };
  }

  static TrickInProgress fromJson(final Map<String, dynamic> json) {
    return TrickInProgress(
        json["leader"] as int, PlayingCard.cardsFromString(json["cards"] as String));
  }

  Trick finish({Suit? trump}) {
    int winnerRelIndex = trickWinnerIndex(cards, trump: trump);
    int winner = (leader + winnerRelIndex) % cards.length;
    return Trick(leader, cards, winner);
  }
}
