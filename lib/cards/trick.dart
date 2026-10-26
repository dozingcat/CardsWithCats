import './card.dart' show SuitedCard, Suit, Rank, PlayingCard;

// Default implementation that uses standard rank ordering and no jokers.
// Games (e.g. Rook, 500) can provide a different function and pass it to
// TrickInProgress.finish.
int defaultTrickWinnerIndex(final List<PlayingCard> cards, {Suit? trump}) {
  final c0 = cards[0] as SuitedCard;
  int topIndex = 0;
  SuitedCard topCard = c0;
  for (int i = 1; i < cards.length; i++) {
    final ci = cards[i] as SuitedCard;
    bool higherThanTop = (ci.suit == topCard.suit && ci.rank.isHigherThan(topCard.rank));
    bool firstTrump = (topCard.suit != trump && ci.suit == trump);
    if (higherThanTop || firstTrump) {
      topIndex = i;
      topCard = ci;
    }
  }
  return topIndex;
}

typedef TrickWinnerFn = int Function(List<SuitedCard> cards, {Suit? trump});

SuitedCard highestCardInTrick(List<SuitedCard> cards, {Suit? trump}) {
  return cards[defaultTrickWinnerIndex(cards, trump: trump)];
}

class Trick {
  final int leader;
  final List<SuitedCard> cards;
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
    return Trick(json["leader"] as int, SuitedCard.cardsFromString(json["cards"] as String),
        json["winner"] as int);
  }
}

class TrickInProgress {
  final int leader;
  final List<SuitedCard> cards;

  TrickInProgress(this.leader, [List<SuitedCard>? _cards]) : cards = _cards ?? [];

  TrickInProgress copy() => TrickInProgress(leader, List.of(cards));

  Map<String, dynamic> toJson() {
    return {
      "leader": leader,
      "cards": PlayingCard.stringFromCards(cards),
    };
  }

  static TrickInProgress fromJson(final Map<String, dynamic> json) {
    return TrickInProgress(
        json["leader"] as int, SuitedCard.cardsFromString(json["cards"] as String));
  }

  Trick finish({Suit? trump, TrickWinnerFn winnerFn = defaultTrickWinnerIndex}) {
    int winnerRelIndex = winnerFn(cards, trump: trump);
    int winner = (leader + winnerRelIndex) % cards.length;
    return Trick(leader, cards, winner);
  }
}

// Returns true if the current player is guaranteed to win all remaining tricks.
// It's assumed that there is no trick in progress.
bool willLeadingPlayerWinAllRemainingTricks({
  required List<SuitedCard> leadingPlayerCards,
  required List<SuitedCard> remainingCards,
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

SuitedCard? lastCardPlayedByPlayer({
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
