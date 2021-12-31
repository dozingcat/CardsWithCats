import 'dart:math';

import 'package:hearts/cards/card.dart';
import 'package:hearts/cards/trick.dart';

enum MoonShooting {
  disabled,
  opponentsPlus26,
  // TODO: Allow option of subtracting 26 from the shooter's score.
}

final queenOfSpades = PlayingCard(Rank.queen, Suit.spades);
final jackOfDiamonds = PlayingCard(Rank.jack, Suit.diamonds);
final twoOfClubs = PlayingCard(Rank.two, Suit.clubs);

class HeartsRuleSet {
  int numPlayers = 4;
  int numPassedCards = 3;
  List<PlayingCard> removedCards = [];
  int pointLimit = 100;
  bool pointsOnFirstTrick = false;
  bool queenBreaksHearts = false;
  bool jdMinus10 = false;
  MoonShooting moonShooting = MoonShooting.opponentsPlus26;

  HeartsRuleSet();

  HeartsRuleSet copy() => HeartsRuleSet.from(this);

  HeartsRuleSet.from(HeartsRuleSet src) :
      numPlayers = src.numPlayers,
      numPassedCards = src.numPassedCards,
      removedCards = List.from(src.removedCards),
      pointLimit = src.pointLimit,
      pointsOnFirstTrick = src.pointsOnFirstTrick,
      queenBreaksHearts = src.queenBreaksHearts,
      jdMinus10 = src.jdMinus10,
      moonShooting = src.moonShooting;

  Map<String, Object> toJson() {
    return {
      "numPlayers": numPlayers,
      "numPassedCards": numPassedCards,
      "removedCards": PlayingCard.stringFromCards(removedCards),
      "pointLimit": pointLimit,
      "pointsOnFirstTrick": pointsOnFirstTrick,
      "queenBreaksHearts": queenBreaksHearts,
      "jdMinus10": jdMinus10,
      "moonShooting": moonShooting.name,
    };
  }

  static HeartsRuleSet fromJson(Map<String, Object> json) {
    return HeartsRuleSet()
      ..numPlayers = json["numPlayers"] as int
      ..numPassedCards = json["numPassedCards"] as int
      ..removedCards = PlayingCard.cardsFromString(json["removedCards"] as String)
      ..pointLimit = json["pointLimit"] as int
      ..pointsOnFirstTrick = json["pointsOnFirstTrick"] as bool
      ..queenBreaksHearts = json["queenBreaksHearts"] as bool
      ..jdMinus10 = json["jdMinus10"] as bool
      ..moonShooting = MoonShooting.values.firstWhere((v) => v.name == json["moonShooting"])
      ;
  }

  int get numberOfUsedCards => (52 - removedCards.length);
  int get numberOfCardsPerPlayer => numberOfUsedCards ~/ numPlayers;
}

int pointsForCard(PlayingCard card, HeartsRuleSet ruleSet) {
  if (card.suit == Suit.hearts) {
    return 1;
  }
  if (card == queenOfSpades) {
    return 13;
  }
  if (ruleSet.jdMinus10 && card == jackOfDiamonds) {
    return -10;
  }
  return 0;
}

int pointsForCards(List<PlayingCard> cards, HeartsRuleSet ruleSet) {
  int points = 0;
  for (final c in cards) {
    points += pointsForCard(c, ruleSet);
  }
  return points;
}

// Accounts for shooting the moon if set in the rules.
List<int> pointsForTricks(List<Trick> tricks, HeartsRuleSet ruleSet) {
  List<int> points = List.filled(ruleSet.numPlayers, 0);
  for (final t in tricks) {
    points[t.winner] += pointsForCards(t.cards, ruleSet);
  }
  // If a player shot the moon, deduct 26 points from their score and add it to
  // each other player.
  if (ruleSet.moonShooting == MoonShooting.opponentsPlus26) {
    final shooter = moonShooter(tricks);
    if (shooter != null) {
      for (int i = 0; i < ruleSet.numPlayers; i++) {
        points[i] += (i == shooter) ? -26 : 26;
      }
    }
  }
  return points;
}

int? moonShooter(List<Trick> tricks) {
  // Find the player who took the queen and see if they took all the hearts.
  int? qsOwner;
  int? heartsOwner;
  int numHearts = 0;
  for (final t in tricks) {
    for (final c in t.cards) {
      if (c == queenOfSpades) {
        qsOwner = t.winner;
      }
      else if (c.suit == Suit.hearts) {
        if (heartsOwner != null && heartsOwner != t.winner) {
          return null;
        }
        heartsOwner = t.winner;
        numHearts++;
      }
    }
  }
  return (qsOwner == heartsOwner && numHearts == 13) ? qsOwner : null;
}

bool _areHeartsBroken(
    TrickInProgress currentTrick, List<Trick> prevTricks, HeartsRuleSet rules) {
  bool qb = rules.queenBreaksHearts;
  for (final t in prevTricks) {
    for (final c in t.cards) {
      if (c.suit == Suit.hearts || (qb && c == queenOfSpades)) {
        return true;
      }
    }
  }
  for (final c in currentTrick.cards) {
    if (c.suit == Suit.hearts || (qb && c == queenOfSpades)) {
      return true;
    }
  }
  return false;
}

List<PlayingCard> legalPlays(
    List<PlayingCard> hand,
    TrickInProgress currentTrick,
    List<Trick> prevTricks,
    HeartsRuleSet rules) {
  if (prevTricks.isEmpty) {
    // First trick.
    if (currentTrick.cards.isEmpty) {
      return hand.contains(twoOfClubs) ? [twoOfClubs] : [];
    }
    // Follow suit if possible.
    final lead = currentTrick.cards[0].suit;
    final matching = hand.where((c) => c.suit == lead).toList();
    if (matching.isNotEmpty) {
      return matching;
    }
    if (!rules.pointsOnFirstTrick) {
      final nonPoints = hand.where((c) => pointsForCard(c, rules) <= 0).toList();
      if (nonPoints.isNotEmpty) {
        return nonPoints;
      }
    }
    // Either points are allowed or we have nothing but points.
    return hand;
  }
  else if (currentTrick.cards.isEmpty) {
    // Leading a new trick; remove hearts unless hearts are broken or there's no choice.
    if (!_areHeartsBroken(currentTrick, prevTricks, rules)) {
      final nonHearts = hand.where((c) => c.suit != Suit.hearts).toList();
      if (nonHearts.isNotEmpty) {
        return nonHearts;
      }
    }
    return hand;
  }
  else {
    // Follow suit if possible; otherwise play anything.
    final lead = currentTrick.cards[0].suit;
    final matching = hand.where((c) => c.suit == lead).toList();
    return matching.isNotEmpty ? matching : hand;
  }
}

int indexOfPlayerWithCard(List<HeartsPlayer> players, PlayingCard card) {
  return players.indexWhere((p) => p.hand.contains(card));
}

class HeartsPlayer {
  List<PlayingCard> hand;
  List<PlayingCard> passedCards;
  List<PlayingCard> receivedCards;

  HeartsPlayer(
      List<PlayingCard> _hand) :
        hand = List.from(_hand),
        passedCards = [],
        receivedCards = [];

  HeartsPlayer.from(HeartsPlayer src) :
      hand = List.from(src.hand),
      passedCards = List.from(src.passedCards),
      receivedCards = List.from(src.receivedCards);

  HeartsPlayer copy() => HeartsPlayer.from(this);
  static List<HeartsPlayer> copyAll(Iterable<HeartsPlayer> ps) => ps.map((p) => p.copy()).toList();

  Map<String, Object> toJson() {
    return {
      "hand": PlayingCard.stringFromCards(hand),
      "passedCards": PlayingCard.stringFromCards(passedCards),
      "receivedCards": PlayingCard.stringFromCards(receivedCards),
    };
  }

  static HeartsPlayer fromJson(final Map<String, Object> json) {
    return HeartsPlayer(PlayingCard.cardsFromString(json["hand"] as String))
      ..passedCards = PlayingCard.cardsFromString(json["passedCards"] as String)
      ..receivedCards = PlayingCard.cardsFromString(json["receivedCards"] as String)
      ;
  }
}

enum HeartsRoundStatus {
  passing,
  playing,
}

class HeartsRound {
  HeartsRoundStatus status = HeartsRoundStatus.passing;
  late HeartsRuleSet rules;
  late List<HeartsPlayer> players;
  late List<int> initialScores;
  late int passDirection;
  late TrickInProgress currentTrick;
  List<Trick> previousTricks = [];

  static HeartsRound deal(HeartsRuleSet rules, List<int> scores, int passDirection, Random rng) {
    List<PlayingCard> cards = List.from(standardDeckCards(), growable: true);
    cards.removeWhere((c) => rules.removedCards.contains(c));
    cards.shuffle(rng);
    List<HeartsPlayer> players = [];
    int numCardsPerPlayer = cards.length ~/ rules.numPlayers;
    for (int i = 0; i < rules.numPlayers; i++) {
      final playerCards = cards.sublist(i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
      players.add(HeartsPlayer(playerCards));
    }
    int startingPlayer = indexOfPlayerWithCard(players, twoOfClubs);

    final round = HeartsRound();
    round.rules = rules.copy();
    round.status = (passDirection == 0) ? HeartsRoundStatus.playing : HeartsRoundStatus.passing;
    round.initialScores = List.from(scores);
    round.players = players;
    round.passDirection = passDirection;
    round.currentTrick = TrickInProgress(startingPlayer);

    return round;
  }

  HeartsRound copy() {
    return HeartsRound()
      ..rules = rules.copy()
      ..status = status
      ..players = HeartsPlayer.copyAll(players)
      ..initialScores = List.of(initialScores)
      ..passDirection = passDirection
      ..currentTrick = currentTrick.copy()
      ..previousTricks = Trick.copyAll(previousTricks);
  }

  Map<String, Object> toJson() {
    return {
      "rules": rules.toJson(),
      "status": status.name,
      "players": players.map((p) => p.toJson()),
      "initialScores": initialScores,
      "passDirection": passDirection,
      "currentTrick": currentTrick.toJson(),
      "previousTricks": previousTricks.map((t) => t.toJson()),
    };
  }

  static HeartsRound fromJson(final Map<String, Object> json) {
    return HeartsRound()
      ..rules = HeartsRuleSet.fromJson(json["rules"] as Map<String, Object>)
      ..status = HeartsRoundStatus.values.firstWhere((v) => v.name == json["status"])
      ..players = [...(json["players"] as List<Map<String, Object>>).map(HeartsPlayer.fromJson)]
      ..initialScores = json["initialScores"] as List<int>
      ..passDirection = json["passDirection"] as int
      ..currentTrick = TrickInProgress.fromJson(json["currentTrick"] as Map<String, Object>)
      ..previousTricks = [...(json["previousTricks"] as List<Map<String, Object>>).map(Trick.fromJson)]
      ;
  }

  bool isOver() {
    return players.every((p) => p.hand.isEmpty);
  }

  List<int> pointsTaken() {
    return pointsForTricks(previousTricks, rules);
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  HeartsPlayer currentPlayer() => players[currentPlayerIndex()];

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(currentPlayer().hand, currentTrick, previousTricks, rules);
  }

  bool areHeartsBroken() {
    return _areHeartsBroken(currentTrick, previousTricks, rules);
  }

  bool canPassCards(int playerIndex, List<PlayingCard> cards) {
    if (cards.length != rules.numPassedCards) {
      return false;
    }
    final hand = players[playerIndex].hand;
    return cards.every((c) => hand.contains(c));
  }

  void setPassedCardsForPlayer(int playerIndex, List<PlayingCard> cards) {
    if (status != HeartsRoundStatus.passing) {
      throw Exception("Not in passing mode");
    }
    if (!canPassCards(playerIndex, cards)) {
      throw Exception("Invalid cards");
    }
    players[playerIndex].passedCards = List.from(cards);
  }

  bool readyToPassCards() {
    if (status != HeartsRoundStatus.passing) {
      return false;
    }
    return players.every((p) => p.passedCards.length == rules.numPassedCards);
  }

  void passCards() {
    if (!readyToPassCards()) {
      throw Exception("Not able to pass cards");
    }
    int np = rules.numPlayers;
    for (int i = 0; i < np; i++) {
      final destPlayer = players[(i + passDirection) % np];
      destPlayer.receivedCards = players[i].passedCards;

      final newHand = List.of(destPlayer.receivedCards, growable: true);
      newHand.addAll(destPlayer.hand.where((c) => !destPlayer.passedCards.contains(c)));
      destPlayer.hand = newHand;
    }
    if (players.any((p) => p.hand.length != players[0].hand.length)) {
      throw Exception("Mismatched hand lengths");
    }
    currentTrick = TrickInProgress(indexOfPlayerWithCard(players, twoOfClubs));
    status = HeartsRoundStatus.playing;
  }

  void playCard(PlayingCard card) {
    final p = currentPlayer();
    final cardIndex = p.hand.indexWhere((c) => c == card);
    p.hand.removeAt(cardIndex);
    currentTrick.cards.add(card);
    if (currentTrick.cards.length == rules.numPlayers) {
      final lastTrick = currentTrick.finish();
      previousTricks.add(lastTrick);
      currentTrick = TrickInProgress(lastTrick.winner);
    }
  }
}

class HeartsMatch {
  Random rng;
  HeartsRuleSet rules;
  List<int> scores;
  int passDirection = 0;
  List<HeartsRound> previousRounds = [];
  late HeartsRound currentRound;

  HeartsMatch(HeartsRuleSet _rules, this.rng) :
      rules = _rules.copy(),
      scores = List.filled(_rules.numPlayers, 0)
  {
    _addNewRound();
  }

  Map<String, Object> toJson() {
    return {
      "rules": rules.toJson(),
      "scores": scores,
      "passDirection": passDirection,
      "previousRounds": previousRounds.map((r) => r.toJson()),
      "currentRound": currentRound.toJson(),
    };
  }

  static HeartsMatch fromJson(final Map<String, Object> json, Random rng) {
    return HeartsMatch(HeartsRuleSet.fromJson(json["rules"] as Map<String, Object>), rng)
      ..scores = json["scores"] as List<int>
      ..passDirection = json["passDirection"] as int
      ..previousRounds =
          [...(json["previousRules"] as List<Map<String, Object>>).map(HeartsRound.fromJson)]
      ..currentRound = HeartsRound.fromJson(json["currentRound"] as Map<String, Object>)
      ;
  }

  void _addNewRound() {
    int np = rules.numPlayers;
    if (np <= 3) {
      passDirection = (passDirection + 1) % np;
    }
    else {
      // Order is left, right, "middle" (from left to right if >1), none.
      if (passDirection == 1) {
        passDirection = np - 1;
      }
      else if (passDirection == np - 2) {
        passDirection = 0;
      }
      else if (passDirection == np - 1) {
        passDirection = 2;
      }
      else {
        passDirection += 1;
      }
    }
    currentRound = HeartsRound.deal(rules, scores, passDirection, rng);
  }

  void finishRound() {
    if (!currentRound.isOver()) {
      throw Exception("Current round is not over");
    }
    final roundScores = currentRound.pointsTaken();
    for (int i = 0; i < rules.numPlayers; i++) {
      scores[i] += roundScores[i];
    }
    previousRounds.add(currentRound);
    if (!isMatchOver()) {
      _addNewRound();
    }
  }

  bool isMatchOver() {
    return scores.any((s) => s >= rules.pointLimit);
  }

  List<int> winningPlayers() {
    if (!isMatchOver()) {
      return [];
    }
    final minScore = scores.reduce(min);
    List<int> winners = [];
    for (int i = 0; i < rules.numPlayers; i++) {
      if (scores[i] == minScore) {
        winners.add(i);
      }
    }
    return winners;
  }
}
