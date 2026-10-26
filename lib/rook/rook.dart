import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/hearts/hearts.dart';

const int numPlayers = 4;
const int numNestCards = 5;
const PlayingCard joker = JokerCard(1);

class RookRuleSet {
  int pointLimit = 300;
  int pointsForFive = 5;
  int pointsForTen = 10;
  int pointsForAce = 10;
  int pointsForJoker = 20;
}

List<Rank> rookDeckRanks = Rank.values.where((r) => r.isHigherThan(.four)).toList();

List<PlayingCard> rookDeckCards() => [
  JokerCard(1),
  for (var r in rookDeckRanks) SuitedCard(r, Suit.clubs),
  for (var r in rookDeckRanks) SuitedCard(r, Suit.diamonds),
  for (var r in rookDeckRanks) SuitedCard(r, Suit.hearts),
  for (var r in rookDeckRanks) SuitedCard(r, Suit.spades),
];

int pointsForCard(PlayingCard card, RookRuleSet ruleSet) {
  return switch (card) {
    JokerCard() => ruleSet.pointsForJoker,
    SuitedCard(:final rank) => switch (rank) {
      .ace => ruleSet.pointsForAce,
      .ten => ruleSet.pointsForTen,
      .five => ruleSet.pointsForFive,
      _ => 0,
    }
  };
}

int pointsForCards(List<PlayingCard> cards, RookRuleSet ruleSet) {
  int points = 0;
  for (final c in cards) {
    points += pointsForCard(c, ruleSet);
  }
  return points;
}

// Winner of the last trick gets the nest.
List<int> teamPointsForTricks(List<Trick> tricks, List<PlayingCard> lastTrickExtraCards, RookRuleSet ruleSet) {
  List<int> points = [0, 0];
  for (final t in tricks) {
    points[t.winner % 2] += pointsForCards(t.cards, ruleSet);
  }
  final lastTrickWinner = tricks.last.winner;
  points[lastTrickWinner % 2] += pointsForCards(lastTrickExtraCards, ruleSet);
  return points;
}

// The joker always wins the trick.
int rookTrickWinnerIndex(final List<SuitedCard> cards, {Suit? trump}) {
  final j = cards.indexWhere((c) => c is JokerCard);
  if (j >= 0) {
    return j;
  }
  return defaultTrickWinnerIndex(cards, trump: trump);
}

class RookPlayer {
  List<PlayingCard> hand;

  RookPlayer(this.hand);

  RookPlayer copy() => RookPlayer(List.from(hand));

  Map<String, dynamic> toJson() {
    return {
      "hand": PlayingCard.stringFromCards(hand),
    };
  }

  static RookPlayer fromJson(Map<String, dynamic> json) {
    return RookPlayer(SuitedCard.cardsFromString(json["hand"] as String));
  }
}

List<PlayingCard> legalPlays(
    List<PlayingCard> hand, TrickInProgress currentTrick, Suit trump) {
  if (currentTrick.cards.isEmpty) {
    return hand;
  }
  bool hasJoker = hand.contains(joker);
  final matchingSuit = hand.where(
      (c) => c is SuitedCard && c.suit == currentTrick.cards[0].suit).toList();
  if (matchingSuit.isNotEmpty) {
    // Joker is always a legal play, even if it's possible to follow suit.
    return [
      ...matchingSuit,
      if (hasJoker) joker,
    ];
  }
  // If trump was led and you have no trumps but do have the joker, you have to
  // play it.
  if (currentTrick.cards.isNotEmpty && currentTrick.cards[0].suit == trump && hasJoker) {
    return [joker];
  }
  return hand;
}

class PlayerBid {
  final int player;
  final int? bid;

  PlayerBid(this.player, this.bid);

  bool get isPass => bid == null;

  Map<String, dynamic> toJson() {
    return {
      "player": player,
      "bid": bid,
    };
  }

  static PlayerBid fromJson(Map<String, dynamic> json) {
    return PlayerBid(json["player"], json["bid"]);
  }
}

class Contract {
  final int declarer;
  final int bid;
  final Suit trump;

  Contract({required this.declarer, required this.bid, required this.trump});

  Map<String, dynamic> toJson() {
    return {
      "declarer": declarer,
      "bid": bid,
      "trump": trump.name,
    };
  }

  static Contract fromJson(final Map<String, dynamic> json) {
    return Contract(
      declarer: json["declarer"],
      bid: json["bid"],
      trump: Suit.values.firstWhere((s) => s.name == json["trump"]),
    );
  }
}

enum RookRoundStatus {
  bidding,
  declarerChoosingCardsAndTrump,
  playing,
}

class RookRound {
  RookRoundStatus status = .bidding;
  List<PlayerBid> bidHistory = [];
  late RookRuleSet rules;
  late List<RookPlayer> players;
  late int dealer;
  late List<int> initialScores;
  late TrickInProgress currentTrick;
  List<PlayingCard> initialNest = const [];
  List<PlayingCard> finalNest = const [];
  List<Trick> previousTricks = [];
  Contract? contract;

  List<PlayingCard> cardsForPlayer(int playerIndex) => players[playerIndex].hand;

  bool isOver() {
    return isPassedOut() || players.every((p) => p.hand.isEmpty);
  }

  bool isPassedOut() {
    return bidHistory.length == numPlayers && bidHistory.every((b) => b.isPass);
  }

  static RookRound deal(int dealer, Random rng) {
    List<PlayingCard> cards = List.from(rookDeckCards());
    cards.shuffle(rng);
    List<RookPlayer> players = [];
    int numCardsPerPlayer = (cards.length - numNestCards) ~/ numPlayers;
    for (int i = 0; i < numPlayers; i++) {
      final playerCards = cards.sublist(i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
      players.add(RookPlayer(playerCards));
    }
    final nest = cards.sublist(numPlayers * numCardsPerPlayer);

    return RookRound()
        ..players = players
        ..dealer = dealer
        ..currentTrick = TrickInProgress(0)
        ..initialNest = nest
        ;
  }

  RookRound copy() {
    return RookRound()
        ..status = status
        ..players = players.map((p) => p.copy()).toList()
        ..dealer = dealer
        ..bidHistory = List.from(bidHistory)
        ..currentTrick = currentTrick.copy()
        ..previousTricks = Trick.copyAll(previousTricks)
        ..contract = contract
        ..initialNest = List.from(initialNest)
        ..finalNest = List.from(finalNest)
        ;
  }

  Map<String, dynamic> toJson() {
    return {
      "status": status.name,
      "players": [...players.map((p) => p.toJson())],
      "dealer": dealer,
      "bidHistory": [...bidHistory.map((b) => b.toJson())],
      "currentTrick": currentTrick.toJson(),
      "previousTricks": [...previousTricks.map((t) => t.toJson())],
      "contract": contract?.toJson(),
      "initialNest": PlayingCard.stringFromCards(initialNest),
      "finalNest": PlayingCard.stringFromCards(finalNest),
    };
  }

  static RookRound fromJson(final Map<String, dynamic> json) {
    return RookRound()
      ..status =
      RookRoundStatus.values.firstWhere((s) => s.name == json["status"])
      ..players = [
        ...json["players"]
            .map((p) => RookPlayer.fromJson(p as Map<String, dynamic>))
      ]
      ..dealer = json["dealer"] as int
      ..bidHistory = [
        ...json["bidHistory"]
            .map((b) => PlayerBid.fromJson(b as Map<String, dynamic>))
      ]
      ..currentTrick = TrickInProgress.fromJson(json["currentTrick"] as Map<String, dynamic>)
      ..previousTricks = [
        ...json["previousTricks"]
            .map((t) => Trick.fromJson(t as Map<String, dynamic>))
      ]
      ..contract = (json["contract"] != null)
          ? Contract.fromJson(json["contract"])
          : null
      ..initialNest = PlayingCard.cardsFromString(json["initialNest"])
      ..finalNest = PlayingCard.cardsFromString(json["finalNest"])
    ;
  }

  int currentBidder() {
    return (dealer + bidHistory.length) % numPlayers;
  }

  void addBid(PlayerBid bid) {
    if (status != .bidding) {
      throw Exception("Bidding is over");
    }
    if (bid.player != currentBidder()) {
      throw Exception(
          "Got bid from wrong player (${bid.player}, expected ${currentBidder()}");
    }
    bidHistory.add(bid);
    if (isBiddingOver(bidHistory)) {
      _endBidding();
    }
  }

  void _endBidding() {
    status = .declarerChoosingCardsAndTrump;
  }

  void discardAndChooseTrump(Set<PlayingCard> discards, Suit trump) {
    if (status != .declarerChoosingCardsAndTrump) {
      throw Exception("Invalid round status: $status");
    }
    PlayerBid declarerBid = bidHistory.lastWhere((b) => !b.isPass);
    Set<PlayingCard> startingHandPlusInitialNest = {
      ...cardsForPlayer(declarerBid.player),
      ...initialNest,
    };
    if (discards.length != initialNest.length) {
      throw Exception("Expected ${initialNest.length} discards but got ${discards.length}");
    }
    if (!startingHandPlusInitialNest.containsAll(discards)) {
      final invalidDiscards = discards.difference(startingHandPlusInitialNest);
      throw Exception("Invalid discards (not in hand or nest): ${PlayingCard.stringFromCards(invalidDiscards)}");
    }

    players[declarerBid.player].hand = startingHandPlusInitialNest.difference(discards).toList();
    finalNest = discards.toList();
    status = .playing;
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % 4;
  }

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(cardsForPlayer(currentPlayerIndex()), currentTrick, contract!.trump);
  }

  List<int> contractScoresForTeams() {
    if (isPassedOut() || !isOver()) {
      throw Exception("Round is not finished");
    }
    List<int> basePoints = teamPointsForTricks(previousTricks, finalNest, rules);
    // Defenders always get their points, declaring side loses the bid amount
    // if they didn't make it.
    if (contract!.declarer % 2 == 0) {
      return [
        basePoints[0] >= contract!.bid ? basePoints[0] : -contract!.bid,
        basePoints[1],
      ];
    }
    else {
      return [
        basePoints[0],
        basePoints[1] >= contract!.bid ? basePoints[1] : -contract!.bid,
      ];
    }
  }
}

bool isBiddingOver(List<PlayerBid> bids) {
  // At least 4 bids, ending in 3 passes.
  int n = bids.length;
  if (n < numPlayers) {
    return false;
  }
  for (int i = 0; i < numPlayers - 1; i++) {
    if (!bids[n - i - 1].isPass) {
      return false;
    }
  }
  return true;
}

bool canCurrentBidderMakeBid(List<PlayerBid> bids, int? bid) {
  // TODO: Enforce that once a player has passed, they can't bid again.
  if (bid == null) {
    return true;
  }
  int lastBidIndex = bids.lastIndexWhere((b) => !b.isPass);
  if (lastBidIndex < 0) {
    return true;
  }
  return bid > bids[lastBidIndex].bid!;
}
