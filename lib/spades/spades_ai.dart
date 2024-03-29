import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/spades/spades.dart';
import 'package:cards_with_cats/spades/spades.dart' as spades;

const debugOutput = false;

void printd(String msg) {
  if (debugOutput) print(msg);
}

class BidRequest {
  final SpadesRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<int> otherBids;
  final List<PlayingCard> hand;

  BidRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.otherBids,
    required this.hand,
  });
}

class CardToPlayRequest {
  final SpadesRuleSet rules;
  final List<int> scoresBeforeRound;
  final List<PlayingCard> hand;
  final List<Trick> previousTricks;
  final TrickInProgress currentTrick;
  final List<int> bids;

  CardToPlayRequest({
    required this.rules,
    required this.scoresBeforeRound,
    required this.hand,
    required this.previousTricks,
    required this.currentTrick,
    required this.bids,
  });

  static CardToPlayRequest fromRound(final SpadesRound round) => CardToPlayRequest(
        rules: round.rules.copy(),
        scoresBeforeRound: List.from(round.initialScores),
        hand: List.from(round.currentPlayer().hand),
        previousTricks: Trick.copyAll(round.previousTricks),
        currentTrick: round.currentTrick.copy(),
        bids: [...round.players.map((p) => p.bid!)],
      );

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % rules.numPlayers;
  }

  List<PlayingCard> legalPlays() {
    return spades.legalPlays(hand, currentTrick, previousTricks, rules);
  }

  bool hasCardBeenPlayed(final PlayingCard card) {
    if (currentTrick.cards.contains(card)) {
      return true;
    }
    for (final t in previousTricks) {
      if (t.cards.contains(card)) {
        return true;
      }
    }
    return false;
  }

  bool isCardKnown(final PlayingCard card) {
    return hand.contains(card) || hasCardBeenPlayed(card);
  }
}

double _estimatedTricksForNonspades(List<Rank> ranks) {
  if (ranks.isEmpty) {
    return 0;
  }
  if (ranks.length == 1) {
    switch (ranks[0]) {
      case Rank.ace:
        return 1;
      case Rank.king:
        return 0.6;
      case Rank.queen:
        return 0.2;
      default:
        return 0;
    }
  }
  double scale = ranks.length < 3 ? 1.0 : (1.0 - 0.1 * (ranks.length - 3));
  switch (ranks[0]) {
    case Rank.ace:
      switch (ranks[1]) {
        case Rank.king:
          return 2 * scale;
        case Rank.queen:
          return 1.7 * scale;
        case Rank.jack:
          return 1.3 * scale;
        default:
          return 1 * scale;
      }
    case Rank.king:
      switch (ranks[1]) {
        case Rank.queen:
          return 1.1 * scale;
        case Rank.jack:
          return 0.8 * scale;
        default:
          return 0.6 * scale;
      }
    case Rank.queen:
      return 0.3 * scale;
    default:
      return 0;
  }
}

double _estimatedTricksForSpades(List<Rank> ranks) {
  if (ranks.isEmpty) {
    return 0;
  }
  // Look at gaps for first 3 spades, assume 4th spade and beyond are good.
  int gaps = 0;
  int numRanksToCheck = min(3, ranks.length);
  int previousTopRankIndex = Rank.ace.index + 1;
  double gapPenalty = 0;
  for (int i = 0; i < numRanksToCheck; i++) {
    gaps += previousTopRankIndex - ranks[i].index - 1;
    gapPenalty += (gaps == 0)
        ? 0
        : (gaps == 1)
            ? 0.4
            : (gaps == 2)
                ? 0.8
                : 1;
    previousTopRankIndex = ranks[i].index;
  }
  return ranks.length - gapPenalty;
}

bool _canBidNilSpades(List<Rank> ranks) {
  if (ranks.isEmpty) {
    return true;
  }
  if (ranks.length > 3) {
    return false;
  }
  if (ranks[0].index > Rank.ten.index) {
    return false;
  }
  return true;
}

bool _canBidNilNonSpades(List<Rank> ranks) {
  if (ranks.isEmpty) {
    return true;
  }
  if (ranks[0].index < Rank.ten.index) {
    return true;
  }
  int rankCount = ranks.length;
  /* The goal is to determine whether, even if the suit could potentially take
    one or more tricks, it is reasonably safe to bid nil anyhow. The thought
    being that gaining 100 points from a nil bid is better than only gaining 10
    or 20 points by not bidding nil. If a hand does have one or more high cards
    (Jack or higher) but there are enough low-enough rank cards in the suit to
    run the other players out of the suit before needing to play the high card(s)
    then bidding nil should be a safe, and even desirable, course of action. */

  // If there are any high cards then there needs to be at least 4 cards of the suit.
  if (ranks[0].index > Rank.ten.index && rankCount < 4) {
    return false;
  }
  // If there are multiple high cards then there needs to be at least 5 cards of the suit.
  if (rankCount > 1 && ranks[1].index > Rank.ten.index && rankCount < 5) {
    return false;
  }
  // If there is an ace then there needs to be at least 5 cards of the suit
  if (ranks[0].index == Rank.ace.index && rankCount < 5) {
    return false;
  }

  double rankSum = 0;
  for (int i = 0; i < rankCount; i++) {
    rankSum += ranks[i].index + 2;
  }
  double aveRank = rankSum / rankCount ;
  /* 8.0 seems to be a sweet spot. Setting the average too low and the player
    will almost never make an intentional nil bid and setting the average too
    high results in more instances of failing to realize the nil bid. */
  if (aveRank < 8.0) {
    return true;
  }

  return false;
}

int chooseBid(BidRequest req) {
  List<Rank> srSpades = sortedRanksInSuit(req.hand, Suit.spades);
  List<Rank> srHearts = sortedRanksInSuit(req.hand, Suit.hearts);
  List<Rank> srDiamonds = sortedRanksInSuit(req.hand, Suit.diamonds);
  List<Rank> srClubs = sortedRanksInSuit(req.hand, Suit.clubs);

  // Check first to see if the player can safely bid nil.
  bool cbnS = _canBidNilSpades(srSpades);
  bool canBidNil = cbnS
      && _canBidNilNonSpades(srHearts)
      && _canBidNilNonSpades(srDiamonds)
      && _canBidNilNonSpades(srClubs);
  if ( canBidNil ) {
    return 0;
  }

  // Get the estimated tricks for each suit.
  double estimatedTricks = _estimatedTricksForSpades(srSpades)
      + _estimatedTricksForNonspades(srHearts)
      + _estimatedTricksForNonspades(srDiamonds)
      + _estimatedTricksForNonspades(srClubs);
  int bid = estimatedTricks.round();

  if (bid == 0) {
    // If it isn't considered safe to bid nil for spades then bid 1.
    if (!cbnS) {
      return 1;
    }
    return 0;
  }

  // If this is the last bid and sum of bids is low, increase bid by up to 2.
  if (req.otherBids.length == req.rules.numPlayers - 1) {
    final sumOfBids = bid + req.otherBids.reduce((a, b) => a + b);
    int diff = req.rules.numberOfCardsPerPlayer - sumOfBids;
    if (diff > 2) {
      bid += (diff == 3) ? 1 : 2;
    }
  }
  return bid;
}

// Returns the estimated probability of the player at `player_index` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int teamIndex, SpadesRuleSet rules) {
  int maxScore = scores.reduce(max);
  // We're arbitrarily defining the "target" score as the match limit plus 50.
  int target = max(rules.pointLimit, (maxScore ~/ 10) * 10) + 50;
  // equity is 1 - (my distance to target) / (sum of all distances to target)
  // Distance is penalized by number of bags, quadratically. (Going from 1 to 2
  // bags is less bad than going from 7 to 8. Max penalty is 0.5*9*9 = 40.5).
  final distances = scores.map((s) {
    final bags = s % 10;
    return target - (s - bags - 0.5 * bags * bags);
  }).toList();
  final distSum = distances.reduce((a, b) => a + b);
  return 1 - (distances[teamIndex] / distSum);
}

PlayingCard chooseCardRandom(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  return legalPlays[rng.nextInt(legalPlays.length)];
}

PlayingCard _lowDiscard(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  bool anySpades = false;
  bool allSpades = true;
  for (int i = 0; i < legalPlays.length; i++) {
    if (legalPlays[i].suit == Suit.spades) {
      anySpades = true;
    } else {
      allSpades = false;
    }
  }
  if (allSpades || !anySpades) {
    return minCardByRank(legalPlays);
  } else {
    return minCardByRank([...legalPlays.where((c) => c.suit != Suit.spades)]);
  }
}

PlayingCard _highDiscard(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  bool anySpades = false;
  bool allSpades = true;
  for (int i = 0; i < legalPlays.length; i++) {
    if (legalPlays[i].suit == Suit.spades) {
      anySpades = true;
    } else {
      allSpades = false;
    }
  }
  if (allSpades || !anySpades) {
    return maxCardByRank(legalPlays);
  } else {
    return maxCardByRank([...legalPlays.where((c) => c.suit != Suit.spades)]);
  }
}

PlayingCard _avoidTakingTrick(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  final ct = req.currentTrick;
  if (ct.cards.isEmpty) {
    return chooseCardRandom(req, rng);
  }
  final highCard = ct.cards[trickWinnerIndex(ct.cards)];
  if (legalPlays.every((c) => c.suit == highCard.suit)) {
    PlayingCard? lowestAbove;
    PlayingCard? highestBelow;
    for (final c in legalPlays) {
      if (c.rank.isHigherThan(highCard.rank)) {
        if (lowestAbove == null || c.rank.isLowerThan(lowestAbove.rank)) {
          lowestAbove = c;
        }
      } else {
        if (highestBelow == null || c.rank.isHigherThan(highestBelow.rank)) {
          highestBelow = c;
        }
      }
    }
    return highestBelow ?? lowestAbove!;
  } else if (highCard.suit == Suit.spades) {
    PlayingCard? bestLowerSpade;
    for (final c in legalPlays) {
      if (c.suit == Suit.spades && c.rank.isLowerThan(highCard.rank)) {
        if (bestLowerSpade == null || bestLowerSpade.rank.isLowerThan(c.rank)) {
          bestLowerSpade = c;
        }
      }
    }
    return bestLowerSpade ?? _highDiscard(req, legalPlays, rng);
  } else {
    return _highDiscard(req, legalPlays, rng);
  }
}

PlayingCard _coverPartnerNil(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  final ct = req.currentTrick;
  if (ct.cards.isEmpty) {
    // TODO
    return chooseCardRandom(req, rng);
  }
  final highCard = ct.cards[trickWinnerIndex(ct.cards)];
  if (ct.cards.length == 1) {
    if (legalPlays[0].suit == highCard.suit) {
      // Following suit, go as high as possible so partner can play under.
      final maxCard = maxCardByRank(legalPlays);
      return maxCard.rank.isHigherThan(highCard.rank) ? maxCard : minCardByRank(legalPlays);
    }
  }
  return _lowestWinnerOrLowest(req, legalPlays, highCard, rng);
}

PlayingCard _highestIfCanWinOrLowest(List<PlayingCard> legalPlays, PlayingCard currentHigh) {
  var maxCard = maxCardByRank(legalPlays);
  return maxCard.rank.isHigherThan(currentHigh.rank) ? maxCard : minCardByRank(legalPlays);
}

PlayingCard _lowestWinnerOrLowest(
    CardToPlayRequest req, List<PlayingCard> legalPlays, PlayingCard highCard, Random rng) {
  if (highCard.suit == Suit.spades) {
    final higherSpades =
        legalPlays.where((c) => c.suit == Suit.spades && c.rank.isHigherThan(highCard.rank));
    if (higherSpades.isNotEmpty) {
      return minCardByRank([...higherSpades]);
    }
  } else {
    if (legalPlays[0].suit == highCard.suit) {
      // legalPlays should all be same suit.
      final higherInSuit = legalPlays.where((c) => c.rank.isHigherThan(highCard.rank));
      if (higherInSuit.isNotEmpty) {
        return minCardByRank([...higherInSuit]);
      }
    } else {
      final spades = legalPlays.where((c) => c.suit == Suit.spades);
      if (spades.isNotEmpty) {
        return minCardByRank([...spades]);
      }
    }
  }
  return _lowDiscard(req, legalPlays, rng);
}

PlayingCard _abovePartnerIfPossible(
    CardToPlayRequest req, PlayingCard partnerCard, List<PlayingCard> legalPlays, Random rng) {
  // Find the first "gap" above partner's card, e.g. if partner played 8, 10 was previously played,
  // and 9 is in hand, then J is the first gap and we only want to play Q or higher.
  PlayingCard firstGap = partnerCard;
  while (firstGap.rank != Rank.ace && req.isCardKnown(firstGap)) {
    firstGap = PlayingCard(Rank.values[firstGap.rank.index + 1], firstGap.suit);
  }
  var maxCard = maxCardByRank(legalPlays);
  return maxCard.rank.isHigherThan(firstGap.rank) ? maxCard : minCardByRank(legalPlays);
}

bool _areAllHigherCardsKnown(CardToPlayRequest req, PlayingCard card) {
  var rank = Rank.ace;
  while (rank != card.rank) {
    if (!req.isCardKnown(PlayingCard(rank, card.suit))) {
      return false;
    }
    rank = Rank.values[rank.index - 1];
  }
  return true;
}

PlayingCard _trumpOverPartnerIfUseful(
    CardToPlayRequest req, PlayingCard partnerCard, List<PlayingCard> legalPlays, Random rng) {
  final spades = sortedCardsInSuit(legalPlays, Suit.spades);
  if (spades.isNotEmpty) {
    // We can trump, but should we? Probably not if partner's card is
    // high or if our trump is high.
    if (!_areAllHigherCardsKnown(req, partnerCard) && !_areAllHigherCardsKnown(req, spades.last)) {
      return spades.last;
    }
  }
  return _lowDiscard(req, legalPlays, rng);
}

PlayingCard _maximizeTricksCard3(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  // Beat the opponent's card if higher.
  // This assumes partners.
  final tc = req.currentTrick.cards;
  if (trickWinnerIndex(tc, trump: Suit.spades) == 1) {
    // Trump as low as possible, non-trump as high as possible.
    if (tc[0].suit == Suit.spades) {
      if (legalPlays[0].suit == Suit.spades) {
        // All legal plays must be spades.
        return _highestIfCanWinOrLowest(legalPlays, tc[1]);
      } else {
        return _lowDiscard(req, legalPlays, rng);
      }
    } else {
      if (legalPlays[0].suit == tc[0].suit) {
        // We have to follow suit. If opponent trumped then go low.
        if (tc[1].suit == Suit.spades) {
          return minCardByRank(legalPlays);
        } else {
          return _highestIfCanWinOrLowest(legalPlays, tc[1]);
        }
      } else {
        final spades = sortedCardsInSuit(legalPlays, Suit.spades);
        if (spades.isEmpty) {
          return _lowDiscard(req, legalPlays, rng);
        }
        if (tc[1].suit == tc[0].suit) {
          // Trump low.
          return spades.last;
        } else {
          assert(tc[1].suit == Suit.spades);
          if (spades.isNotEmpty && spades[0].rank.index > tc[1].rank.index) {
            // Overtrump as low as needed to be highest.
            for (final c in spades.reversed) {
              if (c.rank.index > tc[1].rank.index) {
                return c;
              }
            }
          } else {
            // Can't win.
            return _lowDiscard(req, legalPlays, rng);
          }
        }
      }
    }
  } else {
    // Partner has high card, go higher if possible or trump low.
    if (legalPlays[0].suit == tc[0].suit) {
      // Following suit, go higher if useful.
      return _abovePartnerIfPossible(req, tc[0], legalPlays, rng);
    } else {
      return _trumpOverPartnerIfUseful(req, tc[0], legalPlays, rng);
    }
  }
  return chooseCardRandom(req, rng);
}

PlayingCard _maximizeTricksCard4(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  final tc = req.currentTrick.cards;
  int leader = trickWinnerIndex(tc, trump: Suit.spades);
  if (leader == 1) {
    // Partner is winning.
    return _lowDiscard(req, legalPlays, rng);
  } else {
    return _lowestWinnerOrLowest(req, legalPlays, tc[leader], rng);
  }
}

PlayingCard _maximizeTricks(CardToPlayRequest req, List<PlayingCard> legalPlays, Random rng) {
  final tc = req.currentTrick.cards;
  switch (tc.length) {
    case 0:
      // TODO
      return chooseCardRandom(req, rng);
    case 1:
      // Play over leader if possible, but as low as possible?
      return _lowestWinnerOrLowest(req, legalPlays, tc[0], rng);
    case 2:
      return _maximizeTricksCard3(req, legalPlays, rng);
    case 3:
      return _maximizeTricksCard4(req, legalPlays, rng);
  }
  // TODO
  return chooseCardRandom(req, rng);
}

int numTopSpadesInHand(final CardToPlayRequest req) {
  int numTop = 0;
  var spade = PlayingCard(Rank.ace, Suit.spades);
  while (true) {
    if (req.hand.contains(spade)) {
      numTop += 1;
    }
    if (!req.hasCardBeenPlayed(spade) || spade.rank.index == 0) {
      break;
    }
    spade = PlayingCard(Rank.values[spade.rank.index - 1], Suit.spades);
  }
  return numTop;
}

bool _shouldAvoidOvertricks(final CardToPlayRequest req) {
  int pIndex = req.currentPlayerIndex();
  // Assumes 2v2.
  int partnerIndex = (pIndex + 2) % 4;
  int teamTricks = 0;
  for (final t in req.previousTricks) {
    if (t.winner == pIndex || t.winner == partnerIndex) {
      teamTricks += 1;
    }
  }
  teamTricks += numTopSpadesInHand(req);
  int teamBid = req.bids[pIndex] + req.bids[partnerIndex];
  if (teamTricks < teamBid) {
    return false;
  }
  int oppTricks = req.previousTricks.length - teamTricks;
  int oppBid = req.bids[(pIndex + 1) % 4] + req.bids[(pIndex + 3) % 4];
  if (oppTricks >= oppBid) {
    return true;
  }
  int neededToSet = req.rules.numberOfCardsPerPlayer - oppBid + 1;
  if (teamTricks >= neededToSet) {
    return true;
  }
  return false;
}

PlayingCard chooseCardToMakeBids(final CardToPlayRequest req, Random rng) {
  final legalPlays = req.legalPlays();
  assert(legalPlays.isNotEmpty);
  if (legalPlays.length == 1) {
    return legalPlays[0];
  }
  int pIndex = req.currentPlayerIndex();
  if (req.bids[pIndex] == 0) {
    return _avoidTakingTrick(req, legalPlays, rng);
  }
  // Assumes 2v2.
  int partnerIndex = (pIndex + 2) % 4;
  if (req.bids[partnerIndex] == 0) {
    return _coverPartnerNil(req, legalPlays, rng);
  }
  if (_shouldAvoidOvertricks(req)) {
    return _avoidTakingTrick(req, legalPlays, rng);
  }
  return _maximizeTricks(req, legalPlays, rng);
}

typedef ChooseCardFn = PlayingCard Function(CardToPlayRequest req, Random rng);

CardDistributionRequest makeCardDistributionRequest(final CardToPlayRequest req) {
  final numPlayers = req.rules.numPlayers;
  final seenCards = Set.from(req.hand);
  final voidedSuits = List.generate(numPlayers, (_) => Set<Suit>());

  var spadesBroken = false;

  void processTrick(List<PlayingCard> cards, int leader) {
    final trickSuit = cards[0].suit;
    if (!spadesBroken && trickSuit == Suit.spades) {
      spadesBroken = true;
      if (req.rules.spadeLeading == SpadeLeading.after_broken) {
        // Led spades when they weren't broken, so must have had no other choice.
        voidedSuits[leader].addAll([Suit.hearts, Suit.diamonds, Suit.clubs]);
      }
    }
    seenCards.add(cards[0]);
    for (int i = 1; i < cards.length; i++) {
      final c = cards[i];
      seenCards.add(c);
      if (c.suit != trickSuit) {
        voidedSuits[(leader + i) % numPlayers].add(trickSuit);
      }
      if (c.suit == Suit.spades) {
        spadesBroken = true;
      }
    }
  }

  for (final t in req.previousTricks) {
    processTrick(t.cards, t.leader);
  }
  if (req.currentTrick.cards.isNotEmpty) {
    processTrick(req.currentTrick.cards, req.currentTrick.leader);
  }

  final baseNumCards = req.rules.numberOfCardsPerPlayer - req.previousTricks.length;
  final cardCounts = List.generate(numPlayers, (_n) => baseNumCards);
  for (int i = 0; i < req.currentTrick.cards.length; i++) {
    final pi = (req.currentTrick.leader + i) % numPlayers;
    cardCounts[pi] -= 1;
  }
  cardCounts[req.currentPlayerIndex()] = 0;

  final constraints = List.generate(
      numPlayers,
      (pnum) => CardDistributionConstraint(
            numCards: cardCounts[pnum],
            voidedSuits: voidedSuits[pnum].toList(),
            fixedCards: [],
          ));
  final Set<PlayingCard> cardsToAssign = Set.from(standardDeckCards());
  cardsToAssign.removeAll(seenCards);
  cardsToAssign.removeAll(req.rules.removedCards);
  return CardDistributionRequest(cardsToAssign: cardsToAssign.toList(), constraints: constraints);
}

SpadesRound? possibleRound(CardToPlayRequest cardReq, CardDistributionRequest distReq, Random rng) {
  final dist = possibleCardDistribution(distReq, rng);
  if (dist == null) {
    return null;
  }
  final currentPlayer = cardReq.currentPlayerIndex();
  final resultPlayers = List.generate(cardReq.rules.numPlayers,
      (i) => SpadesPlayer(i == currentPlayer ? cardReq.hand : dist[i])..bid = cardReq.bids[i]);
  return SpadesRound()
    ..rules = cardReq.rules.copy()
    ..players = resultPlayers
    ..initialScores = List.of(cardReq.scoresBeforeRound)
    ..currentTrick = cardReq.currentTrick.copy()
    ..previousTricks = Trick.copyAll(cardReq.previousTricks)
    ..status = SpadesRoundStatus.playing
    ..dealer = 0;
}

List<PlayingCard> cardsToConsiderPlaying(CardToPlayRequest req, Random rng) {
  // For testing with and without this feature.
  // It possibly makes the AI slightly worse: with rounds=30, rollouts=30,
  // the team that had this feature disabled won 517 out of 1000. Could be
  // within random chance (stdev=sqrt(1000*.5*.5)=15.8).
  if (req.currentPlayerIndex() % 2 == 0) return req.legalPlays();

  final legalPlays = req.legalPlays();
  // Choose one card at random from each group of identical cards.
  final groups = groupsOfEffectivelyIdenticalCards(legalPlays, req.previousTricks);
  final result = groups.map((g) => g[rng.nextInt(g.length)]).toList();
  if (legalPlays.length != result.length) {
    printd("Reduced ${legalPlays.length} choices to ${result.length}");
  }
  return result;
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
      print("MC failed to generate round, falling back to default");
      final bestCard = chooseCardToMakeBids(cardReq, rng);
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
        final pointsForRound = rolloutRound.pointsTaken();
        final scoresAfterRound = pointsForRound.map((p) => p.endingMatchPoints).toList();
        playEquities[ci] +=
            matchEquityForScores(scoresAfterRound, pnum % cardReq.rules.numTeams, cardReq.rules);
        numRollouts += 1;
        numRolloutCardsPlayed += cardsPerRollout;
      }
    }
    numRounds += 1;
    if (mcParams.maxTimeMillis != null && timeFn() - startTime >= mcParams.maxTimeMillis!) {
      break;
    }
  }
  int bestIndex = 0;
  for (int i = 1; i < legalPlays.length; i++) {
    if (playEquities[i] > playEquities[bestIndex]) {
      bestIndex = i;
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

void doRollout(SpadesRound round, ChooseCardFn chooseFn, Random rng) {
  final bids = [...round.players.map((p) => p.bid!)];
  while (!round.isOver()) {
    // CardToPlayRequest.fromRound makes deep copies of HeartsRound fields,
    // which is safe but expensive. Here we can just copy the references,
    // because we know the round won't be modified during the lifetime of `req`.
    // This is around a 2x speedup.
    final req = CardToPlayRequest(
      rules: round.rules,
      scoresBeforeRound: round.initialScores,
      hand: round.currentPlayer().hand,
      previousTricks: round.previousTricks,
      currentTrick: round.currentTrick,
      bids: bids,
    );
    final cardToPlay = chooseFn(req, rng);
    round.playCard(cardToPlay);
  }
}
