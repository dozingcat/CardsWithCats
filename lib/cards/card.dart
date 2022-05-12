enum Suit {
  clubs, diamonds, hearts, spades;

  String get asciiChar {
    switch (this) {
      case clubs:
        return 'C';
      case diamonds:
        return 'D';
      case hearts:
        return 'H';
      case spades:
        return 'S';
    }
  }

  String get symbolChar {
    switch (this) {
      case clubs:
        return '♣';
      case diamonds:
        return '♦';
      case hearts:
        return '♥';
      case spades:
        return '♠';
    }
  }

  static Suit fromChar(String ch) {
    switch (ch) {
      case 'C':
      case '♣':
        return clubs;
      case 'D':
      case '♦':
        return diamonds;
      case 'H':
      case '♥':
        return hearts;
      case 'S':
      case '♠':
        return spades;
      default:
        throw FormatException("Unknown suit: ${ch}");
    }
  }
}

enum Rank {
  two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace;

  // Returns number for non-face card, or jack=11, queen=12, king=13, ace=14.
  int get numericValue {
    return index + 2;
  }

  String get asciiChar {
    switch (this) {
      case ace:
        return 'A';
      case king:
        return 'K';
      case queen:
        return 'Q';
      case jack:
        return 'J';
      case ten:
        return 'T';
      default:
        return numericValue.toString();
    }
  }

  bool isHigherThan(Rank other) => index > other.index;
  bool isLowerThan(Rank other) => index < other.index;

  Rank nextHigherRank() => values[index + 1];
  Rank nextLowerRank() => values[index - 1];

  static Rank fromChar(String ch) {
    switch (ch) {
      case 'A':
        return ace;
      case 'K':
        return king;
      case 'Q':
        return queen;
      case 'J':
        return jack;
      case 'T':
        return ten;
      case '10':
        return ten;
      case '9':
        return nine;
      case '8':
        return eight;
      case '7':
        return seven;
      case '6':
        return six;
      case '5':
        return five;
      case '4':
        return four;
      case '3':
        return three;
      case '2':
        return two;
      default:
        throw FormatException("Unknown rank: ${ch}");
    }
  }
}

// "Card" is a Flutter UI class, PlayingCard avoids having to disambiguate.
class PlayingCard {
  PlayingCard(this.rank, this.suit);

  final Rank rank;
  final Suit suit;

  @override
  int get hashCode => this.rank.index << 8 + this.suit.index;

  @override
  bool operator ==(Object other) {
    return (other is PlayingCard && other.rank == this.rank && other.suit == this.suit);
  }

  @override
  String toString() {
    return this.rank.asciiChar + this.suit.asciiChar;
  }

  String symbolString() {
    return this.rank.asciiChar + this.suit.symbolChar;
  }

  static PlayingCard cardFromString(String s) {
    final suitChar = s[s.length - 1];
    final rankChar = s.substring(0, s.length - 1);
    return PlayingCard(Rank.fromChar(rankChar), Suit.fromChar(suitChar));
  }

  static List<PlayingCard> cardsFromString(String s) {
    if (s.isEmpty) return [];
    final pieces = s.split(" ");
    return pieces.map((s) => PlayingCard.cardFromString(s)).toList();
  }

  static String stringFromCards(Iterable<PlayingCard> cards) {
    return cards.map((c) => c.toString()).toList().join(" ");
  }
}

List<PlayingCard> standardDeckCards() => [
      for (var r in Rank.values) PlayingCard(r, Suit.clubs),
      for (var r in Rank.values) PlayingCard(r, Suit.diamonds),
      for (var r in Rank.values) PlayingCard(r, Suit.hearts),
      for (var r in Rank.values) PlayingCard(r, Suit.spades),
    ];

List<PlayingCard> sortedCardsInSuit(Iterable<PlayingCard> cards, Suit suit) {
  List<PlayingCard> matching = cards.where((c) => c.suit == suit).toList();
  matching.sort((c1, c2) => c2.rank.index - c1.rank.index);
  return matching;
}

// Returns the ranks of cards in the specified suit, sorted descending from ace to two.
List<Rank> sortedRanksInSuit(Iterable<PlayingCard> cards, Suit suit) {
  return sortedCardsInSuit(cards, suit).map((c) => c.rank).toList();
}

PlayingCard minCardByRank(List<PlayingCard> cards) {
  var minCard = cards[0];
  for (final c in cards) {
    if (c.rank.isLowerThan(minCard.rank)) {
      minCard = c;
    }
  }
  return minCard;
}

PlayingCard maxCardByRank(List<PlayingCard> cards) {
  var maxCard = cards[0];
  for (final c in cards) {
    if (c.rank.isHigherThan(maxCard.rank)) {
      maxCard = c;
    }
  }
  return maxCard;
}

String descriptionWithSuitGroups(List<PlayingCard> cards) {
  String stringForRanksInSuit(Suit suit) =>
      suit.symbolChar + sortedRanksInSuit(cards, suit).map((r) => r.asciiChar).join("");
  return [
    stringForRanksInSuit(Suit.spades),
    stringForRanksInSuit(Suit.hearts),
    stringForRanksInSuit(Suit.diamonds),
    stringForRanksInSuit(Suit.clubs),
  ].join(" ");
}
