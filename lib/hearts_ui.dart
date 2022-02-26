import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'hearts/hearts.dart';
import 'hearts/hearts_ai.dart';

int nowMillis() => DateTime.now().millisecondsSinceEpoch % 10000;

PlayingCard computeCard(final CardToPlayRequest req) {
  print("In computeCard (t=${nowMillis()})");
  return chooseCardMonteCarlo(
      req, MonteCarloParams(numHands: 20, rolloutsPerHand: 50), chooseCardAvoidingPoints, Random());
}

class HeartsMatchDisplay extends StatefulWidget {
  final HeartsMatch Function() initialMatchFn;
  final HeartsMatch Function() createMatchFn;
  final void Function(HeartsMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final Stream matchUpdateStream;

  const HeartsMatchDisplay({
    Key? key,
    required this.initialMatchFn,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.dialogVisible,
    required this.catImageIndices,
    required this.matchUpdateStream,
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
  bool showScoreOverlay = false;
  late StreamSubscription matchUpdateSubscription;

  HeartsRound get round => match.currentRound;
  final suitDisplayOrder = [Suit.hearts, Suit.spades, Suit.diamonds, Suit.clubs];

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is HeartsMatch) {
        _updateMatch(event);
      }
    });
    _scheduleAiPlayIfNeeded();
  }

  @override
  void deactivate() {
    super.deactivate();
    matchUpdateSubscription.cancel();
  }

  void _updateMatch(HeartsMatch newMatch) {
    setState(() {
      match = newMatch;
      _startRound();
    });
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

  void _scheduleAiPlayIfNeeded() {
    if (round.isOver()) {
      return;
    }
    if (round.currentPlayerIndex() != 0 && round.status == HeartsRoundStatus.playing) {
      _computeAiPlay(minDelayMillis: 500);
    }
  }

  void _computeAiPlay({required int minDelayMillis}) async {
    // Do this in a separate thread/isolate. Note: `compute` has an overhead of
    // several hundred milliseconds in debug mode, but not in release mode.
    final t1 = DateTime.now().millisecondsSinceEpoch;
    try {
      print("Starting isolate (t=${nowMillis()})");
      final card = await compute(computeCard, CardToPlayRequest.fromRound(round));
      print("Got card: ${card.toString()} (t=${nowMillis()})");
      final elapsed = DateTime.now().millisecondsSinceEpoch - t1;
      final delayMillis = max(0, minDelayMillis - elapsed);
      print("Delaying for $delayMillis ms");
      Future.delayed(Duration(milliseconds: delayMillis), () => _playCard(card));
    } catch (ex) {
      print("*** Exception in isolate: $ex");
    }
  }

  void _playCard(final PlayingCard card) {
    // print(round.toJson());
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
    // print(round.toJson());
    playerMoods.clear();
    if (match.isMatchOver()) {
      final winners = match.winningPlayers();
      for (int i = 1; i < match.rules.numPlayers; i++) {
        playerMoods[i] = (winners.contains(i)) ? Mood.veryHappy : Mood.mad;
      }
    } else if (round.isOver()) {
      final points = round.pointsTaken();
      for (int i = 1; i < match.rules.numPlayers; i++) {
        if (points[i] <= 0) {
          playerMoods[i] = Mood.happy;
        } else if (points[i] >= 13) {
          playerMoods[i] = Mood.mad;
        }
      }
    } else {
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
      } else if (hasJD && !hasQS) {
        playerMoods[trick.winner] = Mood.happy;
      }
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {
        animationMode = AnimationMode.none;
      });
      _scheduleAiPlayIfNeeded();
    } else {
      setState(() {
        animationMode = AnimationMode.moving_trick_to_winner;
      });
      _updateMoodsAfterTrick();
    }
  }

  void _trickToWinnerAnimationFinished() {
    setState(() {
      animationMode = AnimationMode.none;
    });
    _scheduleAiPlayIfNeeded();
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
    _scheduleAiPlayIfNeeded();
  }

  void handleHandCardClicked(final PlayingCard card) {
    print(
        "Clicked ${card.toString()}, status: ${round.status}, index: ${round.currentPlayerIndex()}");
    if (round.status == HeartsRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        print("Playing ${card.toString()}");
        _playCard(card);
      }
    } else if (round.status == HeartsRoundStatus.passing) {
      setState(() {
        if (selectedCardsToPass.contains(card)) {
          selectedCardsToPass.remove(card);
        } else if (selectedCardsToPass.length < round.rules.numPassedCards) {
          selectedCardsToPass.add(card);
        }
      });
    }
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    final rects = playerHandCardRects(layout, cards, suitDisplayOrder);

    bool isHumanTurn = round.status == HeartsRoundStatus.playing && round.currentPlayerIndex() == 0;
    List<PlayingCard> highlightedCards = [];
    if (isHumanTurn) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    } else if (round.status == HeartsRoundStatus.passing) {
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
      humanPlayerSuitOrder: suitDisplayOrder,
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  List<String> _currentRoundScoreMessages() {
    if (round.status == HeartsRoundStatus.passing) {
      return List.generate(round.rules.numPlayers, (i) => "Score: ${round.initialScores[i]}");
    }
    final messages = <String>[];
    for (int i = 0; i < round.rules.numPlayers; i++) {
      bool hasQS = false;
      bool hasJD = false;
      int numHearts = 0;
      for (final t in round.previousTricks) {
        if (t.winner == i) {
          if (t.cards.contains(queenOfSpades)) {
            hasQS = true;
          }
          if (round.rules.jdMinus10 && t.cards.contains(jackOfDiamonds)) {
            hasJD = true;
          }
          numHearts += t.cards.where((c) => c.suit == Suit.hearts).length;
        }
      }
      String taken = [if (hasQS) "Q♠", if (hasJD) "J♦", "$numHearts♥"].join(", ");
      messages.add("Score: ${round.initialScores[i]}\nTaken: $taken");
    }
    return messages;
  }

  bool shouldShowScoreOverlay() {
    return showScoreOverlay && !widget.dialogVisible && !round.isOver();
  }

  bool shouldShowScoreOverlayToggle() {
    return !widget.dialogVisible && !round.isOver();
  }

  bool _shouldShowNoPassingMessage() {
    return round.passDirection == 0 &&
        round.previousTricks.isEmpty &&
        round.currentTrick.cards.isEmpty;
  }

  bool _shouldShowPassDialog() {
    return !widget.dialogVisible &&
        (round.status == HeartsRoundStatus.passing || _shouldShowNoPassingMessage());
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver();
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  Widget scoreOverlayButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 80, 10, 10),
      child: FloatingActionButton(
        onPressed: () {
          setState(() {
            showScoreOverlay = !showScoreOverlay;
          });
        },
        child: Icon(showScoreOverlay ? Icons.search_off : Icons.search),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);

    return Stack(
      children: <Widget>[
        _handCards(layout, round.players[0].hand),
        _trickCards(layout),
        if (_shouldShowPassDialog())
          PassCardsDialog(
            layout: layout,
            round: round,
            selectedCards: selectedCardsToPass,
            onConfirm: _passCards,
          ),
        if (_shouldShowEndOfRoundDialog())
          EndOfRoundDialog(
            layout: layout,
            match: match,
            onContinue: _startRound,
            onMainMenu: _showMainMenuAfterMatch,
            catImageIndices: widget.catImageIndices,
          ),
        PlayerMoods(layout: layout, moods: playerMoods),
        if (shouldShowScoreOverlay())
          PlayerMessagesOverlay(layout: layout, messages: _currentRoundScoreMessages()),
        if (shouldShowScoreOverlayToggle()) scoreOverlayButton(),
        // Text("${match.scores} ${round.status} ${_shouldShowPassDialog()}"),
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

  const PassCardsDialog(
      {Key? key,
      required this.layout,
      required this.round,
      required this.selectedCards,
      required this.onConfirm})
      : super(key: key);

  String passMessage() {
    switch (round.passDirection) {
      case 0:
        return "No passing this round";
      case 1:
        return "Choose ${round.rules.numPassedCards} cards to pass left";
      case 2:
        return "Choose ${round.rules.numPassedCards} cards to pass across";
      case 3:
        return "Choose ${round.rules.numPassedCards} cards to pass right";
      default:
        throw AssertionError("Bad pass direction: ${round.passDirection}");
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
    final textStyle = TextStyle(fontSize: layout.dialogBaseFontSize());
    final halfPadding = textStyle.fontSize! * 0.75;
    return Center(
      child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: halfPadding),
            _paddingAll(halfPadding, Text(passMessage(), style: textStyle)),
            _paddingAll(
                halfPadding,
                ElevatedButton(
                  child: Text(buttonLabel()),
                  onPressed: isButtonEnabled() ? onConfirm : null,
                )),
            SizedBox(height: halfPadding),
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
  final List<int> catImageIndices;

  const EndOfRoundDialog({
    Key? key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
    required this.catImageIndices,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scores = match.currentRound.pointsTaken();
    final headerFontSize = layout.dialogBaseFontSize();
    final pointsFontSize = layout.dialogBaseFontSize() * 1.2;
    const cellPad = 4.0;

    Widget pointsCell(Object p) => _paddingAll(cellPad,
        Text(p.toString(), textAlign: TextAlign.right, style: TextStyle(fontSize: pointsFontSize)));

    Widget headerCell(String msg) => _paddingAll(
        cellPad,
        Text(msg,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)));

    Widget catImageCell(int imageIndex) {
      final imageHeight = headerFontSize * 1.3;
      final leftPadding = headerFontSize * 1.1;
      return Padding(
          padding: EdgeInsets.only(left: leftPadding),
          child: Image.asset(catImageForIndex(imageIndex), height: imageHeight));
    }

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
            insetPadding: EdgeInsets.zero,
            backgroundColor: dialogBackgroundColor,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (match.isMatchOver())
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(
                        10,
                        Text(matchOverMessage(),
                            style: TextStyle(fontSize: layout.dialogHeaderFontSize()))),
                  ],
                ),
              _paddingAll(
                  10,
                  Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(children: [
                        _paddingAll(cellPad, headerCell("")),
                        _paddingAll(cellPad, headerCell("You")),
                        _paddingAll(cellPad, catImageCell(catImageIndices[1])),
                        _paddingAll(cellPad, catImageCell(catImageIndices[2])),
                        _paddingAll(cellPad, catImageCell(catImageIndices[3])),
                      ]),
                      pointsRow("Previous", match.currentRound.initialScores),
                      pointsRow("Round score", scores),
                      pointsRow("Total score", match.scores),
                    ],
                  )),
              if (match.isMatchOver())
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(
                        15,
                        ElevatedButton(
                          child: const Text("Rematch"),
                          onPressed: onContinue,
                        )),
                    _paddingAll(
                        15,
                        ElevatedButton(
                          child: const Text("Main Menu"),
                          onPressed: onMainMenu,
                        )),
                  ],
                ),
              if (!match.isMatchOver())
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(
                        15,
                        ElevatedButton(
                          child: const Text("Continue"),
                          onPressed: onContinue,
                        ))
                  ],
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
