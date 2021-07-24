import 'package:flutter_test/flutter_test.dart';
import 'package:hearts/cards/card.dart';

void main() {
  test('equality and hashing', () {
    final c1 = PlayingCard(Rank.three, Suit.clubs);
    final c2 = PlayingCard(Rank.three, Suit.clubs);
    final c3 = PlayingCard(Rank.three, Suit.hearts);
    final c4 = PlayingCard(Rank.ace, Suit.clubs);

    expect(c1 == c2, true);
    expect(c1 == c3, false);
    expect(c1 == c4, false);
    expect(c1.hashCode == c2.hashCode, true);
    expect(c1.hashCode == c3.hashCode, false);
    expect(c1.hashCode == c4.hashCode, false);
  });

  test("parsing", () {
    expect(PlayingCard.cardFromString("QS"), PlayingCard(Rank.queen, Suit.spades));
    expect(PlayingCard.cardFromString("TD"), PlayingCard(Rank.ten, Suit.diamonds));
    expect(PlayingCard.cardFromString("10H"), PlayingCard(Rank.ten, Suit.hearts));
    expect(PlayingCard.cardFromString("3♣"), PlayingCard(Rank.three, Suit.clubs));
  });

  test("ranks for suit", () {
    final cards = PlayingCard.cardsFromString("4S 7H JS 2D 2S AS KD");
    expect(sortedRanksInSuit(cards, Suit.spades), [Rank.ace, Rank.jack, Rank.four, Rank.two]);
    expect(sortedRanksInSuit(cards, Suit.hearts), [Rank.seven]);
    expect(sortedRanksInSuit(cards, Suit.diamonds), [Rank.king, Rank.two]);
    expect(sortedRanksInSuit(cards, Suit.clubs), []);
  });
}
