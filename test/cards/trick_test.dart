import 'package:flutter_test/flutter_test.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

void main() {
  test('All same suit', () {
    final trickCards = PlayingCard.cardsFromString("2C QC KC TC");
    expect(trickWinnerIndex(trickCards), 2);

    final tip = TrickInProgress(3);
    tip.cards.addAll(trickCards);
    final trick = tip.finish();
    expect(trick.winner, 1);
  });

  test('High card not following suit', () {
    final trickCards = PlayingCard.cardsFromString("2C QH KD TC");
    expect(trickWinnerIndex(trickCards), 3);

    final tip = TrickInProgress(3);
    tip.cards.addAll(trickCards);
    final trick = tip.finish();
    expect(trick.winner, 2);
  });

  test('Trump winner', () {
    final trickCards = PlayingCard.cardsFromString("4C 2H KC TC");
    expect(trickWinnerIndex(trickCards, trump: Suit.hearts), 1);

    final tip = TrickInProgress(2);
    tip.cards.addAll(trickCards);
    final trick = tip.finish(trump: Suit.hearts);
    expect(trick.winner, 3);
  });
}
