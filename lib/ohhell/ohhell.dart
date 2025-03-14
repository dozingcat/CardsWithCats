import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

import '../cards/round.dart';

// Always score 10 points for a successful bid. Points may also be scored
// for each trick taken either always or for successful bids.
enum TrickScoring {
  onePointPerTrickAlways,
  onePointPerTrickSuccessfulBidOnly,
  noPointsPerTrick,
}

enum TrumpMethod {
  // The last card dealt to the dealer is the trump suit.
  dealerLastCard,
  // After all hands are dealt, the top card of the deck is the trump suit.
  firstCardAfterDeal,
}

enum OhHellRoundSequenceVariation {
  tenToOneToTen,
  oneToThirteen,
  alwaysThirteen,
}

class OhHellRuleSet {
  int numPlayers;
  OhHellRoundSequenceVariation roundSequenceVariation;
  bool bidTotalCantEqualTricks;
  TrickScoring trickScoring;
  int pointsForSuccessfulBid;
  TrumpMethod trumpMethod;

  OhHellRuleSet({
    this.numPlayers = 4,
    this.roundSequenceVariation = OhHellRoundSequenceVariation.tenToOneToTen,
    this.bidTotalCantEqualTricks = false,
    this.trickScoring = TrickScoring.onePointPerTrickAlways,
    this.pointsForSuccessfulBid = 10,
    this.trumpMethod = TrumpMethod.firstCardAfterDeal,
  });

  int get tricksPerRoundSequenceStart {
    switch (roundSequenceVariation) {
      case OhHellRoundSequenceVariation.tenToOneToTen:
        return 10;
      case OhHellRoundSequenceVariation.oneToThirteen:
        return 1;
      case OhHellRoundSequenceVariation.alwaysThirteen:
        return 13;
    }
  }

  int get tricksPerRoundSequenceEnd {
    switch (roundSequenceVariation) {
      case OhHellRoundSequenceVariation.tenToOneToTen:
        return 1;
      case OhHellRoundSequenceVariation.oneToThirteen:
        return 13;
      case OhHellRoundSequenceVariation.alwaysThirteen:
        return 13;
    }
  }

  int? get numRoundsInMatch {
    switch (roundSequenceVariation) {
      case OhHellRoundSequenceVariation.tenToOneToTen:
        return 19;
      case OhHellRoundSequenceVariation.oneToThirteen:
        return 13;
      case OhHellRoundSequenceVariation.alwaysThirteen:
        return null;
    }
  }

  int? get pointLimit {
    switch (roundSequenceVariation) {
      case OhHellRoundSequenceVariation.tenToOneToTen:
        return null;
      case OhHellRoundSequenceVariation.oneToThirteen:
        return null;
      case OhHellRoundSequenceVariation.alwaysThirteen:
        return 100;
    }
  }

  OhHellRuleSet copy() => OhHellRuleSet.from(this);

  static OhHellRuleSet from(OhHellRuleSet src) => OhHellRuleSet(
    numPlayers: src.numPlayers,
    bidTotalCantEqualTricks: src.bidTotalCantEqualTricks,
    roundSequenceVariation: src.roundSequenceVariation,
    trickScoring: src.trickScoring,
    pointsForSuccessfulBid: src.pointsForSuccessfulBid,
    trumpMethod: src.trumpMethod,
  );

  Map<String, dynamic> toJson() {
    return {
      "numPlayers": numPlayers,
      "bidTotalCantEqualTricks": bidTotalCantEqualTricks,
      "roundSequenceVariation": roundSequenceVariation.name,
      "trickScoring": trickScoring.name,
      "pointsForSuccessfulBid": pointsForSuccessfulBid,
      "trumpMethod": trumpMethod.name,
    };
  }

  static OhHellRuleSet fromJson(Map<String, dynamic> json) {
    return OhHellRuleSet(
      numPlayers: json["numPlayers"] as int,
      bidTotalCantEqualTricks: json["bidTotalCantEqualTricks"] as bool,
      roundSequenceVariation: OhHellRoundSequenceVariation.values.byName(json["roundSequenceVariation"]),
      trickScoring: TrickScoring.values.firstWhere((v) => v.name == json["trickScoring"]),
      pointsForSuccessfulBid: json["pointsForSuccessfulBid"] as int,
      trumpMethod: TrumpMethod.values.firstWhere((v) => v.name == json["trumpMethod"]),
    );
  }
}

List<PlayingCard> legalPlays(List<PlayingCard> hand, TrickInProgress currentTrick,
    List<Trick> prevTricks, OhHellRuleSet rules) {
  if (currentTrick.cards.isEmpty) {
    return hand;
  }
  // Follow suit if possible.
  final lead = currentTrick.cards[0].suit;
  final matching = hand.where((c) => c.suit == lead);
  return matching.isNotEmpty ? [...matching] : hand;
}

class OhHellPlayer {
  List<PlayingCard> hand;
  int? bid;

  OhHellPlayer(List<PlayingCard> _hand, {this.bid}) : hand = List.from(_hand);

  OhHellPlayer.from(OhHellPlayer src)
      : hand = List.from(src.hand),
        bid = src.bid;

  OhHellPlayer copy() => OhHellPlayer.from(this);
  static List<OhHellPlayer> copyAll(Iterable<OhHellPlayer> ps) => [...ps.map((p) => p.copy())];

  Map<String, dynamic> toJson() {
    return {
      "hand": PlayingCard.stringFromCards(hand),
      "bid": bid,
    };
  }

  static OhHellPlayer fromJson(Map<String, dynamic> json) {
    return OhHellPlayer(PlayingCard.cardsFromString(json["hand"] as String),
        bid: json["bid"] as int?);
  }
}

class OhHellRoundScoreResult {
  int trickPoints = 0;
  int madeBidPoints = 0;

  int get totalRoundPoints => trickPoints + madeBidPoints;
}

List<OhHellRoundScoreResult> pointsForTricks(
    List<Trick> tricks, List<int> bids, List<int> previousPoints, OhHellRuleSet rules) {
  final trickWinners = [...tricks.map((t) => t.winner)];
  List<int> winnerCounts = List.filled(rules.numPlayers, 0);
  for (int tw in trickWinners) {
    winnerCounts[tw] += 1;
  }
  List<OhHellRoundScoreResult> results = [];
  for (int i = 0; i < rules.numPlayers; i++) {
    final result = OhHellRoundScoreResult();
    bool madeBid = winnerCounts[i] == bids[i];
    if (madeBid) {
      result.madeBidPoints = rules.pointsForSuccessfulBid;
    }
    if (rules.trickScoring == TrickScoring.onePointPerTrickAlways || (madeBid && rules.trickScoring == TrickScoring.onePointPerTrickSuccessfulBidOnly)) {
      result.trickPoints = winnerCounts[i];
    }
    results.add(result);
  }
  return results;
}

enum OhHellRoundStatus {
  bidding,
  playing,
}

class OhHellRound extends BaseTrickRound {
  OhHellRoundStatus status = OhHellRoundStatus.bidding;
  late OhHellRuleSet rules;
  late List<OhHellPlayer> players;
  late int numCardsPerPlayer;
  late PlayingCard trumpCard;
  late List<int> initialScores;
  late int dealer;
  @override late TrickInProgress currentTrick;
  @override List<Trick> previousTricks = [];

  @override int get numberOfPlayers => rules.numPlayers;
  @override List<PlayingCard> cardsForPlayer(int playerIndex) => players[playerIndex].hand;

  static OhHellRound deal({
      required OhHellRuleSet rules,
      required List<int> scores,
      required int dealer,
      required int numCardsPerPlayer,
      required Random rng}) {
    List<PlayingCard> cards = List.from(standardDeckCards(), growable: true);
    cards.shuffle(rng);
    List<OhHellPlayer> players = [];
    for (int i = 0; i < rules.numPlayers; i++) {
      final playerCards = cards.sublist(
          i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
      players.add(OhHellPlayer(playerCards));
    }

    final trumpCard = rules.trumpMethod == TrumpMethod.firstCardAfterDeal &&
        numCardsPerPlayer * rules.numPlayers < cards.length ?
    cards.last : players[dealer].hand[0];

    return OhHellRound()
      ..rules = rules.copy()
      ..players = players
      ..numCardsPerPlayer = numCardsPerPlayer
      ..initialScores = [...scores]
      ..dealer = dealer
      ..trumpCard = trumpCard
      ..currentTrick = TrickInProgress((dealer + 1) % rules.numPlayers)
    ;
  }

  OhHellRound copy() {
    return OhHellRound()
      ..rules = rules.copy()
      ..status = status
      ..players = OhHellPlayer.copyAll(players)
      ..numCardsPerPlayer = numCardsPerPlayer
      ..initialScores = List.of(initialScores)
      ..dealer = dealer
      ..trumpCard = trumpCard
      ..currentTrick = currentTrick.copy()
      ..previousTricks = Trick.copyAll(previousTricks);
  }

  Suit get trumpSuit => trumpCard.suit;

  bool dealerHasTrumpCard() => players[dealer].hand.contains(trumpCard);

  @override bool isOver() {
    return players.every((p) => p.hand.isEmpty);
  }

  List<OhHellRoundScoreResult> pointsTaken() {
    return pointsForTricks(previousTricks, [...players.map((p) => p.bid!)], initialScores, rules);
  }

  @override int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  OhHellPlayer currentPlayer() => players[currentPlayerIndex()];

  int firstBidder() {
    return (dealer + 1) % rules.numPlayers;
  }

  int currentBidder() {
    final fb = firstBidder();
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

  int? disallowedBidForCurrentBidder() {
    if (!rules.bidTotalCantEqualTricks) {
      return null;
    }
    if (players.where((p) => p.bid == null).length != 1) {
      return null;
    }
    int sumOfBids = 0;
    for (final p in players) {
      sumOfBids += p.bid ?? 0;
    }
    final tricksRemaining = numCardsPerPlayer - sumOfBids;
    return (tricksRemaining >= 0) ? tricksRemaining : null;
  }

  @override List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(currentPlayer().hand, currentTrick, previousTricks, rules);
  }

  void setBidForPlayer({required int bid, required int playerIndex}) {
    players[playerIndex].bid = bid;
    if (players.every((p) => p.bid != null)) {
      status = OhHellRoundStatus.playing;
    }
  }

  void playCard(PlayingCard card) {
    final p = currentPlayer();
    final cardIndex = p.hand.indexWhere((c) => c == card);
    p.hand.removeAt(cardIndex);
    currentTrick.cards.add(card);
    if (currentTrick.cards.length == rules.numPlayers) {
      final lastTrick = currentTrick.finish(trump: trumpSuit);
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
      "numCardsPerPlayer": numCardsPerPlayer,
      "trumpCard": trumpCard.toString(),
      "currentTrick": currentTrick.toJson(),
      "previousTricks": [...previousTricks.map((t) => t.toJson())],
    };
  }

  static OhHellRound fromJson(final Map<String, dynamic> json) {
    return OhHellRound()
      ..rules = OhHellRuleSet.fromJson(json["rules"] as Map<String, dynamic>)
      ..status = OhHellRoundStatus.values.firstWhere((s) => s.name == json["status"])
      ..players = [...json["players"].map((p) => OhHellPlayer.fromJson(p as Map<String, dynamic>))]
      ..initialScores = List<int>.from(json["initialScores"])
      ..dealer = json["dealer"] as int
      ..numCardsPerPlayer = json["numCardsPerPlayer"] as int
      ..trumpCard = PlayingCard.cardFromString(json["trumpCard"] as String)
      ..currentTrick = TrickInProgress.fromJson(json["currentTrick"] as Map<String, dynamic>)
      ..previousTricks = [
        ...json["previousTricks"].map((t) => Trick.fromJson(t as Map<String, dynamic>))
      ];
  }
}

class OhHellMatch {
  Random rng;
  OhHellRuleSet rules;
  List<OhHellRound> previousRounds = [];
  late OhHellRound currentRound;

  OhHellMatch(OhHellRuleSet r, this.rng) : rules = r.copy() {
    int dealer = rng.nextInt(rules.numPlayers);
    currentRound = OhHellRound.deal(
        rules: rules,
        scores: List.filled(rules.numPlayers, 0),
        dealer: dealer,
        numCardsPerPlayer: rules.tricksPerRoundSequenceStart,
        rng: rng);
  }

  Map<String, dynamic> toJson() {
    return {
      "rules": rules.toJson(),
      "previousRounds": [...previousRounds.map((r) => r.toJson())],
      "currentRound": currentRound.toJson(),
    };
  }

  static OhHellMatch fromJson(final Map<String, dynamic> json, Random rng) {
    final rules = OhHellRuleSet.fromJson(json["rules"] as Map<String, dynamic>);
    return OhHellMatch(rules, rng)
      ..previousRounds = [
        ...json["previousRounds"].map((r) => OhHellRound.fromJson(r as Map<String, dynamic>))
      ]
      ..currentRound = OhHellRound.fromJson(json["currentRound"] as Map<String, dynamic>);
  }

  OhHellMatch copy() {
    // Cheesy, but convenient.
    return OhHellMatch.fromJson(toJson(), rng);
  }

  void _addNewRound() {
    int nextDealer = (previousRounds.last.dealer + 1) % rules.numPlayers;
    int prevTricks = previousRounds.last.numCardsPerPlayer;
    int tricksDelta = 0;
    if (rules.tricksPerRoundSequenceStart != rules.tricksPerRoundSequenceEnd) {
      if (prevTricks == rules.tricksPerRoundSequenceStart) {
        // Going from start to end.
        tricksDelta = rules.tricksPerRoundSequenceEnd > rules.tricksPerRoundSequenceStart ? 1 : -1;
      }
      else if (prevTricks == rules.tricksPerRoundSequenceEnd) {
        // Going from end to start.
        tricksDelta = rules.tricksPerRoundSequenceStart > rules.tricksPerRoundSequenceEnd ? 1 : -1;
      }
      else {
        // Continuing in same direction.
        tricksDelta = prevTricks -
            previousRounds[previousRounds.length - 2].numCardsPerPlayer;
      }
    }
    int nextNumTricks = prevTricks + tricksDelta;
    // print("Match scores: $scores");
    currentRound = OhHellRound.deal(
        rules: rules,
        scores: scores,
        dealer: nextDealer,
        numCardsPerPlayer: nextNumTricks,
        rng: rng);
    // print("New round initial scores: ${currentRound.initialScores}");
  }

  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    if (!isMatchOver()) {
      previousRounds.add(currentRound);
      _addNewRound();
    }
  }

  List<int> get scores {
    if (currentRound.isOver()) {
      final roundPoints = currentRound.pointsTaken().map((s) => s.totalRoundPoints).toList();
      return List.generate(rules.numPlayers, (p) => currentRound.initialScores[p] + roundPoints[p]);
    } else {
      return currentRound.initialScores;
    }
  }

  bool isMatchOver() {
    if (rules.numRoundsInMatch != null) {
      int completedRounds = previousRounds.length + (currentRound.isOver() ? 1 : 0);
      return completedRounds >= rules.numRoundsInMatch!;
    }
    int high = scores.reduce(max);
    if (high >= rules.pointLimit!) {
      return true;
    }
    return false;
  }

  List<int> winningPlayers() {
    if (!isMatchOver()) {
      return [];
    }
    final maxScore = scores.reduce(max);
    List<int> winners = [];
    for (int i = 0; i < rules.numPlayers; i++) {
      if (scores[i] == maxScore) {
        winners.add(i);
      }
    }
    return winners;
  }
}
