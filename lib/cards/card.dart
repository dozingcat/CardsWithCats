enum Suit {clubs, diamonds, hearts, spades}

extension SuitExtension on Suit {
  String get asciiChar {
    switch (this) {
      case Suit.clubs: return 'C';
      case Suit.diamonds: return 'D';
      case Suit.hearts: return 'H';
      case Suit.spades: return 'S';
    }
  }

  String get symbolChar {
    switch (this) {
      case Suit.clubs: return '♣';
      case Suit.diamonds: return '♦';
      case Suit.hearts: return '♥';
      case Suit.spades: return '♠';
    }
  }
}

Suit suitFromChar(String ch) {
  switch (ch) {
    case 'C':
    case '♣':
      return Suit.clubs;
    case 'D':
    case '♦':
      return Suit.diamonds;
    case 'H':
    case '♥':
      return Suit.hearts;
    case 'S':
    case '♠':
      return Suit.spades;
    default:
      throw FormatException("Unknown suit: ${ch}");
  }
}

enum Rank {two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace}

extension RankExtension on Rank {
  // Returns number for non-face card, or jack=11, queen=12, king=13, ace=14.
  int get numericValue {
    return this.index + 2;
  }

  String get asciiChar {
    switch (this) {
      case Rank.ace: return 'A';
      case Rank.king: return 'K';
      case Rank.queen: return 'Q';
      case Rank.jack: return 'J';
      case Rank.ten: return 'T';
      default:
        return this.numericValue.toString();
    }
  }

  bool isHigherThan(Rank other) {
    return this.index > other.index;
  }
}

Rank rankFromChar(String ch) {
  switch (ch) {
    case 'A': return Rank.ace;
    case 'K': return Rank.king;
    case 'Q': return Rank.queen;
    case 'J': return Rank.jack;
    case 'T': return Rank.ten;
    case '10': return Rank.ten;
    case '9': return Rank.nine;
    case '8': return Rank.eight;
    case '7': return Rank.seven;
    case '6': return Rank.six;
    case '5': return Rank.five;
    case '4': return Rank.four;
    case '3': return Rank.three;
    case '2': return Rank.two;
    default:
      throw FormatException("Unknown rank: ${ch}");
  }
}

// "Card" is a Flutter UI class, PlayingCard avoids having to disambiguate.
class PlayingCard {
  PlayingCard(this.rank, this.suit);

  final Rank rank;
  final Suit suit;

  @override int get hashCode => this.rank.index << 8 + this.suit.index;

  @override bool operator==(Object other) {
    return (other is PlayingCard && other.rank == this.rank && other.suit == this.suit);
  }

  @override String toString() {
    return this.rank.asciiChar + this.suit.asciiChar;
  }

  static PlayingCard cardFromString(String s) {
    final suitChar = s[s.length - 1];
    final rankChar = s.substring(0, s.length - 1);
    return PlayingCard(rankFromChar(rankChar), suitFromChar(suitChar));
  }

  static List<PlayingCard> cardsFromString(String s) {
    final pieces = s.split(" ");
    return pieces.map((s) => PlayingCard.cardFromString(s)).toList();
  }
}

List<PlayingCard> standardDeckCards() => [
  for (var r in Rank.values) PlayingCard(r, Suit.clubs),
  for (var r in Rank.values) PlayingCard(r, Suit.diamonds),
  for (var r in Rank.values) PlayingCard(r, Suit.hearts),
  for (var r in Rank.values) PlayingCard(r, Suit.spades),
];

// Returns the ranks of cards in the specified suit, sorted descending from ace to two.
List<Rank> ranksForSuit(Iterable<PlayingCard> cards, Suit suit) {
  List<Rank> ranks = cards.where((c) => c.suit == suit).map((c) => c.rank).toList();
  ranks.sort((r1, r2) => r2.index - r1.index);
  return ranks;
}