import "dart:math";

import "package:cards_with_cats/cards/card.dart";

import "../cards/rollout.dart";
import "../cards/trick.dart";
import "bridge.dart";
import "bridge.dart" as bridge;

int pointsForCard(PlayingCard card) {
  switch (card.rank) {
    case Rank.ace: return 4;
    case Rank.king: return 3;
    case Rank.queen: return 2;
    case Rank.jack: return 1;
    default: return 0;
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

class Range {
  int? min;
  int? max;

  Range({this.min, this.max});
}

class HandEstimate {
  Range highCardPoints = Range();
  Map<Suit, Range> suitLengths = {
    Suit.spades: Range(),
    Suit.hearts: Range(),
    Suit.diamonds: Range(),
    Suit.clubs: Range(),
  };
}

class CardToPlayRequest {
  final List<PlayingCard> hand;
  final List<PlayingCard> dummyHand;
  final List<Trick> previousTricks;
  final TrickInProgress currentTrick;
  final List<PlayerBid> bidHistory;
  final Vulnerability vulnerability;
  final Contract contract;

  CardToPlayRequest({
    required this.hand,
    required this.dummyHand,
    required this.previousTricks,
    required this.currentTrick,
    required this.bidHistory,
    required this.vulnerability,
  }) : contract = contractFromBids(
      bids: bidHistory,
      vulnerability: vulnerability);

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % 4;
  }

  List<PlayingCard> legalPlays() {
    return bridge.legalPlays(hand, currentTrick);
  }

  static CardToPlayRequest fromRoundWithSharedReferences(final BridgeRound round) => CardToPlayRequest(
    hand: round.currentPlayer().hand,
    dummyHand: round.players[round.contract.dummy].hand,
    previousTricks: round.previousTricks,
    currentTrick: round.currentTrick,
    bidHistory: round.bidHistory,
    vulnerability: round.vulnerability,
  );
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

CardDistributionRequest makeCardDistributionRequest(final CardToPlayRequest req) {
  // If this is the first lead, the dummy isn't revealed.
  if (req.previousTricks.isEmpty && req.currentTrick.cards.isEmpty) {
    final constraints = List.generate(
        numPlayers, (pnum) => CardDistributionConstraint(
        numCards: req.hand.length,
        fixedCards: pnum == req.currentPlayerIndex() ? req.hand : []));
    return CardDistributionRequest(
        cardsToAssign: standardDeckCards(),
        constraints: constraints);
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

  constraints[req.contract.dummy].fixedCards = req.dummyHand;
  final Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  cardsToAssign.removeAll(seenCards);
  return CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
}

BridgeRound? possibleRound(CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng) {
  final dist = possibleCardDistribution(distReq, rng);
  if (dist == null) {
    return null;
  }
  final resultPlayers = List.generate(dist.length, (pnum) => BridgePlayer(dist[pnum]));
  return BridgeRound()
    ..status = BridgeRoundStatus.playing
    ..players = resultPlayers
    ..currentTrick = cardReq.currentTrick.copy()
    ..previousTricks = Trick.copyAll(cardReq.previousTricks)
    ..contract = cardReq.contract
    ..vulnerability = cardReq.vulnerability
  ;
}

MonteCarloResult chooseCardMonteCarlo(
    CardToPlayRequest cardReq, MonteCarloParams mcParams, ChooseCardFn rolloutChooseFn, Random rng,
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
  final cardsPerRollout =
      52 - (4 * cardReq.previousTricks.length + cardReq.currentTrick.cards.length);
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
    if (mcParams.maxTimeMillis != null && timeFn() - startTime >= mcParams.maxTimeMillis!) {
      break;
    }
  }
  final normalizedEquities = playEquities.map((e) => e / numRollouts * legalPlays.length).toList();
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
