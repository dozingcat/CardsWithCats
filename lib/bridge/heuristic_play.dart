/// A rule-based card-play policy for bridge. It is deliberately cheap:
/// its main job is to replace uniformly random play inside Monte Carlo
/// rollouts, where thousands of decisions are made per real play. It also
/// encodes standard defensive agreements (sequence leads, fourth best,
/// second hand low, third hand high) so that simulated defenders behave
/// like plausible opponents.
library;

import 'dart:math';

import '../cards/card.dart';
import '../cards/trick.dart';
import 'bridge.dart';
import 'bridge_ai.dart';

const _honorRanks = [Rank.ace, Rank.king, Rank.queen];

class _PlayContext {
  final CardToPlayRequest req;
  final int seat;
  final Suit? trump;
  final int declarer;
  final int dummy;
  final bool isDeclarerSide;
  final List<PlayingCard> legal;
  final Set<PlayingCard> played = {};
  // Cards of my side's other hand, when visible (dummy for declarer,
  // declarer's hand when I am the dummy). Null for defenders.
  final List<PlayingCard>? partnerVisible;
  // The visible dummy when I'm a defender, null otherwise.
  final List<PlayingCard>? opponentDummy;

  _PlayContext._(this.req, this.seat, this.trump, this.declarer, this.dummy,
      this.isDeclarerSide, this.legal, this.partnerVisible, this.opponentDummy);

  factory _PlayContext(CardToPlayRequest req) {
    final seat = req.currentPlayerIndex();
    final declarer = req.contract.declarer;
    final dummy = req.contract.dummy;
    final isDeclarerSide = seat == declarer || seat == dummy;
    List<PlayingCard>? partnerVisible;
    List<PlayingCard>? opponentDummy;
    if (seat == declarer) {
      partnerVisible = req.dummyHand;
    } else if (seat == dummy) {
      partnerVisible = req.declarerHand;
    } else {
      opponentDummy = req.dummyHand;
    }
    final ctx = _PlayContext._(req, seat, req.trump(), declarer, dummy,
        isDeclarerSide, req.legalPlays(), partnerVisible, opponentDummy);
    for (final t in req.previousTricks) {
      ctx.played.addAll(t.cards);
    }
    ctx.played.addAll(req.currentTrick.cards);
    return ctx;
  }

  List<PlayingCard> get hand => req.hand;

  List<PlayingCard> suitCards(Suit s) =>
      sortedCardsInSuit(hand, s); // descending

  /// True if no card that could beat `card` remains with a hidden player
  /// or a visible opponent.
  bool isMaster(PlayingCard card) {
    for (var r = card.rank; r != Rank.ace;) {
      r = r.nextHigherRank();
      final higher = PlayingCard(r, card.suit);
      if (played.contains(higher) || hand.contains(higher)) continue;
      if (partnerVisible != null && partnerVisible!.contains(higher)) continue;
      return false;
    }
    return true;
  }

  /// Number of cards of `suit` held by players other than me and my
  /// visible partner (i.e. potentially by the opponents).
  int hiddenCount(Suit suit) {
    int seen = hand.where((c) => c.suit == suit).length +
        played.where((c) => c.suit == suit).length +
        (partnerVisible?.where((c) => c.suit == suit).length ?? 0);
    return 13 - seen;
  }
}

PlayingCard chooseCardHeuristic(CardToPlayRequest req, Random rng) {
  final ctx = _PlayContext(req);
  if (ctx.legal.length == 1) return ctx.legal[0];
  switch (req.currentTrick.cards.length) {
    case 0:
      return _chooseLead(ctx);
    case 1:
      return _chooseSecondHand(ctx);
    case 2:
      return _chooseThirdHand(ctx);
    default:
      return _chooseFourthHand(ctx);
  }
}

// ---------------------------------------------------------------------------
// Leads

PlayingCard _chooseLead(_PlayContext ctx) {
  if (ctx.isDeclarerSide) {
    return _chooseDeclarerLead(ctx);
  }
  return _chooseDefenderLead(ctx);
}

PlayingCard _chooseDeclarerLead(_PlayContext ctx) {
  final trump = ctx.trump;
  // Draw trumps while the opponents still hold any and we have the balance
  // of power in the suit.
  if (trump != null) {
    final myTrumps = ctx.suitCards(trump);
    final partnerTrumps = ctx.partnerVisible == null
        ? <PlayingCard>[]
        : sortedCardsInSuit(ctx.partnerVisible!, trump);
    final oppTrumps = ctx.hiddenCount(trump);
    if (myTrumps.isNotEmpty &&
        oppTrumps > 0 &&
        myTrumps.length + partnerTrumps.length > oppTrumps) {
      if (ctx.isMaster(myTrumps.first)) {
        return myTrumps.first;
      }
      // Lead low toward partner's honors, or just cheaply.
      return myTrumps.last;
    }
  }
  // Cash a master in a side suit.
  final master = _masterToCash(ctx);
  if (master != null) return master;
  // Otherwise lead low from our longest side suit.
  return _lowFromLongestSideSuit(ctx);
}

PlayingCard _chooseDefenderLead(_PlayContext ctx) {
  final trump = ctx.trump;
  final isNotrump = trump == null;

  // Cash a master rather than break new suits.
  final master = _masterToCash(ctx);
  if (master != null) return master;

  // Top of a two-card (or better) honor sequence.
  final seq = _sequenceLead(ctx);
  if (seq != null) return seq;

  if (!isNotrump) {
    // A singleton in a side suit, hoping to ruff.
    for (final s in Suit.values) {
      if (s == trump) continue;
      final cards = ctx.suitCards(s);
      if (cards.length == 1 &&
          !_honorRanks.contains(cards[0].rank) &&
          ctx.suitCards(trump).isNotEmpty) {
        return cards[0];
      }
    }
  }

  // Partner's bid suit.
  final partnerSuit = _suitBidBy(ctx, (ctx.seat + 2) % 4);
  if (partnerSuit != null) {
    final cards = ctx.suitCards(partnerSuit);
    if (cards.isNotEmpty && partnerSuit != trump) {
      return cards.length >= 3 ? cards.last : cards.first;
    }
  }

  // Fourth best from the longest suit; against a trump contract avoid
  // underleading an ace, and avoid leading trumps.
  final candidates = <Suit>[];
  for (final s in Suit.values) {
    if (s == trump) continue;
    final cards = ctx.suitCards(s);
    if (cards.isEmpty) continue;
    if (!isNotrump && cards.first.rank == Rank.ace) continue;
    candidates.add(s);
  }
  Suit? best;
  for (final s in candidates) {
    if (best == null || ctx.suitCards(s).length > ctx.suitCards(best).length) {
      best = s;
    }
  }
  if (best != null) {
    final cards = ctx.suitCards(best);
    return cards.length >= 4 ? cards[3] : cards.last;
  }
  // Only ace-headed suits (or trumps) left: cash an ace if we have one.
  for (final s in Suit.values) {
    if (s == trump) continue;
    final cards = ctx.suitCards(s);
    if (cards.isNotEmpty && cards.first.rank == Rank.ace) return cards.first;
  }
  return _lowFromLongestSideSuit(ctx);
}

/// A master card worth cashing: highest of a non-trump suit where nothing
/// unseen beats it.
PlayingCard? _masterToCash(_PlayContext ctx) {
  for (final s in Suit.values) {
    if (s == ctx.trump) continue;
    final cards = ctx.suitCards(s);
    if (cards.isEmpty) continue;
    // Only cash when the opponents may still follow (crude protection
    // against setting up ruffs and squandering entries late).
    if (ctx.isMaster(cards.first) && ctx.hiddenCount(s) > 0) {
      return cards.first;
    }
  }
  return null;
}

/// Top of a touching honor sequence (QJ or better, 2+ cards).
PlayingCard? _sequenceLead(_PlayContext ctx) {
  for (final s in Suit.values) {
    if (s == ctx.trump) continue;
    final cards = ctx.suitCards(s);
    if (cards.length < 2) continue;
    final top = cards[0];
    final second = cards[1];
    if (top.rank.index >= Rank.jack.index &&
        second.rank.index == top.rank.index - 1) {
      return top;
    }
  }
  return null;
}

PlayingCard _lowFromLongestSideSuit(_PlayContext ctx) {
  Suit? best;
  for (final s in Suit.values) {
    if (s == ctx.trump && ctx.hand.any((c) => c.suit != s)) continue;
    final cards = ctx.suitCards(s);
    if (cards.isEmpty) continue;
    if (best == null || cards.length > ctx.suitCards(best).length) {
      best = s;
    }
  }
  best ??= ctx.hand[0].suit;
  return ctx.suitCards(best).last;
}

/// First suit bid naturally-looking by `seat` in the auction, if any.
Suit? _suitBidBy(_PlayContext ctx, int seat) {
  for (final bid in ctx.req.bidHistory) {
    if (bid.player == seat &&
        bid.action.bidType == BidType.contract &&
        bid.action.contractBid!.trump != null) {
      return bid.action.contractBid!.trump;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Following to a trick

List<PlayingCard> _followingSuit(_PlayContext ctx) {
  final ledSuit = ctx.req.currentTrick.cards[0].suit;
  return sortedCardsInSuit(ctx.legal, ledSuit); // descending; empty if void
}

/// The card currently winning the trick, and whether my side played it.
(PlayingCard, bool) _currentWinner(_PlayContext ctx) {
  final tc = ctx.req.currentTrick.cards;
  final wi = trickWinnerIndex(tc, trump: ctx.trump);
  final winnerSeat = (ctx.req.currentTrick.leader + wi) % 4;
  return (tc[wi], winnerSeat % 2 == ctx.seat % 2);
}

/// Cheapest card in `cards` (descending order) that would win against
/// `target` given the led suit and trump; null if none.
PlayingCard? _cheapestBeater(
    _PlayContext ctx, List<PlayingCard> cards, PlayingCard target) {
  final ledSuit = ctx.req.currentTrick.cards[0].suit;
  PlayingCard? best;
  for (final c in cards) {
    final beats = _beats(c, target, ledSuit, ctx.trump);
    if (beats) best = c; // descending order: last winner found is cheapest
  }
  return best;
}

bool _beats(PlayingCard a, PlayingCard b, Suit ledSuit, Suit? trump) {
  if (a.suit == b.suit) return a.rank.isHigherThan(b.rank);
  if (trump != null && a.suit == trump) return true;
  return false;
}

PlayingCard _chooseSecondHand(_PlayContext ctx) {
  final following = _followingSuit(ctx);
  final led = ctx.req.currentTrick.cards[0];
  if (following.isNotEmpty) {
    // Win outright with a master when the suit is threatened.
    if (ctx.isMaster(following.first) &&
        led.rank.index >= Rank.ten.index) {
      return _cheapestMasterEquivalent(ctx, following);
    }
    // Cover an honor with an honor.
    if (led.rank.index >= Rank.jack.index) {
      final cover = _cheapestBeater(ctx, following, led);
      if (cover != null && cover.rank.index >= Rank.queen.index) {
        return cover;
      }
    }
    // Second hand low.
    return following.last;
  }
  // Void: ruff a threatening lead, otherwise discard.
  if (ctx.trump != null && led.suit != ctx.trump) {
    final trumps = ctx.suitCards(ctx.trump!);
    if (trumps.isNotEmpty && led.rank.index >= Rank.ten.index) {
      return trumps.last;
    }
  }
  return _bestDiscard(ctx);
}

PlayingCard _chooseThirdHand(_PlayContext ctx) {
  final following = _followingSuit(ctx);
  final (winner, mySide) = _currentWinner(ctx);
  // The fourth player may be the visible dummy; then we know exactly what
  // we have to beat.
  final fourthSeat = (ctx.req.currentTrick.leader + 3) % 4;
  List<PlayingCard>? fourthKnown;
  if (ctx.opponentDummy != null && fourthSeat == ctx.dummy) {
    fourthKnown = ctx.opponentDummy;
  }

  if (following.isNotEmpty) {
    final ledSuit = ctx.req.currentTrick.cards[0].suit;
    if (mySide) {
      // Partner is winning. Stay low if their card looks safe: an honor,
      // a master, or nothing higher in a known fourth hand.
      final safe = winner.rank.index >= Rank.ten.index ||
          ctx.isMaster(winner) ||
          (fourthKnown != null &&
              !fourthKnown.any((c) => _beats(c, winner, ledSuit, ctx.trump)));
      if (safe) return following.last;
    }
    // Third hand high: beat the current winner, and the known fourth hand
    // if visible, as cheaply as possible.
    PlayingCard target = winner;
    if (fourthKnown != null) {
      final fourthFollow = sortedCardsInSuit(fourthKnown, ledSuit);
      if (fourthFollow.isNotEmpty &&
          _beats(fourthFollow.first, target, ledSuit, ctx.trump)) {
        target = fourthFollow.first;
      }
    }
    final beater = _cheapestBeater(ctx, following, target);
    if (beater != null) return _lowestEquivalentWinner(ctx, following, beater);
    return following.last;
  }
  // Void.
  if (!mySide && ctx.trump != null) {
    final ledSuit = ctx.req.currentTrick.cards[0].suit;
    if (ledSuit != ctx.trump) {
      final ruff = _cheapestBeater(ctx, ctx.suitCards(ctx.trump!), winner);
      if (ruff != null) return ruff;
    }
  }
  return _bestDiscard(ctx);
}

PlayingCard _chooseFourthHand(_PlayContext ctx) {
  final following = _followingSuit(ctx);
  final (winner, mySide) = _currentWinner(ctx);
  if (mySide) {
    return following.isNotEmpty ? following.last : _bestDiscard(ctx);
  }
  if (following.isNotEmpty) {
    final beater = _cheapestBeater(ctx, following, winner);
    if (beater != null) return beater;
    return following.last;
  }
  if (ctx.trump != null && ctx.req.currentTrick.cards[0].suit != ctx.trump) {
    final trumps = ctx.suitCards(ctx.trump!);
    final ruff = _cheapestBeater(ctx, trumps, winner);
    if (ruff != null) return ruff;
  }
  return _bestDiscard(ctx);
}

/// When winning with the top of touching cards, use the cheapest
/// equivalent (e.g. play the queen from KQ over the jack).
PlayingCard _lowestEquivalentWinner(
    _PlayContext ctx, List<PlayingCard> following, PlayingCard beater) {
  var result = beater;
  bool changed = true;
  while (changed) {
    changed = false;
    for (final c in following) {
      if (c.rank.index == result.rank.index - 1) {
        result = c;
        changed = true;
      }
    }
  }
  return result;
}

PlayingCard _cheapestMasterEquivalent(
    _PlayContext ctx, List<PlayingCard> following) {
  var result = following.first;
  for (final c in following.skip(1)) {
    if (ctx.isMaster(c)) result = c;
  }
  return result;
}

/// Discard: lowest card from the weakest side suit, trying not to
/// unguard honors or throw winners.
PlayingCard _bestDiscard(_PlayContext ctx) {
  PlayingCard? best;
  int bestScore = -1 << 30;
  for (final c in ctx.legal) {
    int score = 0;
    if (ctx.trump != null && c.suit == ctx.trump) score -= 100;
    if (ctx.isMaster(c)) score -= 80;
    final suitCards = ctx.suitCards(c.suit);
    // Keep guards: penalize discards that reduce a suit holding an honor
    // below the length needed to protect it.
    final top = suitCards.isEmpty ? null : suitCards.first;
    if (top != null && _honorRanks.contains(top.rank) && !ctx.isMaster(top)) {
      final guardsNeeded = Rank.ace.index - top.rank.index;
      if (suitCards.length - 1 <= guardsNeeded) score -= 40;
    }
    // Prefer low cards from long, weak suits.
    score -= c.rank.index * 2;
    score += suitCards.length;
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return best ?? minCardByRank(ctx.legal);
}
