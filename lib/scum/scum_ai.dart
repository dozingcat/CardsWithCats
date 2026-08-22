import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/scum/scum.dart';

/// Everything the AI needs to choose a play. All fields are snapshots; the AI
/// never mutates round state.
class ScumPlayRequest {
  final ScumRuleSet rules;
  final List<PlayingCard> hand;

  /// Player indices in role order (President first, Scum last).
  final List<int> seatOrder;

  /// Cumulative match scores, indexed by player.
  final List<int> scores;

  /// Number of cards each player holds.
  final List<int> handCounts;

  /// Cards seen outside this trick: previous plays plus the trades we made
  /// and received.
  final Set<PlayingCard> seenCards;

  final int playerIndex;
  final ScumTrick currentTrick;

  ScumPlayRequest({
    required this.rules,
    required this.hand,
    required this.seatOrder,
    required this.scores,
    required this.handCounts,
    required this.seenCards,
    required this.playerIndex,
    required this.currentTrick,
  });

  static ScumPlayRequest fromRound(ScumRound round, int playerIndex) {
    final seen = <PlayingCard>{...round.players[playerIndex].hand};
    // Seen cards are reconstructed from the current trick only; the round does
    // not retain completed tricks, so the AI counts what is visible now plus
    // its own trade knowledge. This keeps the request cheap to build every turn.
    for (final a in round.currentTrick.actions) {
      seen.addAll(a.cards);
    }
    final player = round.players[playerIndex];
    seen.addAll(player.receivedCards);
    return ScumPlayRequest(
      rules: round.rules.copy(),
      hand: List.from(player.hand),
      seatOrder: List.of(round.seatOrder),
      scores: List.of(round.initialScores),
      handCounts: [for (final p in round.players) p.hand.length],
      seenCards: seen,
      playerIndex: playerIndex,
      currentTrick: ScumTrick.copy(round.currentTrick),
    );
  }

  ScumRole get myRole => ScumRole.values[seatOrder.indexOf(playerIndex)];

  bool get amLeading => currentTrick.bestAction == null;
}

/// Cards a president or vice president chooses to give down during the trade.
class ScumTradeRequest {
  final List<PlayingCard> hand;
  final int count;
  final ScumRole myRole;

  ScumTradeRequest({
    required this.hand,
    required this.count,
    required this.myRole,
  });
}

List<PlayingCard> mandatoryCardsToGive(List<PlayingCard> hand, int count) {
  return highestCards(hand, count);
}

/// Presidents and vice presidents give away their least useful cards: lowest
/// ranks first, and never break up a set while a lower singleton exists.
List<PlayingCard> chooseCardsToGive(ScumTradeRequest req) {
  if (req.count <= 0 || req.hand.isEmpty) return [];
  final byRank = <Rank, List<PlayingCard>>{};
  for (final c in req.hand) {
    byRank.putIfAbsent(c.rank, () => []).add(c);
  }
  final result = <PlayingCard>[];
  // Give singletons from the lowest rank upward, then pairs, then triples.
  for (int setSize = 1; setSize <= 4 && result.length < req.count; setSize++) {
    final ranks = byRank.keys.where((r) => byRank[r]!.length == setSize).toList()
      ..sort((a, b) => a.index - b.index);
    for (final rank in ranks) {
      if (result.length >= req.count) break;
      result.addAll(byRank[rank]!.take(req.count - result.length));
    }
  }
  return result.sublist(0, min(req.count, result.length));
}

/// Unseen copies of each rank, from the AI's point of view.
Map<Rank, int> unseenCountByRank(ScumPlayRequest req) {
  final counts = {for (final r in Rank.values) r: 0};
  for (final card in standardDeckCards()) {
    if (!req.seenCards.contains(card)) {
      counts[card.rank] = counts[card.rank]! + 1;
    }
  }
  return counts;
}

/// Whether any unseen set of `size` cards could outrank `rank`.
bool canAnyUnseenSetBeat(ScumPlayRequest req, Rank rank, int size) {
  final counts = unseenCountByRank(req);
  for (final r in Rank.values) {
    if (r.index > rank.index && counts[r]! >= size) return true;
  }
  return false;
}

/// Total unseen cards that could beat a play of `rank` with `size` cards,
/// weighted toward sets that are actually formable.
double pressureFromAbove(ScumPlayRequest req, Rank rank, int size) {
  final counts = unseenCountByRank(req);
  double pressure = 0;
  for (final r in Rank.values) {
    if (r.index <= rank.index) continue;
    final n = counts[r]!;
    if (n >= size) {
      // Higher ranks are more dangerous to play under.
      pressure += n * (1 + (r.index - rank.index) / 8.0);
    }
  }
  return pressure;
}

/// Chooses the next play for an AI cat. Returns the cards to play, or an empty
/// list to pass (only allowed when not leading).
List<PlayingCard> chooseScumPlay(ScumPlayRequest req, Random rng) {
  if (req.amLeading) {
    return _chooseLead(req, rng);
  }
  return _chooseFollow(req, rng);
}

List<PlayingCard> _chooseLead(ScumPlayRequest req, Random rng) {
  final options = legalSetsForHand(req.hand, null);
  assert(options.isNotEmpty);

  // Going out beats everything.
  for (final option in options) {
    if (option.length == req.hand.length) return option;
  }

  double bestScore = -1e9;
  List<PlayingCard> best = options.first;
  for (final option in options) {
    final rank = option[0].rank;
    final size = option.length;
    double score = -rank.numericValue.toDouble(); // Prefer shedding low cards.

    // Sets are precious: leading them early wastes future control, but a low
    // set sheds more cards at once, so give a small bonus for larger sets of
    // low ranks.
    score += size * (2.5 - rank.numericValue * 0.15);

    // An unbeatable lead guarantees keeping the lead. More valuable late,
    // when high cards would otherwise be trapped, or when rivals are close
    // to going out.
    final safe = !canAnyUnseenSetBeat(req, rank, size);
    final smallestRivalHand =
        (req.handCounts.toList()..removeAt(req.playerIndex)).reduce(min);
    if (safe) {
      score += 6 + (13 - req.hand.length) * 0.6 +
          (smallestRivalHand <= 2 ? 3 : 0);
    }

    // Don't burn the top ranks while plenty of hand remains unless they're
    // trapped singles anyway.
    if (rank.index >= Rank.king.index && req.hand.length > 5 && size == 1) {
      score -= 5;
    }

    // A high quad is the strongest weapon in the game: dropping it early
    // costs the presidency. Split it into pairs/singles and keep it for a
    // decisive moment instead (#10).
    if (size == 4 &&
        rank.index >= Rank.queen.index &&
        req.hand.length > size + 3) {
      score -= 14;
    }
    // High pairs/triples are nearly as precious while the hand is deep.
    if (size >= 2 &&
        rank.index >= Rank.king.index &&
        req.hand.length > size + 4) {
      score -= 4;
    }

    // Leading our lowest single is always decent.
    if (size == 1 && rank == _lowestRank(req.hand)) {
      score += 1.5;
    }

    score += rng.nextDouble() * 0.75;
    if (score > bestScore) {
      bestScore = score;
      best = option;
    }
  }
  return best;
}

Rank _lowestRank(List<PlayingCard> hand) {
  var lowest = hand[0].rank;
  for (final c in hand) {
    if (c.rank.index < lowest.index) lowest = c.rank;
  }
  return lowest;
}

List<PlayingCard> _chooseFollow(ScumPlayRequest req, Random rng) {
  final options = legalSetsForHand(req.hand, req.currentTrick);
  if (options.isEmpty) return []; // Forced pass.
  final best = req.currentTrick.bestAction!;
  final winner = best.player;
  final winningRank = best.cards[0].rank;
  final size = best.cards.length;

  // Cheapest beat for each candidate rank.
  options.sort((a, b) => a[0].rank.index - b[0].rank.index);

  // Would playing here empty our hand? Always take it.
  for (final option in options) {
    if (option.length == req.hand.length) return option;
  }

  final myRole = req.myRole;
  final winnerRole = ScumRole.values[req.seatOrder.indexOf(winner)];
  final winnerHandCount = req.handCounts[winner];

  // Is the current winner about to escape (run out)? Blocking matters most
  // when they are a rival close to finishing ahead of us.
  bool winnerAboutToGoOut = winnerHandCount <= 2;
  bool winnerIsRival = winnerRole != myRole;
  // Everyone is a rival in Scum, but beating the player who sits better than
  // us has extra value because finish positions carry the role swap.
  bool winnerSitsBetter = winnerRole.index < myRole.index;

  // Acting last means nobody can overtake our play this trick.
  final activeAfterMe = <int>[];
  for (int offset = 1; offset < req.rules.numPlayers; offset++) {
    final p = (req.playerIndex + offset) % req.rules.numPlayers;
    if (req.handCounts[p] > 0) activeAfterMe.add(p);
  }
  final actingLast = activeAfterMe.isEmpty;
  final passesNeeded = activeAfterMe.length;

  double passScore = -1.0; // Slight bias toward taking action over passing.

  // Passing is fine when the play is expensive to beat and we keep
  // flexibility. It gets worse when the winner is escaping, sits better than
  // us, or a cheap beat is available.
  if (winnerAboutToGoOut) passScore -= 6;
  if (winnerSitsBetter) passScore -= 2;
  // If we hold the only possible beats, letting a cheap play stand invites
  // the winner to shed again next trick.
  if (pressureFromAbove(req, winningRank, size) < 1.0 &&
      options.isNotEmpty &&
      options[0][0].rank.numericValue <= 9) {
    passScore -= 3;
  }
  // A cheap beat is available: passing concedes the lead for nothing.
  final cheapestBeat = options[0][0].rank;
  if (cheapestBeat.numericValue <= winningRank.numericValue + 3) {
    passScore -= 2.5;
  }

  // Beating lets us lead the next trick and shed our low cards.
  final lowCardsInHand =
      req.hand.where((c) => c.rank.numericValue <= 9).length;
  final controlBonus = min(2.5, lowCardsInHand * 0.35);

  double bestScore = passScore + rng.nextDouble() * 0.5;
  List<PlayingCard>? choice;

  for (final option in options) {
    final rank = option[0].rank;
    double score = -rank.numericValue * 0.35; // Cost of committing high cards.

    // Beating cheaply keeps us flexible and often steals the lead for free.
    if (rank.numericValue <= winningRank.numericValue + 2) score += 4;

    // Mid-rank cards are fine to spend on winning a trick.
    if (rank.numericValue <= 10) score += 1.5;

    // Winning the lead is worth more when we still have trash to unload.
    score += controlBonus;

    // Nobody can beat us afterwards: strong lead position for next trick, but
    // only worth much if the rest of our hand can then be unloaded. Winning
    // with our top card while leaving nothing but other high cards just burns
    // control early.
    final lowAfterPlay = req.hand
        .where((c) => c.rank.numericValue <= 9 && !option.contains(c))
        .length;
    if (!canAnyUnseenSetBeat(req, rank, size)) {
      score += 0.25 + min(5.5, lowAfterPlay * 0.75);
    } else if (actingLast) {
      score += 2;
    }

    // Breaking up our own bigger set of the same rank costs future power.
    final myCountOfRank = req.hand.where((c) => c.rank == rank).length;
    if (myCountOfRank > option.length) score -= 4;

    // Late game: staying alive to dump the last cards matters more.
    if (req.hand.length <= 3) score += 2.5;

    // Beating with a large high set early is as wasteful as leading it.
    if (option.length >= 3 &&
        rank.index >= Rank.queen.index &&
        req.hand.length > option.length + 3) {
      score -= 8;
    }

    // Block a rival who is about to go out.
    if (winnerAboutToGoOut && winnerIsRival) score += 5;

    // When several players still act after us, higher risk of being overtaken:
    // discount risky plays slightly, capped so it never dominates the decision.
    if (passesNeeded >= 2) {
      score -= min(2.0, pressureFromAbove(req, rank, size) * 0.03);
    }

    score += rng.nextDouble() * 0.75;
    if (score > bestScore) {
      bestScore = score;
      choice = option;
    }
  }
  return choice ?? [];
}
