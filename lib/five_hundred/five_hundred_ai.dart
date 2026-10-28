import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';

import 'five_hundred.dart';

// 500 AI. Functions that choose an action for a player in a round only look
// at the information that player can see: their own hand, the bids, the
// cards played so far, and the discards if they're the declarer. Rollouts
// call them with hypothetical rounds where the hidden cards have been dealt
// randomly, consistent with what's known.

// The card to play, and the suit to choose if it's the joker led in no trump.
typedef CardChoice = (PlayingCard card, Suit? jokerLeadSuit);

typedef ChooseCardFn = CardChoice Function(FiveHundredRound round, Random rng);

// ---------------------------------------------------------------------------
// Card tracking

List<PlayingCard> playedCards(FiveHundredRound round) => [
  for (final t in round.previousTricks) ...t.cards,
  ...round.currentTrick.cards,
];

// Cards whose location is unknown to `player`: not in their hand, not played,
// and not discarded if they're the declarer.
Set<PlayingCard> unseenCards(FiveHundredRound round, int player) {
  final unseen = fiveHundredDeckCards().toSet();
  unseen.removeAll(round.players[player].hand);
  unseen.removeAll(playedCards(round));
  if (round.contract?.declarer == player) {
    unseen.removeAll(round.discards);
  }
  return unseen;
}

// Suits that each player is known to be out of, based on failing to follow
// suit. Since the left bower and joker belong to the trump suit, a player who
// didn't follow a trump lead doesn't have them either. In no trump, playing
// the joker on another suit also shows a void, since it can only be played
// when the player can't follow suit.
List<Set<Suit>> knownVoids(FiveHundredRound round) {
  final trump = round.trump;
  final voids = List.generate(numPlayers, (_) => <Suit>{});
  void processTrick(int trickIndex, int leader, List<PlayingCard> cards) {
    if (cards.isEmpty) return;
    final leadSuit = (cards[0] is JokerCard && trump == null)
        ? round.jokerLeadSuits[trickIndex]
        : effectiveSuit(cards[0], trump);
    if (leadSuit == null) return;
    for (int i = 1; i < cards.length; i++) {
      if (effectiveSuit(cards[i], trump) != leadSuit) {
        voids[(leader + i) % numPlayers].add(leadSuit);
      }
    }
  }
  for (int i = 0; i < round.previousTricks.length; i++) {
    final t = round.previousTricks[i];
    processTrick(i, t.leader, t.cards);
  }
  processTrick(round.previousTricks.length, round.currentTrick.leader, round.currentTrick.cards);
  return voids;
}

// True if no unseen card of the same effective suit can beat `card`. In no
// trump the joker is ignored, since it can only beat cards of suits its
// holder is void in.
bool isMasterCard(PlayingCard card, Suit? trump, Iterable<PlayingCard> unseen) {
  final suit = effectiveSuit(card, trump);
  final power = cardRankValue(card, trump);
  return !unseen.any((c) => effectiveSuit(c, trump) == suit && cardRankValue(c, trump) > power);
}

int _winnerIndex(List<PlayingCard> cards, Suit? trump) => fiveHundredTrickWinnerIndex(cards, trump: trump);

bool _wouldWin(List<PlayingCard> trickCards, PlayingCard card, Suit? trump) =>
    _winnerIndex([...trickCards, card], trump) == trickCards.length;

// ---------------------------------------------------------------------------
// Auction inference. Bids are natural, so a player who bid a suit is assumed
// to hold several trumps in it, and a no trump bidder to hold aces. The
// minimums are roughly the 10th percentile of what the AI's own bids hold.

bool isHandConsistentWithBid(List<PlayingCard> hand, FiveHundredBid bid) {
  final trump = bid.trump;
  if (trump == null) {
    return hand.where((c) => c is JokerCard || (c is SuitedCard && c.rank == .ace)).length >= 2;
  }
  return hand.where((c) => effectiveSuit(c, trump) == trump).length >= min(bid.tricks - 3, 5);
}

bool isHandConsistentWithBids(List<PlayingCard> hand, int player, List<PlayerBid> bids) {
  return bids.every((b) => b.player != player || b.isPass || isHandConsistentWithBid(hand, b.bid!));
}

// The cards a player was dealt (after the kitty and discards, for the
// declarer): their current hand plus what they've played.
List<PlayingCard> _originalHand(FiveHundredRound round, int player) {
  final cards = List.of(round.players[player].hand);
  for (final t in [...round.previousTricks.map((t) => (t.leader, t.cards)), (round.currentTrick.leader, round.currentTrick.cards)]) {
    final (leader, trickCards) = t;
    for (int i = 0; i < trickCards.length; i++) {
      if ((leader + i) % numPlayers == player) {
        cards.add(trickCards[i]);
      }
    }
  }
  return cards;
}

// ---------------------------------------------------------------------------
// Heuristic card play, used directly and as the rollout policy for Monte Carlo.

class HeuristicPlayParams {
  // Whether the declaring team leads trump while opponents may have trumps.
  bool declarerPullsTrump;
  // When not last to play, only win with cards that can't be beaten.
  bool onlyWinWithSafeCards;
  // With `onlyWinWithSafeCards`, ruff (trump a side suit lead) when an
  // opponent is winning, even if it could be overruffed.
  bool ruffWhenPossible;
  // When second to play, only win with cards that can't be beaten (partner
  // plays later).
  bool secondHandLow;

  HeuristicPlayParams({
    this.declarerPullsTrump = true,
    this.onlyWinWithSafeCards = false,
    this.ruffWhenPossible = true,
    this.secondHandLow = false,
  });
}

final defaultHeuristicParams = HeuristicPlayParams();

// For the joker led in no trump: the suit with the most unseen cards, so that
// the other players are most likely to have to follow it.
Suit _jokerLeadSuitHeuristic(FiveHundredRound round, int player) {
  final unseen = unseenCards(round, player);
  int count(Suit s) => unseen.where((c) => c is SuitedCard && c.suit == s).length;
  return Suit.values.reduce((a, b) => count(a) >= count(b) ? a : b);
}

CardChoice chooseCardHeuristic(FiveHundredRound round, Random rng, [HeuristicPlayParams? playParams]) {
  final params = playParams ?? defaultHeuristicParams;
  final legal = round.legalPlaysForCurrentPlayer();
  final player = round.currentPlayerIndex();
  CardChoice choice(PlayingCard c) =>
      (c, round.needsJokerLeadSuit(c) ? _jokerLeadSuitHeuristic(round, player) : null);
  if (legal.length == 1) {
    return choice(legal[0]);
  }
  final team = player % numTeams;
  final contract = round.contract!;
  final trump = contract.trump;
  final isDeclaringTeam = contract.declarer % numTeams == team;
  final unseen = unseenCards(round, player);
  final trick = round.currentTrick.cards;

  bool isTrump(PlayingCard c) => trump != null && effectiveSuit(c, trump) == trump;
  int power(PlayingCard c) => cardRankValue(c, trump);
  // Cards to give up when we don't want to win: not trump, low rank.
  PlayingCard lowest(Iterable<PlayingCard> cards) {
    int cost(PlayingCard c) => (c is JokerCard ? 10000 : 0) + (isTrump(c) ? 1000 : 0) + power(c);
    return cards.reduce((a, b) => cost(a) <= cost(b) ? a : b);
  }
  // Cheapest card that wins: non-trumps before trumps, then lowest rank.
  PlayingCard cheapest(Iterable<PlayingCard> cards) => lowest(cards);

  if (trick.isEmpty) {
    final trumps = legal.where(isTrump).toList();
    final unseenTrumps = unseen.where(isTrump);
    if (params.declarerPullsTrump && isDeclaringTeam && trumps.isNotEmpty && unseenTrumps.isNotEmpty) {
      // Lead a master trump if we have one, otherwise a low trump to draw out
      // higher ones.
      final masters = trumps.where((c) => isMasterCard(c, trump, unseen)).toList();
      if (masters.isNotEmpty) {
        return choice(masters.reduce((a, b) => power(a) >= power(b) ? a : b));
      }
      if (trumps.length >= 2) {
        return choice(lowest(trumps));
      }
    }
    // Side suit masters. In no trump the joker is saved for capturing tricks.
    final sideMasters = legal.where((c) => c is! JokerCard && !isTrump(c) && isMasterCard(c, trump, unseen)).toList();
    if (sideMasters.isNotEmpty) {
      return choice(sideMasters.reduce((a, b) => power(a) >= power(b) ? a : b));
    }
    final nonTrump = legal.where((c) => c is! JokerCard && !isTrump(c));
    return choice(lowest(nonTrump.isNotEmpty ? nonTrump : legal));
  }

  final leader = round.currentTrick.leader;
  final winnerPos = _winnerIndex(trick, trump);
  final partnerWinning = (leader + winnerPos) % numPlayers % numTeams == team;
  final isLast = trick.length == numPlayers - 1;
  // A card in the trick is safe if no unseen card would beat it. This ignores
  // which players are still to play.
  bool isSafe(List<PlayingCard> cards) {
    final w = cards[_winnerIndex(cards, trump)];
    return w is JokerCard || !unseen.any((c) => _wouldWin(cards, c, trump));
  }

  if (partnerWinning) {
    return choice(lowest(legal));
  }
  final winners = legal.where((c) => _wouldWin(trick, c, trump)).toList();
  if (winners.isEmpty) {
    return choice(lowest(legal));
  }
  if (isLast) {
    return choice(cheapest(winners));
  }
  final safeWinners = winners.where((c) => isSafe([...trick, c])).toList();
  if (safeWinners.isNotEmpty) {
    return choice(cheapest(safeWinners));
  }
  if (params.secondHandLow && trick.length == 1) {
    return choice(lowest(legal));
  }
  if (!params.onlyWinWithSafeCards) {
    return choice(cheapest(winners));
  }
  // Ruff a side suit lead even if it could be overruffed.
  final ledTrump = isTrump(trick[0]);
  final ruffs = winners.where(isTrump).toList();
  if (params.ruffWhenPossible && !ledTrump && ruffs.isNotEmpty) {
    return choice(cheapest(ruffs));
  }
  return choice(lowest(legal));
}

CardChoice chooseCardRandom(FiveHundredRound round, Random rng) {
  final plays = round.legalPlaysForCurrentPlayer();
  final card = plays[rng.nextInt(plays.length)];
  final suit = round.needsJokerLeadSuit(card) ? Suit.values[rng.nextInt(Suit.values.length)] : null;
  return (card, suit);
}

void playOutRound(FiveHundredRound round, ChooseCardFn chooseFn, Random rng) {
  while (!round.isOver()) {
    final (card, suit) = chooseFn(round, rng);
    round.playCard(card, jokerLeadSuit: suit);
  }
}

// Round score differential from the point of view of `team`.
int teamScoreDifferential(FiveHundredRound round, int team) {
  final scores = round.contractScoresForTeams();
  return scores[team] - scores[1 - team];
}

// ---------------------------------------------------------------------------
// Monte Carlo card play

// Returns a copy of `round` where the cards hidden from `player` (other hands
// and the discards unless they're the declarer) are randomly redistributed,
// consistent with the number of cards each player has and the suits they're
// known to be out of.
FiveHundredRound? possibleRoundForPlayer(FiveHundredRound round, int player, Random rng, {int auctionAttempts = 0}) {
  final trump = round.trump;
  final isDeclarer = round.contract!.declarer == player;
  final voids = knownVoids(round);
  final unseen = unseenCards(round, player).toList();
  final constraints = <CardDistributionConstraint<PlayingCard>>[];
  final constraintPlayers = <int>[];
  for (int p = 0; p < numPlayers; p++) {
    if (p != player) {
      constraints.add(CardDistributionConstraint(
          numCards: round.players[p].hand.length, voidedSuits: voids[p].toList()));
      constraintPlayers.add(p);
    }
  }
  if (!isDeclarer) {
    constraints.add(CardDistributionConstraint(numCards: round.discards.length));
  }
  final request = CardDistributionRequest(
    cardsToAssign: unseen,
    constraints: constraints,
    suitForCard: (c) => effectiveSuit(c, trump),
  );
  // Tries to find a deal consistent with the bids. The declarer's bid isn't
  // checked, since their hand changed when they took the kitty.
  FiveHundredRound? result;
  for (int attempt = 0; attempt <= auctionAttempts; attempt++) {
    final dist = possibleCardDistribution(request, rng);
    if (dist == null) {
      return result;
    }
    result = round.copy();
    for (int i = 0; i < constraintPlayers.length; i++) {
      result.players[constraintPlayers[i]].hand = dist[i];
    }
    if (!isDeclarer) {
      result.discards = dist.last;
    }
    final isConsistent = constraintPlayers.every((p) =>
        p == round.contract!.declarer || isHandConsistentWithBids(_originalHand(result!, p), p, round.bidHistory));
    if (isConsistent) {
      break;
    }
  }
  return result;
}

class FiveHundredMonteCarloParams {
  int numDeals;
  int? maxTimeMillis;
  ChooseCardFn rolloutChooseFn;
  // Attempts to deal hidden cards consistently with the bids (0 to ignore the
  // auction).
  int auctionAttempts;

  FiveHundredMonteCarloParams({
    this.numDeals = 30,
    this.maxTimeMillis,
    this.rolloutChooseFn = chooseCardHeuristic,
    this.auctionAttempts = 0,
  });
}

// The plays to consider: each legal card, and for the joker led in no trump,
// each suit it could be led as.
List<CardChoice> candidatePlays(FiveHundredRound round) => [
  for (final c in round.legalPlaysForCurrentPlayer())
    if (round.needsJokerLeadSuit(c))
      for (final s in Suit.values) (c, s)
    else
      (c, null),
];

CardChoice chooseCardMonteCarlo(FiveHundredRound round, FiveHundredMonteCarloParams params, Random rng) {
  final candidates = candidatePlays(round);
  if (candidates.length == 1) {
    return candidates[0];
  }
  final startTime = DateTime.now().millisecondsSinceEpoch;
  final player = round.currentPlayerIndex();
  final team = player % numTeams;
  final totals = List.filled(candidates.length, 0);
  for (int d = 0; d < params.numDeals; d++) {
    final hypo = possibleRoundForPlayer(round, player, rng, auctionAttempts: params.auctionAttempts);
    if (hypo == null) {
      break;
    }
    for (int ci = 0; ci < candidates.length; ci++) {
      final rolloutRound = hypo.copy();
      rolloutRound.playCard(candidates[ci].$1, jokerLeadSuit: candidates[ci].$2);
      playOutRound(rolloutRound, params.rolloutChooseFn, rng);
      totals[ci] += teamScoreDifferential(rolloutRound, team);
    }
    if (params.maxTimeMillis != null && DateTime.now().millisecondsSinceEpoch - startTime >= params.maxTimeMillis!) {
      break;
    }
  }
  int best = 0;
  for (int i = 1; i < candidates.length; i++) {
    if (totals[i] > totals[best]) {
      best = i;
    }
  }
  return candidates[best];
}

// ---------------------------------------------------------------------------
// Discards

class DiscardParams {
  // Prefer discarding short side suits to create voids.
  bool createVoids;
  // Keep a king when it has at least this many cards in its suit to guard it
  // (in no trump, or any side suit).
  int guardedKingMinLength;

  DiscardParams({
    this.createVoids = true,
    this.guardedKingMinLength = 2,
  });
}

final defaultDiscardParams = DiscardParams();

// Keeps the joker, trumps, and side aces (and guarded kings), and tries to
// empty short side suits so that the declarer can trump them.
Set<PlayingCard> chooseDiscardsHeuristic(List<PlayingCard> cards, Suit? trump, [DiscardParams? discardParams]) {
  final params = discardParams ?? defaultDiscardParams;
  bool isTrump(PlayingCard c) => trump != null && effectiveSuit(c, trump) == trump;
  final sideSuitCounts = suitCounts(cards.whereType<SuitedCard>().where((c) => !isTrump(c)));
  int keepPriority(PlayingCard c) {
    if (c is JokerCard) return 100000;
    if (isTrump(c)) return 10000 + cardRankValue(c, trump);
    final sc = c as SuitedCard;
    final length = sideSuitCounts[sc.suit]!;
    int priority = sc.rank.index;
    if (sc.rank == .ace) priority += 5000;
    if (sc.rank == .king && length >= params.guardedKingMinLength) priority += 2000;
    // Discard from short suits first: in a trump contract this creates voids
    // to trump, and in no trump long suits can be established.
    if (trump == null || params.createVoids) priority += length * 100;
    return priority;
  }
  final sorted = List.of(cards)..sort((a, b) => keepPriority(a) - keepPriority(b));
  return sorted.take(numKittyCards).toSet();
}

Set<PlayingCard> chooseDiscards(FiveHundredRound round, Random rng, [DiscardParams? params]) {
  return chooseDiscardsHeuristic(round.declarerAvailableCards(), round.winningBid().bid!.trump, params);
}

// ---------------------------------------------------------------------------
// Bidding

// Simulates the player with `hand` winning the bid with `trump` (null for no
// trump): deals the other cards randomly, takes the kitty, discards, and plays
// the hand out with the heuristic policy. Returns the number of tricks the
// declaring team took in each simulated deal.
List<int> simulateDeclarerTricks({
  required List<PlayingCard> hand,
  required int player,
  required Suit? trump,
  required FiveHundredRuleSet rules,
  required int numDeals,
  required Random rng,
  ChooseCardFn playFn = chooseCardHeuristic,
  List<PlayerBid> bidHistory = const [],
  int auctionAttempts = 0,
}) {
  final others = fiveHundredDeckCards().where((c) => !hand.contains(c)).toList();
  final results = <int>[];
  for (int d = 0; d < numDeals; d++) {
    // Deal the other hands, trying to make them consistent with the bids.
    late List<FiveHundredPlayer> players;
    late int offset;
    for (int attempt = 0; attempt <= auctionAttempts; attempt++) {
      others.shuffle(rng);
      players = <FiveHundredPlayer>[];
      offset = 0;
      for (int p = 0; p < numPlayers; p++) {
        if (p == player) {
          players.add(FiveHundredPlayer(hand));
        } else {
          players.add(FiveHundredPlayer(others.sublist(offset, offset + hand.length)));
          offset += hand.length;
        }
      }
      if (List.generate(numPlayers, (p) => p == player || isHandConsistentWithBids(players[p].hand, p, bidHistory))
          .every((ok) => ok)) {
        break;
      }
    }
    final round = FiveHundredRound()
      ..rules = rules
      ..initialScores = [0, 0]
      ..players = players
      ..dealer = (player + numPlayers - 1) % numPlayers
      ..initialKitty = others.sublist(offset, offset + numKittyCards)
      ..bidHistory = [PlayerBid(player, FiveHundredBid(minimumBidTricks, trump))]
      ..status = FiveHundredRoundStatus.declarerDiscarding
      ..currentTrick = TrickInProgress(player);
    round.discard(chooseDiscards(round, rng));
    playOutRound(round, playFn, rng);
    results.add(round.tricksTakenByTeam()[player % numTeams]);
  }
  return results;
}

// Expected round score differential for the declaring team with `bid`, given
// simulated trick counts.
double expectedDeclarerDifferential(List<int> trickSamples, FiveHundredBid bid, FiveHundredRuleSet rules) {
  double total = 0;
  for (final t in trickSamples) {
    final made = t >= bid.tricks;
    final declarerScore = made
        ? (t == numTricksPerRound ? max(bid.value, rules.slamPoints) : bid.value)
        : -bid.value;
    total += declarerScore - (numTricksPerRound - t) * rules.pointsPerDefenderTrick;
  }
  return total / trickSamples.length;
}

class FiveHundredBidParams {
  // Simulated deals for each possible trump suit (and no trump).
  int numDeals;
  // Only bid if the expected differential is at least this. Negative because
  // letting the opponents declare is also costly.
  double minExpectedDifferential;
  // Never outbid partner.
  bool neverOutbidPartner;
  // Attempts to deal the other hands consistently with the bids (0 to ignore
  // the auction).
  int auctionAttempts;

  FiveHundredBidParams({
    this.numDeals = 300,
    this.minExpectedDifferential = 30,
    this.neverOutbidPartner = true,
    this.auctionAttempts = 50,
  });
}

final defaultBidParams = FiveHundredBidParams();

// Expected differential for every bid, from simulating each trump suit.
Map<FiveHundredBid, double> bidExpectations(FiveHundredRound round, int player, Random rng, FiveHundredBidParams params) {
  final result = <FiveHundredBid, double>{};
  for (final trump in FiveHundredBid.suitOrder) {
    final samples = simulateDeclarerTricks(
      hand: round.cardsForPlayer(player),
      player: player,
      trump: trump,
      rules: round.rules,
      numDeals: params.numDeals,
      rng: rng,
      bidHistory: round.bidHistory,
      auctionAttempts: params.auctionAttempts,
    );
    for (int t = minimumBidTricks; t <= maximumBidTricks; t++) {
      final bid = FiveHundredBid(t, trump);
      result[bid] = expectedDeclarerDifferential(samples, bid, round.rules);
    }
  }
  return result;
}

// Bids the legal bid with the highest expected score differential, if it's
// above the threshold. Bids are natural: the AI bids the contract it expects
// to make best, which may be a jump.
FiveHundredBid? chooseBid(FiveHundredRound round, int player, Random rng, [FiveHundredBidParams? bidParams]) {
  final params = bidParams ?? defaultBidParams;
  final high = highBid(round.bidHistory);
  if (params.neverOutbidPartner && high != null && high.player % numTeams == player % numTeams) {
    return null;
  }
  final expectations = bidExpectations(round, player, rng, params);
  FiveHundredBid? best;
  for (final e in expectations.entries) {
    if (round.canCurrentBidderMakeBid(e.key) &&
        e.value >= params.minExpectedDifferential &&
        (best == null || e.value > expectations[best]!)) {
      best = e.key;
    }
  }
  return best;
}
