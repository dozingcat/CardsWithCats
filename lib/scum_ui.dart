import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum/scum_ai.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:flutter/material.dart';

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);
const aiDelayMillis = 650;

Widget _paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

class ScumMatchDisplay extends StatefulWidget {
  final ScumMatch Function() initialMatchFn;
  final ScumMatch Function() createMatchFn;
  final void Function(ScumMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;

  const ScumMatchDisplay({
    Key? key,
    required this.initialMatchFn,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.dialogVisible,
    required this.catImageIndices,
    required this.matchUpdateStream,
    required this.soundPlayer,
  }) : super(key: key);

  @override
  _ScumMatchState createState() => _ScumMatchState();
}

class _ScumMatchState extends State<ScumMatchDisplay> {
  late ScumMatch match;
  List<PlayingCard> selectedCards = [];
  Map<int, Mood> playerMoods = {};
  late StreamSubscription matchUpdateSubscription;
  bool processingAi = false;

  ScumRound get round => match.currentRound;

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is ScumMatch) {
        setState(() {
          match = event;
          _startRound();
        });
      }
    });
    _prepareRoundIfNeeded();
    _scheduleAiIfNeeded();
  }

  @override
  void deactivate() {
    super.deactivate();
    matchUpdateSubscription.cancel();
  }

  void _prepareRoundIfNeeded() {
    // Fill in AI trade selections so the exchange can proceed once the human
    // has made any required choice.
    if (round.status == ScumRoundStatus.trading) {
      for (int i = 1; i < round.numberOfPlayers; i++) {
        final needed = round.numCardsToSelectForTrade(i);
        if (needed > 0 && round.tradeSelections[i].length != needed) {
          round.setTradeSelection(
              i,
              chooseCardsToGive(ScumTradeRequest(
                hand: round.players[i].hand,
                count: needed,
                myRole: round.roleForPlayer(i),
              )));
        }
      }
    }
  }

  void _startRound() {
    selectedCards = [];
    playerMoods.clear();
    _prepareRoundIfNeeded();
    widget.saveMatchFn(match);
    _scheduleAiIfNeeded();
  }

  bool get isHumanTurn =>
      round.status == ScumRoundStatus.playing &&
      !round.isOver() &&
      round.currentPlayerIndex() == 0;

  void _scheduleAiIfNeeded({int minDelayMillis = aiDelayMillis}) {
    if (widget.dialogVisible) return;
    if (round.status != ScumRoundStatus.playing) return;
    if (round.isOver()) {
      _updateMoodsAfterRound();
      return;
    }
    if (processingAi) return;
    processingAi = true;
    Future.delayed(Duration(milliseconds: minDelayMillis), () {
      if (!mounted) return;
      _runTurns();
    });
  }

  /// Plays out turns (with small pauses) until the human can choose a play.
  /// A human turn with no legal plays passes automatically (issue #3).
  Future<void> _runTurns() async {
    while (mounted &&
        round.status == ScumRoundStatus.playing &&
        !round.isOver() &&
        processingAi) {
      final playerIndex = round.currentPlayerIndex();
      if (playerIndex == 0) {
        if (round.legalPlaysForCurrentPlayer().isNotEmpty) {
          // Waiting for the human to choose a play or pass.
          setState(() {
            processingAi = false;
          });
          return;
        }
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted ||
            round.status != ScumRoundStatus.playing ||
            round.isOver() ||
            round.currentPlayerIndex() != 0 ||
            round.legalPlaysForCurrentPlayer().isNotEmpty) {
          continue;
        }
      }
      setState(() {
        if (playerIndex == 0) {
          round.pass();
        } else {
          final req = ScumPlayRequest.fromRound(round, playerIndex);
          final cards = chooseScumPlay(req, Random());
          if (cards.isEmpty) {
            round.pass();
          } else {
            round.playCards(cards);
          }
        }
        selectedCards = [];
        if (round.isOver()) {
          _updateMoodsAfterRound();
        }
      });
      widget.saveMatchFn(match);
      await Future.delayed(const Duration(milliseconds: aiDelayMillis));
    }
    if (mounted) {
      setState(() {
        processingAi = false;
      });
      _scheduleAiIfNeeded();
    }
  }

  void _playSelectedCards() {
    if (!isHumanTurn || !isValidPlay(round.players[0].hand, selectedCards, round.currentTrick)) {
      return;
    }
    setState(() {
      round.playCards(List.of(selectedCards));
      selectedCards = [];
      if (round.isOver()) {
        _updateMoodsAfterRound();
      }
    });
    widget.saveMatchFn(match);
    _scheduleAiIfNeeded();
  }

  void _passTurn() {
    if (!isHumanTurn || !round.canCurrentPlayerPass()) return;
    setState(() {
      round.pass();
      selectedCards = [];
      if (round.isOver()) {
        _updateMoodsAfterRound();
      }
    });
    widget.saveMatchFn(match);
    _scheduleAiIfNeeded();
  }

  /// Whether the human has made any required trade selection.
  bool _humanTradeSelectionReady() {
    final needed = round.numCardsToSelectForTrade(0);
    return needed == 0 || selectedCards.length == needed;
  }

  void _exchangeCards() {
    final needed = round.numCardsToSelectForTrade(0);
    if (needed > 0) {
      if (selectedCards.length != needed) return;
      round.setTradeSelection(0, List.of(selectedCards));
    }
    if (!round.readyToExchange()) return;
    setState(() {
      round.exchangeCards();
      selectedCards = [];
    });
    widget.saveMatchFn(match);
    _scheduleAiIfNeeded(minDelayMillis: 400);
  }

  void _continueToNextRound() {
    setState(() {
      match.finishRound();
      _startRound();
    });
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  void _rematch() {
    final newMatch = widget.createMatchFn();
    setState(() {
      match = newMatch;
      _startRound();
    });
  }

  void _updateMoodsAfterRound() {
    playerMoods.clear();
    final order = round.finishOrder();
    for (int i = 1; i < round.numberOfPlayers; i++) {
      final position = order.indexOf(i);
      if (position == 0) {
        playerMoods[i] = Mood.veryHappy;
      } else if (position == round.numberOfPlayers - 1) {
        playerMoods[i] = Mood.mad;
      } else if (position <= 1) {
        playerMoods[i] = Mood.happy;
      }
    }
    bool hasHappy = playerMoods.containsValue(Mood.happy) ||
        playerMoods.containsValue(Mood.veryHappy);
    bool hasMad = playerMoods.containsValue(Mood.mad);
    if (hasHappy) widget.soundPlayer.playHappySound();
    if (hasMad) widget.soundPlayer.playMadSound();
  }

  void handleHandCardClicked(final PlayingCard card) {
    if (widget.dialogVisible) return;
    if (round.status == ScumRoundStatus.trading) {
      final needed = round.numCardsToSelectForTrade(0);
      if (needed == 0) return;
      setState(() {
        if (selectedCards.contains(card)) {
          selectedCards.remove(card);
        } else if (selectedCards.length < needed) {
          selectedCards.add(card);
        }
      });
      return;
    }
    if (!isHumanTurn) return;
    // Selecting a card selects all copies of that rank (issue #4). Tapping a
    // selected card again removes just that card, so partial sets remain
    // playable. When following, the batch is clamped to the required size.
    final hand = round.players[0].hand;
    setState(() {
      if (selectedCards.contains(card)) {
        selectedCards = [...selectedCards]..remove(card);
        return;
      }
      if (selectedCards.isNotEmpty && selectedCards[0].rank != card.rank) {
        selectedCards = [];
      }
      var target = hand.where((c) => c.rank == card.rank).length;
      final best = round.currentTrick.bestAction;
      if (best != null && best.player != 0) {
        target = min(target, best.cards.length);
      }
      target = min(target, 4);
      final copies =
          hand.where((c) => c.rank == card.rank).toList()
            ..sort((a, b) => b.suit.index - a.suit.index);
      selectedCards = copies.sublist(0, min(target, copies.length));
    });
  }

  bool canPlaySelectedCards() {
    return isHumanTurn &&
        isValidPlay(round.players[0].hand, selectedCards, round.currentTrick);
  }

  /// Scum ignores suits: the hand reads best to worst, aces on the left and
  /// twos on the right (issue #1).
  static List<PlayingCard> _rankSortHand(Iterable<PlayingCard> cards) {
    final list = [...cards];
    list.sort((a, b) {
      int cmp = b.rank.index - a.rank.index;
      if (cmp != 0) return cmp;
      return b.suit.index - a.suit.index;
    });
    return list;
  }

  Widget _playerCards(final Layout layout) {
    const suitOrder = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];
    final humanHand = round.players[0].hand;
    Iterable<PlayingCard> highlighted = const [];
    if (round.status == ScumRoundStatus.trading && round.numCardsToSelectForTrade(0) > 0 ||
        isHumanTurn) {
      highlighted = [
        ...humanHand.where((c) => !selectedCards.contains(c))
      ];
    }
    return PlayerHandCards(
      layout: layout,
      suitDisplayOrder: suitOrder,
      cards: humanHand,
      highlightedCards: highlighted,
      onCardClicked: (_shouldIgnoreCardClicks()) ? null : handleHandCardClicked,
      playerIndex: 0,
      customCardSort: _rankSortHand,
    );
  }

  bool _shouldIgnoreCardClicks() {
    // Card taps stay active during the trading phase so the president and
    // vice president can select cards to give away.
    return widget.dialogVisible || processingAi || _shouldShowEndOfRoundDialog();
  }

  /// The played cards of the current trick, fanned near each player's seat.
  /// Center point of the played-set pile for a seat. The bottom seat is
  /// biased upward so plays never cover the human hand.
  Offset _trickPlayCenter(final Layout layout, final int player) {
    var center = layout.trickCardAreaForPlayer(player).center;
    if (player == 0) {
      center -= Offset(0, layout.playerHeight * 1.5);
    }
    return center;
  }

  /// Height of played cards: much smaller than hand cards so they never
  /// crowd the hand at the bottom of the table.
  double _playCardHeight(final Layout layout) =>
      layout.displaySize.height * 0.115;

  Widget _trickPlays(final Layout layout) {
    final widgets = <Widget>[];
    int globalIndex = 0;
    final playHeight = _playCardHeight(layout);
    final playWidth = playHeight * defaultCardAspectRatio;
    for (final action in round.currentTrick.actions) {
      if (action.cards.isEmpty) continue;
      final center = _trickPlayCenter(layout, action.player);
      final fanStep = playWidth * 0.38;
      final totalWidth = playWidth + (action.cards.length - 1) * fanStep;
      final startX = center.dx - totalWidth / 2;
      for (int i = 0; i < action.cards.length; i++) {
        final offset = globalIndex.toDouble();
        widgets.add(PositionedCard(
          rect: Rect.fromLTWH(
            startX + i * fanStep,
            center.dy - playHeight / 2 - offset * 2,
            playWidth,
            playHeight,
          ),
          card: action.cards[i],
        ));
      }
      globalIndex += 1;
    }
    return Stack(children: widgets);
  }

  Widget _statusBadges(final Layout layout) {
    final widgets = <Widget>[];
    final ca = layout.cardArea();
    TextStyle badgeStyle(bool active, bool isScum) => TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active
              ? Colors.yellow.shade200
              : (isScum ? Colors.red.shade100 : Colors.white70),
        );
    Color backdrop(bool active) =>
        active ? Colors.black.withValues(alpha: 0.75) : Colors.black38;

    Offset positionFor(int player, double badgeWidth) {
      switch (player) {
        case 1:
          return Offset(8, layout.displaySize.height / 2 - layout.playerHeight * 1.55);
        case 2:
          return Offset(layout.displaySize.width / 2 - badgeWidth / 2, ca.top + 4);
        case 3:
          return Offset(layout.displaySize.width - badgeWidth - 8,
              layout.displaySize.height / 2 - layout.playerHeight * 1.55);
        default:
          // Top-left corner, clear of the hand and the played cards.
          return const Offset(8, 8);
      }
    }

    for (int player = 0; player < round.numberOfPlayers; player++) {
      final role = round.roleForPlayer(player);
      final label = round.displayNameForPlayer(player);
      final cardCount = round.players[player].hand.length;
      final isActive = round.status == ScumRoundStatus.playing &&
          !round.isOver() &&
          round.currentPlayerIndex() == player;
      final badgeWidth = max(label.length, 7) * 8.5 + 20.0;
      final pos = positionFor(player, badgeWidth);
      widgets.add(Positioned(
        left: pos.dx,
        top: pos.dy,
        child: Container(
          decoration: BoxDecoration(
            color: backdrop(isActive),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label, style: badgeStyle(isActive, role == ScumRole.scum)),
              Text("$cardCount ${cardCount == 1 ? "card" : "cards"}",
                  style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? Colors.yellow.shade100
                          : Colors.white60)),
            ],
          ),
        ),
      ));
    }
    return Stack(children: widgets);
  }

  bool _shouldShowTradeDialog() {
    return !widget.dialogVisible && round.status == ScumRoundStatus.trading;
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver();
  }

  String _tradeMessage() {
    final role = round.roleForPlayer(0);
    switch (role) {
      case ScumRole.president:
        return "You're President! Choose 2 cards to give to the scummy Scum.";
      case ScumRole.vicePresident:
        return "You're Vice President. Choose 1 card to give to Vice Scum.";
      case ScumRole.viceScum:
        return "You're Vice Scum. Your highest card goes to the Vice President.";
      case ScumRole.scum:
        return "You're Scum :( Your two highest cards go to the President.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);
    final canPass = isHumanTurn && round.canCurrentPlayerPass();

    return Stack(children: <Widget>[
      _playerCards(layout),
      _trickPlays(layout),
      _statusBadges(layout),
      if (_shouldShowTradeDialog())
        Center(
          child: Transform.scale(
            scale: layout.dialogScale(),
            child: Dialog(
              backgroundColor: dialogBackgroundColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paddingAll(10, Text(_tradeMessage(), style: const TextStyle(fontSize: 15))),
                  if (round.numCardsToSelectForTrade(0) > 0)
                    _paddingAll(
                        5,
                        Text(
                            "Selected ${selectedCards.length} of ${round.numCardsToSelectForTrade(0)}",
                            style: const TextStyle(fontSize: 13))),
                  _paddingAll(
                      10,
                      ElevatedButton(
                        onPressed: _humanTradeSelectionReady()
                            ? _exchangeCards
                            : null,
                        child: Text(round.numCardsToSelectForTrade(0) > 0 &&
                                selectedCards.length !=
                                    round.numCardsToSelectForTrade(0)
                            ? "Select ${round.numCardsToSelectForTrade(0) - selectedCards.length} more"
                            : "Exchange cards"),
                      )),
                ],
              ),
            ),
          ),
        ),
      // The action row floats midway between the top cat's plays and the
      // bottom play pile, clear of both plus the badges and the hand.
      if (isHumanTurn && !processingAi)
        Positioned(
          top: (_trickPlayCenter(layout, 2).dy +
                  _trickPlayCenter(layout, 0).dy) /
              2 -
              30,
          left: 0,
          right: 0,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: canPlaySelectedCards() ? _playSelectedCards : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(canPass ? "Play set" : "Play"),
                ),
                const SizedBox(width: 16),
                if (canPass)
                  ElevatedButton(
                    onPressed: _passTurn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Pass"),
                  ),
              ],
            ),
        ),
      if (_shouldShowEndOfRoundDialog())
        EndOfRoundDialog(
          layout: layout,
          match: match,
          onContinue: match.isMatchOver() ? _rematch : _continueToNextRound,
          onMainMenu: _showMainMenuAfterMatch,
          catImageIndices: widget.catImageIndices,
        ),
      PlayerMoods(layout: layout, moods: playerMoods),
    ]);
  }
}

class EndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final ScumMatch match;
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

  TableRow row(String title, List<Object> values, {bool bold = false}) {
    Widget cell(Object v) => _paddingAll(
        4,
        Text(v.toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
    return TableRow(children: [
      _paddingAll(
          4,
          Text(title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
      ...values.map(cell),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final round = match.currentRound;
    final order = round.finishOrder();
    final roundPoints = round.pointsTaken();

    Widget headerCell(String msg, {Widget? child}) => _paddingAll(
        4,
        child ??
            Text(msg,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)));

    Widget catImageCell(int imageIndex) {
      return Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Image.asset(catImageForIndex(imageIndex), height: 20));
    }

    String matchOverMessage() {
      final winners = match.winningPlayers();
      if (winners.contains(0)) {
        return winners.length == 1 ? "You win!" : "You tied for the win!";
      }
      return "You lose :(";
    }

    final dialog = Center(
        child: Transform.scale(
            scale: layout.dialogScale(),
            child: Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: dialogBackgroundColor,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (match.isMatchOver())
                    _paddingAll(
                        10,
                        Text(matchOverMessage(),
                            style: const TextStyle(fontSize: 26))),
                  _paddingAll(
                      10,
                      Table(
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        defaultColumnWidth: const IntrinsicColumnWidth(),
                        children: [
                          TableRow(children: [
                            headerCell("Role"),
                            headerCell("You"),
                            headerCell("", child: catImageCell(catImageIndices[1])),
                            headerCell("", child: catImageCell(catImageIndices[2])),
                            headerCell("", child: catImageCell(catImageIndices[3])),
                          ]),
                          row("Finish", [
                            for (int p = 0; p < round.numberOfPlayers; p++)
                              "${order.indexOf(p) + 1}${order.indexOf(p) == 0 ? 'st' : order.indexOf(p) == 1 ? 'nd' : order.indexOf(p) == 2 ? 'rd' : 'th'}"
                          ]),
                          row("This round", [
                            for (int p = 0; p < round.numberOfPlayers; p++)
                              round.displayNameForPlayer(p)
                          ]),
                          row("Round points", [
                            for (int p = 0; p < round.numberOfPlayers; p++) roundPoints[p]
                          ]),
                          row("Total score", [
                            for (int p = 0; p < round.numberOfPlayers; p++) match.scores[p]
                          ], bold: true),
                        ],
                      )),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _paddingAll(
                        15,
                        ElevatedButton(
                            onPressed: onContinue,
                            child: Text(match.isMatchOver() ? "Rematch" : "Continue"))),
                    if (match.isMatchOver())
                      _paddingAll(
                          15,
                          ElevatedButton(
                              onPressed: onMainMenu, child: const Text("Main Menu"))),
                  ]),
                ]))));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) => Opacity(opacity: val.clamp(0.0, 1.0), child: child!),
    );
  }
}
