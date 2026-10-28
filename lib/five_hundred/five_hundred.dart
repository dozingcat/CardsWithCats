import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

// Rules are from https://en.wikipedia.org/wiki/500_(card_game), for the
// standard 4 player partnership game:
// - 43 card deck: 4 through ace in each suit except the black 4s, plus a joker.
// - Each player gets 10 cards, with 3 in the kitty.
// - Bids are a number of tricks (6 to 10) and a trump suit or no trump,
//   ranked by their value in the Avondale scoring table.
// - In a trump contract, the joker is the highest trump, followed by the jack
//   of trumps (right bower) and the other jack of the same color (left bower),
//   which is part of the trump suit.
// - In no trump, the joker can only be played if the player can't follow
//   suit. If it's led, the leader chooses the suit that the other players must
//   follow. It always wins the trick.
// - The winning bidder takes the kitty, discards 3 cards, and leads.
// - Misère bids aren't supported.

const int numPlayers = 4;
const int numTeams = 2;
const int numKittyCards = 3;
const int minimumBidTricks = 6;
const int maximumBidTricks = 10;
const int numTricksPerRound = 10;
const PlayingCard joker = JokerCard(1);

class FiveHundredRuleSet {
  // A team wins by reaching `pointLimit`, and loses by falling to `negativePointLimit`.
  int pointLimit;
  int negativePointLimit;
  // Points for each trick taken by the team that didn't win the bid.
  int pointsPerDefenderTrick;
  // Taking all 10 tricks scores at least this much, for bids worth less.
  int slamPoints;

  FiveHundredRuleSet({
    this.pointLimit = 500,
    this.negativePointLimit = -500,
    this.pointsPerDefenderTrick = 10,
    this.slamPoints = 250,
  });

  FiveHundredRuleSet copy() => FiveHundredRuleSet.fromJson(toJson());

  Map<String, dynamic> toJson() {
    return {
      "pointLimit": pointLimit,
      "negativePointLimit": negativePointLimit,
      "pointsPerDefenderTrick": pointsPerDefenderTrick,
      "slamPoints": slamPoints,
    };
  }

  static FiveHundredRuleSet fromJson(Map<String, dynamic> json) {
    return FiveHundredRuleSet(
      pointLimit: json["pointLimit"] as int,
      negativePointLimit: json["negativePointLimit"] as int,
      pointsPerDefenderTrick: json["pointsPerDefenderTrick"] as int,
      slamPoints: json["slamPoints"] as int,
    );
  }
}

List<PlayingCard> fiveHundredDeckCards() => [
  joker,
  for (final suit in Suit.values)
    for (final rank in Rank.values)
      if (rank.isHigherThan(.three) && !(rank == .four && (suit == .clubs || suit == .spades)))
        SuitedCard(rank, suit),
];

// The other suit of the same color.
Suit sameColorSuit(Suit suit) => switch (suit) {
  .clubs => .spades,
  .spades => .clubs,
  .diamonds => .hearts,
  .hearts => .diamonds,
};

bool isRightBower(PlayingCard card, Suit? trump) =>
    trump != null && card is SuitedCard && card.rank == .jack && card.suit == trump;

bool isLeftBower(PlayingCard card, Suit? trump) =>
    trump != null && card is SuitedCard && card.rank == .jack && card.suit == sameColorSuit(trump);

// The suit a card belongs to for following suit. In a trump contract the
// joker and left bower are trumps. In no trump the joker has no suit (null).
Suit? effectiveSuit(PlayingCard card, Suit? trump) {
  return switch (card) {
    JokerCard() => trump,
    SuitedCard(:final suit) => isLeftBower(card, trump) ? trump : suit,
  };
}

// For comparing cards of the same effective suit; higher is better.
int cardRankValue(PlayingCard card, Suit? trump) {
  if (card is JokerCard) {
    return 100;
  }
  if (isRightBower(card, trump)) {
    return 99;
  }
  if (isLeftBower(card, trump)) {
    return 98;
  }
  return (card as SuitedCard).rank.index;
}

// The joker always wins. Otherwise the highest trump wins, or the highest
// card of the led suit if there are no trumps.
int fiveHundredTrickWinnerIndex(final List<PlayingCard> cards, {Suit? trump}) {
  final j = cards.indexWhere((c) => c is JokerCard);
  if (j >= 0) {
    return j;
  }
  final winningSuit = cards.any((c) => trump != null && effectiveSuit(c, trump) == trump)
      ? trump
      : effectiveSuit(cards[0], trump);
  int best = -1;
  for (int i = 0; i < cards.length; i++) {
    if (effectiveSuit(cards[i], trump) == winningSuit &&
        (best < 0 || cardRankValue(cards[i], trump) > cardRankValue(cards[best], trump))) {
      best = i;
    }
  }
  return best;
}

// The suit that players must follow: the effective suit of the led card, or
// the suit chosen by the leader if the joker is led in no trump.
Suit? ledSuit(TrickInProgress<PlayingCard> trick, Suit? trump, Suit? jokerLeadSuit) {
  if (trick.cards.isEmpty) {
    return null;
  }
  final lead = trick.cards[0];
  return (lead is JokerCard && trump == null) ? jokerLeadSuit : effectiveSuit(lead, trump);
}

// Players must follow suit if possible. In no trump the joker doesn't belong
// to any suit, so it can only be played by a player who can't follow suit.
List<PlayingCard> legalPlays(
    List<PlayingCard> hand, TrickInProgress<PlayingCard> currentTrick, Suit? trump, Suit? jokerLeadSuit) {
  final suit = ledSuit(currentTrick, trump, jokerLeadSuit);
  if (suit == null) {
    return hand;
  }
  final matchingSuit = hand.where((c) => effectiveSuit(c, trump) == suit).toList();
  return matchingSuit.isNotEmpty ? matchingSuit : hand;
}

// Number of tricks and trump suit; a null trump suit is no trump.
class FiveHundredBid {
  final int tricks;
  final Suit? trump;

  const FiveHundredBid(this.tricks, this.trump);

  // Avondale table order: spades, clubs, diamonds, hearts, no trump.
  static const List<Suit?> suitOrder = [Suit.spades, Suit.clubs, Suit.diamonds, Suit.hearts, null];

  bool get isNoTrump => trump == null;

  // Avondale table: 40 for 6 spades, +20 for each higher suit, +100 for each
  // additional trick. Higher bids are worth more.
  int get value => 40 + 100 * (tricks - minimumBidTricks) + 20 * suitOrder.indexOf(trump);

  String get trumpString => trump?.symbolChar ?? "NT";

  @override
  String toString() => "$tricks$trumpString";

  @override
  bool operator ==(Object other) => other is FiveHundredBid && other.tricks == tricks && other.trump == trump;

  @override
  int get hashCode => Object.hash(tricks, trump);

  Map<String, dynamic> toJson() => {"tricks": tricks, "trump": trump?.name};

  static FiveHundredBid fromJson(Map<String, dynamic> json) {
    final trump = json["trump"] as String?;
    return FiveHundredBid(json["tricks"] as int, trump != null ? Suit.values.byName(trump) : null);
  }

  static List<FiveHundredBid> allBids() => [
    for (int t = minimumBidTricks; t <= maximumBidTricks; t++)
      for (final s in suitOrder) FiveHundredBid(t, s),
  ];
}

class PlayerBid {
  final int player;
  final FiveHundredBid? bid;

  PlayerBid(this.player, this.bid);

  PlayerBid.pass(this.player) : bid = null;

  bool get isPass => bid == null;

  Map<String, dynamic> toJson() => {"player": player, "bid": bid?.toJson()};

  static PlayerBid fromJson(Map<String, dynamic> json) {
    final bid = json["bid"] as Map<String, dynamic>?;
    return PlayerBid(json["player"] as int, bid != null ? FiveHundredBid.fromJson(bid) : null);
  }
}

class Contract {
  final int declarer;
  final FiveHundredBid bid;

  Contract({required this.declarer, required this.bid});

  Suit? get trump => bid.trump;

  Map<String, dynamic> toJson() => {"declarer": declarer, "bid": bid.toJson()};

  static Contract fromJson(final Map<String, dynamic> json) {
    return Contract(
      declarer: json["declarer"] as int,
      bid: FiveHundredBid.fromJson(json["bid"] as Map<String, dynamic>),
    );
  }
}

enum FiveHundredRoundStatus {
  bidding,
  declarerDiscarding,
  playing,
}

// Returns the highest bid made so far, or null if all bids are passes.
PlayerBid? highBid(List<PlayerBid> bids) {
  final i = bids.lastIndexWhere((b) => !b.isPass);
  return (i >= 0) ? bids[i] : null;
}

// Bidding ends when everyone has passed, when only one player hasn't passed
// and that player has bid, or when someone makes the highest possible bid.
bool isBiddingOver(List<PlayerBid> bids) {
  final high = highBid(bids);
  if (high != null && high.bid == FiveHundredBid.allBids().last) {
    return true;
  }
  final numPassed = bids.where((b) => b.isPass).length;
  if (numPassed == numPlayers) {
    return true;
  }
  return high != null && numPassed == numPlayers - 1;
}

bool isValidBid(List<PlayerBid> bids, FiveHundredBid? bid) {
  if (bid == null) {
    return true;
  }
  if (bid.tricks < minimumBidTricks || bid.tricks > maximumBidTricks) {
    return false;
  }
  final high = highBid(bids);
  return high == null || bid.value > high.bid!.value;
}

class FiveHundredPlayer {
  List<PlayingCard> hand;

  FiveHundredPlayer(List<PlayingCard> hand) : hand = List.of(hand);

  FiveHundredPlayer copy() => FiveHundredPlayer(hand);

  Map<String, dynamic> toJson() => {"hand": PlayingCard.stringFromCards(hand)};

  static FiveHundredPlayer fromJson(Map<String, dynamic> json) {
    return FiveHundredPlayer(PlayingCard.cardsFromString(json["hand"] as String));
  }
}

class FiveHundredRound {
  FiveHundredRoundStatus status = .bidding;
  List<PlayerBid> bidHistory = [];
  late FiveHundredRuleSet rules;
  late List<FiveHundredPlayer> players;
  late int dealer;
  // Team scores; players 0 and 2 are team 0, players 1 and 3 are team 1.
  late List<int> initialScores;
  late TrickInProgress<PlayingCard> currentTrick;
  List<PlayingCard> initialKitty = const [];
  List<PlayingCard> discards = const [];
  List<Trick<PlayingCard>> previousTricks = [];
  // Suits chosen when leading the joker in no trump, by trick index.
  Map<int, Suit> jokerLeadSuits = {};
  Contract? contract;

  List<PlayingCard> cardsForPlayer(int playerIndex) => players[playerIndex].hand;

  bool isOver() {
    return isPassedOut() || (status == .playing && players.every((p) => p.hand.isEmpty));
  }

  bool isPassedOut() {
    return bidHistory.length == numPlayers && bidHistory.every((b) => b.isPass);
  }

  static FiveHundredRound deal({
    required FiveHundredRuleSet rules,
    required List<int> scores,
    required int dealer,
    required Random rng,
  }) {
    List<PlayingCard> cards = fiveHundredDeckCards();
    cards.shuffle(rng);
    final numCardsPerPlayer = (cards.length - numKittyCards) ~/ numPlayers;
    final players = [
      for (int i = 0; i < numPlayers; i++)
        FiveHundredPlayer(cards.sublist(i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer)),
    ];
    return FiveHundredRound()
        ..rules = rules.copy()
        ..initialScores = List.of(scores)
        ..players = players
        ..dealer = dealer
        ..currentTrick = TrickInProgress((dealer + 1) % numPlayers)
        ..initialKitty = cards.sublist(numPlayers * numCardsPerPlayer)
        ;
  }

  FiveHundredRound copy() {
    return FiveHundredRound()
        ..status = status
        ..rules = rules.copy()
        ..initialScores = List.of(initialScores)
        ..players = players.map((p) => p.copy()).toList()
        ..dealer = dealer
        ..bidHistory = List.from(bidHistory)
        ..currentTrick = currentTrick.copy()
        ..previousTricks = Trick.copyAll(previousTricks)
        ..jokerLeadSuits = Map.of(jokerLeadSuits)
        ..contract = contract
        ..initialKitty = List.from(initialKitty)
        ..discards = List.from(discards)
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
      "jokerLeadSuits": {for (final e in jokerLeadSuits.entries) e.key.toString(): e.value.name},
      "contract": contract?.toJson(),
      "initialKitty": PlayingCard.stringFromCards(initialKitty),
      "discards": PlayingCard.stringFromCards(discards),
    };
  }

  static FiveHundredRound fromJson(final Map<String, dynamic> json) {
    return FiveHundredRound()
      ..status = FiveHundredRoundStatus.values.byName(json["status"] as String)
      ..rules = FiveHundredRuleSet.fromJson(json["rules"] as Map<String, dynamic>)
      ..initialScores = List<int>.from(json["initialScores"])
      ..players = [
        ...json["players"].map((p) => FiveHundredPlayer.fromJson(p as Map<String, dynamic>))
      ]
      ..dealer = json["dealer"] as int
      ..bidHistory = [
        ...json["bidHistory"].map((b) => PlayerBid.fromJson(b as Map<String, dynamic>))
      ]
      ..currentTrick = TrickInProgress.fromJson(
          json["currentTrick"] as Map<String, dynamic>, PlayingCard.cardsFromString)
      ..previousTricks = [
        ...json["previousTricks"]
            .map((t) => Trick.fromJson(t as Map<String, dynamic>, PlayingCard.cardsFromString))
      ]
      ..jokerLeadSuits = {
        for (final e in (json["jokerLeadSuits"] as Map<String, dynamic>).entries)
          int.parse(e.key): Suit.values.byName(e.value as String)
      }
      ..contract = (json["contract"] != null)
          ? Contract.fromJson(json["contract"] as Map<String, dynamic>)
          : null
      ..initialKitty = PlayingCard.cardsFromString(json["initialKitty"] as String)
      ..discards = PlayingCard.cardsFromString(json["discards"] as String)
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

  bool canCurrentBidderMakeBid(FiveHundredBid? bid) => isValidBid(bidHistory, bid);

  void addBid(PlayerBid bid) {
    if (status != .bidding) {
      throw Exception("Bidding is over");
    }
    if (bid.player != currentBidder()) {
      throw Exception("Got bid from wrong player (${bid.player}, expected ${currentBidder()})");
    }
    if (!canCurrentBidderMakeBid(bid.bid)) {
      throw Exception("Invalid bid: ${bid.bid}");
    }
    bidHistory.add(bid);
    if (isBiddingOver(bidHistory) && !isPassedOut()) {
      status = .declarerDiscarding;
    }
  }

  // Valid when the round status is `declarerDiscarding` or later.
  PlayerBid winningBid() => highBid(bidHistory)!;

  int declarer() => winningBid().player;

  // The cards the declarer chooses discards from: their hand plus the kitty.
  List<PlayingCard> declarerAvailableCards() {
    return [...cardsForPlayer(declarer()), ...initialKitty];
  }

  bool isValidDiscardForDeclarer(Set<PlayingCard> cards) {
    final available = declarerAvailableCards();
    return cards.length == numKittyCards && cards.every(available.contains);
  }

  // The declarer leads the first trick.
  void discard(Set<PlayingCard> cards) {
    if (status != .declarerDiscarding) {
      throw Exception("Invalid round status: $status");
    }
    if (!isValidDiscardForDeclarer(cards)) {
      throw Exception("Invalid discards: ${PlayingCard.stringFromCards(cards)}");
    }
    final bid = winningBid();
    players[bid.player].hand = declarerAvailableCards().where((c) => !cards.contains(c)).toList();
    discards = cards.toList();
    contract = Contract(declarer: bid.player, bid: bid.bid!);
    currentTrick = TrickInProgress(bid.player);
    status = .playing;
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % numPlayers;
  }

  Suit? get trump => contract?.trump;

  // The suit chosen for the joker if it was led in the current trick.
  Suit? currentJokerLeadSuit() => jokerLeadSuits[previousTricks.length];

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(cardsForPlayer(currentPlayerIndex()), currentTrick, trump, currentJokerLeadSuit());
  }

  // Whether playing this card requires choosing a suit for the joker.
  bool needsJokerLeadSuit(PlayingCard card) {
    return card is JokerCard && trump == null && currentTrick.cards.isEmpty;
  }

  void playCard(PlayingCard card, {Suit? jokerLeadSuit}) {
    if (status != .playing) {
      throw Exception("Invalid round status: $status");
    }
    if (!legalPlaysForCurrentPlayer().contains(card)) {
      throw Exception("Illegal play: $card");
    }
    if (needsJokerLeadSuit(card)) {
      if (jokerLeadSuit == null) {
        throw Exception("Joker led in no trump requires a suit");
      }
      jokerLeadSuits[previousTricks.length] = jokerLeadSuit;
    }
    cardsForPlayer(currentPlayerIndex()).remove(card);
    currentTrick.cards.add(card);
    if (currentTrick.cards.length == numPlayers) {
      final lastTrick = currentTrick.finish(trump: trump, winnerFn: fiveHundredTrickWinnerIndex);
      previousTricks.add(lastTrick);
      currentTrick = TrickInProgress(lastTrick.winner);
    }
  }

  List<int> tricksTakenByTeam() {
    final tricks = List.filled(numTeams, 0);
    for (final t in previousTricks) {
      tricks[t.winner % numTeams] += 1;
    }
    return tricks;
  }

  bool didDeclarerMakeContract() {
    final c = contract!;
    return tricksTakenByTeam()[c.declarer % numTeams] >= c.bid.tricks;
  }

  // The declaring team scores the bid's value if they make it (or the slam
  // bonus if they take every trick and it's worth more), and loses it if they
  // don't. Defenders get points for each trick they take.
  List<int> contractScoresForTeams() {
    if (isPassedOut() || !isOver()) {
      throw Exception("Round is not finished");
    }
    final c = contract!;
    final tricks = tricksTakenByTeam();
    final declarerTeam = c.declarer % numTeams;
    final defenderTeam = 1 - declarerTeam;
    final scores = List.filled(numTeams, 0);
    if (tricks[declarerTeam] >= c.bid.tricks) {
      scores[declarerTeam] = (tricks[declarerTeam] == numTricksPerRound)
          ? max(c.bid.value, rules.slamPoints)
          : c.bid.value;
    } else {
      scores[declarerTeam] = -c.bid.value;
    }
    scores[defenderTeam] = tricks[defenderTeam] * rules.pointsPerDefenderTrick;
    return scores;
  }
}

class FiveHundredMatch {
  Random rng;
  FiveHundredRuleSet rules;
  int dealer;
  List<FiveHundredRound> previousRounds = [];
  late FiveHundredRound currentRound;

  FiveHundredMatch(FiveHundredRuleSet rules, this.rng) : rules = rules.copy(), dealer = rng.nextInt(numPlayers) {
    currentRound = FiveHundredRound.deal(
        rules: this.rules, scores: List.filled(numTeams, 0), dealer: dealer, rng: rng);
  }

  Map<String, dynamic> toJson() {
    return {
      "rules": rules.toJson(),
      "dealer": dealer,
      "previousRounds": [...previousRounds.map((r) => r.toJson())],
      "currentRound": currentRound.toJson(),
    };
  }

  static FiveHundredMatch fromJson(final Map<String, dynamic> json, Random rng) {
    final rules = FiveHundredRuleSet.fromJson(json["rules"] as Map<String, dynamic>);
    return FiveHundredMatch(rules, rng)
      ..dealer = json["dealer"] as int
      ..previousRounds = [
        ...json["previousRounds"].map((r) => FiveHundredRound.fromJson(r as Map<String, dynamic>))
      ]
      ..currentRound = FiveHundredRound.fromJson(json["currentRound"] as Map<String, dynamic>);
  }

  FiveHundredMatch copy() {
    return FiveHundredMatch.fromJson(toJson(), rng);
  }

  // If everyone passes, the same dealer redeals and the passed out round isn't
  // recorded.
  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    if (currentRound.isPassedOut()) {
      currentRound = FiveHundredRound.deal(rules: rules, scores: scores, dealer: dealer, rng: rng);
      return;
    }
    previousRounds.add(currentRound);
    if (!isMatchOver()) {
      dealer = (dealer + 1) % numPlayers;
      currentRound = FiveHundredRound.deal(rules: rules, scores: scores, dealer: dealer, rng: rng);
    }
  }

  List<int> get scores {
    if (currentRound.isOver() && !currentRound.isPassedOut()) {
      final roundScores = currentRound.contractScoresForTeams();
      return List.generate(numTeams, (t) => currentRound.initialScores[t] + roundScores[t]);
    }
    return currentRound.initialScores;
  }

  bool isMatchOver() => winningTeam() != null;

  // A team wins by reaching the point limit, or when the other team falls to
  // the negative limit. If both teams reach the point limit in the same round,
  // the declaring team wins.
  int? winningTeam() {
    final s = scores;
    final reachedLimit = [for (int t = 0; t < numTeams; t++) if (s[t] >= rules.pointLimit) t];
    if (reachedLimit.length == 1) {
      return reachedLimit[0];
    }
    if (reachedLimit.length > 1) {
      final lastRound = currentRound.isOver() ? currentRound : previousRounds.last;
      return lastRound.contract!.declarer % numTeams;
    }
    for (int t = 0; t < numTeams; t++) {
      if (s[t] <= rules.negativePointLimit) {
        return 1 - t;
      }
    }
    return null;
  }
}
