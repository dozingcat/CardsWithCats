import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/material.dart';

import 'card_images.dart';
import 'common_ui.dart';
import 'cards/card.dart';
import 'rook/rook.dart';
import 'rook/rook_ai.dart';

const debugOutput = false;

void printd(String msg) {
  if (debugOutput) print(msg);
}

class RookMatchDisplay extends StatefulWidget {
  final RookMatch Function() initialMatchFn;
  final RookMatch Function() createMatchFn;
  final void Function(RookMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final bool tintTrumpCards;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;
  final StatsStore statsStore;
  final CardImageSet cardImageSet;

  const RookMatchDisplay({
    super.key,
    required this.initialMatchFn,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.dialogVisible,
    required this.catImageIndices,
    required this.tintTrumpCards,
    required this.matchUpdateStream,
    required this.soundPlayer,
    required this.statsStore,
    required this.cardImageSet,
  });

  @override
  RookMatchState createState() => RookMatchState();
}

// Trump suit first, then alternating colors. Before trump is chosen, uses the
// same order as when spades are trump.
List<Suit> _suitDisplayOrder(Suit? trump) {
  switch (trump) {
    case null:
    case Suit.spades:
      return [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];
    case Suit.hearts:
      return [Suit.hearts, Suit.spades, Suit.diamonds, Suit.clubs];
    case Suit.diamonds:
      return [Suit.diamonds, Suit.spades, Suit.hearts, Suit.clubs];
    case Suit.clubs:
      return [Suit.clubs, Suit.hearts, Suit.spades, Suit.diamonds];
  }
}

// Sorts by suit and then descending rank, with the joker at the top of the
// trump suit (or the first suit, if trump hasn't been chosen).
HandOrdering rookHandOrdering(Suit? trump) {
  final suitOrder = _suitDisplayOrder(trump);
  (int, int) sortKey(PlayingCard c) => switch (c) {
    SuitedCard(:final suit, :final rank) => (suitOrder.indexOf(suit), -rank.index),
    JokerCard() => (0, -Rank.values.length),
  };
  int compareFn(PlayingCard a, PlayingCard b) {
    final (suitA, rankA) = sortKey(a);
    final (suitB, rankB) = sortKey(b);
    return (suitA != suitB) ? suitA - suitB : rankA - rankB;
  }
  return HandOrdering(compareFn, suitOrder);
}

class RookMatchState extends State<RookMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  // Shown after an AI player wins the bid and chooses trump.
  bool showContractDialog = false;
  Set<PlayingCard> selectedDiscards = {};
  Suit? selectedTrump;
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late RookMatch match;
  late StreamSubscription matchUpdateSubscription;

  RookRound get round => match.currentRound;

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is RookMatch) {
        _updateMatch(event);
      }
    });
    _scheduleNextActionIfNeeded();
  }

  @override
  void deactivate() {
    super.deactivate();
    matchUpdateSubscription.cancel();
  }

  void _updateMatch(RookMatch newMatch) {
    setState(() {
      match = newMatch;
      _startRound();
    });
  }

  void _resetRoundState() {
    playerMoods.clear();
    showContractDialog = false;
    selectedDiscards = {};
    selectedTrump = null;
  }

  // Called after the end of round dialog is dismissed, or when the round is
  // passed out and needs to be redealt.
  void _startRound() {
    _resetRoundState();
    if (round.isOver()) {
      match.finishRound();
    }
    if (match.isMatchOver()) {
      match = widget.createMatchFn();
    }
    widget.saveMatchFn(match);
    _scheduleNextActionIfNeeded();
  }

  void _scheduleNextActionIfNeeded() {
    if (round.isOver()) {
      return;
    }
    // Delayed actions check that the round and player haven't changed, in case
    // the match was replaced or the state was updated in the meantime.
    final r = round;
    switch (round.status) {
      case RookRoundStatus.bidding:
        final bidder = round.currentBidder();
        if (bidder != 0) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (identical(r, round) && round.status == RookRoundStatus.bidding && round.currentBidder() == bidder) {
              _makeBidForAiPlayer(bidder);
            }
          });
        }
      case RookRoundStatus.declarerChoosingCardsAndTrump:
        if (round.declarer() != 0) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (identical(r, round) && round.status == RookRoundStatus.declarerChoosingCardsAndTrump) {
              _discardAndChooseTrumpForAiPlayer();
            }
          });
        }
      case RookRoundStatus.playing:
        final player = round.currentPlayerIndex();
        final numPlayed = round.previousTricks.length * numPlayers + round.currentTrick.cards.length;
        if (player != 0 && !showContractDialog) {
          Future.delayed(const Duration(milliseconds: 750), () {
            final nowPlayed = round.previousTricks.length * numPlayers + round.currentTrick.cards.length;
            if (identical(r, round) && !round.isOver() && nowPlayed == numPlayed) {
              _playCard(chooseCardRandom(round, rng));
            }
          });
        }
    }
  }

  void _addBid(PlayerBid bid) {
    printd("P${bid.player} bids ${bid.bid ?? "pass"}");
    setState(() {
      round.addBid(bid);
    });
    widget.saveMatchFn(match);
    _scheduleNextActionIfNeeded();
  }

  void _makeBidForAiPlayer(int playerIndex) {
    final bid = chooseBid(round, playerIndex, rng);
    _addBid(PlayerBid(playerIndex, bid));
  }

  void _discardAndChooseTrumpForAiPlayer() {
    final choice = chooseDiscardsAndTrump(round, rng);
    setState(() {
      round.discardAndChooseTrump(choice.discards, choice.trump);
      showContractDialog = true;
    });
    widget.saveMatchFn(match);
  }

  void _handleContractDialogConfirm() {
    setState(() {
      showContractDialog = false;
    });
    _scheduleNextActionIfNeeded();
  }

  void _handleHumanDiscardsConfirmed() {
    setState(() {
      round.discardAndChooseTrump(selectedDiscards, selectedTrump!);
      selectedDiscards = {};
      selectedTrump = null;
    });
    widget.saveMatchFn(match);
    _scheduleNextActionIfNeeded();
  }

  void _playCard(final PlayingCard card) {
    playerMoods.clear();
    if (round.status == RookRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.movingTrickCard;
      });
      widget.saveMatchFn(match);
    }
  }

  void _updateMoodsAfterTrick() {
    playerMoods.clear();
    if (match.isMatchOver()) {
      final winner = match.winningTeam();
      for (int i = 1; i < numPlayers; i++) {
        playerMoods[i] = (i % numTeams == winner) ? Mood.veryHappy : Mood.mad;
      }
    } else if (round.isOver()) {
      // Declaring team is happy if they made the bid, mad if not.
      final contract = round.contract!;
      final declarerTeam = contract.declarer % numTeams;
      final madeBid = round.teamPointsTaken()[declarerTeam] >= contract.bid;
      for (int i = 1; i < numPlayers; i++) {
        if (i % numTeams == declarerTeam) {
          playerMoods[i] = madeBid ? Mood.happy : Mood.mad;
        }
      }
    } else {
      // Happy when taking the Rook card.
      final trick = round.previousTricks.last;
      if (trick.winner != 0 && trick.cards.contains(joker)) {
        playerMoods[trick.winner] = Mood.happy;
      }
    }
  }

  void _playSoundsForMoods() {
    if (match.isMatchOver()) {
      if (match.winningTeam() == 0) {
        widget.soundPlayer.playHappySound();
      } else {
        widget.soundPlayer.playMadSound();
      }
    } else {
      if (playerMoods.containsValue(Mood.happy) || playerMoods.containsValue(Mood.veryHappy)) {
        widget.soundPlayer.playHappySound();
      }
      if (playerMoods.containsValue(Mood.mad)) {
        widget.soundPlayer.playMadSound();
      }
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {
        animationMode = AnimationMode.none;
      });
      _scheduleNextActionIfNeeded();
    } else {
      setState(() {
        animationMode = AnimationMode.movingTrickToWinner;
        _updateMoodsAfterTrick();
        _playSoundsForMoods();
      });
    }
  }

  void _trickToWinnerAnimationFinished() {
    setState(() {
      animationMode = AnimationMode.none;
    });
    _scheduleNextActionIfNeeded();
  }

  bool _isHumanChoosingDiscards() {
    return round.status == RookRoundStatus.declarerChoosingCardsAndTrump && round.declarer() == 0;
  }

  void handleHandCardClicked(final PlayingCard card) {
    printd("Clicked $card, status: ${round.status}");
    if (widget.dialogVisible) {
      return;
    }
    if (round.status == RookRoundStatus.playing && round.currentPlayerIndex() == 0 && !showContractDialog) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        _playCard(card);
      }
    } else if (_isHumanChoosingDiscards()) {
      setState(() {
        if (selectedDiscards.contains(card)) {
          selectedDiscards.remove(card);
        } else if (selectedDiscards.length < numNestCards) {
          selectedDiscards.add(card);
        }
      });
    }
  }

  Suit? _trumpSuit() => round.contract?.trump ?? (_isHumanChoosingDiscards() ? selectedTrump : null);

  Map<PlayingCard, Color> _cardBackgrounds() {
    // Tint the nest cards while choosing discards.
    if (_isHumanChoosingDiscards()) {
      return {for (final c in round.initialNest) c: Colors.lightBlue.shade200};
    }
    return {};
  }

  Widget _playerCards(final Layout layout) {
    if (_shouldShowEndOfRoundDialog()) {
      return const SizedBox();
    }
    final handOrdering = rookHandOrdering(_trumpSuit());
    final isChoosingDiscards = _isHumanChoosingDiscards();
    // While choosing discards, the nest cards are shown in the player's hand.
    List<PlayingCard> humanCards = isChoosingDiscards ? round.declarerAvailableCards() : round.players[0].hand;
    List<PlayingCard> highlightedCards = [];
    if (round.status == RookRoundStatus.bidding) {
      highlightedCards = humanCards;
    } else if (isChoosingDiscards) {
      highlightedCards = humanCards.where((c) => !selectedDiscards.contains(c)).toList();
    } else if (round.status == RookRoundStatus.playing && round.currentPlayerIndex() == 0 && !showContractDialog) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    final playerTrickCard = lastCardPlayedByPlayer(
      playerIndex: 0,
      numberOfPlayers: numPlayers,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
    );
    final previousPlayerCards = (playerTrickCard != null) ? [...humanCards, playerTrickCard] : null;
    // Flutter needs a key property to determine whether the PlayerHandCards
    // component has changed between renders.
    var key = "H${humanCards.map((c) => c.toString()).join()}";
    if (playerTrickCard != null) {
      key += ":${playerTrickCard.toString()}";
    }

    return MultiplePlayerHandCards(
      layout: layout,
      playerHands: [PlayerHandParams(
        key: Key(key),
        playerIndex: 0,
        cards: humanCards,
        highlightedCards: highlightedCards,
        animateFromCards: previousPlayerCards,
        onCardClicked: handleHandCardClicked,
      )],
      handOrdering: handOrdering,
      trumpSuit: widget.tintTrumpCards ? _trumpSuit() : null,
      cardBackgroundColors: _cardBackgrounds(),
    );
  }

  Widget _trickCards(final Layout layout) {
    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
      trumpSuit: widget.tintTrumpCards ? round.contract?.trump : null,
      animationMode: animationMode,
      numPlayers: numPlayers,
      displayedHands: [DisplayedHand(playerIndex: 0, cards: round.players[0].hand)],
      handOrdering: rookHandOrdering(round.contract?.trump),
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  List<String> _currentRoundScoreMessages() {
    final messages = <String>[];
    // Points so far, not including the nest which goes to the last trick winner.
    final teamPoints = List.filled(numTeams, 0);
    for (final t in round.previousTricks) {
      teamPoints[t.winner % numTeams] += pointsForCards(t.cards, round.rules);
    }
    for (int i = 0; i < numPlayers; i++) {
      final team = i % numTeams;
      var msg = "Score: ${round.initialScores[team]}";
      if (round.status == RookRoundStatus.playing) {
        msg += "\nPoints: ${teamPoints[team]}";
        if (round.contract!.declarer == i) {
          msg += "\nBid ${round.contract!.bid}";
        }
      }
      messages.add(msg);
    }
    return messages;
  }

  bool _shouldShowScoreOverlay() {
    return showScoreOverlay && !widget.dialogVisible && !round.isOver();
  }

  bool _shouldShowScoreOverlayToggle() {
    return !widget.dialogVisible && !round.isOver();
  }

  // The bid dialog stays visible for the whole auction, and while an AI player
  // who won the bid is choosing trump.
  bool _shouldShowBidDialog() {
    return !widget.dialogVisible &&
        (round.status == RookRoundStatus.bidding ||
            (round.status == RookRoundStatus.declarerChoosingCardsAndTrump && round.declarer() != 0));
  }

  bool _shouldShowDiscardDialog() {
    return !widget.dialogVisible && _isHumanChoosingDiscards();
  }

  bool _shouldShowContractDialog() {
    return !widget.dialogVisible && showContractDialog;
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver() && !round.isPassedOut();
  }

  Widget _bidTable() {
    const headerStyle = TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold);
    Widget catImageCell(int playerIndex) => paddingHorizontal(12,
        Image.asset(catImageForIndex(widget.catImageIndices[playerIndex]), height: 18));
    final isBidding = round.status == RookRoundStatus.bidding && !round.isPassedOut();
    return BidTable(
      headerCells: [
        paddingHorizontal(12, const Text("You", textAlign: TextAlign.center, style: headerStyle)),
        catImageCell(1),
        catImageCell(2),
        catImageCell(3),
      ],
      entries: [
        for (final b in round.bidHistory) BidTableEntry(b.player, b.isPass ? "Pass" : b.bid.toString()),
      ],
      firstBidder: (round.dealer + 1) % numPlayers,
      nextBidder: isBidding ? round.currentBidder() : null,
    );
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context, cardImageSet: widget.cardImageSet);

    return Stack(
      children: <Widget>[
        _playerCards(layout),
        _trickCards(layout),

        if (_shouldShowBidDialog())
          RookBidDialog(
            // Recreate the dialog for each bid, so it starts at the new minimum.
            key: ValueKey(round.bidHistory.length),
            layout: layout,
            round: round,
            bidTable: _bidTable(),
            onBid: (bid) => _addBid(PlayerBid(0, bid)),
            onRedeal: () => setState(_startRound),
          ),
        if (_shouldShowDiscardDialog())
          RookDiscardDialog(
            layout: layout,
            round: round,
            selectedDiscards: selectedDiscards,
            selectedTrump: selectedTrump,
            onTrumpSelected: (suit) => setState(() {selectedTrump = suit;}),
            onConfirm: _handleHumanDiscardsConfirmed,
          ),
        if (_shouldShowContractDialog())
          RookMessageDialog(
            layout: layout,
            message: Column(mainAxisSize: MainAxisSize.min, children: [
              _bidTable(),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                ..._playerLabel(round.contract!.declarer, widget.catImageIndices),
                Text(" won the bid at ${round.contract!.bid}. Trump is ${round.contract!.trump.symbolChar}."),
              ]),
            ]),
            buttonLabel: "Start round",
            onConfirm: _handleContractDialogConfirm,
          ),
        if (_shouldShowEndOfRoundDialog())
          RookEndOfRoundDialog(
            layout: layout,
            match: match,
            onContinue: () => setState(_startRound),
            onMainMenu: _showMainMenuAfterMatch,
            catImageIndices: widget.catImageIndices,
          ),
        PlayerMoods(layout: layout, moods: playerMoods),
        if (_shouldShowScoreOverlay())
          PlayerMessagesOverlay(layout: layout, messages: _currentRoundScoreMessages()),
        if (_shouldShowScoreOverlayToggle()) scoreToggleIconButton(
          layout: layout,
          onPressed: () {
            setState(() {
              showScoreOverlay = !showScoreOverlay;
            });
          },
          showingScore: showScoreOverlay,
        ),
      ],
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

// "You", or the player's cat image.
List<Widget> _playerLabel(int playerIndex, List<int> catImageIndices, {double height = 16}) {
  if (playerIndex == 0) {
    return [const Text("You")];
  }
  return [Image.asset(catImageForIndex(catImageIndices[playerIndex]), height: height)];
}

class RookBidDialog extends StatefulWidget {
  final Layout layout;
  final RookRound round;
  final Widget bidTable;
  final void Function(int?) onBid;
  final void Function() onRedeal;

  const RookBidDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.bidTable,
    required this.onBid,
    required this.onRedeal,
  });

  @override
  State<RookBidDialog> createState() => _RookBidDialogState();
}

class _RookBidDialogState extends State<RookBidDialog> {
  late int bidAmount;

  RookRound get round => widget.round;
  RookRuleSet get rules => round.rules;

  int minimumBid() {
    final high = highBid(round.bidHistory);
    return (high == null) ? rules.minimumBid : high.bid! + rules.bidIncrement;
  }

  @override
  void initState() {
    super.initState();
    bidAmount = min(minimumBid(), rules.maximumBid);
  }

  bool isHumanBidding() =>
      round.status == RookRoundStatus.bidding && !round.isPassedOut() && round.currentBidder() == 0;

  bool canDecrementBid() => bidAmount - rules.bidIncrement >= minimumBid();

  bool canIncrementBid() => bidAmount + rules.bidIncrement <= rules.maximumBid;

  @override
  Widget build(BuildContext context) {
    const adjustBidTextStyle = TextStyle(fontSize: 18, height: 0);
    const rowPadding = 15.0;
    final isBidding = isHumanBidding();
    // Bid controls are shown (but disabled while others bid) until the human
    // player passes.
    final showBidControls = round.status == RookRoundStatus.bidding &&
        !round.isPassedOut() && !round.hasPlayerPassed(0);

    return Center(
        child: Transform.translate(
            offset: Offset(0, -widget.layout.displaySize.height * 0.1),
            child: Transform.scale(scale: widget.layout.dialogScale(), child: Dialog(
            backgroundColor: dialogBackgroundColor,
            child: FittedBox(fit: .scaleDown, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                paddingAll(10, widget.bidTable),
                if (round.isPassedOut()) ...[
                  const Text("Everyone passed. The cards will be redealt."),
                  paddingAll(rowPadding, ElevatedButton(onPressed: widget.onRedeal, child: const Text("Redeal"))),
                ],
                if (showBidControls) ...[
                  Row(
                      spacing: 12,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: (isBidding && canDecrementBid()) ? () => setState(() {bidAmount -= rules.bidIncrement;}) : null,
                          child: const Text("–", style: adjustBidTextStyle),
                        ),
                        Text(bidAmount.toString(), style: adjustBidTextStyle),
                        ElevatedButton(
                          onPressed: (isBidding && canIncrementBid()) ? () => setState(() {bidAmount += rules.bidIncrement;}) : null,
                          child: const Text("+", style: adjustBidTextStyle),
                        ),
                      ]),
                  paddingAll(
                      rowPadding,
                      Row(
                          spacing: 8,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: (isBidding && round.canCurrentBidderMakeBid(bidAmount)) ? () => widget.onBid(bidAmount) : null,
                              child: Text("Bid $bidAmount"),
                            ),
                            ElevatedButton(
                              onPressed: isBidding ? () => widget.onBid(null) : null,
                              child: const Text("Pass"),
                            ),
                          ])),
                ],
                if (!showBidControls && !round.isPassedOut()) const SizedBox(height: rowPadding),
              ],
            ))))));
  }
}

class RookDiscardDialog extends StatelessWidget {
  final Layout layout;
  final RookRound round;
  final Set<PlayingCard> selectedDiscards;
  final Suit? selectedTrump;
  final void Function(Suit) onTrumpSelected;
  final void Function() onConfirm;

  const RookDiscardDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.selectedDiscards,
    required this.selectedTrump,
    required this.onTrumpSelected,
    required this.onConfirm,
  });

  String _buttonLabel() {
    final remaining = numNestCards - selectedDiscards.length;
    if (remaining > 0) {
      return "Select $remaining more";
    }
    if (!round.isValidDiscardForDeclarer(selectedDiscards)) {
      return "Can't discard point cards";
    }
    if (selectedTrump == null) {
      return "Choose trump";
    }
    return "Start round";
  }

  bool _isButtonEnabled() {
    return selectedTrump != null && round.isValidDiscardForDeclarer(selectedDiscards);
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    final halfPadding = textStyle.fontSize! * 0.5;
    // The declarer's hand has the nest cards added and may take two rows, so
    // keep the dialog compact and move it up so it doesn't cover any cards.
    return Center(child: Transform.translate(
      offset: Offset(0, -layout.displaySize.height * 0.15),
      child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: FittedBox(fit: .scaleDown, child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: halfPadding,
          children: [

            paddingAll(halfPadding, Text(
                "You won the bid at ${round.winningBid().bid}.\n"
                "Choose $numNestCards cards to discard, and the trump suit.",
                style: textStyle, textAlign: TextAlign.center)),
            if (!round.rules.allowDiscardingPointCards)
              const Text("Point cards can't be discarded.", style: TextStyle(fontSize: 12)),

            SegmentedButton<Suit>(
              segments: const [
                ButtonSegment(value: Suit.clubs, label: Text("♣")),
                ButtonSegment(value: Suit.diamonds, label: Text("♦")),
                ButtonSegment(value: Suit.hearts, label: Text("♥")),
                ButtonSegment(value: Suit.spades, label: Text("♠")),
              ],
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              selected: {?selectedTrump},
              onSelectionChanged: (Set<Suit> suits) {
                if (suits.isNotEmpty) {
                  onTrumpSelected(suits.first);
                }
              },
            ),

            ElevatedButton(
              onPressed: _isButtonEnabled() ? onConfirm : null,
              child: Text(_buttonLabel()),
            ),
            SizedBox(height: halfPadding),
          ],
        )),
      ),
    )));
  }
}

class RookMessageDialog extends StatelessWidget {
  final Layout layout;
  final Widget message;
  final String buttonLabel;
  final void Function() onConfirm;

  const RookMessageDialog({
    super.key,
    required this.layout,
    required this.message,
    required this.buttonLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    final halfPadding = textStyle.fontSize! * 0.75;
    return Center(child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: halfPadding),
            paddingAll(halfPadding, DefaultTextStyle.merge(style: textStyle, child: message)),
            paddingAll(halfPadding, ElevatedButton(onPressed: onConfirm, child: Text(buttonLabel))),
            SizedBox(height: halfPadding),
          ],
        ))));
  }
}

class RookEndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final RookMatch match;
  final Function() onContinue;
  final Function() onMainMenu;
  final List<int> catImageIndices;

  const RookEndOfRoundDialog({
    super.key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
    required this.catImageIndices,
  });

  @override
  Widget build(BuildContext context) {
    final round = match.currentRound;
    final contract = round.contract!;
    final pointsTaken = round.teamPointsTaken();
    final roundScores = round.contractScoresForTeams();
    final madeBid = pointsTaken[contract.declarer % numTeams] >= contract.bid;
    const headerFontSize = 14.0;
    const pointsFontSize = headerFontSize * 1.2;
    const cellPad = 4.0;
    const catImageHeight = headerFontSize * 1.3;
    const headerStyle = TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold);

    Widget pointsCell(Object p) => paddingAll(cellPad,
        Text(p.toString(), textAlign: TextAlign.right, style: const TextStyle(fontSize: pointsFontSize)));

    Widget headerCell(String msg) => paddingAll(cellPad, Text(msg, textAlign: TextAlign.right, style: headerStyle));

    Widget humanTeamHeaderCell() => Row(children: [
          const Text("You", style: headerStyle),
          const SizedBox(width: headerFontSize * 0.1),
          const Text("/", style: headerStyle),
          Image.asset(catImageForIndex(catImageIndices[2]), height: catImageHeight),
        ]);

    Widget opponentTeamHeaderCell() => Padding(
        padding: const EdgeInsets.only(left: headerFontSize * 1.25),
        child: Row(children: [
          Image.asset(catImageForIndex(catImageIndices[1]), height: catImageHeight),
          const Text(" /", style: headerStyle),
          Image.asset(catImageForIndex(catImageIndices[3]), height: catImageHeight),
        ]));

    TableRow pointsRow(String title, List<Object> points) => TableRow(children: [
          paddingAll(cellPad, headerCell(title)),
          ...points.map((p) => paddingAll(cellPad, pointsCell(p.toString())))
        ]);

    String matchOverMessage() => match.winningTeam() == 0 ? "You win!" : "You lose :(";

    final dialog = Center(
        child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: dialogBackgroundColor,
            child: FittedBox(fit: .scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (match.isMatchOver())
                paddingAll(10, Text(matchOverMessage(), style: const TextStyle(fontSize: 26))),
              Padding(padding: const EdgeInsets.all(10), child: Row(mainAxisSize: MainAxisSize.min, children: [
                ..._playerLabel(contract.declarer, catImageIndices, height: catImageHeight),
                Text(" bid ${contract.bid} and "
                    "${madeBid ? "made it." : "failed."}"),
              ])),
              paddingAll(
                  10,
                  Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(children: [
                        paddingAll(cellPad, const SizedBox()),
                        paddingAll(cellPad, humanTeamHeaderCell()),
                        paddingAll(cellPad, opponentTeamHeaderCell()),
                      ]),
                      pointsRow("Previous score", round.initialScores),
                      pointsRow("Points taken", pointsTaken),
                      pointsRow("Round score", roundScores),
                      pointsRow("Total score", match.scores),
                    ],
                  )),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (match.isMatchOver()) ...[
                    paddingAll(15, ElevatedButton(onPressed: onContinue, child: const Text("Rematch"))),
                    paddingAll(15, ElevatedButton(onPressed: onMainMenu, child: const Text("Main Menu"))),
                  ] else
                    paddingAll(15, ElevatedButton(onPressed: onContinue, child: const Text("Continue"))),
                ],
              ),
            ])))));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) => Opacity(opacity: val.clamp(0.0, 1.0), child: child),
    );
  }
}
