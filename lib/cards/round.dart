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
