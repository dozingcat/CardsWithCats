import "dart:math";

import "package:cards_with_cats/cards/card.dart";

import "../cards/rollout.dart";
import "../cards/trick.dart";
import "bridge.dart";
import "bridge.dart" as bridge;

int pointsForCard(PlayingCard card) {
  switch (card.rank) {
    case Rank.ace:
      return 4;
    case Rank.king:
      return 3;
    case Rank.queen:
      return 2;
    case Rank.jack:
      return 1;
    default:
      return 0;
  }
}

int highCardPoints(final List<PlayingCard> hand) {
  return hand.map(pointsForCard).reduce((a, b) => a + b);
}

int lengthPoints(final List<PlayingCard> hand) {
  int points = 0;
  points += max(0, hand.where((c) => c.suit == Suit.spades).length - 4);
  points += max(0, hand.where((c) => c.suit == Suit.hearts).length - 4);
  points += max(0, hand.where((c) => c.suit == Suit.diamonds).length - 4);
  points += max(0, hand.where((c) => c.suit == Suit.clubs).length - 4);
  return points;
}

int lengthPointsForSuitCounts(final Map<Suit, int> suitCounts) {
  int points = 0;
  for (final entry in suitCounts.entries) {
    points += max(0, entry.value - 4);
  }
  return points;
}

class Range {
  final int? low;
  final int? high;

  const Range({this.low, this.high});

  @override
  String toString() {
    return "Range(low: $low, high: $high)";
  }

  String shortString() {
    if (low == null && high == null) {
      return "any";
    }
    if (low == null) {
      return "<=$high";
    }
    if (high == null) {
      return ">=$low";
    }
    return "$low-$high";
  }

  @override
  bool operator ==(Object other) {
    return other is Range && low == other.low && high == other.high;
  }

  @override
  int get hashCode => Object.hash(low, high);

  bool contains(int value) {
    return (low == null || value >= low!) && (high == null || value <= high!);
  }

  Range combine(Range? other) {
    if (other == null) {
      return this;
    }
    return Range(
      low: low == null
          ? other.low
          : other.low == null
              ? low
              : max(low!, other.low!),
      high: high == null
          ? other.high
          : other.high == null
              ? high
              : min(high!, other.high!),
    );
  }

  bool isDisjointWith(Range other) {
    return (high != null && other.low != null && high! < other.low!) ||
        (low != null && other.high != null && low! > other.high!);
  }

  Range combineOrReplace(Range? other) {
    if (other != null && isDisjointWith(other)) {
      return other;
    }
    return combine(other);
  }

  Range plusConstant(int n) {
    // Assumes nonnegative values.
    return Range(
      low: (low == null ? n : n + low!),
      high: (high == null) ? null : high! + n,
    );
  }
}

Map<Suit, Range> _addMissingSuitRanges(Map<Suit, Range>? suitLengths) {
  Map<Suit, Range> allSuitLengths = {};
  for (final suit in Suit.values) {
    allSuitLengths[suit] = suitLengths?[suit] ?? const Range();
  }
  return allSuitLengths;
}

enum HandPointBonusType {
  none,
  suitLength,
}

class HandEstimate {
  final Range pointRange;
  final Map<Suit, Range> suitLengthRanges;
  final HandPointBonusType pointBonusType;

  HandEstimate._(
      {required this.pointRange,
      required this.suitLengthRanges,
      required this.pointBonusType});

  factory HandEstimate(
      {pointRange = const Range(),
      Map<Suit, Range>? suitLengthRanges,
      HandPointBonusType pointBonusType = HandPointBonusType.none}) {
    return HandEstimate._(
      pointRange: pointRange,
      suitLengthRanges: _addMissingSuitRanges(suitLengthRanges),
      pointBonusType: pointBonusType,
    );
  }

  @override
  String toString() {
    final s = suitLengthRanges;
    return "Points: ${pointRange.shortString()} S:${s[Suit.spades]!.shortString()} H:${s[Suit.hearts]!.shortString()} D:${s[Suit.diamonds]!.shortString()} C:${s[Suit.clubs]!.shortString()}";
  }

  bool matches(List<PlayingCard> hand, Map<Suit, int> suitCounts) {
    int points = highCardPoints(hand);
    if (pointBonusType == HandPointBonusType.suitLength) {
      points += lengthPointsForSuitCounts(suitCounts);
    }
    // print("Checking points: $pointRange $points");
    if (!pointRange.contains(points)) {
      // print("Failed point range");
      return false;
    }
    for (final suit in Suit.values) {
      // print("Checking suit: $suit ${suitLengthRanges[suit]} ${suitCounts[suit]}");
      if (!suitLengthRanges[suit]!.contains(suitCounts[suit]!)) {
        // print("Failed suit length");
        return false;
      }
    }
    return true;
  }

  HandEstimate combineOrReplace(HandEstimate other) {
    final combinedPoints = pointRange.combineOrReplace(other.pointRange);
    final combinedSuits = {
      Suit.clubs: suitLengthRanges[Suit.clubs]!
          .combineOrReplace(other.suitLengthRanges[Suit.clubs]),
      Suit.diamonds: suitLengthRanges[Suit.diamonds]!
          .combineOrReplace(other.suitLengthRanges[Suit.diamonds]),
      Suit.hearts: suitLengthRanges[Suit.hearts]!
          .combineOrReplace(other.suitLengthRanges[Suit.hearts]),
      Suit.spades: suitLengthRanges[Suit.spades]!
          .combineOrReplace(other.suitLengthRanges[Suit.spades]),
    };
    return HandEstimate(
      pointRange: combinedPoints,
      suitLengthRanges: combinedSuits,
    );
  }
}

class BidAnalysis {
  final HandEstimate handEstimate;
  final bool Function(List<PlayingCard>, Map<Suit, int> suitCounts)?
      handMatcher;
  final String description;

  BidAnalysis({
    required this.handEstimate,
    this.handMatcher,
    required this.description,
  });

  bool matches(List<PlayingCard> hand, Map<Suit, int> suitCounts) {
    if (!handEstimate.matches(hand, suitCounts)) {
      return false;
    }
    if (handMatcher != null) {
      // print("Checking custom matcher");
      if (!handMatcher!(hand, suitCounts)) {
        // print("Failed custom matcher");
        return false;
      }
    }
    // print("Passes!");
    return true;
  }
}

class CardToPlayRequest {
  final List<PlayingCard> hand;
  // dummyHand is set for all players except the dummy.
  // declarerHand is set only for the dummy.
  final List<PlayingCard>? dummyHand;
  final List<PlayingCard>? declarerHand;
  final List<Trick> previousTricks;
  final TrickInProgress currentTrick;
  final List<PlayerBid> bidHistory;
  final Vulnerability vulnerability;
  final Contract contract;

  CardToPlayRequest({
    required this.hand,
    this.dummyHand,
    this.declarerHand,
    required this.previousTricks,
    required this.currentTrick,
    required this.bidHistory,
    required this.vulnerability,
  }) : contract =
            contractFromBids(bids: bidHistory, vulnerability: vulnerability);

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % 4;
  }

  Suit? trump() => contract.bid.trump;

  List<PlayingCard> legalPlays() {
    return bridge.legalPlays(hand, currentTrick);
  }

  static CardToPlayRequest fromRound(final BridgeRound round) {
    final contract = round.contract;
    if (contract == null) {
      throw Exception("Contract is null");
    }
    bool isDummy = (round.currentPlayerIndex() == contract.dummy);
    final dummyHand = isDummy ? null : round.players[contract.dummy].hand;
    final declarerHand = isDummy ? round.players[contract.declarer].hand : null;
    return CardToPlayRequest(
      hand: List.from(round.currentPlayer().hand),
      dummyHand: dummyHand != null ? List.from(dummyHand) : null,
      declarerHand: declarerHand != null ? List.from(declarerHand) : null,
      previousTricks: Trick.copyAll(round.previousTricks),
      currentTrick: round.currentTrick.copy(),
      bidHistory: List.from(round.bidHistory),
      vulnerability: round.vulnerability,
    );
  }

  static CardToPlayRequest fromRoundWithSharedReferences(
      final BridgeRound round) {
    final contract = round.contract;
    if (contract == null) {
      throw Exception("Contract is null");
    }
    bool isDummy = (round.currentPlayerIndex() == contract.dummy);
    final dummyHand = isDummy ? null : round.players[contract.dummy].hand;
    final declarerHand = isDummy ? round.players[contract.declarer].hand : null;
    return CardToPlayRequest(
      hand: round.currentPlayer().hand,
      dummyHand: dummyHand,
      declarerHand: declarerHand,
      previousTricks: round.previousTricks,
      currentTrick: round.currentTrick,
      bidHistory: round.bidHistory,
      vulnerability: round.vulnerability,
    );
  }
}

typedef ChooseCardFn = PlayingCard Function(CardToPlayRequest req, Random rng);

List<PlayingCard> cardsToConsiderPlaying(CardToPlayRequest req, Random rng) {
  // Possibly use groupsOfEffectivelyIdenticalCards
  return req.legalPlays();
}

PlayingCard chooseCardRandom(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  return legalPlays[rng.nextInt(legalPlays.length)];
}

PlayingCard _lowDiscard(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  Suit? trump = req.trump();
  if (trump == null) {
    return minCardByRank(legalPlays);
  }
  final nonTrumps = legalPlays.where((c) => c.suit != trump).toList();
  if (nonTrumps.isNotEmpty) {
    return minCardByRank(nonTrumps);
  } else {
    return minCardByRank(legalPlays);
  }
}

PlayingCard _lowestWinnerOrLowest(
    final CardToPlayRequest req, PlayingCard highCard, Random rng) {
  final legalPlays = req.legalPlays();
  // Play a higher card of the same suit if possible.
  final sameSuitWinners = legalPlays
      .where(
          (c) => c.suit == highCard.suit && c.rank.isHigherThan(highCard.rank))
      .toList();
  if (sameSuitWinners.isNotEmpty) {
    return minCardByRank(sameSuitWinners);
  }
  // Trump if possible.
  Suit? trump = req.trump();
  if (trump != null && highCard.suit != trump) {
    final trumpCards = legalPlays.where((c) => c.suit == trump).toList();
    if (trumpCards.isNotEmpty) {
      return minCardByRank(trumpCards);
    }
  }
  // Can't win.
  return _lowDiscard(req, rng);
}

bool _canPlayHigherInTrick(final CardToPlayRequest req) {
  final tc = req.currentTrick.cards;
  if (tc.isEmpty) {
    return true;
  }
  final trump = req.contract.bid.trump;
  final legalPlays = req.legalPlays();
  final highCard = tc[trickWinnerIndex(tc, trump: trump)];
  if (legalPlays.any(
      (c) => c.suit == highCard.suit && c.rank.isHigherThan(highCard.rank))) {
    return true;
  }
  if (trump != null &&
      highCard.suit != trump &&
      legalPlays.any((c) => c.suit == trump)) {
    return true;
  }
  return false;
}

PlayingCard _maximizeTricksCard4(final CardToPlayRequest req, Random rng) {
  final tc = req.currentTrick.cards;
  final trump = req.contract.bid.trump;
  int leader = trickWinnerIndex(tc, trump: trump);
  if (leader == 1) {
    // Partner is winning.
    return _lowDiscard(req, rng);
  } else {
    return _lowestWinnerOrLowest(req, tc[leader], rng);
  }
}

PlayingCard chooseCardToMaximizeTricks(
    final CardToPlayRequest req, Random rng) {
  switch (req.currentTrick.cards.length) {
    case 3:
      return _maximizeTricksCard4(req, rng);
    default:
      // TODO
      if (!_canPlayHigherInTrick(req)) {
        return _lowDiscard(req, rng);
      }
      return chooseCardRandom(req, rng);
  }
}

CardDistributionRequest makeCardDistributionRequest(
    final CardToPlayRequest req) {
  // If this is the first lead, the dummy isn't revealed.
  if (req.previousTricks.isEmpty && req.currentTrick.cards.isEmpty) {
    final constraints = List.generate(
        numPlayers,
        (pnum) => CardDistributionConstraint(
            numCards: req.hand.length,
            fixedCards: pnum == req.currentPlayerIndex() ? req.hand : []));
    return CardDistributionRequest(
        cardsToAssign: standardDeckCards(), constraints: constraints);
  }

  final seenCards = <PlayingCard>{};
  final voidedSuits = List.generate(numPlayers, (i) => <Suit>{});

  // Record when a player is out of a suit.
  void processTrick(List<PlayingCard> cards, int leader) {
    final trickSuit = cards[0].suit;
    seenCards.add(cards[0]);
    for (int i = 1; i < cards.length; i++) {
      final c = cards[i];
      seenCards.add(c);
      if (c.suit != trickSuit) {
        voidedSuits[(leader + i) % numPlayers].add(trickSuit);
      }
    }
  }

  for (final t in req.previousTricks) {
    processTrick(t.cards, t.leader);
  }
  if (req.currentTrick.cards.isNotEmpty) {
    processTrick(req.currentTrick.cards, req.currentTrick.leader);
  }

  final baseNumCards = req.hand.length;
  final cardCounts = List.generate(numPlayers, (_n) => baseNumCards);
  for (int i = 0; i < req.currentTrick.cards.length; i++) {
    final pi = (req.currentTrick.leader + i) % numPlayers;
    cardCounts[pi] -= 1;
  }

  int currentPlayerIndex = req.currentPlayerIndex();
  final constraints = List.generate(
      numPlayers,
      (pnum) => CardDistributionConstraint(
            numCards: cardCounts[pnum],
            voidedSuits: voidedSuits[pnum].toList(),
            fixedCards: pnum == currentPlayerIndex ? req.hand : [],
          ));

  if (req.dummyHand != null) {
    constraints[req.contract.dummy].fixedCards = req.dummyHand!;
  }
  if (req.declarerHand != null) {
    constraints[req.contract.declarer].fixedCards = req.declarerHand!;
  }

  final Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  cardsToAssign.removeAll(seenCards);
  return CardDistributionRequest(
      cardsToAssign: cardsToAssign.toList(), constraints: constraints);
}

BridgeRound? possibleRound(
    CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng) {
  final dist = possibleCardDistribution(distReq, rng);
  if (dist == null) {
    return null;
  }
  final resultPlayers =
      List.generate(dist.length, (pnum) => BridgePlayer(dist[pnum]));
  return BridgeRound()
    ..status = BridgeRoundStatus.playing
    ..players = resultPlayers
    ..currentTrick = cardReq.currentTrick.copy()
    ..previousTricks = Trick.copyAll(cardReq.previousTricks)
    ..bidHistory = cardReq.bidHistory
    ..contract = cardReq.contract
    ..vulnerability = cardReq.vulnerability
    ..dealer = cardReq.bidHistory[0].player;
}

MonteCarloResult chooseCardMonteCarlo(CardToPlayRequest cardReq,
    MonteCarloParams mcParams, ChooseCardFn rolloutChooseFn, Random rng,
    {int Function()? timeFn}) {
  timeFn ??= () => DateTime.now().millisecondsSinceEpoch;
  final startTime = timeFn();
  final legalPlays = cardsToConsiderPlaying(cardReq, rng);
  assert(legalPlays.isNotEmpty);
  if (legalPlays.length == 1) {
    return MonteCarloResult.rolloutNotNeeded(bestCard: legalPlays[0]);
  }

  final pnum = cardReq.currentPlayerIndex();
  final playEquities = List.generate(legalPlays.length, (_) => 0.0);
  final distReq = makeCardDistributionRequest(cardReq);
  int numRounds = 0;
  int numRollouts = 0;
  int numRolloutCardsPlayed = 0;
  final cardsPerRollout = 52 -
      (4 * cardReq.previousTricks.length + cardReq.currentTrick.cards.length);
  for (int i = 0; i < mcParams.maxRounds; i++) {
    final hypoRound = possibleRound(cardReq, distReq, rng);
    if (hypoRound == null) {
      print("MC failed to generate round, falling back to random");
      final bestCard = chooseCardRandom(cardReq, rng);
      final normalizedEquities =
          playEquities.map((e) => e / numRollouts * legalPlays.length).toList();
      return MonteCarloResult.rolloutFailed(
        bestCard: bestCard,
        cardEquities: Map.fromIterables(legalPlays, normalizedEquities),
        numRounds: numRounds,
        numRollouts: numRollouts,
        numRolloutCardsPlayed: numRolloutCardsPlayed,
        elapsedMillis: timeFn() - startTime,
      );
    }
    for (int ci = 0; ci < legalPlays.length; ci++) {
      for (int r = 0; r < mcParams.rolloutsPerRound; r++) {
        final rolloutRound = hypoRound.copy();
        rolloutRound.playCard(legalPlays[ci]);
        doRollout(rolloutRound, rolloutChooseFn, rng);
        final score = rolloutRound.contractScoreForPlayer(pnum);
        playEquities[ci] += score;
        numRollouts += 1;
        numRolloutCardsPlayed += cardsPerRollout;
      }
    }
    numRounds += 1;
    if (mcParams.maxTimeMillis != null &&
        timeFn() - startTime >= mcParams.maxTimeMillis!) {
      break;
    }
  }
  final normalizedEquities =
      playEquities.map((e) => e / numRollouts * legalPlays.length).toList();
  return MonteCarloResult.rolloutSuccess(
    cardEquities: Map.fromIterables(legalPlays, normalizedEquities),
    numRounds: numRounds,
    numRollouts: numRollouts,
    numRolloutCardsPlayed: numRolloutCardsPlayed,
    elapsedMillis: timeFn() - startTime,
  );
}

void doRollout(BridgeRound round, ChooseCardFn chooseFn, Random rng) {
  while (!round.isOver()) {
    final req = CardToPlayRequest.fromRoundWithSharedReferences(round);
    final cardToPlay = chooseFn(req, rng);
    round.playCard(cardToPlay);
  }
}
