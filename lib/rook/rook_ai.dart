import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/rook/rook.dart';

// Rook AI. Functions that choose an action for a player in a round only look
// at the information that player can see: their own hand, the bids, the
// cards played so far, and the discards if they're the declarer. Rollouts
// call them with hypothetical rounds where the hidden cards have been dealt
// randomly, consistent with what's known.

// ---------------------------------------------------------------------------
// Card tracking

List<PlayingCard> playedCards(RookRound round) => [
  for (final t in round.previousTricks) ...t.cards,
  ...round.currentTrick.cards,
];

// Cards whose location is unknown to `player`: not in their hand, not played,
// and not in the nest if they're the declarer and chose the discards.
Set<PlayingCard> unseenCards(RookRound round, int player) {
  final unseen = rookDeckCards().toSet();
  unseen.removeAll(round.players[player].hand);
  unseen.removeAll(playedCards(round));
  if (round.contract?.declarer == player) {
    unseen.removeAll(round.finalNest);
  }
  return unseen;
}

// Higher is better: trumps beat other suits, the joker beats everything. Only
// meaningful for comparing cards of the same effective suit.
int _cardPower(PlayingCard card) => switch (card) {
  SuitedCard(:final rank) => rank.index,
  JokerCard() => Rank.values.length,
};

// True if no unseen card can beat `card` when following its suit, so leading
// it wins the trick unless someone trumps it.
bool isMasterCard(PlayingCard card, Suit trump, Set<PlayingCard> unseen) {
  final suit = effectiveSuit(card, trump);
  final power = _cardPower(card);
  return !unseen.any((c) => effectiveSuit(c, trump) == suit && _cardPower(c) > power);
}

// Suits that each player is known to be out of, based on failing to follow
// suit. The joker can be played at any time so it never shows a void, and
// because it counts as a trump, a player who didn't follow a trump lead
// doesn't have the joker either.
List<Set<Suit>> knownVoids(RookRound round) {
  final trump = round.contract!.trump;
  final voids = List.generate(numPlayers, (_) => <Suit>{});
  void processTrick(int leader, List<PlayingCard> cards) {
    if (cards.isEmpty) return;
    final leadSuit = effectiveSuit(cards[0], trump);
    for (int i = 1; i < cards.length; i++) {
      final c = cards[i];
      if (c is SuitedCard && effectiveSuit(c, trump) != leadSuit) {
        voids[(leader + i) % numPlayers].add(leadSuit);
      }
    }
  }
  for (final t in round.previousTricks) {
    processTrick(t.leader, t.cards);
  }
  processTrick(round.currentTrick.leader, round.currentTrick.cards);
  return voids;
}

int _currentWinnerIndex(List<PlayingCard> cards, Suit trump) => rookTrickWinnerIndex(cards, trump: trump);

bool _wouldWin(List<PlayingCard> trickCards, PlayingCard card, Suit trump) =>
    _currentWinnerIndex([...trickCards, card], trump) == trickCards.length;

// ---------------------------------------------------------------------------
// Heuristic card play, used directly and as the rollout policy for Monte Carlo.

class HeuristicPlayParams {
  // Minimum points in the trick to capture it with the joker, when it isn't
  // already won by partner.
  int jokerCaptureMinPoints;
  // Whether the declaring team leads trump to pull the opponents' trumps.
  bool declarerPullsTrump;
  // Whether to give counters to partner when partner is winning the trick.
  bool smearToPartner;
  // When not the last to play, only try to win a trick with a card that can't
  // be beaten by the players after us.
  bool onlyWinWithSafeCards;
  // Lead side suit masters before pulling trump.
  bool leadMastersBeforeTrump;
  // When partner is winning but could be beaten, play the cheapest counter
  // (rather than no counter) if it costs at most this many points.
  int riskySmearMaxPoints;
  // Count the nest's points (known or expected) as part of the last trick.
  bool countNestInLastTrick;

  HeuristicPlayParams({
    this.jokerCaptureMinPoints = 10,
    this.declarerPullsTrump = true,
    this.smearToPartner = true,
    this.onlyWinWithSafeCards = false,
    this.leadMastersBeforeTrump = false,
    this.riskySmearMaxPoints = 5,
    this.countNestInLastTrick = false,
  });
}

final defaultHeuristicParams = HeuristicPlayParams();

PlayingCard chooseCardHeuristic(RookRound round, Random rng, [HeuristicPlayParams? playParams]) {
  final params = playParams ?? defaultHeuristicParams;
  final legal = round.legalPlaysForCurrentPlayer();
  if (legal.length == 1) {
    return legal[0];
  }
  final rules = round.rules;
  final player = round.currentPlayerIndex();
  final team = player % numTeams;
  final contract = round.contract!;
  final trump = contract.trump;
  final isDeclaringTeam = contract.declarer % numTeams == team;
  final unseen = unseenCards(round, player);
  final trick = round.currentTrick.cards;

  int points(PlayingCard c) => pointsForCard(c, rules);
  bool isTrump(PlayingCard c) => effectiveSuit(c, trump) == trump;
  // Cards to give up when we don't want to win: no points, not trump, low rank.
  PlayingCard lowestValue(Iterable<PlayingCard> cards) {
    int cost(PlayingCard c) =>
        (c is JokerCard ? 10000 : 0) + points(c) * 100 + (isTrump(c) ? 50 : 0) + _cardPower(c);
    return cards.reduce((a, b) => cost(a) <= cost(b) ? a : b);
  }

  if (trick.isEmpty) {
    final sideMasters = legal.where((c) => !isTrump(c) && isMasterCard(c, trump, unseen)).toList();
    if (params.leadMastersBeforeTrump && sideMasters.isNotEmpty) {
      return sideMasters.reduce((a, b) => points(a) >= points(b) ? a : b);
    }
    final trumps = legal.where(isTrump).toList();
    final unseenTrumps = unseen.where(isTrump);
    if (params.declarerPullsTrump && isDeclaringTeam && trumps.isNotEmpty && unseenTrumps.isNotEmpty) {
      // Lead a master trump if we have one, otherwise a low trump to draw
      // out higher ones (the joker is always a master).
      final masters = trumps.where((c) => isMasterCard(c, trump, unseen)).toList();
      if (masters.isNotEmpty) {
        return masters.reduce((a, b) => _cardPower(a) <= _cardPower(b) ? a : b);
      }
      if (trumps.length >= 2) {
        return lowestValue(trumps);
      }
    }
    // Lead a side suit master, preferring ones with points.
    if (sideMasters.isNotEmpty) {
      return sideMasters.reduce((a, b) => points(a) >= points(b) ? a : b);
    }
    final nonTrump = legal.where((c) => !isTrump(c));
    return lowestValue(nonTrump.isNotEmpty ? nonTrump : legal);
  }

  final leader = round.currentTrick.leader;
  final winner = (leader + _currentWinnerIndex(trick, trump)) % numPlayers;
  final partnerWinning = winner % numTeams == team;
  final isLast = trick.length == numPlayers - 1;
  var trickPoints = pointsForCards(trick, rules);
  if (params.countNestInLastTrick && round.players[player].hand.length == 1) {
    if (contract.declarer == player) {
      trickPoints += pointsForCards(round.finalNest, rules);
    } else if (unseen.isNotEmpty) {
      // The nest's expected points, assuming it's a random subset of the unseen cards.
      trickPoints += (pointsForCards(unseen, rules) * numNestCards / unseen.length).round();
    }
  }
  var winningPlays = legal.where((c) => _wouldWin(trick, c, trump)).toList();
  if (params.onlyWinWithSafeCards && !isLast) {
    // A winning card is safe if no unseen card would beat it.
    winningPlays = winningPlays.where((w) {
      final withW = [...trick, w];
      return !unseen.any((c) => _wouldWin(withW, c, trump));
    }).toList();
  }

  if (partnerWinning) {
    // Partner's card is safe if we're last, or nobody can beat it. Ignores
    // which opponents still have to play.
    final winningCard = trick[_currentWinnerIndex(trick, trump)];
    final leadSuit = effectiveSuit(trick[0], trump);
    final canBeBeaten = unseen.any((c) =>
        _wouldWin(trick, c, trump) && (effectiveSuit(c, trump) == leadSuit || effectiveSuit(c, trump) == trump)) &&
        winningCard is! JokerCard;
    if (params.smearToPartner && (isLast || !canBeBeaten)) {
      final nonJoker = legal.where((c) => c is! JokerCard).toList();
      if (nonJoker.isNotEmpty) {
        // Highest points, then lowest rank.
        return nonJoker.reduce((a, b) {
          if (points(a) != points(b)) return points(a) > points(b) ? a : b;
          if (isTrump(a) != isTrump(b)) return isTrump(a) ? b : a;
          return _cardPower(a) <= _cardPower(b) ? a : b;
        });
      }
    }
    if (params.riskySmearMaxPoints > 0) {
      final cheapCounters = legal.where((c) =>
          c is! JokerCard && !isTrump(c) && points(c) > 0 && points(c) <= params.riskySmearMaxPoints).toList();
      if (cheapCounters.isNotEmpty) {
        return lowestValue(cheapCounters);
      }
    }
    return lowestValue(legal);
  }

  if (winningPlays.isNotEmpty) {
    final nonJokerWinners = winningPlays.where((c) => c is! JokerCard).toList();
    if (nonJokerWinners.isNotEmpty && (trickPoints > 0 || isLast)) {
      if (isLast) {
        // Can't be overtaken, so win with the most points.
        return nonJokerWinners.reduce((a, b) => points(a) >= points(b) ? a : b);
      }
      // Win as cheaply as possible, preferring non-trump and low ranks.
      return nonJokerWinners.reduce((a, b) {
        if (isTrump(a) != isTrump(b)) return isTrump(a) ? b : a;
        return _cardPower(a) <= _cardPower(b) ? a : b;
      });
    }
    if (winningPlays.contains(joker) && trickPoints >= params.jokerCaptureMinPoints) {
      return joker;
    }
  }
  final nonJoker = legal.where((c) => c is! JokerCard);
  return lowestValue(nonJoker.isNotEmpty ? nonJoker : legal);
}

PlayingCard chooseCardRandom(RookRound round, Random rng) {
  final plays = round.legalPlaysForCurrentPlayer();
  return plays[rng.nextInt(plays.length)];
}

typedef RookChooseCardFn = PlayingCard Function(RookRound round, Random rng);

void playOutRound(RookRound round, RookChooseCardFn chooseFn, Random rng) {
  while (!round.isOver()) {
    round.playCard(chooseFn(round, rng));
  }
}

// Round score differential from the point of view of `team`.
int teamScoreDifferential(RookRound round, int team) {
  final scores = round.contractScoresForTeams();
  return scores[team] - scores[1 - team];
}

// ---------------------------------------------------------------------------
// Monte Carlo card play

// Returns a copy of `round` where the cards hidden from `player` (other hands
// and possibly the nest) are randomly redistributed, consistent with the
// number of cards each player has and the suits they're known to be out of.
RookRound? possibleRoundForPlayer(RookRound round, int player, Random rng) {
  final trump = round.contract!.trump;
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
    constraints.add(CardDistributionConstraint(numCards: round.finalNest.length));
  }
  final dist = possibleCardDistribution(
      CardDistributionRequest(
        cardsToAssign: unseen,
        constraints: constraints,
        suitForCard: (c) => effectiveSuit(c, trump),
      ),
      rng);
  if (dist == null) {
    return null;
  }
  final result = round.copy();
  for (int i = 0; i < constraintPlayers.length; i++) {
    result.players[constraintPlayers[i]].hand = dist[i];
  }
  if (!isDeclarer) {
    result.finalNest = dist.last;
  }
  return result;
}

class RookMonteCarloParams {
  int numDeals;
  int rolloutsPerDeal;
  int? maxTimeMillis;
  RookChooseCardFn rolloutChooseFn;

  RookMonteCarloParams({
    this.numDeals = 30,
    this.rolloutsPerDeal = 1,
    this.maxTimeMillis,
    this.rolloutChooseFn = chooseCardHeuristic,
  });
}

PlayingCard chooseCardMonteCarlo(RookRound round, RookMonteCarloParams params, Random rng) {
  final legal = round.legalPlaysForCurrentPlayer();
  if (legal.length == 1) {
    return legal[0];
  }
  final startTime = DateTime.now().millisecondsSinceEpoch;
  final player = round.currentPlayerIndex();
  final team = player % numTeams;
  final totals = List.filled(legal.length, 0);
  for (int d = 0; d < params.numDeals; d++) {
    final hypo = possibleRoundForPlayer(round, player, rng);
    if (hypo == null) {
      break;
    }
    for (int ci = 0; ci < legal.length; ci++) {
      for (int r = 0; r < params.rolloutsPerDeal; r++) {
        final rolloutRound = hypo.copy();
        rolloutRound.playCard(legal[ci]);
        playOutRound(rolloutRound, params.rolloutChooseFn, rng);
        totals[ci] += teamScoreDifferential(rolloutRound, team);
      }
    }
    if (params.maxTimeMillis != null && DateTime.now().millisecondsSinceEpoch - startTime >= params.maxTimeMillis!) {
      break;
    }
  }
  int best = 0;
  for (int i = 1; i < legal.length; i++) {
    if (totals[i] > totals[best]) {
      best = i;
    }
  }
  return legal[best];
}

// ---------------------------------------------------------------------------
// Choosing trump and discards

class DiscardsAndTrump {
  final Set<PlayingCard> discards;
  final Suit trump;

  DiscardsAndTrump(this.discards, this.trump);
}

class DiscardParams {
  // Weight of high cards relative to length when choosing trump.
  double trumpHighCardWeight;
  // Preference for keeping (positive) or discarding (negative) side suit point
  // cards. Discarded points go to the winner of the last trick, which is
  // usually the declarer's team.
  int pointCardKeepWeight;
  // Preference for keeping side suit aces.
  int aceKeepWeight;
  // Prefer discarding short suits to create voids.
  bool createVoids;

  DiscardParams({
    this.trumpHighCardWeight = 1.0,
    this.pointCardKeepWeight = -300,
    this.aceKeepWeight = 5000,
    this.createVoids = true,
  });
}

final defaultDiscardParams = DiscardParams();

// Rough strength of a suit as trump: length, plus extra for high cards.
double trumpSuitScore(Iterable<PlayingCard> cards, Suit suit, [double highCardWeight = 1.0]) {
  double score = 0;
  for (final c in cards) {
    if (c is SuitedCard && c.suit == suit) {
      score += 2.0;
      if (c.rank == Rank.ace) score += 1.5 * highCardWeight;
      if (c.rank == Rank.king) score += 1.0 * highCardWeight;
      if (c.rank == Rank.queen) score += 0.5 * highCardWeight;
    }
  }
  return score;
}

Suit chooseTrumpHeuristic(Iterable<PlayingCard> cards, [double highCardWeight = 1.0]) {
  return Suit.values.reduce((a, b) =>
      trumpSuitScore(cards, a, highCardWeight) >= trumpSuitScore(cards, b, highCardWeight) ? a : b);
}

// Keeps trumps and side suit aces, and tries to empty short side suits so that
// the declarer can trump them.
Set<PlayingCard> chooseDiscardsHeuristic(List<PlayingCard> cards, Suit trump, RookRuleSet rules, [DiscardParams? discardParams]) {
  final params = discardParams ?? defaultDiscardParams;
  final sideSuitCounts = suitCounts(cards.whereType<SuitedCard>().where((c) => c.suit != trump));
  int keepPriority(PlayingCard c) {
    final isTrump = effectiveSuit(c, trump) == trump;
    final isPointCard = pointsForCard(c, rules) > 0;
    int priority = 0;
    if (isPointCard && !rules.allowDiscardingPointCards) priority += 100000;
    if (isTrump) priority += 10000;
    if (c is SuitedCard) {
      if (!isTrump && c.rank == Rank.ace) priority += params.aceKeepWeight;
      if (!isTrump && isPointCard) priority += params.pointCardKeepWeight;
      // Shorter suits are discarded first, to create voids.
      if (!isTrump && params.createVoids) priority += sideSuitCounts[c.suit]! * 100;
    }
    return priority + _cardPower(c);
  }
  final sorted = List.of(cards)..sort((a, b) => keepPriority(a) - keepPriority(b));
  return sorted.take(numNestCards).toSet();
}

DiscardsAndTrump chooseDiscardsAndTrump(RookRound round, Random rng, [DiscardParams? params]) {
  params ??= defaultDiscardParams;
  final cards = round.declarerAvailableCards();
  final trump = chooseTrumpHeuristic(cards, params.trumpHighCardWeight);
  return DiscardsAndTrump(chooseDiscardsHeuristic(cards, trump, round.rules, params), trump);
}

// ---------------------------------------------------------------------------
// Bidding

// Simulates the player with `hand` winning the bid: deals the other cards
// randomly, takes the nest, discards and chooses trump, and plays the hand
// out with the heuristic policy. Returns the declaring team's points (not
// counting whether the bid was made) for each simulated deal.
List<int> simulateDeclarerPoints({
  required List<PlayingCard> hand,
  required int player,
  required int dealer,
  required RookRuleSet rules,
  required int numDeals,
  required Random rng,
  RookChooseCardFn playFn = chooseCardHeuristic,
}) {
  final others = rookDeckCards().where((c) => !hand.contains(c)).toList();
  final results = <int>[];
  for (int d = 0; d < numDeals; d++) {
    others.shuffle(rng);
    final players = <RookPlayer>[];
    int offset = 0;
    for (int p = 0; p < numPlayers; p++) {
      if (p == player) {
        players.add(RookPlayer(hand));
      } else {
        players.add(RookPlayer(others.sublist(offset, offset + hand.length)));
        offset += hand.length;
      }
    }
    final round = RookRound()
      ..rules = rules
      ..initialScores = [0, 0]
      ..players = players
      ..dealer = dealer
      ..initialNest = others.sublist(offset, offset + numNestCards)
      ..bidHistory = [PlayerBid(player, rules.minimumBid)]
      ..status = RookRoundStatus.declarerChoosingCardsAndTrump
      ..currentTrick = TrickInProgress((dealer + 1) % numPlayers);
    final choice = chooseDiscardsAndTrump(round, rng);
    round.discardAndChooseTrump(choice.discards, choice.trump);
    playOutRound(round, playFn, rng);
    results.add(round.teamPointsTaken()[player % numTeams]);
  }
  return results;
}

// Expected round score differential for the declaring team when bidding
// `bid`, given simulated point totals. Making the bid scores the team's
// points; going set loses the bid. Either way the defenders score theirs.
double expectedDeclarerDifferential(List<int> pointSamples, int bid, int totalPoints) {
  double total = 0;
  for (final p in pointSamples) {
    final defenderPoints = totalPoints - p;
    total += (p >= bid ? p : -bid) - defenderPoints;
  }
  return total / pointSamples.length;
}

class RookBidParams {
  int numDeals;
  // Bid up to the highest amount whose expected differential is at least this.
  // This is negative because letting the opponents declare is also costly; in
  // self-play the declaring team averages about 100 of the 120 points.
  double minExpectedDifferential;
  // Added to the expected differential if partner has bid, since the
  // simulations otherwise assume partner has a random hand.
  double partnerBidBonus;
  // If not null, outbid partner when our maximum bid is at least this much
  // more than partner's bid.
  int? outbidPartnerMargin;
  // The Rook always wins its trick, so whoever holds it scores its points: a
  // bid above the other points can only be made by the Rook holder's team.
  // With the Rook, pass when the opponents have bid more than that (they're
  // certain to be set). Without it, don't bid more than that.
  bool respectRookLimit;

  RookBidParams({
    this.numDeals = 200,
    this.minExpectedDifferential = -70,
    this.partnerBidBonus = 0,
    this.outbidPartnerMargin,
    this.respectRookLimit = true,
  });
}

final defaultBidParams = RookBidParams();

// The highest bid the player would make with this hand, or null if they
// shouldn't bid at all.
int? maxBidForHand(RookRound round, int player, Random rng, [RookBidParams? params]) {
  params ??= defaultBidParams;
  final rules = round.rules;
  final samples = simulateDeclarerPoints(
    hand: round.players[player].hand,
    player: player,
    dealer: round.dealer,
    rules: rules,
    numDeals: params.numDeals,
    rng: rng,
  );
  final totalPoints = pointsForCards(rookDeckCards(), rules);
  final partnerHasBid = round.bidHistory.any((b) => !b.isPass && b.player == (player + 2) % numPlayers);
  final bonus = partnerHasBid ? params.partnerBidBonus : 0;
  int? best;
  for (int bid = rules.minimumBid; bid <= rules.maximumBid; bid += rules.bidIncrement) {
    if (expectedDeclarerDifferential(samples, bid, totalPoints) + bonus >= params.minExpectedDifferential) {
      best = bid;
    }
  }
  return best;
}

// Returns the bid amount, or null to pass.
int? chooseBid(RookRound round, int playerIndex, Random rng, [RookBidParams? bidParams]) {
  final params = bidParams ?? defaultBidParams;
  final rules = round.rules;
  final high = highBid(round.bidHistory);
  final hasRook = round.players[playerIndex].hand.contains(joker);
  final withoutRookLimit = pointsForCards(rookDeckCards(), rules) - rules.pointsForJoker;
  if (params.respectRookLimit &&
      hasRook &&
      high != null &&
      high.player % numTeams != playerIndex % numTeams &&
      high.bid! > withoutRookLimit) {
    return null;
  }
  final nextBid = (high == null) ? rules.minimumBid : high.bid! + rules.bidIncrement;
  if (params.respectRookLimit && !hasRook && nextBid > withoutRookLimit) {
    return null;
  }
  var maxBid = maxBidForHand(round, playerIndex, rng, params);
  if (maxBid == null) {
    return null;
  }
  if (params.respectRookLimit && !hasRook) {
    maxBid = min(maxBid, withoutRookLimit);
  }
  // Don't outbid partner, unless our hand is much stronger.
  if (high != null && high.player % numTeams == playerIndex % numTeams) {
    final margin = params.outbidPartnerMargin;
    if (margin == null || maxBid < high.bid! + margin) {
      return null;
    }
  }
  return (nextBid <= maxBid) ? nextBid : null;
}
