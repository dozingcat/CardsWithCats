import 'package:flutter_test/flutter_test.dart';
import 'package:cards_with_cats/cards/card.dart';

void main() {
  test('equality and hashing', () {
    final c1 = SuitedCard(Rank.three, Suit.clubs);
    final c2 = SuitedCard(Rank.three, Suit.clubs);
    final c3 = SuitedCard(Rank.three, Suit.hearts);
    final c4 = SuitedCard(Rank.ace, Suit.clubs);

    expect(c1 == c2, true);
    expect(c1 == c3, false);
    expect(c1 == c4, false);
    expect(c1.hashCode == c2.hashCode, true);
    expect(c1.hashCode == c3.hashCode, false);
    expect(c1.hashCode == c4.hashCode, false);
  });

  test("parsing", () {
    expect(SuitedCard.cardFromString("QS"), SuitedCard(Rank.queen, Suit.spades));
    expect(SuitedCard.cardFromString("TD"), SuitedCard(Rank.ten, Suit.diamonds));
    expect(SuitedCard.cardFromString("10H"), SuitedCard(Rank.ten, Suit.hearts));
    expect(SuitedCard.cardFromString("3♣"), SuitedCard(Rank.three, Suit.clubs));
  });

  test("ranks for suit", () {
    final cards = SuitedCard.cardsFromString("4S 7H JS 2D 2S AS KD");
    expect(sortedRanksInSuit(cards, Suit.spades), [Rank.ace, Rank.jack, Rank.four, Rank.two]);
    expect(sortedRanksInSuit(cards, Suit.hearts), [Rank.seven]);
    expect(sortedRanksInSuit(cards, Suit.diamonds), [Rank.king, Rank.two]);
    expect(sortedRanksInSuit(cards, Suit.clubs), []);
  });
}
