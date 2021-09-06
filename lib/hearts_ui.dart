import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'hearts/hearts.dart';
import 'hearts/hearts_ai.dart';

PlayingCard computeCard(final CardToPlayRequest req) {
  return chooseCardMonteCarlo(
      req,
      MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
      chooseCardAvoidingPoints,
      Random());
}


class HeartsMatchDisplay extends StatefulWidget {
  const HeartsMatchDisplay({Key? key}) : super(key: key);

  @override
  _HeartsMatchState createState() => _HeartsMatchState();
}

class _HeartsMatchState extends State<HeartsMatchDisplay> {
  final rng = Random();
  final rules = HeartsRuleSet();
  var animationMode = AnimationMode.none;
  var aiMode = AiMode.human_player_0;
  late HeartsMatch match;
  List<PlayingCard> selectedCardsToPass = [];

  HeartsRound get round => match.currentRound;

  @override void initState() {
    super.initState();
    _startMatch();
    Future.delayed(const Duration(milliseconds: 500), _playNextCard);
  }

  void _startMatch() {
    match = HeartsMatch(rules, rng);
    _startRound();
  }

  void _startRound() {
    if (round.isOver()) {
      match.finishRound();
    }
    selectedCardsToPass = [];
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
    if (round.status == HeartsRoundStatus.playing) {
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

  void _passCards() {
    for (int i = 0; i < round.rules.numPlayers; i++) {
      round.setPassedCardsForPlayer(0, selectedCardsToPass);
      final passReq = CardsToPassRequest(
        rules: round.rules,
        scoresBeforeRound: round.initialScores,
        hand: round.players[i].hand,
        direction: round.passDirection,
        numCards: round.rules.numPassedCards,
      );
      final cards = chooseCardsToPass(passReq);
      round.setPassedCardsForPlayer(i, cards);
    }
    round.passCards();
    _scheduleNextPlayIfNeeded();
  }

  void handleHandCardClicked(final PlayingCard card) {
    print("Clicked ${card.toString()}, status: ${round.status}, index: ${round.currentPlayerIndex()}");
    if (round.status == HeartsRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        print("Playing");
        _playCard(card);
      }
    }
    else if (round.status == HeartsRoundStatus.passing) {
      setState(() {
        if (selectedCardsToPass.contains(card)) {
          selectedCardsToPass.remove(card);
        }
        else if (selectedCardsToPass.length < round.rules.numPassedCards) {
          selectedCardsToPass.add(card);
          if (selectedCardsToPass.length == round.rules.numPassedCards) {
            _passCards();
          }
        }
      });
    }
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    final rects = playerHandCardRects(layout, cards);

    bool isHumanTurn = round.status == HeartsRoundStatus.playing && round.currentPlayerIndex() == 0;
    List<PlayingCard> highlightedCards = [];
    if (isHumanTurn) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }
    else if (round.status == HeartsRoundStatus.passing) {
      highlightedCards = cards.where((c) => !selectedCardsToPass.contains(c)).toList();
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
