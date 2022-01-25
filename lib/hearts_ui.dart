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
  final HeartsMatch initialMatch;
  final HeartsMatch Function() createMatchFn;
  final void Function(HeartsMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;

  const HeartsMatchDisplay({
    Key? key,
    required this.initialMatch,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.dialogVisible,
  }) : super(key: key);

  @override
  _HeartsMatchState createState() => _HeartsMatchState();
}

class _HeartsMatchState extends State<HeartsMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  var aiMode = AiMode.human_player_0;
  late HeartsMatch match;
  List<PlayingCard> selectedCardsToPass = [];
  Map<int, Mood> playerMoods = {};

  HeartsRound get round => match.currentRound;

  @override void initState() {
    super.initState();
    match = widget.initialMatch.copy();
    _scheduleNextPlayIfNeeded();
  }

  void _startRound() {
    setState(() {
      _clearMoods();
      if (round.isOver()) {
        match.finishRound();
      }
      if (match.isMatchOver()) {
        match = widget.createMatchFn();
      }
      selectedCardsToPass = [];
    });
    widget.saveMatchFn(match);
  }

  void _scheduleNextPlayIfNeeded() {
    if (round.isOver()) {
      return;
    }
    if (round.currentPlayerIndex() != 0) {
      Future.delayed(const Duration(milliseconds: 500), _playNextCard);
    }
  }

  void _playCard(final PlayingCard card) {
    print(round.toJson());
    if (round.status == HeartsRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.moving_trick_card;
      });
      widget.saveMatchFn(match);
    }
  }

  void _clearMoods() {
    playerMoods.clear();
  }

  void _updateMoodsAfterTrick() {
    print(round.toJson());
    playerMoods.clear();
    if (match.isMatchOver()) {
      final winners = match.winningPlayers();
      for (int i = 1; i < match.rules.numPlayers; i++) {
        playerMoods[i] = (winners.contains(i)) ? Mood.veryHappy : Mood.mad;
      }
    }
    else if (round.isOver()) {
      final points = round.pointsTaken();
      for (int i = 1; i < match.rules.numPlayers; i++) {
        if (points[i] <= 0) {
          playerMoods[i] = Mood.happy;
        }
        else if (points[i] >= 13) {
          playerMoods[i] = Mood.mad;
        }
      }
    }
    else {
      // Mad when taking QS, happy when taking JD.
      final trick = round.previousTricks.last;
      final hasQS = trick.cards.contains(queenOfSpades);
      final hasJD = round.rules.jdMinus10 && trick.cards.contains(jackOfDiamonds);
      if (hasQS && !hasJD) {
        // Only mad if another player has taken a heart, otherwise might be trying to shoot.
        bool otherPlayerHasHeart = false;
        for (int i = 0; i < round.previousTricks.length - 1; i++) {
          final pt = round.previousTricks[i];
          if (pt.winner != trick.winner && pt.cards.any((c) => c.suit == Suit.hearts)) {
            otherPlayerHasHeart = true;
            break;
          }
        }
        if (otherPlayerHasHeart) {
          playerMoods[trick.winner] = Mood.mad;
        }
      }
      else if (hasJD && !hasQS) {
        playerMoods[trick.winner] = Mood.happy;
      }
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {animationMode = AnimationMode.none;});
      _scheduleNextPlayIfNeeded();
    }
    else {
      setState(() {animationMode = AnimationMode.moving_trick_to_winner;});
      _updateMoodsAfterTrick();
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
    if (round.passDirection != 0) {
      setState(() {
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
      });
    }
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

  bool _shouldShowNoPassingMessage() {
    return round.passDirection == 0 &&
        round.previousTricks.isEmpty && round.currentTrick.cards.isEmpty;
  }

  bool _shouldShowPassDialog() {
    return !widget.dialogVisible && (
        round.status == HeartsRoundStatus.passing || _shouldShowNoPassingMessage());
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver();
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);

    return Stack(
      children: <Widget>[
        _handCards(layout, round.players[0].hand),
        _trickCards(layout),
        if (_shouldShowPassDialog()) PassCardsDialog(
            layout: layout,
            round: round,
            selectedCards: selectedCardsToPass,
            onConfirm: _passCards,
        ),
        if (_shouldShowEndOfRoundDialog()) EndOfRoundDialog(
            layout: layout,
            match: match,
            onContinue: _startRound,
            onMainMenu: _showMainMenuAfterMatch,
        ),
        PlayerMoods(layout: layout, moods: playerMoods),
        Text("${match.scores} ${round.status} ${_shouldShowPassDialog()}"),
      ],
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

Widget _paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

class PassCardsDialog extends StatelessWidget {
  final Layout layout;
  final HeartsRound round;
  final List<PlayingCard> selectedCards;
  final Function() onConfirm;

  const PassCardsDialog({Key? key, required this.layout, required this.round, required this.selectedCards, required this.onConfirm}): super(key: key);

  String passMessage() {
    switch (round.passDirection) {
      case 0: return "No passing this round";
      case 1: return "Choose ${round.rules.numPassedCards} cards to pass left";
      case 2: return "Choose ${round.rules.numPassedCards} cards to pass across";
      case 3: return "Choose ${round.rules.numPassedCards} cards to pass right";
      default: throw AssertionError("Bad pass direction: ${round.passDirection}");
    }
  }

  bool isButtonEnabled() {
    return round.passDirection == 0 || selectedCards.length == round.rules.numPassedCards;
  }

  String buttonLabel() {
    if (round.passDirection == 0) {
      return "Start round";
    }
    final remaining = round.rules.numPassedCards - selectedCards.length;
    return remaining == 0 ? "Pass cards" : "Select $remaining more";
  }

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Dialog(
            backgroundColor: dialogBackgroundColor,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paddingAll(15, Text(passMessage())),
                  _paddingAll(15, ElevatedButton(
                    child: Text(buttonLabel()),
                    onPressed: isButtonEnabled() ? onConfirm : null,
                  )),
                ],
            ),
        ),
    );
  }
}

class EndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final HeartsMatch match;
  final Function() onContinue;
  final Function() onMainMenu;

  const EndOfRoundDialog({
    Key? key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    final scores = match.currentRound.pointsTaken();
    final tableFontSize = layout.dialogBaseFontSize();
    const cellPad = 4.0;

    Widget pointsCell(Object p) => _paddingAll(
        cellPad,
        Text(p.toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: tableFontSize)));

    Widget headerCell(String msg) => _paddingAll(
        cellPad,
        Text(msg,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: tableFontSize*0.9, fontWeight: FontWeight.bold)));

    TableRow pointsRow(String title, List<Object> points) => TableRow(children: [
      _paddingAll(cellPad, headerCell(title)),
      ...points.map((p) => _paddingAll(cellPad, pointsCell(p.toString())))
    ]);

    String matchOverMessage() {
      final p = match.winningPlayers();
      if (p.contains(0)) {
        return (p.length == 1) ? "You win!" : "You tied for the win!";
      }
      return "You lose :(";
    }

    final dialog = Center(
        child: Dialog(
            backgroundColor: dialogBackgroundColor,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (match.isMatchOver()) Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _paddingAll(10, Text(matchOverMessage(), style: TextStyle(fontSize: layout.dialogHeaderFontSize()))),
                    ],
                  ),
                  _paddingAll(10, Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(children: [
                        _paddingAll(cellPad, headerCell("")),
                        _paddingAll(cellPad, headerCell("You")),
                        _paddingAll(cellPad, headerCell("West")),
                        _paddingAll(cellPad, headerCell("North")),
                        _paddingAll(cellPad, headerCell("East")),
                      ]),
                      pointsRow("Previous points", match.currentRound.initialScores),
                      pointsRow("Round points", scores),
                      pointsRow("Total points", match.scores),
                    ],
                  )),
                  if (match.isMatchOver()) Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _paddingAll(15, ElevatedButton(
                        child: const Text("New Game"),
                        onPressed: onContinue,
                      )),
                      _paddingAll(15, ElevatedButton(
                        child: const Text("Main Menu"),
                        onPressed: onMainMenu,
                      )),
                    ],
                  ),
                  if (!match.isMatchOver()) Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [_paddingAll(15, ElevatedButton(
                      child: const Text("Continue"),
                      onPressed: onContinue,
                    ))],
                  ),
                ])));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) => Opacity(opacity: val.clamp(0.0, 1.0), child: child),
    );
    return dialog;
  }
}
