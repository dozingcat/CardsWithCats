import "dart:math";

import "package:cards_with_cats/cards/card.dart";

import "../cards/rollout.dart";
import "../cards/trick.dart";
import "bridge.dart";
import "bridge.dart" as bridge;
import "dd_solver.dart";
import "heuristic_play.dart";
import "sayc/sayc_bidding.dart" show BidMeaning, HandAnalysis, explainSaycAuction;

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
  // Cards that are interchangeable for trick-taking (e.g. the queen and
  // jack of a suit when holding both) need only one representative; play
  // the cheapest. This shrinks the branching factor and stops equity noise
  // from picking a wastefully high equal.
  final groups = groupsOfEffectivelyIdenticalCards(
      req.legalPlays(), req.previousTricks);
  return [for (final g in groups) g.last];
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
    CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng,
    {BiddingDealFilter? filter}) {
  List<List<PlayingCard>>? dist;
  if (filter == null) {
    dist = possibleCardDistribution(distReq, rng);
  } else {
    // Rejection-sample against the constraints the auction placed on the
    // hidden hands; if nothing qualifies, fall back to the sample that
    // satisfied the most seats.
    List<List<PlayingCard>>? best;
    int bestSatisfied = -1;
    for (int attempt = 0; attempt < 100; attempt++) {
      final candidate = possibleCardDistribution(distReq, rng);
      if (candidate == null) continue;
      final satisfied = filter.numSatisfiedSeats(candidate);
      if (satisfied > bestSatisfied) {
        bestSatisfied = satisfied;
        best = candidate;
      }
      if (satisfied == filter.numConstrainedSeats) break;
    }
    dist = best;
  }
  if (dist == null) {
    return null;
  }
  final hands = dist;
  final resultPlayers =
      List.generate(hands.length, (pnum) => BridgePlayer(hands[pnum]));
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

/// Constraints that the auction places on the hidden hands, used to make
/// Monte Carlo deal samples consistent with the bidding. Each hidden seat's
/// original 13 cards (current sample plus the cards it already played) must
/// satisfy the seat's accumulated bid meanings.
class BiddingDealFilter {
  // Absolute seat -> accumulated constraints; null for seats whose cards
  // are already known to the player (self, visible dummy/declarer) or that
  // showed nothing.
  final List<BidMeaning?> _meaningForSeat;
  final List<List<PlayingCard>> _playedBySeat;

  BiddingDealFilter._(this._meaningForSeat, this._playedBySeat);

  int get numConstrainedSeats =>
      _meaningForSeat.where((m) => m != null).length;

  /// Builds the filter, or null if the auction can't be interpreted or
  /// constrains nothing hidden.
  static BiddingDealFilter? fromRequest(CardToPlayRequest req) {
    if (req.bidHistory.isEmpty) return null;
    final dealer = req.bidHistory[0].player;
    final actions = [for (final b in req.bidHistory) b.action];
    Map<int, BidMeaning> bySeatFromDealer;
    try {
      bySeatFromDealer = explainSaycAuction(actions).players;
    } catch (e) {
      return null;
    }
    final knownSeats = <int>{req.currentPlayerIndex()};
    // On the opening lead the dummy hasn't been revealed, and the deal
    // sampler doesn't fix its cards, so its auction constraints must
    // still apply.
    final dummyRevealed =
        req.previousTricks.isNotEmpty || req.currentTrick.cards.isNotEmpty;
    if (req.dummyHand != null && dummyRevealed) {
      knownSeats.add(req.contract.dummy);
    }
    if (req.declarerHand != null) knownSeats.add(req.contract.declarer);

    final meanings = List<BidMeaning?>.filled(numPlayers, null);
    for (int seat = 0; seat < numPlayers; seat++) {
      if (knownSeats.contains(seat)) continue;
      final m = bySeatFromDealer[(seat - dealer + numPlayers) % numPlayers];
      if (m == null) continue;
      meanings[seat] = m;
    }
    if (meanings.every((m) => m == null)) return null;

    final played = List.generate(numPlayers, (_) => <PlayingCard>[]);
    void record(List<PlayingCard> cards, int leader) {
      for (int i = 0; i < cards.length; i++) {
        played[(leader + i) % numPlayers].add(cards[i]);
      }
    }

    for (final t in req.previousTricks) {
      record(t.cards, t.leader);
    }
    record(req.currentTrick.cards, req.currentTrick.leader);
    return BiddingDealFilter._(meanings, played);
  }

  int numSatisfiedSeats(List<List<PlayingCard>> dist) {
    int satisfied = 0;
    for (int seat = 0; seat < numPlayers; seat++) {
      final meaning = _meaningForSeat[seat];
      if (meaning == null) continue;
      final original = [...dist[seat], ..._playedBySeat[seat]];
      if (meaning.satisfiedBy(HandAnalysis(original))) satisfied++;
    }
    return satisfied;
  }
}

MonteCarloResult chooseCardMonteCarlo(CardToPlayRequest cardReq,
    MonteCarloParams mcParams, ChooseCardFn rolloutChooseFn, Random rng,
    {int Function()? timeFn, bool useBiddingInference = false}) {
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
  final filter =
      useBiddingInference ? BiddingDealFilter.fromRequest(cardReq) : null;
  int numRounds = 0;
  int numRollouts = 0;
  int numRolloutCardsPlayed = 0;
  final cardsPerRollout = 52 -
      (4 * cardReq.previousTricks.length + cardReq.currentTrick.cards.length);
  for (int i = 0; i < mcParams.maxRounds; i++) {
    final hypoRound = possibleRound(cardReq, distReq, rng, filter: filter);
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

/// Monte Carlo with exact endgame evaluation: samples deals consistent with
/// the auction, and evaluates each candidate play on each sampled deal by
/// playing forward with a cheap policy until at most [ddTricksLimit] tricks
/// remain, then solving the rest double-dummy. This rewards plays whose
/// payoff needs *correct* continuation (finesses, establishment, endplays),
/// which policy rollouts systematically miss.
MonteCarloResult chooseCardMonteCarloDD(
  CardToPlayRequest cardReq,
  Random rng, {
  int maxRounds = 20,
  int? maxTimeMillis,
  bool useBiddingInference = true,
  int ddTricksLimit = 8,
  ChooseCardFn? prerollFn,
  double equityMargin = 5,
  double defenderEquityMargin = 18,
  bool tryFullDepthSolve = true,
  int Function()? timeFn,
}) {
  timeFn ??= () => DateTime.now().millisecondsSinceEpoch;
  final startTime = timeFn();
  final legalPlays = cardsToConsiderPlaying(cardReq, rng);
  assert(legalPlays.isNotEmpty);
  if (legalPlays.length == 1) {
    return MonteCarloResult.rolloutNotNeeded(bestCard: legalPlays[0]);
  }
  prerollFn ??= chooseCardHeuristic;

  final pnum = cardReq.currentPlayerIndex();
  final contract = cardReq.contract;
  final declarerSideIsNS = contract.declarer % 2 == 0;
  final playerIsDeclarerSide = pnum % 2 == contract.declarer % 2;
  final playEquities = List.generate(legalPlays.length, (_) => 0.0);
  final distReq = makeCardDistributionRequest(cardReq);
  final filter =
      useBiddingInference ? BiddingDealFilter.fromRequest(cardReq) : null;

  // A pathological solve gives up after this many search nodes rather
  // than blowing the latency budget; the whole sampled deal is then
  // discarded (a per-candidate skip would bias the equities).
  const solveNodeLimit = 3000000;
  // Full-depth solve attempts get a smaller budget: an abort here is
  // routine (it just switches this call to preroll mode) and must stay
  // around ~100ms. Solves that fit are typically 5-50ms.
  const fullSolveNodeLimit = 1500000;

  int numRounds = 0;
  final roundEquities = List.generate(legalPlays.length, (_) => 0.0);
  // Per-committed-round equities, for the paired significance test in the
  // guide-preference step below.
  final perRoundEquities = <List<double>>[];
  // Prerolling with the heuristic policy before solving injects a little
  // follow-up competence bias back into the evaluation: a candidate whose
  // continuation the heuristic misplays gets systematically undervalued,
  // occasionally inverting decisions. So first try to solve candidate
  // positions to full depth (cheap in trump-heavy or cash-out positions
  // thanks to the solver's quick-trick bounds); only if a full solve
  // aborts on its node budget fall back to preroll-then-solve for the
  // rest of this call. A deal is always evaluated one way for all
  // candidates: on a mid-deal abort the deal is discarded and resampled.
  bool tryFullSolve = tryFullDepthSolve;
  outer:
  for (int i = 0; i < maxRounds; i++) {
    final hypoRound = possibleRound(cardReq, distReq, rng, filter: filter);
    if (hypoRound == null) {
      break;
    }
    // Solves of the same sampled deal share position bounds.
    final sharedTable = <int, int>{};
    for (int ci = 0; ci < legalPlays.length; ci++) {
      // Deadline check between candidates; an unfinished deal's partial
      // sums in roundEquities are simply never committed.
      if (numRounds > 0 &&
          maxTimeMillis != null &&
          timeFn() - startTime >= maxTimeMillis) {
        break outer;
      }
      final round = hypoRound.copy();
      round.playCard(legalPlays[ci]);
      if (!tryFullSolve) {
        while (!round.isOver() &&
            13 - round.previousTricks.length > ddTricksLimit) {
          final req = CardToPlayRequest.fromRoundWithSharedReferences(round);
          round.playCard(prerollFn(req, rng));
        }
      }
      int declarerTricks;
      if (round.isOver()) {
        declarerTricks = round.numTricksWonByDeclarer();
      } else {
        final hands = [for (final p in round.players) p.hand];
        final solver = DDSolver.fromHands(
            hands, contract.bid.trump, round.currentTrick.leader,
            sharedTable: sharedTable);
        for (final c in round.currentTrick.cards) {
          solver.addTrickCard(c);
        }
        final nsFuture = solver.solveWithNodeLimit(
            tryFullSolve ? fullSolveNodeLimit : solveNodeLimit);
        if (nsFuture == null) {
          if (tryFullSolve) {
            tryFullSolve = false;
          }
          continue outer; // discard this deal and resample
        }
        final future = 13 - round.previousTricks.length;
        declarerTricks = round.numTricksWonByDeclarer() +
            (declarerSideIsNS ? nsFuture : future - nsFuture);
      }
      final declarerScore = contract.scoreForTricksTaken(declarerTricks);
      roundEquities[ci] =
          (playerIsDeclarerSide ? declarerScore : -declarerScore).toDouble();
    }
    for (int ci = 0; ci < legalPlays.length; ci++) {
      playEquities[ci] += roundEquities[ci];
    }
    perRoundEquities.add(List.of(roundEquities));
    numRounds += 1;
    if (maxTimeMillis != null && timeFn() - startTime >= maxTimeMillis) {
      break;
    }
  }
  if (numRounds == 0) {
    // Nothing completed within budget: fall back to the heuristic policy
    // rather than a random card.
    return MonteCarloResult.rolloutFailed(
      bestCard: prerollFn(cardReq, rng),
      cardEquities: const {},
      numRounds: 0,
      numRollouts: 0,
      numRolloutCardsPlayed: 0,
      elapsedMillis: timeFn() - startTime,
    );
  }
  // Best equity; break exact ties toward the lower card.
  int best = 0;
  for (int ci = 1; ci < legalPlays.length; ci++) {
    final d = playEquities[ci] - playEquities[best];
    if (d > 1e-9 ||
        (d.abs() <= 1e-9 &&
            legalPlays[ci].rank.index < legalPlays[best].rank.index)) {
      best = ci;
    }
  }
  // Honor-waste guard. Double-dummy evaluation is blind to the main cost
  // of leading an unsupported high honor: every sampled declarer already
  // knows where it is, so the lead is rarely punished and often shows a
  // small spurious edge that a real (non-clairvoyant) declarer wouldn't
  // realize. When the equity-best play is a *lead* of a K or Q with no
  // effective touching honor and a lower card available, play the
  // best-scoring candidate that doesn't match that pattern instead,
  // unless the honor lead is decisively better: by more than the margin
  // AND by a statistically significant paired difference across sampled
  // deals (genuine coups — cashing before a ruff, pins, unblocks — clear
  // that bar). All other decisions remain pure equity: deferring to the
  // heuristic policy instead measured -0.86 IMPs/board applied broadly
  // and -0.32 within this guard; falling back along the measured-equity
  // ranking measured +-0. See PLAY_AI.md.
  final margin = playerIsDeclarerSide ? equityMargin : defenderEquityMargin;
  if (margin > 0 && cardReq.currentTrick.cards.isEmpty) {
    // Matches the artifact pattern: a lead of a K or Q with no effective
    // touching honor, no higher card, and a lower card available in the
    // suit.
    bool isArtifactLead(PlayingCard c) {
      if (c.rank != Rank.king && c.rank != Rank.queen) return false;
      final suitCards = sortedCardsInSuit(cardReq.hand, c.suit);
      if (suitCards.any((x) => x.rank.index > c.rank.index)) return false;
      if (!suitCards.any((x) => x.rank.index < c.rank.index)) return false;
      final groups =
          groupsOfEffectivelyIdenticalCards(suitCards, cardReq.previousTricks);
      return groups.firstWhere((g) => g.contains(c)).length == 1;
    }

    if (isArtifactLead(legalPlays[best])) {
      // Fall back to the best-scoring candidate that is NOT itself an
      // artifact lead; the honor keeps the lead only if it beats that
      // candidate decisively.
      int fallback = -1;
      for (int ci = 0; ci < legalPlays.length; ci++) {
        if (ci == best || isArtifactLead(legalPlays[ci])) continue;
        if (fallback < 0 ||
            playEquities[ci] - playEquities[fallback] > 1e-9 ||
            ((playEquities[ci] - playEquities[fallback]).abs() <= 1e-9 &&
                legalPlays[ci].rank.index <
                    legalPlays[fallback].rank.index)) {
          fallback = ci;
        }
      }
      if (fallback >= 0) {
        final n = perRoundEquities.length;
        final meanDiff =
            (playEquities[best] - playEquities[fallback]) / numRounds;
        bool decisive = meanDiff > margin;
        if (decisive && n >= 2) {
          double sumSq = 0;
          for (final round in perRoundEquities) {
            final d = round[best] - round[fallback] - meanDiff;
            sumSq += d * d;
          }
          final stderr = sqrt(sumSq / (n - 1) / n);
          decisive = meanDiff > 2 * stderr;
        }
        if (!decisive) {
          best = fallback;
        }
      }
    }
  }
  return MonteCarloResult(
    resultType: MonteCarloResultType.rollout_success,
    bestCard: legalPlays[best],
    cardEquities: Map.fromIterables(
        legalPlays, playEquities.map((e) => e / numRounds)),
    numRounds: numRounds,
    numRollouts: numRounds * legalPlays.length,
    numRolloutCardsPlayed: 0,
    elapsedMillis: timeFn() - startTime,
  );
}
