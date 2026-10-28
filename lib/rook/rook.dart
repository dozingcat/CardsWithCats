import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

// Rules are from https://en.wikipedia.org/wiki/Rook_(card_game) ("Tournament
// Rook", also known as "Kentucky Discard"). The Rook deck's colors map to
// suits, and its 5-14 cards map to 5 through ace. The Rook Bird card is a
// joker, and is the highest card of the trump suit.

const int numPlayers = 4;
const int numTeams = 2;
const int numNestCards = 5;
const PlayingCard joker = JokerCard(1);

class RookRuleSet {
  int pointLimit;
  int minimumBid;
  int maximumBid;
  int bidIncrement;
  int pointsForFive;
  int pointsForTen;
  int pointsForAce;
  int pointsForJoker;
  // The official rules allow the declarer to discard any cards to the nest.
  // A common variation doesn't allow discarding point cards.
  bool allowDiscardingPointCards;

  RookRuleSet({
    this.pointLimit = 300,
    this.minimumBid = 70,
    this.maximumBid = 120,
    this.bidIncrement = 5,
    this.pointsForFive = 5,
    this.pointsForTen = 10,
    this.pointsForAce = 10,
    this.pointsForJoker = 20,
    this.allowDiscardingPointCards = true,
  });

  RookRuleSet copy() => RookRuleSet.fromJson(toJson());

  Map<String, dynamic> toJson() {
    return {
      "pointLimit": pointLimit,
      "minimumBid": minimumBid,
      "maximumBid": maximumBid,
      "bidIncrement": bidIncrement,
      "pointsForFive": pointsForFive,
      "pointsForTen": pointsForTen,
      "pointsForAce": pointsForAce,
      "pointsForJoker": pointsForJoker,
      "allowDiscardingPointCards": allowDiscardingPointCards,
    };
  }

  static RookRuleSet fromJson(Map<String, dynamic> json) {
    return RookRuleSet(
      pointLimit: json["pointLimit"] as int,
      minimumBid: json["minimumBid"] as int,
      maximumBid: json["maximumBid"] as int,
      bidIncrement: json["bidIncrement"] as int,
      pointsForFive: json["pointsForFive"] as int,
      pointsForTen: json["pointsForTen"] as int,
      pointsForAce: json["pointsForAce"] as int,
      pointsForJoker: json["pointsForJoker"] as int,
      allowDiscardingPointCards: json["allowDiscardingPointCards"] as bool,
    );
  }
}

List<Rank> rookDeckRanks = Rank.values.where((r) => r.isHigherThan(.four)).toList();

List<PlayingCard> rookDeckCards() => [
  joker,
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

int pointsForCards(Iterable<PlayingCard> cards, RookRuleSet ruleSet) {
  int points = 0;
  for (final c in cards) {
    points += pointsForCard(c, ruleSet);
  }
  return points;
}

// The joker is part of the trump suit for following suit and winning tricks.
Suit effectiveSuit(PlayingCard card, Suit trump) {
  return switch (card) {
    SuitedCard(:final suit) => suit,
    JokerCard() => trump,
  };
}

// Winner of the last trick gets the nest.
List<int> teamPointsForTricks(List<Trick<PlayingCard>> tricks, List<PlayingCard> lastTrickExtraCards, RookRuleSet ruleSet) {
  List<int> points = List.filled(numTeams, 0);
  for (final t in tricks) {
    points[t.winner % numTeams] += pointsForCards(t.cards, ruleSet);
  }
  if (tricks.isNotEmpty) {
    final lastTrickWinner = tricks.last.winner;
    points[lastTrickWinner % numTeams] += pointsForCards(lastTrickExtraCards, ruleSet);
  }
  return points;
}

// The joker is the highest trump, so it always wins the trick.
int rookTrickWinnerIndex(final List<PlayingCard> cards, {Suit? trump}) {
  final j = cards.indexWhere((c) => c is JokerCard);
  if (j >= 0) {
    return j;
  }
  return defaultTrickWinnerIndex(cards, trump: trump);
}

class RookPlayer {
  List<PlayingCard> hand;

  RookPlayer(List<PlayingCard> hand) : hand = List.of(hand);

  RookPlayer copy() => RookPlayer(hand);

  Map<String, dynamic> toJson() {
    return {
      "hand": PlayingCard.stringFromCards(hand),
    };
  }

  static RookPlayer fromJson(Map<String, dynamic> json) {
    return RookPlayer(PlayingCard.cardsFromString(json["hand"] as String));
  }
}

// Players must follow suit if possible, where the joker counts as a trump.
// This means that if the joker is led, players must play a trump if they have
// one, and if trump is led and a player's only trump is the joker, they must
// play it. The joker can also be played at any time, even if the player could
// follow suit.
List<PlayingCard> legalPlays(
    List<PlayingCard> hand, TrickInProgress<PlayingCard> currentTrick, Suit trump) {
  if (currentTrick.cards.isEmpty) {
    return hand;
  }
  final leadSuit = effectiveSuit(currentTrick.cards[0], trump);
  final matchingSuit = hand.where((c) => effectiveSuit(c, trump) == leadSuit).toList();
  if (matchingSuit.isEmpty) {
    return hand;
  }
  if (hand.contains(joker) && !matchingSuit.contains(joker)) {
    matchingSuit.add(joker);
  }
  return matchingSuit;
}

class PlayerBid {
  final int player;
  final int? bid;

  PlayerBid(this.player, this.bid);

  PlayerBid.pass(this.player) : bid = null;

  bool get isPass => bid == null;

  Map<String, dynamic> toJson() {
    return {
      "player": player,
      "bid": bid,
    };
  }

  static PlayerBid fromJson(Map<String, dynamic> json) {
    return PlayerBid(json["player"] as int, json["bid"] as int?);
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
      declarer: json["declarer"] as int,
      bid: json["bid"] as int,
      trump: Suit.values.byName(json["trump"] as String),
    );
  }
}

enum RookRoundStatus {
  bidding,
  declarerChoosingCardsAndTrump,
  playing,
}

// Returns the highest bid made so far, or null if all bids are passes.
PlayerBid? highBid(List<PlayerBid> bids) {
  final i = bids.lastIndexWhere((b) => !b.isPass);
  return (i >= 0) ? bids[i] : null;
}

// Bidding ends when everyone has passed, when only one player hasn't passed
// and that player has bid, or when someone makes the maximum bid.
bool isBiddingOver(List<PlayerBid> bids, RookRuleSet rules) {
  final high = highBid(bids);
  if (high != null && high.bid! >= rules.maximumBid) {
    return true;
  }
  final numPassed = bids.where((b) => b.isPass).length;
  if (numPassed == numPlayers) {
    return true;
  }
  return high != null && numPassed == numPlayers - 1;
}

bool isValidBid(List<PlayerBid> bids, int? bid, RookRuleSet rules) {
  if (bid == null) {
    return true;
  }
  if (bid < rules.minimumBid || bid > rules.maximumBid || (bid - rules.minimumBid) % rules.bidIncrement != 0) {
    return false;
  }
  final high = highBid(bids);
  return high == null || bid > high.bid!;
}

// If point cards can't be discarded, the declarer may still have to discard
// some if they have fewer than `numNestCards` non-point cards.
bool isValidDiscard(Iterable<PlayingCard> availableCards, Set<PlayingCard> discards, RookRuleSet rules) {
  if (discards.length != numNestCards || !discards.every(availableCards.contains)) {
    return false;
  }
  if (rules.allowDiscardingPointCards) {
    return true;
  }
  final numNonPointCards = availableCards.where((c) => pointsForCard(c, rules) == 0).length;
  final numPointDiscards = discards.where((c) => pointsForCard(c, rules) > 0).length;
  return numPointDiscards <= max(0, numNestCards - numNonPointCards);
}

class RookRound {
  RookRoundStatus status = .bidding;
  List<PlayerBid> bidHistory = [];
  late RookRuleSet rules;
  late List<RookPlayer> players;
  late int dealer;
  // Team scores; players 0 and 2 are team 0, players 1 and 3 are team 1.
  late List<int> initialScores;
  late TrickInProgress<PlayingCard> currentTrick;
  List<PlayingCard> initialNest = const [];
  List<PlayingCard> finalNest = const [];
  List<Trick<PlayingCard>> previousTricks = [];
  Contract? contract;

  List<PlayingCard> cardsForPlayer(int playerIndex) => players[playerIndex].hand;

  bool isOver() {
    return isPassedOut() || (status == .playing && players.every((p) => p.hand.isEmpty));
  }

  bool isPassedOut() {
    return bidHistory.length == numPlayers && bidHistory.every((b) => b.isPass);
  }

  static RookRound deal({
    required RookRuleSet rules,
    required List<int> scores,
    required int dealer,
    required Random rng,
  }) {
    List<PlayingCard> cards = rookDeckCards();
    cards.shuffle(rng);
    List<RookPlayer> players = [];
    int numCardsPerPlayer = (cards.length - numNestCards) ~/ numPlayers;
    for (int i = 0; i < numPlayers; i++) {
      final playerCards = cards.sublist(i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
      players.add(RookPlayer(playerCards));
    }
    final nest = cards.sublist(numPlayers * numCardsPerPlayer);

    return RookRound()
        ..rules = rules.copy()
        ..initialScores = List.of(scores)
        ..players = players
        ..dealer = dealer
        ..currentTrick = TrickInProgress((dealer + 1) % numPlayers)
        ..initialNest = nest
        ;
  }

  RookRound copy() {
    return RookRound()
        ..status = status
        ..rules = rules.copy()
        ..initialScores = List.of(initialScores)
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
      "rules": rules.toJson(),
      "initialScores": initialScores,
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
      ..status = RookRoundStatus.values.byName(json["status"] as String)
      ..rules = RookRuleSet.fromJson(json["rules"] as Map<String, dynamic>)
      ..initialScores = List<int>.from(json["initialScores"])
      ..players = [
        ...json["players"]
            .map((p) => RookPlayer.fromJson(p as Map<String, dynamic>))
      ]
      ..dealer = json["dealer"] as int
      ..bidHistory = [
        ...json["bidHistory"]
            .map((b) => PlayerBid.fromJson(b as Map<String, dynamic>))
      ]
      ..currentTrick = TrickInProgress.fromJson(
          json["currentTrick"] as Map<String, dynamic>, PlayingCard.cardsFromString)
      ..previousTricks = [
        ...json["previousTricks"]
            .map((t) => Trick.fromJson(t as Map<String, dynamic>, PlayingCard.cardsFromString))
      ]
      ..contract = (json["contract"] != null)
          ? Contract.fromJson(json["contract"] as Map<String, dynamic>)
          : null
      ..initialNest = PlayingCard.cardsFromString(json["initialNest"] as String)
      ..finalNest = PlayingCard.cardsFromString(json["finalNest"] as String)
    ;
  }

  bool hasPlayerPassed(int player) {
    return bidHistory.any((b) => b.player == player && b.isPass);
  }

  // Bidding starts to the left of the dealer, and skips players who have passed.
  int currentBidder() {
    if (bidHistory.isEmpty) {
      return (dealer + 1) % numPlayers;
    }
    var p = bidHistory.last.player;
    for (int i = 0; i < numPlayers; i++) {
      p = (p + 1) % numPlayers;
      if (!hasPlayerPassed(p)) {
        return p;
      }
    }
    throw Exception("All players have passed");
  }

  bool canCurrentBidderMakeBid(int? bid) => isValidBid(bidHistory, bid, rules);

  void addBid(PlayerBid bid) {
    if (status != .bidding) {
      throw Exception("Bidding is over");
    }
    if (bid.player != currentBidder()) {
      throw Exception(
          "Got bid from wrong player (${bid.player}, expected ${currentBidder()})");
    }
    if (!canCurrentBidderMakeBid(bid.bid)) {
      throw Exception("Invalid bid: ${bid.bid}");
    }
    bidHistory.add(bid);
    if (isBiddingOver(bidHistory, rules) && !isPassedOut()) {
      status = .declarerChoosingCardsAndTrump;
    }
  }

  // Valid when the round status is `declarerChoosingCardsAndTrump` or later.
  PlayerBid winningBid() => highBid(bidHistory)!;

  int declarer() => winningBid().player;

  // The cards the declarer chooses discards from: their hand plus the nest.
  List<PlayingCard> declarerAvailableCards() {
    return [...cardsForPlayer(declarer()), ...initialNest];
  }

  bool isValidDiscardForDeclarer(Set<PlayingCard> discards) {
    return isValidDiscard(declarerAvailableCards(), discards, rules);
  }

  void discardAndChooseTrump(Set<PlayingCard> discards, Suit trump) {
    if (status != .declarerChoosingCardsAndTrump) {
      throw Exception("Invalid round status: $status");
    }
    final available = declarerAvailableCards();
    if (!isValidDiscard(available, discards, rules)) {
      throw Exception("Invalid discards: ${PlayingCard.stringFromCards(discards)}");
    }
    final bid = winningBid();
    players[bid.player].hand = available.where((c) => !discards.contains(c)).toList();
    finalNest = discards.toList();
    contract = Contract(declarer: bid.player, bid: bid.bid!, trump: trump);
    currentTrick = TrickInProgress((dealer + 1) % numPlayers);
    status = .playing;
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % numPlayers;
  }

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(cardsForPlayer(currentPlayerIndex()), currentTrick, contract!.trump);
  }

  void playCard(PlayingCard card) {
    if (status != .playing) {
      throw Exception("Invalid round status: $status");
    }
    if (!legalPlaysForCurrentPlayer().contains(card)) {
      throw Exception("Illegal play: $card");
    }
    cardsForPlayer(currentPlayerIndex()).remove(card);
    currentTrick.cards.add(card);
    if (currentTrick.cards.length == numPlayers) {
      final lastTrick = currentTrick.finish(trump: contract!.trump, winnerFn: rookTrickWinnerIndex);
      previousTricks.add(lastTrick);
      currentTrick = TrickInProgress(lastTrick.winner);
    }
  }

  // Points from counters captured by each team, including the nest.
  List<int> teamPointsTaken() {
    return teamPointsForTricks(previousTricks, finalNest, rules);
  }

  // Defenders always get their points; the declaring team loses the bid amount
  // if they didn't make it.
  List<int> contractScoresForTeams() {
    if (isPassedOut() || !isOver()) {
      throw Exception("Round is not finished");
    }
    final points = teamPointsTaken();
    final declarerTeam = contract!.declarer % numTeams;
    if (points[declarerTeam] < contract!.bid) {
      points[declarerTeam] = -contract!.bid;
    }
    return points;
  }
}

class RookMatch {
  Random rng;
  RookRuleSet rules;
  int dealer;
  List<RookRound> previousRounds = [];
  late RookRound currentRound;

  RookMatch(RookRuleSet rules, this.rng) : rules = rules.copy(), dealer = rng.nextInt(numPlayers) {
    currentRound = RookRound.deal(rules: this.rules, scores: List.filled(numTeams, 0), dealer: dealer, rng: rng);
  }

  Map<String, dynamic> toJson() {
    return {
      "rules": rules.toJson(),
      "dealer": dealer,
      "previousRounds": [...previousRounds.map((r) => r.toJson())],
      "currentRound": currentRound.toJson(),
    };
  }

  static RookMatch fromJson(final Map<String, dynamic> json, Random rng) {
    final rules = RookRuleSet.fromJson(json["rules"] as Map<String, dynamic>);
    return RookMatch(rules, rng)
      ..dealer = json["dealer"] as int
      ..previousRounds = [
        ...json["previousRounds"].map((r) => RookRound.fromJson(r as Map<String, dynamic>))
      ]
      ..currentRound = RookRound.fromJson(json["currentRound"] as Map<String, dynamic>);
  }

  RookMatch copy() {
    return RookMatch.fromJson(toJson(), rng);
  }

  // If everyone passes, the same dealer redeals and the passed out round isn't
  // recorded.
  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    if (currentRound.isPassedOut()) {
      currentRound = RookRound.deal(rules: rules, scores: scores, dealer: dealer, rng: rng);
      return;
    }
    previousRounds.add(currentRound);
    if (!isMatchOver()) {
      dealer = (dealer + 1) % numPlayers;
      currentRound = RookRound.deal(rules: rules, scores: scores, dealer: dealer, rng: rng);
    }
  }

  List<int> get scores {
    if (currentRound.isOver() && !currentRound.isPassedOut()) {
      final roundScores = currentRound.contractScoresForTeams();
      return List.generate(numTeams, (t) => currentRound.initialScores[t] + roundScores[t]);
    }
    return currentRound.initialScores;
  }

  // The match ends when a team reaches the point limit with a higher score than
  // the other team. If both teams reach the limit with the same score, play
  // continues until the tie is broken.
  bool isMatchOver() {
    final s = scores;
    int high = s.reduce(max);
    return high >= rules.pointLimit && s.where((x) => x == high).length == 1;
  }

  int? winningTeam() {
    if (!isMatchOver()) {
      return null;
    }
    final s = scores;
    return s.indexOf(s.reduce(max));
  }
}
