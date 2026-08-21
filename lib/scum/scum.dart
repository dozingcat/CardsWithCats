import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';

/// Roles at the table, from best to worst. With four players there is one of
/// each, and they are reassigned every round based on the order in which
/// players run out of cards.
enum ScumRole { president, vicePresident, viceScum, scum }

const scumRoleNames = {
  ScumRole.president: "President",
  ScumRole.vicePresident: "Vice President",
  ScumRole.viceScum: "Vice Scum",
  ScumRole.scum: "Scum",
};

/// Points awarded for a round, indexed by finish position (0 = first out).
const scumPointsForFinishPosition = [3, 2, 1, 0];

class ScumRuleSet {
  int numPlayers = 4;
  int numRounds = 8;

  ScumRuleSet();

  ScumRuleSet copy() => ScumRuleSet()
    ..numPlayers = numPlayers
    ..numRounds = numRounds;

  Map<String, dynamic> toJson() => {
        "numPlayers": numPlayers,
        "numRounds": numRounds,
      };

  static ScumRuleSet fromJson(Map<String, dynamic> json) => ScumRuleSet()
    ..numPlayers = json["numPlayers"] as int
    ..numRounds = json["numRounds"] as int;

  int get cardsPerPlayer => 52 ~/ numPlayers;
}

class ScumPlayer {
  List<PlayingCard> hand;
  List<PlayingCard> receivedCards = [];
  int? finishPosition;

  ScumPlayer(this.hand);

  ScumPlayer.from(ScumPlayer src)
      : hand = List.from(src.hand),
        receivedCards = List.from(src.receivedCards),
        finishPosition = src.finishPosition;

  ScumPlayer copy() => ScumPlayer.from(this);

  static List<ScumPlayer> copyAll(Iterable<ScumPlayer> players) =>
      players.map((p) => p.copy()).toList();

  bool get isOut => hand.isEmpty;

  Map<String, dynamic> toJson() => {
        "hand": PlayingCard.stringFromCards(hand),
        "receivedCards": PlayingCard.stringFromCards(receivedCards),
        "finishPosition": finishPosition,
      };

  static ScumPlayer fromJson(Map<String, dynamic> json) => ScumPlayer(
        PlayingCard.cardsFromString(json["hand"] as String),
      )
        ..receivedCards = PlayingCard.cardsFromString(json["receivedCards"] as String)
        ..finishPosition = json["finishPosition"] as int?;
}

/// A play or pass within the current trick.
class ScumTrickAction {
  final int player;
  final List<PlayingCard> cards; // Empty for a pass.

  ScumTrickAction(this.player, this.cards);

  bool get isPass => cards.isEmpty;

  Map<String, dynamic> toJson() => {
        "player": player,
        "cards": PlayingCard.stringFromCards(cards),
      };

  static ScumTrickAction fromJson(Map<String, dynamic> json) => ScumTrickAction(
        json["player"] as int,
        PlayingCard.cardsFromString(json["cards"] as String),
      );
}

class ScumTrick {
  /// Player who led the trick. This is also the player of the last non-pass
  /// play while the trick is in progress, since plays must be ascending.
  final int leader;
  final List<ScumTrickAction> actions = [];

  ScumTrick(this.leader);

  ScumTrick.copy(ScumTrick src) : leader = src.leader {
    for (final a in src.actions) {
      actions.add(ScumTrickAction(a.player, List.of(a.cards)));
    }
  }

  List<List<PlayingCard>> get plays =>
      [for (final a in actions) if (!a.isPass) a.cards];

  /// The play currently to beat, or null if nobody has played yet.
  ScumTrickAction? get bestAction {
    for (final a in actions.reversed) {
      if (!a.isPass) return a;
    }
    return null;
  }

  int? get winningPlayer => bestAction?.player;

  Map<String, dynamic> toJson() => {
        "leader": leader,
        "actions": [for (final a in actions) a.toJson()],
      };

  static ScumTrick fromJson(Map<String, dynamic> json) {
    final trick = ScumTrick(json["leader"] as int);
    trick.actions.addAll(
        (json["actions"] as List).map((a) => ScumTrickAction.fromJson(a as Map<String, dynamic>)));
    return trick;
  }
}

enum ScumRoundStatus { trading, playing }

/// Returns all groupings of `count` cards of a single rank held by `hand`.
/// The specific suits don't matter in Scum, so representative cards are
/// chosen deterministically (lowest suit first).
List<List<PlayingCard>> setsInHand(List<PlayingCard> hand, {int? maxSize}) {
  final result = <List<PlayingCard>>[];
  final byRank = <Rank, List<PlayingCard>>{};
  for (final c in hand) {
    byRank.putIfAbsent(c.rank, () => []).add(c);
  }
  for (final rank in Rank.values.reversed) {
    final cards = byRank[rank];
    if (cards == null) continue;
    // Prefer spades > hearts > diamonds > clubs within the set for display.
    final ordered = [...cards]..sort((a, b) => b.suit.index.compareTo(a.suit.index));
    final limit = min(maxSize ?? ordered.length, ordered.length);
    for (int size = 1; size <= limit; size++) {
      result.add(ordered.sublist(0, size));
    }
  }
  return result;
}

/// Legal complete plays (as concrete card lists) for a hand given the trick
/// state. An empty trick allows any single-rank set of any size.
List<List<PlayingCard>> legalSetsForHand(
    List<PlayingCard> hand, ScumTrick? currentTrick) {
  final best = currentTrick?.bestAction;
  if (best == null) {
    return setsInHand(hand);
  }
  final requiredSize = best.cards.length;
  final minRankIndex = best.cards[0].rank.index;
  return setsInHand(hand).where((set) {
    return set.length == requiredSize && set[0].rank.index > minRankIndex;
  }).toList();
}

bool isValidPlay(
    List<PlayingCard> hand, List<PlayingCard> selected, ScumTrick? currentTrick) {
  if (selected.isEmpty || selected.length > 4) return false;
  final rank = selected[0].rank;
  if (selected.any((c) => c.rank != rank)) return false;
  final countOfRank = hand.where((c) => c.rank == rank).length;
  if (selected.length > countOfRank) return false;
  final unique = Set.of(selected);
  if (unique.length != selected.length) return false;
  final best = currentTrick?.bestAction;
  if (best != null) {
    if (selected.length != best.cards.length) return false;
    if (rank.index <= best.cards[0].rank.index) return false;
  }
  return true;
}

/// The N highest cards of a hand, used for the mandatory trades from the scum
/// players. Ties are broken by suit order (spades high) for determinism.
List<PlayingCard> highestCards(List<PlayingCard> hand, int count) {
  final sorted = [...hand]..sort((a, b) {
      int cmp = b.rank.index - a.rank.index;
      if (cmp != 0) return cmp;
      return b.suit.index - a.suit.index;
    });
  return sorted.sublist(0, min(count, sorted.length));
}

class ScumRound {
  ScumRoundStatus status = ScumRoundStatus.playing;
  late ScumRuleSet rules;
  late List<ScumPlayer> players;

  /// True for the opening round of a match, where everyone is a citizen,
  /// seats are random, and no cards are exchanged.
  late bool firstRound;

  /// Seat order by role for this round: index 0 is the President seat, etc.
  /// Null entries mean the seats were assigned randomly (first round), but
  /// the list itself is always length numPlayers.
  late List<int> seatOrder;

  /// Cards each player will give away during trading, indexed by player.
  late List<List<PlayingCard>> tradeSelections;

  late ScumTrick currentTrick;
  List<int> initialScores = [];

  int _nextFinishPosition = 0;

  int get numberOfPlayers => rules.numPlayers;

  static ScumRound deal(ScumRuleSet rules, List<int> scores, List<int>? previousSeatOrder,
      Random rng) {
    final deck = standardDeckCards()..shuffle(rng);
    assert(deck.length % rules.numPlayers == 0);
    final players = <ScumPlayer>[];
    final perPlayer = deck.length ~/ rules.numPlayers;
    for (int i = 0; i < rules.numPlayers; i++) {
      players.add(ScumPlayer(deck.sublist(i * perPlayer, (i + 1) * perPlayer)));
    }
    List<int> seats;
    if (previousSeatOrder == null) {
      seats = List.generate(rules.numPlayers, (i) => i)..shuffle(rng);
    } else {
      seats = List.of(previousSeatOrder);
    }
    final round = ScumRound();
    round.rules = rules.copy();
    round.players = players;
    round.seatOrder = seats;
    round.firstRound = previousSeatOrder == null;
    round.initialScores = List.from(scores);
    round.tradeSelections = List.generate(rules.numPlayers, (_) => []);
    if (previousSeatOrder == null && rules.numPlayers >= 2) {
      // No trading on the first round.
      round.status = ScumRoundStatus.playing;
      round.currentTrick = ScumTrick(seats[0]);
    } else {
      round.status = ScumRoundStatus.trading;
      round.currentTrick = ScumTrick(seats[0]);
      _setDefaultTradeSelections(round);
    }
    return round;
  }

  /// Pre-fill the mandatory trades. The scum and vice scum must give their
  /// highest cards; president and vice president choose freely and their
  /// selections start empty.
  static void _setDefaultTradeSelections(ScumRound round) {
    final scumSeat = round.rules.numPlayers - 1;
    final viceScumSeat = round.rules.numPlayers - 2;
    round.tradeSelections[round.seatOrder[scumSeat]] =
        highestCards(round.players[round.seatOrder[scumSeat]].hand, 2);
    round.tradeSelections[round.seatOrder[viceScumSeat]] =
        highestCards(round.players[round.seatOrder[viceScumSeat]].hand, 1);
  }

  ScumRound copy() {
    final copy = ScumRound();
    copy.rules = rules.copy();
    copy.status = status;
    copy.firstRound = firstRound;
    copy.players = ScumPlayer.copyAll(players);
    copy.seatOrder = List.of(seatOrder);
    copy.tradeSelections = [for (final t in tradeSelections) List.of(t)];
    copy.currentTrick = ScumTrick.copy(currentTrick);
    copy.initialScores = List.of(initialScores);
    copy._nextFinishPosition = _nextFinishPosition;
    return copy;
  }

  Map<String, dynamic> toJson() => {
        "status": status.name,
        "firstRound": firstRound,
        "rules": rules.toJson(),
        "players": [for (final p in players) p.toJson()],
        "seatOrder": seatOrder,
        "tradeSelections": [
          for (final t in tradeSelections) PlayingCard.stringFromCards(t)
        ],
        "currentTrick": currentTrick.toJson(),
        "initialScores": initialScores,
        "nextFinishPosition": _nextFinishPosition,
      };

  static ScumRound fromJson(Map<String, dynamic> json) {
    final round = ScumRound();
    round.rules = ScumRuleSet.fromJson(json["rules"] as Map<String, dynamic>);
    round.status = ScumRoundStatus.values.byName(json["status"] as String);
    round.firstRound = json["firstRound"] as bool? ?? false;
    round.players = (json["players"] as List)
        .map((p) => ScumPlayer.fromJson(p as Map<String, dynamic>))
        .toList();
    round.seatOrder = List<int>.from(json["seatOrder"] as List);
    round.tradeSelections = (json["tradeSelections"] as List)
        .map((t) => PlayingCard.cardsFromString(t as String))
        .toList();
    round.currentTrick = ScumTrick.fromJson(json["currentTrick"] as Map<String, dynamic>);
    round.initialScores = List<int>.from(json["initialScores"] as List);
    round._nextFinishPosition = json["nextFinishPosition"] as int? ?? 0;
    return round;
  }

  ScumRole roleForPlayer(int playerIndex) => ScumRole.values[seatOrder.indexOf(playerIndex)];

  /// Display name for a player this round: everyone is a "Citizen" in the
  /// opening round; afterwards the role names apply.
  String displayNameForPlayer(int playerIndex) =>
      firstRound ? "Citizen" : scumRoleNames[roleForPlayer(playerIndex)]!;

  int seatIndexOfRole(ScumRole role) => seatOrder[role.index];

  bool hasTradeForRole(ScumRole role) =>
      status == ScumRoundStatus.trading &&
      (role == ScumRole.president ||
          role == ScumRole.vicePresident ||
          role == ScumRole.viceScum ||
          role == ScumRole.scum);

  /// Number of cards this player gives away during trading.
  int numCardsGivenForTrade(int playerIndex) {
    switch (roleForPlayer(playerIndex)) {
      case ScumRole.president:
      case ScumRole.scum:
        return 2;
      case ScumRole.vicePresident:
      case ScumRole.viceScum:
        return 1;
    }
  }

  /// Number of cards the player still has to choose during trading. The scum
  /// players' mandatory highest-card trades are pre-selected automatically.
  int numCardsToSelectForTrade(int playerIndex) {
    if (status != ScumRoundStatus.trading) return 0;
    switch (roleForPlayer(playerIndex)) {
      case ScumRole.president:
        return 2;
      case ScumRole.vicePresident:
        return 1;
      default:
        return 0; // Mandatory highest-card trades are pre-selected.
    }
  }

  bool canSetTradeSelection(int playerIndex, List<PlayingCard> cards) {
    if (status != ScumRoundStatus.trading) return false;
    if (cards.length != numCardsToSelectForTrade(playerIndex)) return false;
    return cards.every((c) => players[playerIndex].hand.contains(c));
  }

  void setTradeSelection(int playerIndex, List<PlayingCard> cards) {
    if (!canSetTradeSelection(playerIndex, cards)) {
      throw Exception("Invalid trade selection");
    }
    tradeSelections[playerIndex] = List.from(cards);
  }

  /// True when every player's selection is filled in.
  bool readyToExchange() {
    if (status != ScumRoundStatus.trading) return false;
    for (int i = 0; i < numberOfPlayers; i++) {
      if (tradeSelections[i].length != numCardsGivenForTrade(i)) {
        return false;
      }
    }
    return true;
  }

  /// Executes the exchanges between roles and begins play with the President
  /// leading. Scum gives 2 highest cards to the President, who gives any 2
  /// back; Vice Scum gives the highest card to the Vice President, who gives
  /// any 1 back.
  void exchangeCards() {
    if (!readyToExchange()) {
      throw Exception("Not ready to exchange cards");
    }
    void exchange(ScumRole giver, ScumRole receiver) {
      final g = seatOrder[giver.index];
      final r = seatOrder[receiver.index];
      final cards = tradeSelections[g];
      players[g].hand.removeWhere((c) => cards.contains(c));
      players[r].hand.addAll(cards);
      players[r].receivedCards.addAll(cards);
    }

    exchange(ScumRole.scum, ScumRole.president);
    exchange(ScumRole.president, ScumRole.scum);
    exchange(ScumRole.viceScum, ScumRole.vicePresident);
    exchange(ScumRole.vicePresident, ScumRole.viceScum);

    for (final p in players) {
      p.hand.sort((a, b) {
        int cmp = b.rank.index - a.rank.index;
        if (cmp != 0) return cmp;
        return b.suit.index - a.suit.index;
      });
    }
    status = ScumRoundStatus.playing;
    currentTrick = ScumTrick(seatOrder[0]);
  }

  bool isOver() {
    return players.where((p) => !p.isOut).length <= 1;
  }

  /// Players who still have cards, in turn order from the current position.
  List<int> activePlayersInTurnOrder() {
    final actives = <int>[];
    final start = _nextActorWithoutSkipping();
    for (int offset = 0; offset < numberOfPlayers; offset++) {
      final p = (start + offset) % numberOfPlayers;
      if (!players[p].isOut) actives.add(p);
    }
    return actives;
  }

  int _nextActorWithoutSkipping() {
    if (currentTrick.actions.isEmpty) return currentTrick.leader;
    final last = currentTrick.actions.last.player;
    return (last + 1) % numberOfPlayers;
  }

  int currentPlayerIndex() {
    if (status != ScumRoundStatus.playing || isOver()) return -1;
    var next = _nextActorWithoutSkipping();
    while (players[next].isOut) {
      next = (next + 1) % numberOfPlayers;
    }
    return next;
  }

  List<List<PlayingCard>> legalPlaysForCurrentPlayer() {
    final player = currentPlayerIndex();
    if (player < 0) return [];
    final best = currentTrick.bestAction;
    if (best == null || best.player == player) {
      return legalSetsForHand(players[player].hand, null);
    }
    return legalSetsForHand(players[player].hand, currentTrick);
  }

  /// Whether the current player may pass (leaders must play).
  bool canCurrentPlayerPass() {
    final player = currentPlayerIndex();
    if (player < 0) return false;
    final best = currentTrick.bestAction;
    return best != null && best.player != player;
  }

  void playCards(List<PlayingCard> cards) {
    final player = currentPlayerIndex();
    if (player < 0) throw Exception("Round is over");
    if (!isValidPlay(players[player].hand, cards, currentTrick)) {
      throw Exception("Invalid play: ${PlayingCard.stringFromCards(cards)}");
    }
    for (final c in cards) {
      players[player].hand.remove(c);
    }
    currentTrick.actions.add(ScumTrickAction(player, List.of(cards)));
    if (players[player].isOut) {
      _assignFinishPosition(player);
    }
    _checkTrickCompletion();
  }

  void pass() {
    final player = currentPlayerIndex();
    if (player < 0) throw Exception("Round is over");
    if (!canCurrentPlayerPass()) throw Exception("The leader cannot pass");
    currentTrick.actions.add(ScumTrickAction(player, []));
    _checkTrickCompletion();
  }

  void _assignFinishPosition(int player) {
    if (players[player].finishPosition == null) {
      players[player].finishPosition = _nextFinishPosition;
      _nextFinishPosition += 1;
    }
  }

  void _checkTrickCompletion() {
    if (isOver()) {
      // Assign the last remaining player the final position.
      for (int i = 0; i < numberOfPlayers; i++) {
        if (!players[i].isOut) _assignFinishPosition(i);
      }
      return;
    }
    final bestIndex = _indexOfBestAction();
    if (bestIndex < 0) return;
    // Count consecutive passes after the play currently to beat: once every
    // other active player has declined, the play stands.
    int consecutivePasses = 0;
    for (int i = currentTrick.actions.length - 1; i > bestIndex; i--) {
      if (!currentTrick.actions[i].isPass) break;
      consecutivePasses++;
    }
    final activeOthers = [
      for (int i = 0; i < numberOfPlayers; i++)
        if (!players[i].isOut && i != currentTrick.actions[bestIndex].player) i
    ].length;
    if (consecutivePasses >= activeOthers) {
      _completeTrick(currentTrick.actions[bestIndex]);
    }
  }

  int _indexOfBestAction() {
    for (int i = currentTrick.actions.length - 1; i >= 0; i--) {
      if (!currentTrick.actions[i].isPass) return i;
    }
    return -1;
  }

  void _completeTrick(ScumTrickAction winningAction) {
    var leader = winningAction.player;
    if (players[leader].isOut) {
      // If the winner went out with the winning play, the lead passes to the
      // next player in turn order who still has cards.
      var next = (leader + 1) % numberOfPlayers;
      while (players[next].isOut) {
        next = (next + 1) % numberOfPlayers;
      }
      leader = next;
    }
    currentTrick = ScumTrick(leader);
  }

  /// Finish order as a list of player indices, best first.
  List<int> finishOrder() {
    final order = <int>[];
    final byPosition = <int, int>{};
    for (int i = 0; i < players.length; i++) {
      if (players[i].finishPosition != null) {
        byPosition[players[i].finishPosition!] = i;
      }
    }
    final positions = byPosition.keys.toList()..sort();
    for (final pos in positions) {
      order.add(byPosition[pos]!);
    }
    return order;
  }

  List<int> pointsTaken() {
    final points = List.filled(numberOfPlayers, 0);
    for (int position = 0; position < finishOrder().length; position++) {
      points[finishOrder()[position]] = scumPointsForFinishPosition[position];
    }
    return points;
  }
}

class ScumMatch {
  Random rng;
  ScumRuleSet rules;
  List<ScumRound> previousRounds = [];
  late ScumRound currentRound;
  List<int> scores = [];

  ScumMatch(ScumRuleSet _rules, this.rng) : rules = _rules.copy() {
    scores = List.filled(rules.numPlayers, 0);
    currentRound = ScumRound.deal(rules, scores, null, rng);
  }

  Map<String, dynamic> toJson() => {
        "rules": rules.toJson(),
        "scores": scores,
        "previousRounds": [for (final r in previousRounds) r.toJson()],
        "currentRound": currentRound.toJson(),
      };

  static ScumMatch fromJson(Map<String, dynamic> json, Random rng) {
    final match = ScumMatch(
        ScumRuleSet.fromJson(json["rules"] as Map<String, dynamic>), rng)
      ..scores = List<int>.from(json["scores"] as List)
      ..previousRounds = [
        ...json["previousRounds"].map((r) => ScumRound.fromJson(r as Map<String, dynamic>))
      ]
      ..currentRound = ScumRound.fromJson(json["currentRound"] as Map<String, dynamic>);
    return match;
  }

  ScumMatch copy() => ScumMatch.fromJson(toJson(), rng);

  /// Seats for the next round, derived from how players finished the current
  /// round. First out becomes President, last out stays Scum.
  List<int>? get nextSeatOrder {
    if (previousRounds.isEmpty) return null;
    return previousRounds.last.finishOrder();
  }

  bool isRoundOver() => currentRound.isOver();

  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    final roundPoints = currentRound.pointsTaken();
    for (int i = 0; i < rules.numPlayers; i++) {
      scores[i] += roundPoints[i];
    }
    previousRounds.add(currentRound);
    if (!isMatchOver()) {
      currentRound = ScumRound.deal(rules, scores, nextSeatOrder, rng);
    }
  }

  int get roundsCompleted => previousRounds.length;  bool isMatchOver() => roundsCompleted >= rules.numRounds;

  List<int> winningPlayers() {
    final maxScore = scores.reduce(max);
    return [
      for (int i = 0; i < scores.length; i++)
        if (scores[i] == maxScore) i
    ];
  }
}
