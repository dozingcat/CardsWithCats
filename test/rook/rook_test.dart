import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/trick.dart";
import "package:cards_with_cats/rook/rook.dart";
import "package:cards_with_cats/rook/rook_ai.dart";

const c = PlayingCard.cardsFromString;

TrickInProgress<PlayingCard> trick(int leader, String cards) => TrickInProgress(leader, c(cards));

// Returns a round in the playing state with the given hands, without going
// through bidding.
RookRound playingRound(List<String> hands, {Suit trump = Suit.spades, int declarer = 0, int bid = 70, int dealer = 3}) {
  return RookRound()
    ..rules = RookRuleSet()
    ..initialScores = [0, 0]
    ..players = [...hands.map((h) => RookPlayer(c(h)))]
    ..dealer = dealer
    ..status = RookRoundStatus.playing
    ..contract = Contract(declarer: declarer, bid: bid, trump: trump)
    ..currentTrick = TrickInProgress((dealer + 1) % numPlayers);
}

void main() {
  test("Deck", () {
    final deck = rookDeckCards();
    expect(deck.length, 41);
    expect(deck.toSet().length, 41);
    expect(pointsForCards(deck, RookRuleSet()), 120);
  });

  group("Legal plays", () {
    const trump = Suit.spades;

    test("Any card can be led", () {
      final hand = c("5H 9S JOKER1");
      expect(legalPlays(hand, trick(0, ""), trump), hand);
    });

    test("Must follow suit, but the joker can always be played", () {
      expect(legalPlays(c("5H 9H 9S JOKER1"), trick(0, "TH"), trump), c("5H 9H JOKER1"));
      expect(legalPlays(c("5H 9H 9S"), trick(0, "TH"), trump), c("5H 9H"));
    });

    test("Any card if void in the led suit", () {
      final hand = c("5D 9S JOKER1");
      expect(legalPlays(hand, trick(0, "TH"), trump), hand);
    });

    test("Must play trump if the joker is led", () {
      expect(legalPlays(c("5H 9S AS"), trick(0, "JOKER1"), trump), c("9S AS"));
      expect(legalPlays(c("5H 9D"), trick(0, "JOKER1"), trump), c("5H 9D"));
    });

    test("Must play the joker if trump is led and it's the only trump", () {
      expect(legalPlays(c("5H 9D JOKER1"), trick(0, "TS"), trump), c("JOKER1"));
      expect(legalPlays(c("5H 9S JOKER1"), trick(0, "TS"), trump), c("9S JOKER1"));
    });
  });

  group("Trick winner", () {
    int winner(String cards, Suit trump) => trick(0, cards).finish(trump: trump, winnerFn: rookTrickWinnerIndex).winner;

    test("Highest card of led suit", () {
      expect(winner("TH AH 5D 9H", Suit.spades), 1);
    });

    test("Trump beats led suit", () {
      expect(winner("TH AH 5S 6S", Suit.spades), 3);
    });

    test("Joker beats everything", () {
      expect(winner("AS JOKER1 KS QS", Suit.spades), 1);
      expect(winner("TH AH JOKER1 6S", Suit.spades), 2);
      expect(winner("JOKER1 AS KS QS", Suit.spades), 0);
    });
  });

  group("Bidding", () {
    late RookRound round;

    setUp(() {
      round = RookRound.deal(rules: RookRuleSet(), scores: [0, 0], dealer: 3, rng: Random(17));
    });

    test("Deal", () {
      expect(round.players.map((p) => p.hand.length), [9, 9, 9, 9]);
      expect(round.initialNest.length, 5);
      expect(round.currentTrick.leader, 0);
    });

    test("Bid validation", () {
      expect(round.canCurrentBidderMakeBid(65), false);
      expect(round.canCurrentBidderMakeBid(72), false);
      expect(round.canCurrentBidderMakeBid(125), false);
      expect(round.canCurrentBidderMakeBid(70), true);
      expect(round.canCurrentBidderMakeBid(120), true);
      expect(round.canCurrentBidderMakeBid(null), true);
      round.addBid(PlayerBid(0, 80));
      expect(round.canCurrentBidderMakeBid(80), false);
      expect(round.canCurrentBidderMakeBid(85), true);
      expect(() => round.addBid(PlayerBid(1, 75)), throwsException);
      expect(() => round.addBid(PlayerBid(2, 85)), throwsException);
    });

    test("Starts left of dealer and skips players who passed", () {
      expect(round.currentBidder(), 0);
      round.addBid(PlayerBid(0, 70));
      round.addBid(PlayerBid.pass(1));
      round.addBid(PlayerBid(2, 75));
      round.addBid(PlayerBid(3, 80));
      expect(round.currentBidder(), 0);
      round.addBid(PlayerBid(0, 85));
      expect(round.currentBidder(), 2);
      round.addBid(PlayerBid.pass(2));
      expect(round.status, RookRoundStatus.bidding);
      round.addBid(PlayerBid.pass(3));
      expect(round.status, RookRoundStatus.declarerChoosingCardsAndTrump);
      expect(round.declarer(), 0);
      expect(round.winningBid().bid, 85);
    });

    test("Maximum bid ends bidding", () {
      round.addBid(PlayerBid(0, 70));
      round.addBid(PlayerBid(1, 120));
      expect(round.status, RookRoundStatus.declarerChoosingCardsAndTrump);
      expect(round.declarer(), 1);
    });

    test("Last player can bid after three passes", () {
      round.addBid(PlayerBid.pass(0));
      round.addBid(PlayerBid.pass(1));
      round.addBid(PlayerBid.pass(2));
      expect(round.status, RookRoundStatus.bidding);
      round.addBid(PlayerBid(3, 70));
      expect(round.status, RookRoundStatus.declarerChoosingCardsAndTrump);
      expect(round.declarer(), 3);
    });

    test("Passed out", () {
      for (int p in [0, 1, 2, 3]) {
        round.addBid(PlayerBid.pass(p));
      }
      expect(round.isPassedOut(), true);
      expect(round.isOver(), true);
      expect(round.status, RookRoundStatus.bidding);
    });
  });

  group("Discarding", () {
    RookRound roundWithDeclarer(RookRuleSet rules, String hand, String nest) {
      final round = RookRound.deal(rules: rules, scores: [0, 0], dealer: 3, rng: Random(1));
      round.players[0].hand = c(hand);
      round.initialNest = c(nest);
      round.addBid(PlayerBid(0, 70));
      for (int p in [1, 2, 3]) {
        round.addBid(PlayerBid.pass(p));
      }
      return round;
    }

    test("Discard and choose trump", () {
      final round = roundWithDeclarer(RookRuleSet(), "5S 6S 7S 8S 9S JS QS KS AS", "5H 6H 7H 8H JOKER1");
      final discards = c("5H 6H 7H 8H 6S").toSet();
      round.discardAndChooseTrump(discards, Suit.spades);
      expect(round.status, RookRoundStatus.playing);
      expect(round.contract!.trump, Suit.spades);
      expect(round.contract!.bid, 70);
      expect(round.contract!.declarer, 0);
      expect(round.players[0].hand.toSet(), c("5S 7S 8S 9S JS QS KS AS JOKER1").toSet());
      expect(round.finalNest.toSet(), discards);
      expect(round.currentTrick.leader, 0);
    });

    test("Invalid discards", () {
      final round = roundWithDeclarer(RookRuleSet(), "5S 6S 7S 8S 9S JS QS KS AS", "5H 6H 7H 8H JOKER1");
      // Wrong number of cards.
      expect(() => round.discardAndChooseTrump(c("5H 6H 7H 8H").toSet(), Suit.spades), throwsException);
      // Card not in hand or nest.
      expect(() => round.discardAndChooseTrump(c("5H 6H 7H 8H 9H").toSet(), Suit.spades), throwsException);
    });

    test("Point cards can be discarded by default", () {
      final round = roundWithDeclarer(RookRuleSet(), "5S 6S 7S 8S 9S JS QS KS AS", "5H 6H 7H 8H JOKER1");
      expect(round.isValidDiscardForDeclarer(c("JOKER1 AS 5S 5H 6H").toSet()), true);
    });

    test("Point cards can't be discarded if disallowed", () {
      final rules = RookRuleSet(allowDiscardingPointCards: false);
      final round = roundWithDeclarer(rules, "5S 6S 7S 8S 9S JS QS KS AS", "5H 6H 7H 8H JOKER1");
      expect(round.isValidDiscardForDeclarer(c("JOKER1 6S 7S 6H 7H").toSet()), false);
      expect(round.isValidDiscardForDeclarer(c("5S 6S 7S 6H 7H").toSet()), false);
      expect(round.isValidDiscardForDeclarer(c("8S 6S 7S 6H 7H").toSet()), true);
    });

    test("Point cards must be discarded if there aren't enough other cards", () {
      final rules = RookRuleSet(allowDiscardingPointCards: false);
      // 11 point cards and 3 non-point cards, so 2 point cards must be discarded.
      final round = roundWithDeclarer(rules, "5S 5H 5D 5C TS TH TD TC 6S", "AS AH AD 7S 8S");
      expect(round.isValidDiscardForDeclarer(c("6S 7S 8S 5S 5H").toSet()), true);
      expect(round.isValidDiscardForDeclarer(c("6S 7S 5C 5S 5H").toSet()), false);
    });
  });

  group("Playing and scoring", () {
    test("Play tricks and score", () {
      final round = playingRound([
        "AS 5H",
        "KS TH",
        "QS JOKER1",
        "JS AH",
      ], trump: Suit.spades, declarer: 0, bid: 70);
      round.finalNest = c("5D TD");
      expect(round.currentPlayerIndex(), 0);
      expect(() => round.playCard(c("5H")[0]), returnsNormally);
      // Must follow hearts or play joker.
      expect(round.legalPlaysForCurrentPlayer(), c("TH"));
      expect(() => round.playCard(c("KS")[0]), throwsException);
      round.playCard(c("TH")[0]);
      expect(round.legalPlaysForCurrentPlayer(), c("QS JOKER1"));
      round.playCard(c("JOKER1")[0]);
      round.playCard(c("AH")[0]);
      expect(round.previousTricks.last.winner, 2);
      expect(round.currentTrick.leader, 2);
      round.playCard(c("QS")[0]);
      round.playCard(c("JS")[0]);
      round.playCard(c("AS")[0]);
      round.playCard(c("KS")[0]);
      expect(round.isOver(), true);
      expect(round.previousTricks.last.winner, 0);
      // Team 0 took 5H TH JOKER1 AH (45) in the first trick, AS (10) in the
      // second, and the nest (15). Exactly the bid of 70.
      expect(round.teamPointsTaken(), [70, 0]);
      expect(round.contractScoresForTeams(), [70, 0]);
    });

    test("Declarer team set", () {
      final round = playingRound(["AS", "KS", "QS", "JS"], declarer: 1, bid: 70);
      round.finalNest = c("5D");
      for (final card in ["AS", "KS", "QS", "JS"]) {
        round.playCard(c(card)[0]);
      }
      expect(round.teamPointsTaken(), [15, 0]);
      expect(round.contractScoresForTeams(), [15, -70]);
    });
  });

  group("Match", () {
    void playRandomRound(RookMatch match, Random rng, {bool allPass = false}) {
      final round = match.currentRound;
      if (allPass) {
        while (round.status == RookRoundStatus.bidding && !round.isPassedOut()) {
          round.addBid(PlayerBid.pass(round.currentBidder()));
        }
        return;
      }
      round.addBid(PlayerBid(round.currentBidder(), 70));
      while (round.status == RookRoundStatus.bidding) {
        round.addBid(PlayerBid.pass(round.currentBidder()));
      }
      // Discard the cards with the fewest points, so the discards are valid
      // even if point cards can't be discarded.
      final available = round.declarerAvailableCards()..shuffle(rng);
      available.sort((a, b) => pointsForCard(a, round.rules) - pointsForCard(b, round.rules));
      round.discardAndChooseTrump(available.take(numNestCards).toSet(), Suit.values[rng.nextInt(4)]);
      while (!round.isOver()) {
        final plays = round.legalPlaysForCurrentPlayer();
        round.playCard(plays[rng.nextInt(plays.length)]);
      }
    }

    test("Passed out round is redealt by the same dealer", () {
      final rng = Random(5);
      final match = RookMatch(RookRuleSet(), rng);
      final dealer = match.dealer;
      final originalHands = match.currentRound.players.map((p) => p.hand).toList();
      playRandomRound(match, rng, allPass: true);
      match.finishRound();
      expect(match.previousRounds, isEmpty);
      expect(match.dealer, dealer);
      expect(match.currentRound.dealer, dealer);
      expect(match.currentRound.status, RookRoundStatus.bidding);
      expect(match.currentRound.players.map((p) => p.hand).toList(), isNot(originalHands));
      expect(match.scores, [0, 0]);
    });

    test("Random match plays to completion", () {
      final rng = Random(11);
      final match = RookMatch(RookRuleSet(), rng);
      int rounds = 0;
      while (!match.isMatchOver()) {
        final dealer = match.dealer;
        playRandomRound(match, rng);
        final roundScores = match.currentRound.contractScoresForTeams();
        final before = List.of(match.currentRound.initialScores);
        expect(match.scores, [before[0] + roundScores[0], before[1] + roundScores[1]]);
        match.finishRound();
        rounds += 1;
        if (!match.isMatchOver()) {
          expect(match.dealer, (dealer + 1) % numPlayers);
        }
        expect(rounds, lessThan(1000));
      }
      final winner = match.winningTeam()!;
      expect(match.scores[winner], greaterThanOrEqualTo(300));
      expect(match.scores[winner], greaterThan(match.scores[1 - winner]));
    });

    test("JSON round trip", () {
      final rng = Random(3);
      final match = RookMatch(RookRuleSet(allowDiscardingPointCards: false), rng);
      playRandomRound(match, rng);
      match.finishRound();
      final round = match.currentRound;
      round.addBid(PlayerBid(round.currentBidder(), 70));
      final copy = RookMatch.fromJson(match.toJson(), rng);
      expect(copy.toJson(), match.toJson());
      expect(copy.rules.allowDiscardingPointCards, false);
      // The joker should survive serialization wherever it is.
      final allCards = [
        ...copy.previousRounds[0].previousTricks.expand((t) => t.cards),
        ...copy.previousRounds[0].finalNest,
      ];
      expect(allCards.contains(joker), true);
    });
  });

  group("AI", () {
    test("Discards are valid with either discard rule", () {
      for (final allowPoints in [true, false]) {
        final rules = RookRuleSet(allowDiscardingPointCards: allowPoints);
        for (int seed = 0; seed < 50; seed++) {
          final rng = Random(seed);
          final round = RookRound.deal(rules: rules, scores: [0, 0], dealer: 3, rng: rng);
          round.addBid(PlayerBid(0, 70));
          for (int p in [1, 2, 3]) {
            round.addBid(PlayerBid.pass(p));
          }
          final choice = chooseDiscardsAndTrump(round, rng);
          expect(round.isValidDiscardForDeclarer(choice.discards), true);
          round.discardAndChooseTrump(choice.discards, choice.trump);
          while (!round.isOver()) {
            round.playCard(chooseCardRandom(round, rng));
          }
        }
      }
    });

    test("Point cards are discarded when there aren't enough other cards", () {
      final rules = RookRuleSet(allowDiscardingPointCards: false);
      final round = RookRound.deal(rules: rules, scores: [0, 0], dealer: 3, rng: Random(1));
      round.players[0].hand = c("5S 5H 5D 5C TS TH TD TC 6S");
      round.initialNest = c("AS AH AD 7S 8S");
      round.addBid(PlayerBid(0, 70));
      for (int p in [1, 2, 3]) {
        round.addBid(PlayerBid.pass(p));
      }
      final choice = chooseDiscardsAndTrump(round, Random(1));
      expect(round.isValidDiscardForDeclarer(choice.discards), true);
    });

    test("Known voids, including the joker counting as trump", () {
      final round = playingRound([
        "5H 6H JOKER1",
        "TH 7S 8S",
        "9D 9S AS",
        "AH KS 6C",
      ], trump: Suit.spades);
      // Hearts led: P1 follows, P2 shows out (void in hearts), P3 follows.
      round.playCard(c("5H")[0]);
      round.playCard(c("TH")[0]);
      round.playCard(c("9D")[0]);
      round.playCard(c("AH")[0]);
      // P3 leads spades: P0 must play the joker, which doesn't show a void.
      round.playCard(c("KS")[0]);
      round.playCard(c("JOKER1")[0]);
      final voids = knownVoids(round);
      expect(voids[0], isEmpty);
      expect(voids[1], isEmpty);
      expect(voids[2], {Suit.hearts});
      expect(voids[3], isEmpty);
    });

    test("Sampled rounds are consistent with what the player knows", () {
      final rng = Random(3);
      for (int seed = 0; seed < 20; seed++) {
        final round = RookRound.deal(rules: RookRuleSet(), scores: [0, 0], dealer: 3, rng: Random(seed));
        round.addBid(PlayerBid(0, 70));
        for (int p in [1, 2, 3]) {
          round.addBid(PlayerBid.pass(p));
        }
        final choice = chooseDiscardsAndTrump(round, rng);
        round.discardAndChooseTrump(choice.discards, choice.trump);
        for (int i = 0; i < 14; i++) {
          round.playCard(chooseCardHeuristic(round, rng));
        }
        final player = round.currentPlayerIndex();
        final voids = knownVoids(round);
        for (int n = 0; n < 10; n++) {
          final hypo = possibleRoundForPlayer(round, player, rng)!;
          expect(hypo.players[player].hand, round.players[player].hand);
          final allCards = [...hypo.players.expand((p) => p.hand), ...hypo.finalNest, ...playedCards(hypo)];
          expect(allCards.toSet(), rookDeckCards().toSet());
          expect(allCards.length, 41);
          for (int p = 0; p < numPlayers; p++) {
            expect(hypo.players[p].hand.length, round.players[p].hand.length);
            for (final c in hypo.players[p].hand) {
              expect(voids[p].contains(effectiveSuit(c, round.contract!.trump)), false);
            }
          }
          if (player == 0) {
            expect(hypo.finalNest, round.finalNest);
          }
        }
      }
    });

    test("Heuristic and Monte Carlo players make legal plays", () {
      final rng = Random(8);
      final mcParams = RookMonteCarloParams(numDeals: 5);
      for (int seed = 0; seed < 20; seed++) {
        final round = RookRound.deal(rules: RookRuleSet(), scores: [0, 0], dealer: seed % 4, rng: Random(seed));
        while (round.status == RookRoundStatus.bidding && !round.isPassedOut()) {
          final p = round.currentBidder();
          final bid = chooseBid(round, p, rng, RookBidParams(numDeals: 20));
          expect(round.canCurrentBidderMakeBid(bid), true);
          round.addBid(PlayerBid(p, bid));
        }
        if (round.isPassedOut()) continue;
        final choice = chooseDiscardsAndTrump(round, rng);
        round.discardAndChooseTrump(choice.discards, choice.trump);
        while (!round.isOver()) {
          final useMonteCarlo = round.currentPlayerIndex() % 2 == 0;
          final card = useMonteCarlo ? chooseCardMonteCarlo(round, mcParams, rng) : chooseCardHeuristic(round, rng);
          expect(round.legalPlaysForCurrentPlayer(), contains(card));
          round.playCard(card);
        }
      }
    });
  });
}
