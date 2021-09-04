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

  SpadesPlayer(List<PlayingCard> _hand) :
        hand = List.from(_hand);

  SpadesPlayer.from(SpadesPlayer src) :
        hand = List.from(src.hand),
        bid = src.bid;

  SpadesPlayer copy() => SpadesPlayer.from(this);
  static List<SpadesPlayer> copyAll(Iterable<SpadesPlayer> ps) => [...ps.map((p) => p.copy())];
}

List<int> pointsForTrickWinners(List<int> trickWinners, List<int> bids, SpadesRuleSet rules) {
  List<int> points = List.filled(rules.numTeams, 0);
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
  for (int nb in nilBidders) {
    int nilPoints = winnerCounts[nb] == 0 ? 100 : -100;
    points[nb % rules.numTeams] += nilPoints;
  }
  // 10 points per made bid, 1 point for each overtrick. -10*bid if failed.
  for (int ti = 0; ti < rules.numTeams; ti++) {
    if (teamBids[ti] > 0) {
      if (teamWinnerCounts[ti] >= teamBids[ti]) {
        int bags = rules.penalizeBags ? teamWinnerCounts[ti] - teamBids[ti] : 0;
        points[ti] += 10 * teamBids[ti] + bags;
      }
      else {
        points[ti] -= 10 * teamBids[ti];
      }
    }
  }
  return points;
}

List<int> pointsForTricks(List<Trick> tricks, List<int> bids, SpadesRuleSet rules) {
  return pointsForTrickWinners([...tricks.map((t) => t.winner)], bids, rules);
}

List<int> combinePoints(List<int> p1, List<int> p2, SpadesRuleSet rules) {
  if (p1.length != p2.length) {
    throw Exception("Mismatched lengths: {$p1.length}, {$p2.length}");
  }
  // If 10 or more overtricks, remove 10 overtricks and apply 100 penalty.
  List<int> combined = List.generate(p1.length, (i) => p1[i] + p2[i]);
  for (int i = 0; i < p1.length; i++) {
    if ((p1[i] % 10) + (p2[i] % 10) >= 10) {
      combined[i] -= 110;
    }
  }
  return combined;
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

class SpadesMatch {
  Random rng;
  SpadesRuleSet rules;
  List<int> scores;
  int dealer = -1;
  List<SpadesRound> previousRounds = [];
  late SpadesRound currentRound;

  SpadesMatch(SpadesRuleSet _rules, this.rng) :
        rules = _rules.copy(),
        scores = List.filled(_rules.numTeams, 0)
  {
    _addNewRound();
  }

  void _addNewRound() {
    int np = rules.numPlayers;
    dealer = (dealer == -1) ? rng.nextInt(np) : (dealer + 1) % np;
    currentRound = SpadesRound.deal(rules, scores, dealer, rng);
  }

  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    final roundScores = currentRound.pointsTaken();
    scores = combinePoints(scores, roundScores, rules);
    previousRounds.add(currentRound);
    if (!isMatchOver()) {
      _addNewRound();
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