import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'spades/spades.dart';
import 'spades/spades_ai.dart';

PlayingCard computeCard(final CardToPlayRequest req) {
  return chooseCardMonteCarlo(
      req,
      MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
      chooseCardRandom,
      Random());
}


class SpadesMatchDisplay extends StatefulWidget {
  const SpadesMatchDisplay({Key? key}) : super(key: key);

  @override
  _SpadesMatchState createState() => _SpadesMatchState();
}

class _SpadesMatchState extends State<SpadesMatchDisplay> {
  final rng = Random();
  final rules = SpadesRuleSet();
  var animationMode = AnimationMode.none;
  var aiMode = AiMode.human_player_0;
  late SpadesMatch match;

  SpadesRound get round => match.currentRound;

  @override void initState() {
    super.initState();
    _startMatch();
    Future.delayed(const Duration(milliseconds: 500), _playNextCard);
  }

  void _startMatch() {
    match = SpadesMatch(rules, rng);
    _startRound();
  }

  void _startRound() {
    if (round.isOver()) {
      match.finishRound();
    }
    // TODO: bidding UI.
    for (int i = 0; i < round.rules.numPlayers; i++) {
      round.setBidForPlayer(bid: 3, playerIndex: i);
    }
    _scheduleNextPlayIfNeeded();
  }

  void _scheduleNextPlayIfNeeded() {
    if (round.isOver()) {
      setState(() {
        _startRound();
      });
    }
    if (round.currentPlayerIndex() != 0) {
      Future.delayed(const Duration(milliseconds: 500), _playNextCard);
    }
  }

  void _playCard(final PlayingCard card) {
    if (round.status == SpadesRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.moving_trick_card;
      });
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {animationMode = AnimationMode.none;});
      _scheduleNextPlayIfNeeded();
    }
    else {
      setState(() {animationMode = AnimationMode.moving_trick_to_winner;});
    }
  }

  void _trickToWinnerAnimationFinished() {
    setState(() {animationMode = AnimationMode.none;});
    _scheduleNextPlayIfNeeded();
  }

  void _playNextCard() async {
    // Do this in a separate thread/isolate.
    final card = await compute(computeCard, CardToPlayRequest.fromRound(round));
    _playCard(card);
  }

  void handleHandCardClicked(final PlayingCard card) {
    print("Clicked ${card.toString()}, status: ${round.status}, index: ${round.currentPlayerIndex()}");
    if (round.status == SpadesRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        print("Playing");
        _playCard(card);
      }
    }
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    final rects = playerHandCardRects(layout, cards);

    bool isHumanTurn = round.status == SpadesRoundStatus.playing && round.currentPlayerIndex() == 0;
    List<PlayingCard> highlightedCards = [];
    if (isHumanTurn) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    final List<Widget> cardImages = [];
    for (final entry in rects.entries) {
      final card = entry.key;
      cardImages.add(PositionedCard(
        rect: entry.value,
        card: card,
        opacity: highlightedCards.contains(card) ? 1.0 : 0.5,
        onCardClicked: (card) => handleHandCardClicked(card),
      ));
    }
    return Stack(children: cardImages);
  }


  Widget _trickCards(final Layout layout) {
    final humanHand = aiMode == AiMode.human_player_0 ? round.players[0].hand : null;
    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
      animationMode: animationMode,
      numPlayers: round.rules.numPlayers,
      humanPlayerHand: humanHand,
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);

    return Stack(
      children: <Widget>[
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.green,
        ),
        ...[0, 1, 2, 3].map((i) => AiPlayerImage(layout: layout, playerIndex: i)),
        _handCards(layout, round.players[0].hand),
        _trickCards(layout),
      ],
    );
  }
}
