import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

import '../cards/round.dart';

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
    this.spadeLeading = SpadeLeading.after_broken,
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

  Map<String, dynamic> toJson() {
    return {
      "numPlayers": numPlayers,
      "numTeams": numTeams,
      "removedCards": PlayingCard.stringFromCards(removedCards),
      "pointLimit": pointLimit,
      "spadeLeading": spadeLeading.name,
      "penalizeBags": penalizeBags,
    };
  }

  static SpadesRuleSet fromJson(Map<String, dynamic> json) {
    return SpadesRuleSet(
      numPlayers: json["numPlayers"] as int,
      numTeams: json["numTeams"] as int,
      removedCards: PlayingCard.cardsFromString(json["removedCards"] as String),
      pointLimit: json["pointLimit"] as int,
      spadeLeading: SpadeLeading.values.byName(json["spadeLeading"]),
      penalizeBags: json["penalizeBags"] as bool,
    );
  }

  int get numberOfUsedCards => (52 - removedCards.length);
  int get numberOfCardsPerPlayer => numberOfUsedCards ~/ numPlayers;
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

List<PlayingCard> legalPlays(List<PlayingCard> hand, TrickInProgress currentTrick,
    List<Trick> prevTricks, SpadesRuleSet rules) {
  if (currentTrick.cards.isEmpty) {
    if (!_canLeadSpade(prevTricks, rules)) {
      final nonSpades = [...hand.where((c) => c.suit != Suit.spades)];
      if (nonSpades.isNotEmpty) {
        return nonSpades;
      }
    }
    return hand;
  }
  // Follow suit if possible.
  final lead = currentTrick.cards[0].suit;
  final matching = hand.where((c) => c.suit == lead);
  return matching.isNotEmpty ? [...matching] : hand;
}

class SpadesPlayer {
  List<PlayingCard> hand;
  int? bid;

  SpadesPlayer(List<PlayingCard> _hand, {this.bid}) : hand = List.from(_hand);

  SpadesPlayer.from(SpadesPlayer src)
      : hand = List.from(src.hand),
        bid = src.bid;

  SpadesPlayer copy() => SpadesPlayer.from(this);
  static List<SpadesPlayer> copyAll(Iterable<SpadesPlayer> ps) => [...ps.map((p) => p.copy())];

  Map<String, dynamic> toJson() {
    return {
      "hand": PlayingCard.stringFromCards(hand),
      "bid": bid,
    };
  }

  static SpadesPlayer fromJson(Map<String, dynamic> json) {
    return SpadesPlayer(PlayingCard.cardsFromString(json["hand"] as String),
        bid: json["bid"] as int?);
  }
}

class RoundScoreResult {
  int successfulBidPoints = 0;
  int failedBidPoints = 0;
  int overtricks = 0;
  int overtrickPenalty = 0;
  int successfulNilPoints = 0;
  int failedNilPoints = 0;

  int get totalRoundPoints =>
      successfulBidPoints +
      failedBidPoints +
      overtricks +
      overtrickPenalty +
      successfulNilPoints +
      failedNilPoints;

  int endingMatchPoints = 0;
}

List<RoundScoreResult> pointsForTrickWinners(
    List<int> trickWinners, List<int> bids, List<int> previousPoints, SpadesRuleSet rules) {
  List<RoundScoreResult> results = List.generate(rules.numTeams, (_) => RoundScoreResult());
  List<int> winnerCounts = List.filled(rules.numPlayers, 0);
  List<int> teamWinnerCounts = List.filled(rules.numTeams, 0);
  for (int tw in trickWinners) {
    winnerCounts[tw] += 1;
    teamWinnerCounts[tw % rules.numTeams] += 1;
  }
  List<int> teamBids = List.filled(rules.numTeams, 0);
  List<int> nilBidders = [];
  for (int bi = 0; bi < bids.length; bi++) {
    teamBids[bi % rules.numTeams] += bids[bi];
    if (bids[bi] == 0) {
      nilBidders.add(bi);
    }
  }
  // +100 or -100 for making or failing nil bid.
  // TODO: Special scoring for double nil? (e.g. +400 if successful, -200 if either takes a trick)
  for (int nb in nilBidders) {
    if (winnerCounts[nb] == 0) {
      results[nb % rules.numTeams].successfulNilPoints += 100;
    } else {
      results[nb % rules.numTeams].failedNilPoints -= 100;
    }
  }
  // 10 points per made bid, 1 point for each overtrick. -10*bid if failed.
  for (int ti = 0; ti < rules.numTeams; ti++) {
    if (teamBids[ti] > 0) {
      if (teamWinnerCounts[ti] >= teamBids[ti]) {
        int bags = rules.penalizeBags ? teamWinnerCounts[ti] - teamBids[ti] : 0;
        results[ti].successfulBidPoints += 10 * teamBids[ti];
        if (rules.penalizeBags) {
          results[ti].overtricks = bags;
          if ((previousPoints[ti] % 10) + (bags % 10) >= 10) {
            results[ti].overtrickPenalty = -110;
          }
        }
      } else {
        results[ti].failedBidPoints -= 10 * teamBids[ti];
      }
    }
    results[ti].endingMatchPoints = previousPoints[ti] + results[ti].totalRoundPoints;
  }
  return results;
}

List<RoundScoreResult> pointsForTricks(
    List<Trick> tricks, List<int> bids, List<int> previousPoints, SpadesRuleSet rules) {
  return pointsForTrickWinners([...tricks.map((t) => t.winner)], bids, previousPoints, rules);
}

enum SpadesRoundStatus {
  bidding,
  playing,
}

class SpadesRound extends BaseTrickRound {
  SpadesRoundStatus status = SpadesRoundStatus.bidding;
  late SpadesRuleSet rules;
  late List<SpadesPlayer> players;
  late List<int> initialScores;
  late int dealer;
  @override late TrickInProgress currentTrick;
  @override List<Trick> previousTricks = [];

  @override int get numberOfPlayers => rules.numPlayers;
  @override List<PlayingCard> cardsForPlayer(int playerIndex) => players[playerIndex].hand;

  static SpadesRound deal(SpadesRuleSet rules, List<int> scores, int dealer, Random rng) {
    List<PlayingCard> cards = List.from(standardDeckCards(), growable: true);
    cards.removeWhere((c) => rules.removedCards.contains(c));
    cards.shuffle(rng);
    List<SpadesPlayer> players = [];
    int numCardsPerPlayer = cards.length ~/ rules.numPlayers;
    for (int i = 0; i < rules.numPlayers; i++) {
      final playerCards = cards.sublist(i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
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

  @override bool isOver() {
    return players.every((p) => p.hand.isEmpty);
  }

  List<RoundScoreResult> pointsTaken() {
    return pointsForTricks(previousTricks, [...players.map((p) => p.bid!)], initialScores, rules);
  }

  @override int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  SpadesPlayer currentPlayer() => players[currentPlayerIndex()];

  int firstBidder() {
    return (dealer + 1) % rules.numPlayers;
  }

  int currentBidder() {
    var fb = firstBidder();
    var p = fb;
    while (true) {
      if (players[p].bid == null) {
        return p;
      }
      p = (p + 1) % rules.numPlayers;
      if (p == fb) {
        throw Exception("All players have bid");
      }
    }
  }

  List<int> bidsInOrderMade() {
    final bids = <int>[];
    final fb = firstBidder();
    for (int i = 0; i < rules.numPlayers; i++) {
      int pnum = (fb + i) % rules.numPlayers;
      if (players[pnum].bid != null) {
        bids.add(players[pnum].bid!);
      }
    }
    return bids;
  }

  @override List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(currentPlayer().hand, currentTrick, previousTricks, rules);
  }

  void setBidForPlayer({required int bid, required int playerIndex}) {
    players[playerIndex].bid = bid;
    if (players.every((p) => p.bid != null)) {
      status = SpadesRoundStatus.playing;
    }
  }

  @override void playCard(PlayingCard card) {
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

  Map<String, dynamic> toJson() {
    return {
      "rules": rules.toJson(),
      "status": status.name,
      "players": [...players.map((p) => p.toJson())],
      "initialScores": initialScores,
      "dealer": dealer,
      "currentTrick": currentTrick.toJson(),
      "previousTricks": [...previousTricks.map((t) => t.toJson())],
    };
  }

  static SpadesRound fromJson(final Map<String, dynamic> json) {
    return SpadesRound()
      ..rules = SpadesRuleSet.fromJson(json["rules"] as Map<String, dynamic>)
      ..status = SpadesRoundStatus.values.byName(json["status"])
      ..players = [...json["players"].map((p) => SpadesPlayer.fromJson(p as Map<String, dynamic>))]
      ..initialScores = List<int>.from(json["initialScores"])
      ..dealer = json["dealer"] as int
      ..currentTrick = TrickInProgress.fromJson(json["currentTrick"] as Map<String, dynamic>)
      ..previousTricks = [
        ...json["previousTricks"].map((t) => Trick.fromJson(t as Map<String, dynamic>))
      ];
  }
}

class SpadesMatch {
  Random rng;
  SpadesRuleSet rules;
  int dealer = -1;
  List<SpadesRound> previousRounds = [];
  late SpadesRound currentRound;

  SpadesMatch(SpadesRuleSet _rules, this.rng) : rules = _rules.copy() {
    dealer = rng.nextInt(rules.numPlayers);
    currentRound = SpadesRound.deal(rules, List.filled(rules.numTeams, 0), dealer, rng);
  }

  Map<String, dynamic> toJson() {
    return {
      "rules": rules.toJson(),
      "dealer": dealer,
      "previousRounds": [...previousRounds.map((r) => r.toJson())],
      "currentRound": currentRound.toJson(),
    };
  }

  static SpadesMatch fromJson(final Map<String, dynamic> json, Random rng) {
    final rules = SpadesRuleSet.fromJson(json["rules"] as Map<String, dynamic>);
    return SpadesMatch(rules, rng)
      ..dealer = json["dealer"] as int
      ..previousRounds = [
        ...json["previousRounds"].map((r) => SpadesRound.fromJson(r as Map<String, dynamic>))
      ]
      ..currentRound = SpadesRound.fromJson(json["currentRound"] as Map<String, dynamic>);
  }

  SpadesMatch copy() {
    // Cheesy, but convenient.
    return SpadesMatch.fromJson(toJson(), rng);
  }

  void _addNewRound() {
    dealer = (dealer + 1) % rules.numPlayers;
    currentRound = SpadesRound.deal(rules, scores, dealer, rng);
  }

  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    previousRounds.add(currentRound);
    if (!isMatchOver()) {
      _addNewRound();
    }
  }

  List<int> get scores {
    if (currentRound.isOver()) {
      return [...currentRound.pointsTaken().map((p) => p.endingMatchPoints)];
    } else {
      return currentRound.initialScores;
    }
  }

  bool isMatchOver() {
    int high = scores.reduce(max);
    if (high < rules.pointLimit) {
      return false;
    }
    return scores.where((s) => s ~/ 10 == high ~/ 10).length == 1;
  }

  int? winningTeam() {
    if (!isMatchOver()) {
      return null;
    }
    int high = scores.reduce(max);
    return scores.indexWhere((s) => s ~/ 10 == high ~/ 10);
  }
}
