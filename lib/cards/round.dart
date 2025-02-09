import 'card.dart';
import 'trick.dart';

abstract class BaseTrickRound {
  int get numberOfPlayers;
  TrickInProgress get currentTrick;
  List<Trick> get previousTricks;
  List<PlayingCard> cardsForPlayer(int playerIndex);
  void playCard(PlayingCard card);
  bool isOver();
  int currentPlayerIndex();
  List<PlayingCard> legalPlaysForCurrentPlayer();
}

bool shouldLeaderClaimRemainingTricks(BaseTrickRound round, {Suit? trump, int minRequiredTricks = 2}) {
  if (round.isOver()) {
    return false;
  }
  if (round.currentTrick.cards.isNotEmpty) {
    return false;
  }
  int leader = round.currentTrick.leader;
  if (round.cardsForPlayer(leader).length < minRequiredTricks) {
    return false;
  }
  List<PlayingCard> remainingCards = [];
  for (int i = 0; i < round.numberOfPlayers; i++) {
    if (i != leader) {
      remainingCards.addAll(round.cardsForPlayer(i));
    }
  }
  return willLeadingPlayerWinAllRemainingTricks(
    leadingPlayerCards: round.cardsForPlayer(leader),
    remainingCards: remainingCards,
    trump: trump,
  );
}

void claimRemainingTricks(BaseTrickRound round) {
  assert(shouldLeaderClaimRemainingTricks(round));
  assert(round.currentTrick.cards.isEmpty);
  int claimer = round.currentTrick.leader;
  while (!round.isOver()) {
    final legalPlays = round.legalPlaysForCurrentPlayer();
    round.playCard(legalPlays[0]);
    if (round.currentTrick.cards.isEmpty) {
      assert(round.previousTricks.last.winner == claimer);
    }
  }
}