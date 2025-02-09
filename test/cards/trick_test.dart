import 'package:flutter_test/flutter_test.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

const cs = PlayingCard.cardsFromString;

void main() {
  test('All same suit', () {
    final trickCards = cs("2C QC KC TC");
    expect(trickWinnerIndex(trickCards), 2);

    final tip = TrickInProgress(3);
    tip.cards.addAll(trickCards);
    final trick = tip.finish();
    expect(trick.winner, 1);
  });

  test('High card not following suit', () {
    final trickCards = cs("2C QH KD TC");
    expect(trickWinnerIndex(trickCards), 3);

    final tip = TrickInProgress(3);
    tip.cards.addAll(trickCards);
    final trick = tip.finish();
    expect(trick.winner, 2);
  });

  test('Trump winner', () {
    final trickCards = cs("4C 2H KC TC");
    expect(trickWinnerIndex(trickCards, trump: Suit.hearts), 1);

    final tip = TrickInProgress(2);
    tip.cards.addAll(trickCards);
    final trick = tip.finish(trump: Suit.hearts);
    expect(trick.winner, 3);
  });

  test('Claiming remaining tricks', () {
    final canClaimHighCardsNoTrump = willLeadingPlayerWinAllRemainingTricks(
        leadingPlayerCards: cs("AS KS AH QH JH 6D 4D"),
        remainingCards: cs("QS JS TS 9H 8H 2H 3D 2D AC KC"),
    );
    expect(canClaimHighCardsNoTrump, true);

    final canClaimHighCardsButNotAllTrumps = willLeadingPlayerWinAllRemainingTricks(
        leadingPlayerCards: cs("AS KS AH QH JH 6D 4D"),
        remainingCards: cs("2S 9H 8H 2H 3D 2D AC KC"),
        trump: Suit.spades,
    );
    expect(canClaimHighCardsButNotAllTrumps, false);

    final canClaimWithOnlyHighTrumps = willLeadingPlayerWinAllRemainingTricks(
      leadingPlayerCards: cs("QH JH 9H"),
      remainingCards: cs("8H 7H 6H 5H AS AD AC KC"),
      trump: Suit.hearts,
    );
    expect(canClaimWithOnlyHighTrumps, true);

    final canClaimWithLowerCardThanRemaining = willLeadingPlayerWinAllRemainingTricks(
      leadingPlayerCards: cs("AS KS QS JS 2S AH KD QC"),
      remainingCards: cs("3S KH QH JH 8D 7D 6C 5C"),
    );
    expect(canClaimWithLowerCardThanRemaining, false);

    final canClaimWithLowerTrumpThanRemaining = willLeadingPlayerWinAllRemainingTricks(
      leadingPlayerCards: cs("AD QD JD TD 8D"),
      remainingCards: cs("9D 4S 3S 2S 4H 3H 2H 4C 3C 2C"),
      trump: Suit.diamonds,
    );
    expect(canClaimWithLowerTrumpThanRemaining, false);
  });
}
