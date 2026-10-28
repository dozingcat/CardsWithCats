enum Suit {
  clubs,
  diamonds,
  hearts,
  spades;

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
      case 'c':
      case '♣':
        return clubs;
      case 'D':
      case 'd':
      case '♦':
        return diamonds;
      case 'H':
      case 'h':
      case '♥':
        return hearts;
      case 'S':
      case 's':
      case '♠':
        return spades;
      default:
        throw FormatException("Unknown suit: ${ch}");
    }
  }
}

enum Rank {
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
  ace;

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
sealed class PlayingCard {
  const PlayingCard();

  String symbolString();

  static PlayingCard cardFromString(String s) {
    if (s.startsWith(JokerCard.prefix)) {
      return JokerCard.fromString(s);
    }
    return SuitedCard.cardFromString(s);
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

class SuitedCard extends PlayingCard {
  const SuitedCard(this.rank, this.suit);

  final Rank rank;
  final Suit suit;

  @override
  int get hashCode => rank.index << 8 + suit.index;

  @override
  bool operator ==(Object other) {
    return (other is SuitedCard &&
        other.rank == rank &&
        other.suit == suit);
  }

  @override
  String toString() {
    return rank.asciiChar + suit.asciiChar;
  }

  @override
  String symbolString() {
    return rank.asciiChar + suit.symbolChar;
  }

  static SuitedCard cardFromString(String s) {
    final suitChar = s[s.length - 1];
    final rankChar = s.substring(0, s.length - 1);
    return SuitedCard(Rank.fromChar(rankChar), Suit.fromChar(suitChar));
  }

  static List<SuitedCard> cardsFromString(String s) {
    if (s.isEmpty) return [];
    final pieces = s.split(" ");
    return pieces.map((s) => SuitedCard.cardFromString(s)).toList();
  }
}

class JokerCard extends PlayingCard {
  static const String prefix = "JOKER";
  // 1-based, to distinguish between multiple jokers if needed.
  final int jokerIndex;

  const JokerCard(this.jokerIndex);

  @override
  int get hashCode => jokerIndex;

  @override
  bool operator ==(Object other) {
    return (other is JokerCard && other.jokerIndex == jokerIndex);
  }

  @override
  String toString() {
    return "$prefix$jokerIndex";
  }

  @override
  String symbolString() {
    return toString();
  }

  static JokerCard fromString(String s) {
    final index = int.parse(s.substring(prefix.length));
    return JokerCard(index);
  }
}

List<SuitedCard> standardDeckCards() => [
      for (var r in Rank.values) SuitedCard(r, Suit.clubs),
      for (var r in Rank.values) SuitedCard(r, Suit.diamonds),
      for (var r in Rank.values) SuitedCard(r, Suit.hearts),
      for (var r in Rank.values) SuitedCard(r, Suit.spades),
    ];

List<SuitedCard> sortedCardsInSuit(Iterable<SuitedCard> cards, Suit suit) {
  List<SuitedCard> matching = cards.where((c) => c.suit == suit).toList();
  matching.sort((c1, c2) => c2.rank.index - c1.rank.index);
  return matching;
}

// Returns the ranks of cards in the specified suit, sorted descending from ace to two.
List<Rank> sortedRanksInSuit(Iterable<SuitedCard> cards, Suit suit) {
  return sortedCardsInSuit(cards, suit).map((c) => c.rank).toList();
}

Map<Suit, int> suitCounts(Iterable<SuitedCard> cards) {
  Map<Suit, int> counts = {
    Suit.spades: 0,
    Suit.hearts: 0,
    Suit.diamonds: 0,
    Suit.clubs: 0,
  };
  for (final c in cards) {
    counts[c.suit] = counts[c.suit]! + 1;
  }
  return counts;
}

SuitedCard minCardByRank(List<SuitedCard> cards) {
  var minCard = cards[0];
  for (final c in cards) {
    if (c.rank.isLowerThan(minCard.rank)) {
      minCard = c;
    }
  }
  return minCard;
}

SuitedCard maxCardByRank(List<SuitedCard> cards) {
  var maxCard = cards[0];
  for (final c in cards) {
    if (c.rank.isHigherThan(maxCard.rank)) {
      maxCard = c;
    }
  }
  return maxCard;
}

String descriptionWithSuitGroups(List<SuitedCard> cards) {
  String stringForRanksInSuit(Suit suit) =>
      suit.symbolChar +
      sortedRanksInSuit(cards, suit).map((r) => r.asciiChar).join("");
  return [
    stringForRanksInSuit(Suit.spades),
    stringForRanksInSuit(Suit.hearts),
    stringForRanksInSuit(Suit.diamonds),
    stringForRanksInSuit(Suit.clubs),
  ].join(" ");
}
