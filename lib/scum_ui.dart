import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:cards_with_cats/scum/scum.dart';
import 'package:cards_with_cats/scum/scum_ai.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:flutter/material.dart';

const dialogBackgroundColor = Color(0xF5F4F1E9);

// Fully opaque: the score summary must not let the table or the last trick
// show through the numbers.
const scoreDialogBackgroundColor = Color(0xFFF4F1E9);
const aiDelayMillis = 650;

/// How long the finished table stays uncovered so the cats' reactions to the
/// final standings can be seen before the score dialog appears.
const roundEndReactionDelay = Duration(milliseconds: 1600);

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
  // How many seats had already gone out the last time the cats reacted.
  int _finishesReactedTo = 0;
  bool showEndOfRoundDialog = false;
  Timer? _endOfRoundHold;
  late StreamSubscription matchUpdateSubscription;
  bool processingAi = false;
  Timer? _stallWatchdog;
  Timer? _dialogPoll;

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
    _stallWatchdog?.cancel();
    _dialogPoll?.cancel();
    _endOfRoundHold?.cancel();
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
    _finishesReactedTo = 0;
    _endOfRoundHold?.cancel();
    showEndOfRoundDialog = false;
    _prepareRoundIfNeeded();
    widget.saveMatchFn(match);
    _scheduleAiIfNeeded();
  }

  bool get isHumanTurn =>
      round.status == ScumRoundStatus.playing &&
      !round.isOver() &&
      round.currentPlayerIndex() == 0;

  void _scheduleAiIfNeeded({int minDelayMillis = aiDelayMillis}) {
    // Note: do NOT bail out when a menu dialog is open. Starting a new match
    // pushes the match through the update stream while the Start Match dialog
    // is still up; skipping the schedule here left the round permanently
    // stalled with nobody able to play. Instead the deferred callback waits
    // for the dialog to close.
    if (processingAi) return;
    if (round.status != ScumRoundStatus.playing) return;
    if (round.isOver()) {
      setState(() {
        _updateMoodsForFinishes();
      });
      return;
    }
    processingAi = true;
    Future.delayed(Duration(milliseconds: minDelayMillis), () {
      if (!mounted || !processingAi) return;
      if (widget.dialogVisible) {
        processingAi = false;
        _resumeWhenDialogCloses();
        return;
      }
      _armStallWatchdog();
      _runTurns();
    });
  }

  /// Polls until the menu closes, then resumes normal turn scheduling.
  void _resumeWhenDialogCloses() {
    _dialogPoll?.cancel();
    _dialogPoll = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted || round.status != ScumRoundStatus.playing) {
        timer.cancel();
        return;
      }
      if (!widget.dialogVisible) {
        timer.cancel();
        _scheduleAiIfNeeded(minDelayMillis: 100);
      }
    });
  }

  /// Safety net: if the turn engine ever dies with its latch set, kick it
  /// back to life instead of freezing the table.
  void _armStallWatchdog() {
    _stallWatchdog?.cancel();
    final timer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || !processingAi) return;
      if (round.status == ScumRoundStatus.playing &&
          !round.isOver() &&
          !(round.currentPlayerIndex() == 0 &&
              round.legalPlaysForCurrentPlayer().isNotEmpty)) {
        print("ScumUI: turn engine watchdog fired; resuming");
        processingAi = false;
        _scheduleAiIfNeeded(minDelayMillis: 150);
      }
    });
    _stallWatchdog = timer;
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
          // Waiting for the human to choose a play or pass. With exactly one
          // option it is selected automatically (#5).
          setState(() {
            processingAi = false;
            _stallWatchdog?.cancel();
            final legal = round.legalPlaysForCurrentPlayer();
            selectedCards =
                (legal.length == 1) ? List.of(legal.single) : [];
          });
          return;
        }
        _armStallWatchdog();
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
        try {
          if (playerIndex == 0) {
            round.pass();
          } else {
            final req = ScumPlayRequest.fromRound(round, playerIndex);
            var cards = chooseScumPlay(req, Random());
            if (cards.isNotEmpty &&
                !isValidPlay(round.players[playerIndex].hand, cards,
                    round.currentTrick)) {
              // Never let a bad AI choice freeze the table.
              cards = const [];
            }
            if (cards.isEmpty && !round.canCurrentPlayerPass()) {
              cards = round.legalPlaysForCurrentPlayer().first;
            }
            if (cards.isEmpty) {
              round.pass();
            } else {
              round.playCards(List.of(cards));
            }
          }
        } catch (e) {
          // Last-resort fallback so a bad state cannot stall the game.
          print("ScumUI: AI turn failed ($e); applying a legal fallback");
          if (round.canCurrentPlayerPass() &&
              round.currentPlayerIndex() != 0) {
            round.pass();
          } else {
            final legal = round.legalPlaysForCurrentPlayer();
            if (legal.isNotEmpty) round.playCards(legal.first);
          }
        }
        selectedCards = [];
        _updateMoodsForFinishes();
      });
      widget.saveMatchFn(match);
      // Progress happened: push the stall deadline out again.
      _armStallWatchdog();
      await Future.delayed(const Duration(milliseconds: aiDelayMillis));
    }
    if (mounted) {
      setState(() {
        processingAi = false;
        _stallWatchdog?.cancel();
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
      _updateMoodsForFinishes();
    });
    widget.saveMatchFn(match);
    _scheduleAiIfNeeded();
  }

  void _passTurn() {
    if (!isHumanTurn || !round.canCurrentPlayerPass()) return;
    setState(() {
      round.pass();
      selectedCards = [];
      _updateMoodsForFinishes();
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

  /// Cats react the moment a seat sheds its last card, not just at the end of
  /// the round (issue #19): whoever goes out first is grinning over the
  /// presidency they just won, second place is pleased with the vice
  /// presidency, and everyone still holding cards — now playing for Vice Scum
  /// and Scum — is annoyed about it. Called after every play; it only fires
  /// when the finish order has actually grown.
  void _updateMoodsForFinishes({bool force = false}) {
    final order = round.finishOrder();
    if (!force && order.length == _finishesReactedTo) return;
    _finishesReactedTo = order.length;
    if (order.isEmpty) return;
    playerMoods.clear();
    for (int i = 0; i < round.numberOfPlayers; i++) {
      final position = order.indexOf(i);
      if (position == 0) {
        playerMoods[i] = Mood.veryHappy;
      } else if (position == round.numberOfPlayers - 1) {
        // Scum, once the round is settled.
        playerMoods[i] = Mood.mad;
      } else if (position == 1) {
        playerMoods[i] = Mood.happy;
      } else if (position < 0) {
        // Still holding cards while somebody else banks a good rank.
        playerMoods[i] = Mood.mad;
      }
    }
    bool hasHappy = playerMoods.containsValue(Mood.happy) ||
        playerMoods.containsValue(Mood.veryHappy);
    bool hasMad = playerMoods.containsValue(Mood.mad);
    if (hasHappy) widget.soundPlayer.playHappySound();
    if (hasMad) widget.soundPlayer.playMadSound();
    if (round.isOver()) {
      _holdRoundEndForReactions();
    }
  }

  /// Let the cats have their moment on an uncovered table before the score
  /// dialog goes up over them (issue #17).
  void _holdRoundEndForReactions() {
    _endOfRoundHold?.cancel();
    showEndOfRoundDialog = false;
    _endOfRoundHold = Timer(roundEndReactionDelay, () {
      if (!mounted) return;
      setState(() {
        showEndOfRoundDialog = true;
        playerMoods.clear();
      });
    });
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
    // Card taps stay active during trading and while AI turns resolve —
    // swallowing them made quick taps feel like they needed repeating (#6).
    return widget.dialogVisible || round.isOver() || _shouldShowEndOfRoundDialog();
  }

  /// The played cards of the current trick, fanned near each player's seat.
  /// Center point of the played-set pile for a seat: an evenly spaced ring
  /// around the middle of the table, with the side seats pulled in toward
  /// the center (issue #9).
  Offset _trickPlayCenter(final Layout layout, final int player) {
    final ds = layout.displaySize;
    final ph = layout.playerHeight;
    switch (player) {
      case 2:
        return Offset(ds.width / 2, ds.height / 2 - ph * 1.9);
      case 0:
        // Keep the human pile in the open table area. The previous seat-ring
        // formula put it directly on top of a one-row hand on desktop-sized
        // Flatpak windows.
        return Offset(ds.width / 2, ds.height * 0.58);
      case 1:
        return Offset(ds.width * 0.33, ds.height / 2);
      default:
        return Offset(ds.width * 0.67, ds.height / 2);
    }
  }

  /// Height of played cards: much smaller than hand cards so they never
  /// crowd the hand at the bottom of the table.
  double _playCardHeight(final Layout layout) =>
      layout.displaySize.height * 0.115;

  /// Vertical position of the Play/Pass row: just above the tallest possible
  /// hand layout and below the bottom play pile.
  double _actionRowTop(final Layout layout) {
    final ds = layout.displaySize;
    final pileBottom = _trickPlayCenter(layout, 0).dy + _playCardHeight(layout) / 2;
    final handTop = ds.height * 0.69;
    return (pileBottom + handTop) / 2 - 22;
  }

  Widget _trickPlays(final Layout layout) {
    final widgets = <Widget>[];
    int globalIndex = 0;
    final playHeight = _playCardHeight(layout);
    final playWidth = playHeight * defaultCardAspectRatio;
    for (final action in round.currentTrick.actions) {
      if (action.cards.isEmpty) continue;
      final center = _trickPlayCenter(layout, action.player);
      final fanStep = playWidth * 0.28;
      final totalWidth = playWidth + (action.cards.length - 1) * fanStep;
      final startX = center.dx - totalWidth / 2;
      for (int i = 0; i < action.cards.length; i++) {
        final offset = globalIndex.toDouble();
        final rect = Rect.fromLTWH(
            startX + i * fanStep,
            center.dy - playHeight / 2 - offset * 2,
            playWidth,
            playHeight,
        );
        widgets.add(PositionedCard(
          key: ValueKey("scum-play-${action.player}-$globalIndex-$i-${action.cards[i]}"),
          rect: rect,
          card: action.cards[i],
          animateIn: true,
        ));
      }
      globalIndex += 1;
    }
    return Stack(children: widgets);
  }

  /// Role badges for every seat. They sit outside the play area so a rank
  /// never covers a card that has been played, and "Vice President" wraps onto
  /// two centered lines instead of stretching wide enough to reach the middle
  /// of the table (issue #17).
  Widget _statusBadges(final Layout layout) {
    final ds = layout.displaySize;
    final ph = layout.playerHeight;
    final ca = layout.cardArea();

    TextStyle badgeStyle(bool active, bool isScum) => TextStyle(
          fontSize: 13,
          height: 1.15,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active
              ? Colors.yellow.shade200
              : (isScum ? Colors.red.shade100 : Colors.white70),
        );

    Widget badge(int player) {
      final role = round.roleForPlayer(player);
      // "Vice President" and "Vice Scum" read better stacked and centered than
      // as one long line.
      final label = round.displayNameForPlayer(player).replaceFirst("Vice ", "Vice\n");
      final cardCount = round.players[player].hand.length;
      final isActive = round.status == ScumRoundStatus.playing &&
          !round.isOver() &&
          round.currentPlayerIndex() == player;
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isActive ? 0.75 : 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: badgeStyle(isActive, role == ScumRole.scum)),
            Text("$cardCount ${cardCount == 1 ? "Card" : "Cards"}",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: isActive ? Colors.yellow.shade100 : Colors.white60)),
          ],
        ),
      );
    }

    // Side seats sit above their play piles; the human's sits on the open strip
    // between the bottom pile and the hand, where the Play/Pass row leaves a
    // gap in the middle.
    final sideTop = ds.height / 2 - ph * 2.0;
    return Stack(children: [
      Positioned(
          left: 0,
          right: 0,
          top: _actionRowTop(layout) + 2,
          child: Center(child: badge(0))),
      Positioned(left: 4, top: sideTop, child: badge(1)),
      Positioned(left: 0, right: 0, top: ca.top + 4, child: Center(child: badge(2))),
      Positioned(right: 4, top: sideTop, child: badge(3)),
    ]);
  }

  bool _shouldShowTradeDialog() {
    return !widget.dialogVisible && round.status == ScumRoundStatus.trading;
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver() && showEndOfRoundDialog;
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
      _trickPlays(layout),
      // The hand remains above table effects as a final input-safety net.
      _playerCards(layout),
      _statusBadges(layout),
      if (_shouldShowTradeDialog())
        Center(
          child: Transform.scale(
            scale: layout.dialogScale(),
            child: Dialog(
              backgroundColor: dialogBackgroundColor,
              // Transform.scale doesn't change the laid-out size, so a dialog
              // sized to the full window spilled off both edges once it was
              // scaled up. Lay it out narrow enough that the scaled result fits.
              child: SizedBox(
                width: layout.displaySize.width / layout.dialogScale() - 32,
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paddingAll(10, Text(_tradeMessage(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15))),
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
        ),
      // Play sits on the right (under a right-handed thumb) and Pass on the
      // left, directly above the hand, inset partway toward the middle (#7).
      if (isHumanTurn && !processingAi)
        Positioned(
          top: _actionRowTop(layout),
          left: layout.displaySize.width * 0.10,
          right: layout.displaySize.width * 0.10,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (canPass)
                  ElevatedButton(
                    onPressed: _passTurn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Pass"),
                  )
                else
                  const SizedBox(),
                ElevatedButton(
                  onPressed: canPlaySelectedCards() ? _playSelectedCards : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Play"),
                ),
              ]),
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

  static const _roleAbbrev = {
    "President": "Pres.",
    "Vice President": "V.Pres.",
    "Vice Scum": "V.Scum",
    "Scum": "Scum",
    "Citizen": "Citizen",
  };

  TableRow row(String title, List<Object> values, {bool bold = false}) {
    Widget cell(Object v) => _paddingAll(
        3,
        Text(v.toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
    return TableRow(children: [
      _paddingAll(
          3,
          Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
      ...values.map(cell),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final round = match.currentRound;
    final order = round.finishOrder();
    final roundPoints = round.pointsTaken();

    Widget headerCell(String msg, {Widget? child}) => _paddingAll(
        3,
        child ??
            Text(msg,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)));

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
        child: Dialog(
            insetPadding: EdgeInsets.symmetric(
                horizontal: layout.displaySize.width * 0.04,
                vertical: layout.displaySize.height * 0.04),
            backgroundColor: scoreDialogBackgroundColor,
            child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: layout.displaySize.width * 0.92,
                  maxHeight: layout.displaySize.height * 0.9,
                ),
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (match.isMatchOver())
                    _paddingAll(
                        8,
                        Text(matchOverMessage(),
                            style: const TextStyle(fontSize: 22))),
                  _paddingAll(
                      8,
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
                              _roleAbbrev[round.displayNameForPlayer(p)] ??
                                  round.displayNameForPlayer(p)
                          ]),
                          row("Round points", [
                            for (int p = 0; p < round.numberOfPlayers; p++) roundPoints[p]
                          ]),
                          // match.scores is only folded forward by finishRound(),
                          // which runs when Continue is pressed — so the running
                          // total has to add this round's points itself.
                          row("Total score", [
                            for (int p = 0; p < round.numberOfPlayers; p++)
                              match.scores[p] + roundPoints[p]
                          ], bold: true),
                        ],
                      )),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _paddingAll(
                        12,
                        ElevatedButton(
                            onPressed: onContinue,
                            child: Text(match.isMatchOver() ? "Rematch" : "Continue"))),
                    if (match.isMatchOver())
                      _paddingAll(
                          12,
                          ElevatedButton(
                              onPressed: onMainMenu, child: const Text("Main Menu"))),
                  ]),
                ])))));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) => Opacity(opacity: val.clamp(0.0, 1.0), child: child!),
    );
  }
}
