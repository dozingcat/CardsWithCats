import './card.dart' show SuitedCard, Suit, PlayingCard;

// Default implementation that uses standard rank ordering and no jokers.
// Games (e.g. Rook, 500) can provide a different function and pass it to
// TrickInProgress.finish. This takes List<PlayingCard> rather than
// List<SuitedCard> so that it's usable as a TrickWinnerFn for any card type.
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

typedef TrickWinnerFn<C extends PlayingCard> = int Function(List<C> cards, {Suit? trump});

SuitedCard highestCardInTrick(List<SuitedCard> cards, {Suit? trump}) {
  return cards[defaultTrickWinnerIndex(cards, trump: trump)];
}

// `C` is the type of cards that can be played: SuitedCard for games that use
// the standard 52 card deck, PlayingCard for games that also use jokers.
class Trick<C extends PlayingCard> {
  final int leader;
  final List<C> cards;
  final int winner;

  Trick(this.leader, this.cards, this.winner);

  Trick<C> copy() => Trick(leader, List.of(cards), winner);
  static List<Trick<C>> copyAll<C extends PlayingCard>(List<Trick<C>> tricks) =>
      List.generate(tricks.length, (i) => tricks[i].copy());

  Map<String, dynamic> toJson() {
    return {
      "leader": leader,
      "cards": PlayingCard.stringFromCards(cards),
      "winner": winner,
    };
  }

  // `parseCards` determines the card type, e.g. `SuitedCard.cardsFromString`
  // or `PlayingCard.cardsFromString`.
  static Trick<C> fromJson<C extends PlayingCard>(
      final Map<String, dynamic> json, List<C> Function(String) parseCards) {
    return Trick(json["leader"] as int, parseCards(json["cards"] as String), json["winner"] as int);
  }
}

class TrickInProgress<C extends PlayingCard> {
  final int leader;
  final List<C> cards;

  TrickInProgress(this.leader, [List<C>? _cards]) : cards = _cards ?? [];

  TrickInProgress<C> copy() => TrickInProgress(leader, List.of(cards));

  Map<String, dynamic> toJson() {
    return {
      "leader": leader,
      "cards": PlayingCard.stringFromCards(cards),
    };
  }

  static TrickInProgress<C> fromJson<C extends PlayingCard>(
      final Map<String, dynamic> json, List<C> Function(String) parseCards) {
    return TrickInProgress(json["leader"] as int, parseCards(json["cards"] as String));
  }

  Trick<C> finish({Suit? trump, TrickWinnerFn<C> winnerFn = defaultTrickWinnerIndex}) {
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

C? lastCardPlayedByPlayer<C extends PlayingCard>({
  required int playerIndex,
  required int numberOfPlayers,
  required TrickInProgress<C> currentTrick,
  required List<Trick<C>> previousTricks,
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
