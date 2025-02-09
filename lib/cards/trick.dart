import './card.dart' show PlayingCard, Suit, Rank;

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
    } else {
      if (cs == effectiveTrump) {
        hasTrump = true;
        topIndex = i;
        topRank = cr;
      } else if (cs == leadSuit && cr.isHigherThan(topRank)) {
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
    return Trick(json["leader"] as int, PlayingCard.cardsFromString(json["cards"] as String),
        json["winner"] as int);
  }
}

class TrickInProgress {
  final int leader;
  final List<PlayingCard> cards;

  TrickInProgress(this.leader, [List<PlayingCard>? _cards]) : cards = _cards ?? [];

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

// Returns true if the current player is guaranteed to win all remaining tricks.
// It's assumed that there is no trick in progress.
bool willLeadingPlayerWinAllRemainingTricks({
  required List<PlayingCard> leadingPlayerCards,
  required List<PlayingCard> remainingCards,
  Suit? trump,
}) {
  // If trump, either leading player must have only trumps
  // *or* no other players can have any.
  if (trump != null) {
    bool playerHasOnlyTrumps = leadingPlayerCards.every((c) => c.suit == trump);
    if (!playerHasOnlyTrumps) {
      if (remainingCards.any((c) => c.suit == trump)) {
        return false;
      }
    }
  }
  // No other player can have a card higher than any in `playerCards`.
  for (final pc in leadingPlayerCards) {
    if (remainingCards.any((c) => c.suit == pc.suit && c.rank.isHigherThan(pc.rank))) {
      return false;
    }
  }
  return true;
}

PlayingCard? lastCardPlayedByPlayer({
  required int playerIndex,
  required int numberOfPlayers,
  required TrickInProgress currentTrick,
  required List<Trick> previousTricks,
}) {
  if (currentTrick.cards.isNotEmpty) {
    int cardIndex = playerIndex >= currentTrick.leader
        ? playerIndex - currentTrick.leader
        : numberOfPlayers + playerIndex - currentTrick.leader;
    if (cardIndex < currentTrick.cards.length) {
      return currentTrick.cards[cardIndex];
    }
  }
  if (previousTricks.isNotEmpty) {
    final lt = previousTricks.last;
    int cardIndex = playerIndex >= lt.leader
        ? playerIndex - lt.leader
        : numberOfPlayers + playerIndex - lt.leader;
    return lt.cards[cardIndex];
  }
  return null;
}
