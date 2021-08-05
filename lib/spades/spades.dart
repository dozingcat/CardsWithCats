import 'dart:math';

import 'package:hearts/cards/card.dart';
import 'package:hearts/cards/trick.dart';

enum SpadeLeading {
  always,
  after_first_trick,
  after_broken,
}

class SpadesRuleSet {
  int numPlayers;
  int numTeams;
  List<PlayingCard> removedCards;
  int pointLimit;
  bool penalizeBags;
  SpadeLeading spadeLeading;

  SpadesRuleSet({
    this.numPlayers = 4,
    this.numTeams = 2,
    this.pointLimit = 500,
    this.penalizeBags = true,
    this.removedCards = const [],
    this.spadeLeading = SpadeLeading.always,
  });

  SpadesRuleSet copy() => SpadesRuleSet.from(this);

  static SpadesRuleSet from(SpadesRuleSet src) => SpadesRuleSet(
    numPlayers: src.numPlayers,
    numTeams: src.numTeams,
    removedCards: [...src.removedCards],
    pointLimit: src.pointLimit,
    spadeLeading: src.spadeLeading,
    penalizeBags: src.penalizeBags,
  );
}

bool _canLeadSpade(List<Trick> prevTricks, SpadesRuleSet rules) {
  switch (rules.spadeLeading) {
    case SpadeLeading.always:
      return true;
    case SpadeLeading.after_first_trick:
      return prevTricks.isNotEmpty;
    case SpadeLeading.after_broken:
      return prevTricks.any((t) => t.cards.any((c) => c.suit == Suit.spades));
  }
}

List<PlayingCard> legalPlays(
    List<PlayingCard> hand,
    TrickInProgress currentTrick,
    List<Trick> prevTricks,
    SpadesRuleSet rules) {
  if (currentTrick.cards.isEmpty) {
    return _canLeadSpade(prevTricks, rules) ?
        hand : [...hand.where((c) => c.suit != Suit.spades)];
  }
  // Follow suit if possible.
  final lead = currentTrick.cards[0].suit;
  final matching = hand.where((c) => c.suit == lead);
  return matching.isNotEmpty ? [...matching] : hand;
}

class SpadesPlayer {
  List<PlayingCard> hand;
  int? bid;

  SpadesPlayer(
      List<PlayingCard> _hand) :
        hand = List.from(_hand);

  SpadesPlayer.from(SpadesPlayer src) :
        hand = List.from(src.hand),
        bid = src.bid;

  SpadesPlayer copy() => SpadesPlayer.from(this);
  static List<SpadesPlayer> copyAll(Iterable<SpadesPlayer> ps) => [...ps.map((p) => p.copy())];
}

List<int> pointsForTricks(List<Trick> tricks, List<int> bids, SpadesRuleSet rules) {
  return [];
}

enum SpadesRoundStatus {
  bidding,
  playing,
}

class SpadesRound {
  SpadesRoundStatus status = SpadesRoundStatus.bidding;
  late SpadesRuleSet rules;
  late List<SpadesPlayer> players;
  late List<int> initialScores;
  late int dealer;
  late TrickInProgress currentTrick;
  List<Trick> previousTricks = [];

  static SpadesRound deal(SpadesRuleSet rules, List<int> scores, int dealer, Random rng) {
    List<PlayingCard> cards = List.from(standardDeckCards(), growable: true);
    cards.removeWhere((c) => rules.removedCards.contains(c));
    cards.shuffle(rng);
    List<SpadesPlayer> players = [];
    int numCardsPerPlayer = cards.length ~/ rules.numPlayers;
    for (int i = 0; i < rules.numPlayers; i++) {
      final playerCards = cards.sublist(
          i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
      players.add(SpadesPlayer(playerCards));
    }

    final round = SpadesRound();
    round.rules = rules.copy();
    round.initialScores = List.from(scores);
    round.players = players;
    round.dealer = dealer;
    round.currentTrick = TrickInProgress((dealer + 1) % rules.numPlayers);

    return round;
  }

  SpadesRound copy() {
    return SpadesRound()
      ..rules = rules.copy()
      ..status = status
      ..players = SpadesPlayer.copyAll(players)
      ..initialScores = List.of(initialScores)
      ..dealer = dealer
      ..currentTrick = currentTrick.copy()
      ..previousTricks = Trick.copyAll(previousTricks);
  }

  bool isOver() {
    return players.every((p) => p.hand.isEmpty);
  }

  List<int> pointsTaken() {
    return pointsForTricks(previousTricks, [...players.map((p) => p.bid!)], rules);
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  SpadesPlayer currentPlayer() => players[currentPlayerIndex()];

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(currentPlayer().hand, currentTrick, previousTricks, rules);
  }

  void setBidForPlayer({required int bid, required int playerIndex}) {
    players[playerIndex].bid = bid;
    if (players.every((p) => p.bid != null)) {
      status = SpadesRoundStatus.playing;
    }
  }

  void playCard(PlayingCard card) {
    final p = currentPlayer();
    final cardIndex = p.hand.indexWhere((c) => c == card);
    p.hand.removeAt(cardIndex);
    currentTrick.cards.add(card);
    if (currentTrick.cards.length == rules.numPlayers) {
      final lastTrick = currentTrick.finish(trump: Suit.spades);
      previousTricks.add(lastTrick);
      currentTrick = TrickInProgress(lastTrick.winner);
    }
  }
}