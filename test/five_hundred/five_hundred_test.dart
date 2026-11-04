import 'dart:convert';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/five_hundred/five_hundred.dart';
import 'package:cards_with_cats/five_hundred/five_hundred_ai.dart';
import 'package:flutter_test/flutter_test.dart';

List<PlayingCard> c(String s) => PlayingCard.cardsFromString(s);
PlayingCard c1(String s) => PlayingCard.cardFromString(s);

FiveHundredBid bid(String s) {
  final tricks = int.parse(s.substring(0, s.length - (s.endsWith("NT") ? 2 : 1)));
  return FiveHundredBid(tricks, s.endsWith("NT") ? null : Suit.fromChar(s[s.length - 1]));
}

TrickInProgress<PlayingCard> trick(int leader, String cards) => TrickInProgress(leader, c(cards));

void main() {
  test("Deck", () {
    final deck = fiveHundredDeckCards();
    expect(deck.length, 43);
    expect(deck.toSet().length, 43);
    expect(deck, contains(joker));
    expect(deck, containsAll(c("4H 4D 5C 5S AS")));
    expect(deck, isNot(contains(c1("4C"))));
    expect(deck, isNot(contains(c1("4S"))));
    expect(deck.any((c) => c is SuitedCard && c.rank.isLowerThan(.four)), false);
  });

  test("Effective suit", () {
    expect(effectiveSuit(c1("JH"), Suit.hearts), Suit.hearts);
    expect(effectiveSuit(c1("JD"), Suit.hearts), Suit.hearts);
    expect(effectiveSuit(c1("JC"), Suit.hearts), Suit.clubs);
    expect(effectiveSuit(c1("JS"), Suit.clubs), Suit.clubs);
    expect(effectiveSuit(joker, Suit.spades), Suit.spades);
    expect(effectiveSuit(c1("JD"), null), Suit.diamonds);
    expect(effectiveSuit(joker, null), null);
  });

  test("Trick winner", () {
    int winner(String cards, Suit? trump) => fiveHundredTrickWinnerIndex(c(cards), trump: trump);
    // Joker beats everything.
    expect(winner("JH JD JOKER1 AH", Suit.hearts), 2);
    expect(winner("AS KS JOKER1 QS", null), 2);
    // Right bower beats left bower beats ace.
    expect(winner("AH JD JH KH", Suit.hearts), 2);
    expect(winner("AH JD KH QH", Suit.hearts), 1);
    // Left bower is a trump, so it wins on a side suit lead.
    expect(winner("AS KS JD QS", Suit.hearts), 2);
    // Left bower led is a trump lead; the right bower wins it.
    expect(winner("JD AH JH 5H", Suit.hearts), 2);
    // A jack of the other color is a normal card.
    expect(winner("QC JC 5C AH", Suit.hearts), 3);
    expect(winner("QC JC 5C AD", Suit.hearts), 0);
    // No trump: highest of the led suit.
    expect(winner("TD AS QD 4D", null), 2);
    expect(winner("TD JD QD 4D", null), 2);
  });

  test("Legal plays with trump", () {
    // Must follow trump with the left bower or joker if they're the only trumps.
    expect(legalPlays(c("JD AS KC"), trick(0, "5H"), Suit.hearts, null), c("JD"));
    expect(legalPlays(c("JOKER1 AS KC"), trick(0, "5H"), Suit.hearts, null), c("JOKER1"));
    // The left bower can't follow its printed suit.
    expect(legalPlays(c("JD 9C"), trick(0, "5D"), Suit.hearts, null), c("JD 9C"));
    expect(legalPlays(c("JD 9D 9C"), trick(0, "5D"), Suit.hearts, null), c("9D"));
    // Leading the left bower is a trump lead.
    expect(legalPlays(c("9D 6H"), trick(0, "JD"), Suit.hearts, null), c("6H"));
    // The joker can't be played on a side suit if the player can follow.
    expect(legalPlays(c("JOKER1 9C"), trick(0, "5C"), Suit.hearts, null), c("9C"));
    // Leading the joker requires trumps.
    expect(legalPlays(c("9C 7H"), trick(0, "JOKER1"), Suit.hearts, null), c("7H"));
  });

  test("Legal plays in no trump", () {
    // The joker can only be played when void in the led suit.
    expect(legalPlays(c("JOKER1 9C"), trick(0, "5C"), null, null), c("9C"));
    expect(legalPlays(c("JOKER1 9C"), trick(0, "5D"), null, null), c("JOKER1 9C"));
    // Both jacks are normal cards.
    expect(legalPlays(c("JD 9C"), trick(0, "5H"), null, null), c("JD 9C"));
    // When the joker is led, players follow the chosen suit.
    expect(legalPlays(c("9C 7H"), trick(0, "JOKER1"), null, Suit.clubs), c("9C"));
    expect(legalPlays(c("9D 7H"), trick(0, "JOKER1"), null, Suit.clubs), c("9D 7H"));
  });

  test("Bid values and ordering", () {
    expect(bid("6S").value, 40);
    expect(bid("6C").value, 60);
    expect(bid("6D").value, 80);
    expect(bid("6H").value, 100);
    expect(bid("6NT").value, 120);
    expect(bid("7S").value, 140);
    expect(bid("8H").value, 300);
    expect(bid("10NT").value, 520);
    final all = FiveHundredBid.allBids();
    expect(all.length, 25);
    for (int i = 1; i < all.length; i++) {
      expect(all[i].value, greaterThan(all[i - 1].value));
    }
    expect(bid("7NT").toString(), "7NT");
  });

  group("Round", () {
    late FiveHundredRound round;

    setUp(() {
      round = FiveHundredRound.deal(rules: FiveHundredRuleSet(), scores: [0, 0], dealer: 3, rng: Random(17));
    });

    test("Deal", () {
      expect(round.players.map((p) => p.hand.length), [10, 10, 10, 10]);
      expect(round.initialKitty.length, 3);
      final all = [...round.players.expand((p) => p.hand), ...round.initialKitty];
      expect(all.toSet(), fiveHundredDeckCards().toSet());
    });

    test("Bidding", () {
      expect(round.currentBidder(), 0);
      round.addBid(PlayerBid(0, bid("6S")));
      expect(round.canCurrentBidderMakeBid(bid("6S")), false);
      expect(() => round.addBid(PlayerBid(1, bid("6S"))), throwsException);
      round.addBid(PlayerBid(1, bid("6H")));
      round.addBid(PlayerBid.pass(2));
      round.addBid(PlayerBid(3, bid("7S")));
      // Player 2 passed, so it goes 0, 1, 3.
      round.addBid(PlayerBid(0, bid("7C")));
      round.addBid(PlayerBid.pass(1));
      expect(round.currentBidder(), 3);
      round.addBid(PlayerBid.pass(3));
      expect(round.status, FiveHundredRoundStatus.declarerDiscarding);
      expect(round.declarer(), 0);
      expect(round.winningBid().bid, bid("7C"));
    });

    test("Maximum bid ends bidding", () {
      round.addBid(PlayerBid(0, bid("10NT")));
      expect(round.status, FiveHundredRoundStatus.declarerDiscarding);
    });

    test("Passed out", () {
      for (int p = 0; p < 4; p++) {
        round.addBid(PlayerBid.pass(p));
      }
      expect(round.isPassedOut(), true);
      expect(round.isOver(), true);
    });

    test("Discard and play", () {
      round.addBid(PlayerBid(0, bid("6H")));
      for (int p = 1; p < 4; p++) {
        round.addBid(PlayerBid.pass(p));
      }
      final available = round.declarerAvailableCards();
      expect(available.length, 13);
      expect(round.isValidDiscardForDeclarer(available.take(2).toSet()), false);
      expect(() => round.discard(available.take(4).toSet()), throwsException);
      round.discard(available.take(3).toSet());
      expect(round.players[0].hand.length, 10);
      expect(round.discards, available.take(3).toList());
      expect(round.status, FiveHundredRoundStatus.playing);
      // Declarer leads.
      expect(round.currentPlayerIndex(), 0);
      final rng = Random(5);
      while (!round.isOver()) {
        final (card, suit) = chooseCardRandom(round, rng);
        round.playCard(card, jokerLeadSuit: suit);
      }
      expect(round.previousTricks.length, 10);
      final tricks = round.tricksTakenByTeam();
      expect(tricks[0] + tricks[1], 10);
      final scores = round.contractScoresForTeams();
      expect(scores[1], tricks[1] * 10);
      expect(scores[0], tricks[0] >= 6 ? 100 : -100);

      final restored = FiveHundredRound.fromJson(jsonDecode(jsonEncode(round.toJson())));
      expect(restored.contractScoresForTeams(), scores);
    });

    test("Joker led in no trump", () {
      round.players[0].hand = c("JOKER1 AS KS QS JS TS 9S 8S 7S 6S");
      round.players[1].hand = c("AH KH QH JH TH 9H 8H 7H 6H 5H");
      round.players[2].hand = c("AD KD QD JD TD 9D 8D 7D 6D 5D");
      round.players[3].hand = c("AC KC QC JC TC 9C 8C 7C 6C 5C");
      round.initialKitty = c("4H 4D 5S");
      round.addBid(PlayerBid(0, bid("10NT")));
      round.discard(c("4H 4D 5S").toSet());
      expect(round.needsJokerLeadSuit(joker), true);
      expect(() => round.playCard(joker), throwsException);
      round.playCard(joker, jokerLeadSuit: Suit.hearts);
      expect(round.currentJokerLeadSuit(), Suit.hearts);
      expect(round.legalPlaysForCurrentPlayer(), c("AH KH QH JH TH 9H 8H 7H 6H 5H"));
      round.playCard(c1("5H"));
      round.playCard(c1("5D"));
      round.playCard(c1("5C"));
      expect(round.previousTricks.last.winner, 0);
      expect(round.currentJokerLeadSuit(), null);
      final restored = FiveHundredRound.fromJson(jsonDecode(jsonEncode(round.toJson())));
      expect(restored.jokerLeadSuits, {0: Suit.hearts});
    });
  });

  group("Scoring", () {
    FiveHundredRound finishedRound(String contract, int declarer, int declarerTricks) {
      final round = FiveHundredRound.deal(rules: FiveHundredRuleSet(), scores: [0, 0], dealer: 3, rng: Random(1))
        ..status = FiveHundredRoundStatus.playing
        ..contract = Contract(declarer: declarer, bid: bid(contract));
      for (final p in round.players) {
        p.hand = [];
      }
      round.previousTricks = [
        for (int i = 0; i < 10; i++)
          Trick(0, c("5H 6H 7H 8H"), i < declarerTricks ? declarer : (declarer + 1) % 4),
      ];
      return round;
    }

    test("Made and set", () {
      expect(finishedRound("7H", 0, 7).contractScoresForTeams(), [200, 30]);
      expect(finishedRound("7H", 1, 9).contractScoresForTeams(), [10, 200]);
      expect(finishedRound("8NT", 2, 7).contractScoresForTeams(), [-320, 30]);
    });

    test("Slam", () {
      expect(finishedRound("7S", 0, 10).contractScoresForTeams(), [250, 0]);
      expect(finishedRound("8H", 0, 10).contractScoresForTeams(), [300, 0]);
    });
  });

  group("Match", () {
    FiveHundredMatch matchWithScores(List<int> initial, List<int> roundScores, int declarer) {
      final match = FiveHundredMatch(FiveHundredRuleSet(), Random(1));
      final round = match.currentRound;
      round.initialScores = initial;
      round.status = FiveHundredRoundStatus.playing;
      // A contract and tricks that give `roundScores`.
      final declarerTeam = declarer % 2;
      final made = roundScores[declarerTeam] > 0;
      final defenderTricks = roundScores[1 - declarerTeam] ~/ 10;
      final b = FiveHundredBid.allBids().firstWhere((b) => b.value == roundScores[declarerTeam].abs());
      round.contract = Contract(declarer: declarer, bid: b);
      for (final p in round.players) {
        p.hand = [];
      }
      round.previousTricks = [
        for (int i = 0; i < 10; i++)
          Trick(0, c("5H 6H 7H 8H"), i < defenderTricks ? declarer + 1 : declarer),
      ];
      expect(round.contractScoresForTeams(), roundScores, reason: "made: $made");
      return match;
    }

    test("Not over", () {
      final match = matchWithScores([300, 200], [100, 40], 0);
      expect(match.scores, [400, 240]);
      expect(match.isMatchOver(), false);
    });

    test("Win by reaching the limit", () {
      final match = matchWithScores([400, 200], [100, 40], 0);
      expect(match.winningTeam(), 0);
    });

    test("Defenders can win", () {
      final match = matchWithScores([200, 450], [-100, 50], 0);
      expect(match.winningTeam(), 1);
    });

    test("Declarers win if both reach the limit", () {
      final match = matchWithScores([470, 420], [40, 100], 1);
      expect(match.scores, [510, 520]);
      expect(match.winningTeam(), 1);
      final match2 = matchWithScores([420, 480], [140, 30], 0);
      expect(match2.scores, [560, 510]);
      expect(match2.winningTeam(), 0);
    });

    test("Lose by falling to the negative limit", () {
      final match = matchWithScores([-400, 100], [-140, 40], 0);
      expect(match.winningTeam(), 1);
    });

    test("Finish round rotates the dealer", () {
      final match = matchWithScores([0, 0], [100, 40], 0);
      final dealer = match.dealer;
      match.finishRound();
      expect(match.dealer, (dealer + 1) % 4);
      expect(match.currentRound.initialScores, [100, 40]);
      expect(match.previousRounds.length, 1);
    });
  });

  test("AI plays legal games", () {
    final rng = Random(3);
    for (int i = 0; i < 50; i++) {
      final round = FiveHundredRound.deal(rules: FiveHundredRuleSet(), scores: [0, 0], dealer: i % 4, rng: rng);
      while (round.status == FiveHundredRoundStatus.bidding && !round.isPassedOut()) {
        final p = round.currentBidder();
        round.addBid(PlayerBid(p, chooseBid(round, p, rng, FiveHundredBidParams(numDeals: 5))));
      }
      if (round.isPassedOut()) {
        continue;
      }
      round.discard(chooseDiscards(round, rng));
      while (!round.isOver()) {
        final (card, suit) = (i % 2 == 0)
            ? chooseCardHeuristic(round, rng)
            : chooseCardMonteCarlo(round, FiveHundredMonteCarloParams(numDeals: 3), rng);
        round.playCard(card, jokerLeadSuit: suit);
      }
      round.contractScoresForTeams();
    }
  });

  group("AI", () {
    FiveHundredRound roundWithContract(String contract, List<String> hands, {int declarer = 0}) {
      final round = FiveHundredRound()
        ..rules = FiveHundredRuleSet()
        ..initialScores = [0, 0]
        ..players = hands.map((h) => FiveHundredPlayer(c(h))).toList()
        ..dealer = 3
        ..initialKitty = c("4H 4D 5S")
        ..bidHistory = [
          PlayerBid(declarer, bid(contract)),
          for (int p = 1; p < numPlayers; p++) PlayerBid.pass((declarer + p) % numPlayers),
        ]
        ..status = FiveHundredRoundStatus.declarerDiscarding
        ..currentTrick = TrickInProgress(declarer);
      return round;
    }

    test("Discards keep trumps and the joker", () {
      final round = roundWithContract("7H", [
        "JOKER1 JD 5H 6H AS 9S 8S 7C 6C 5C",
        "AH KH QH JH TH 9H 8H 7H 6H AC",
        "AD KD QD TD 9D 8D 7D 6D 5D KC",
        "KS QS JS TS 6S QC JC TC 9C 8C",
      ]);
      final discards = chooseDiscards(round, Random(1));
      expect(discards.length, 3);
      expect(discards.any((c) => effectiveSuit(c, Suit.hearts) == Suit.hearts), false);
      expect(discards, isNot(contains(c1("AS"))));
      // The kitty's 4D is a singleton, so discarding it makes a void. Then the
      // shortest side suit without an ace is clubs.
      expect(discards, c("4D 5C 6C").toSet());
    });

    test("Known voids", () {
      final round = roundWithContract("6NT", [
        "JOKER1 AS KS QS JS TS 9S 8S 7S 6S",
        "AH KH QH JH TH 9H 8H 7H 6H 5H",
        "AD KD QD JD TD 9D 8D 7D 6D 5D",
        "AC KC QC JC TC 9C 8C 7C 6C 5C",
      ]);
      round.discard(c("4H 4D 5S").toSet());
      round.playCard(c1("AS"));
      round.playCard(c1("AH"));
      expect(knownVoids(round)[1], {Suit.spades});
      round.playCard(c1("AD"));
      round.playCard(c1("AC"));
      expect(knownVoids(round), [<Suit>{}, {Suit.spades}, {Suit.spades}, {Suit.spades}]);
      // Joker led as hearts; player 1 follows, player 2 doesn't.
      round.playCard(joker, jokerLeadSuit: Suit.hearts);
      round.playCard(c1("KH"));
      round.playCard(c1("KD"));
      expect(knownVoids(round)[2], {Suit.spades, Suit.hearts});
    });

    test("Sampled rounds respect voids and hand sizes", () {
      final rng = Random(2);
      for (int i = 0; i < 20; i++) {
        final round = FiveHundredRound.deal(rules: FiveHundredRuleSet(), scores: [0, 0], dealer: 3, rng: rng);
        round.addBid(PlayerBid(0, bid(i.isEven ? "6NT" : "6H")));
        for (int p = 1; p < 4; p++) {
          round.addBid(PlayerBid.pass(p));
        }
        round.discard(chooseDiscards(round, rng));
        for (int j = 0; j < 17; j++) {
          final (card, suit) = chooseCardHeuristic(round, rng);
          round.playCard(card, jokerLeadSuit: suit);
        }
        for (int p = 0; p < 4; p++) {
          final hypo = possibleRoundForPlayer(round, p, rng)!;
          final voids = knownVoids(round);
          for (int q = 0; q < 4; q++) {
            expect(hypo.players[q].hand.length, round.players[q].hand.length);
            if (q != p) {
              expect(hypo.players[q].hand.any((c) => voids[q].contains(effectiveSuit(c, round.trump))), false);
            }
          }
          expect(hypo.players[p].hand, round.players[p].hand);
          final all = [...hypo.players.expand((pl) => pl.hand), ...hypo.discards, ...playedCards(hypo)];
          expect(all.toSet(), fiveHundredDeckCards().toSet());
        }
      }
    });

    test("Monte Carlo considers each suit for the joker led in no trump", () {
      final round = roundWithContract("6NT", [
        "JOKER1 AS KS QS JS TS 9S 8S 7S 6S",
        "AH KH QH JH TH 9H 8H 7H 6H 5H",
        "AD KD QD JD TD 9D 8D 7D 6D 5D",
        "AC KC QC JC TC 9C 8C 7C 6C 5C",
      ]);
      round.discard(c("4H 4D 5S").toSet());
      final plays = candidatePlays(round);
      expect(plays.where((p) => p.$1 == joker).map((p) => p.$2).toSet(), Suit.values.toSet());
      final (card, suit) = chooseCardMonteCarlo(round, FiveHundredMonteCarloParams(numDeals: 5), Random(3));
      expect(round.legalPlaysForCurrentPlayer(), contains(card));
      expect(suit != null, card == joker);
    });

    test("Expected differential", () {
      final rules = FiveHundredRuleSet();
      // Making 7H with 8 tricks: 200 - 20. Set with 6: -200 - 40.
      expect(expectedDeclarerDifferential([8], bid("7H"), rules), 180);
      expect(expectedDeclarerDifferential([6], bid("7H"), rules), -240);
      expect(expectedDeclarerDifferential([10], bid("7S"), rules), 250);
      expect(expectedDeclarerDifferential([8, 6], bid("7H"), rules), -30);
    });
  });
}
