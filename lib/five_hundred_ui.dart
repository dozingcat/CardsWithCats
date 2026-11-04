import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'card_images.dart';
import 'common_ui.dart';
import 'cards/card.dart';
import 'five_hundred/five_hundred.dart';
import 'five_hundred/five_hundred_ai.dart';

const _debugOutput = false;

void _printd(String msg) {
  if (_debugOutput) print(msg);
}

FiveHundredBid? _computeAiBid((FiveHundredRound, int) args) => chooseBid(args.$1, args.$2, Random());

CardChoice _computeAiCard(FiveHundredRound round) =>
    chooseCardMonteCarlo(round, FiveHundredMonteCarloParams(numDeals: 100, maxTimeMillis: 2000), Random());

Set<PlayingCard> _computeAiDiscards(FiveHundredRound round) => chooseDiscards(round, Random());

// How AI players choose their actions. Tests can override these, and run them
// synchronously rather than in a separate isolate.
class FiveHundredAiFunctions {
  final FiveHundredBid? Function((FiveHundredRound, int) roundAndPlayer) chooseBid;
  final Set<PlayingCard> Function(FiveHundredRound round) chooseDiscards;
  final CardChoice Function(FiveHundredRound round) chooseCard;
  final bool runInIsolate;

  const FiveHundredAiFunctions({
    this.chooseBid = _computeAiBid,
    this.chooseDiscards = _computeAiDiscards,
    this.chooseCard = _computeAiCard,
    this.runInIsolate = true,
  });
}

class FiveHundredMatchDisplay extends StatefulWidget {
  final FiveHundredMatch Function() initialMatchFn;
  final FiveHundredMatch Function() createMatchFn;
  final void Function(FiveHundredMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final bool tintTrumpCards;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;
  final StatsStore statsStore;
  final CardImageSet cardImageSet;
  final FiveHundredAiFunctions aiFunctions;

  const FiveHundredMatchDisplay({
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
    this.aiFunctions = const FiveHundredAiFunctions(),
  });

  @override
  FiveHundredMatchState createState() => FiveHundredMatchState();
}

// Trump suit first, then alternating colors. Without a trump suit, uses the
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

// Sorts by suit and then descending rank. With a trump suit, the joker and
// both bowers are at the top of the trump suit. Without one, the joker is first.
HandOrdering fiveHundredHandOrdering(Suit? trump) {
  final suitOrder = _suitDisplayOrder(trump);
  (int, int) sortKey(PlayingCard c) {
    final suit = effectiveSuit(c, trump);
    return (suit == null) ? (-1, 0) : (suitOrder.indexOf(suit), -cardRankValue(c, trump));
  }
  int compareFn(PlayingCard a, PlayingCard b) {
    final (suitA, rankA) = sortKey(a);
    final (suitB, rankB) = sortKey(b);
    return (suitA != suitB) ? suitA - suitB : rankA - rankB;
  }
  return HandOrdering(compareFn, suitOrder);
}

// The joker and left bower are trumps, along with the cards of the trump suit.
IsTrumpFn? fiveHundredTrumpPredicate(Suit? trump) =>
    trump == null ? null : (card) => effectiveSuit(card, trump) == trump;

class FiveHundredMatchState extends State<FiveHundredMatchDisplay> {
  var animationMode = AnimationMode.none;
  // Shown after an AI player wins the bid and discards.
  bool showContractDialog = false;
  // Shown when the human player leads the joker in no trump.
  bool showJokerSuitDialog = false;
  Set<PlayingCard> selectedDiscards = {};
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late FiveHundredMatch match;
  late StreamSubscription matchUpdateSubscription;

  FiveHundredRound get round => match.currentRound;

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is FiveHundredMatch) {
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

  void _updateMatch(FiveHundredMatch newMatch) {
    setState(() {
      match = newMatch;
      _startRound();
    });
  }

  void _resetRoundState() {
    playerMoods.clear();
    showContractDialog = false;
    showJokerSuitDialog = false;
    selectedDiscards = {};
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
      case FiveHundredRoundStatus.bidding:
        final bidder = round.currentBidder();
        if (bidder != 0) {
          _runAiAction(
            ai.chooseBid, (round, bidder), 1000,
            isStillValid: () => identical(r, round) && round.status == FiveHundredRoundStatus.bidding && round.currentBidder() == bidder,
            apply: (FiveHundredBid? bid) => _addBid(PlayerBid(bidder, bid)),
          );
        }
      case FiveHundredRoundStatus.declarerDiscarding:
        if (round.declarer() != 0) {
          _runAiAction(
            ai.chooseDiscards, round, 1000,
            isStillValid: () => identical(r, round) && round.status == FiveHundredRoundStatus.declarerDiscarding,
            apply: _discardForAiPlayer,
          );
        }
      case FiveHundredRoundStatus.playing:
        final player = round.currentPlayerIndex();
        final numPlayed = round.previousTricks.length * numPlayers + round.currentTrick.cards.length;
        if (player != 0 && !showContractDialog) {
          _runAiAction(
            ai.chooseCard, round, 750,
            isStillValid: () {
              final nowPlayed = round.previousTricks.length * numPlayers + round.currentTrick.cards.length;
              return identical(r, round) && !round.isOver() && nowPlayed == numPlayed;
            },
            apply: (CardChoice choice) => _playCard(choice.$1, jokerLeadSuit: choice.$2),
          );
        }
    }
  }

  FiveHundredAiFunctions get ai => widget.aiFunctions;

  // Computes an AI action, normally in a separate isolate, and applies it
  // after at least `minDelayMillis` if the game state hasn't changed.
  void _runAiAction<Q, R>(R Function(Q) fn, Q arg, int minDelayMillis,
      {required bool Function() isStillValid, required void Function(R) apply}) async {
    final t1 = DateTime.now().millisecondsSinceEpoch;
    try {
      // Note: `compute` has an overhead of several hundred milliseconds in
      // debug mode, but not in release mode.
      final result = ai.runInIsolate ? await compute(fn, arg) : fn(arg);
      final elapsed = DateTime.now().millisecondsSinceEpoch - t1;
      Future.delayed(Duration(milliseconds: max(0, minDelayMillis - elapsed)), () {
        if (mounted && isStillValid()) {
          apply(result);
        }
      });
    } catch (ex) {
      print("*** Exception in AI computation: $ex");
    }
  }

  void _addBid(PlayerBid bid) {
    _printd("P${bid.player} bids ${bid.bid ?? "pass"}");
    setState(() {
      round.addBid(bid);
    });
    widget.saveMatchFn(match);
    _scheduleNextActionIfNeeded();
  }

  void _discardForAiPlayer(Set<PlayingCard> discards) {
    setState(() {
      round.discard(discards);
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
      round.discard(selectedDiscards);
      selectedDiscards = {};
    });
    widget.saveMatchFn(match);
    _scheduleNextActionIfNeeded();
  }

  void _playCard(final PlayingCard card, {Suit? jokerLeadSuit}) {
    playerMoods.clear();
    if (round.status == FiveHundredRoundStatus.playing) {
      setState(() {
        round.playCard(card, jokerLeadSuit: jokerLeadSuit);
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
      // Declaring team is happy if they made the bid, mad if not. Defenders
      // are happy if the last trick set the contract.
      final declarerTeam = round.contract!.declarer % numTeams;
      final madeBid = round.didDeclarerMakeContract();
      final setByLastTrick = _wasContractSetByLastTrick();
      for (int i = 1; i < numPlayers; i++) {
        if (i % numTeams == declarerTeam) {
          playerMoods[i] = madeBid ? Mood.happy : Mood.mad;
        } else if (setByLastTrick) {
          playerMoods[i] = Mood.happy;
        }
      }
    } else if (_wasContractSetByLastTrick()) {
      final declarerTeam = round.contract!.declarer % numTeams;
      for (int i = 1; i < numPlayers; i++) {
        playerMoods[i] = (i % numTeams == declarerTeam) ? Mood.mad : Mood.happy;
      }
    }
  }

  // Whether the most recent trick was the one that gave the defenders enough
  // tricks to set the contract.
  bool _wasContractSetByLastTrick() {
    final contract = round.contract!;
    final defenderTeam = 1 - contract.declarer % numTeams;
    final setThreshold = numTricksPerRound - contract.bid.tricks + 1;
    return round.previousTricks.last.winner % numTeams == defenderTeam &&
        round.tricksTakenByTeam()[defenderTeam] == setThreshold;
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
    return round.status == FiveHundredRoundStatus.declarerDiscarding && round.declarer() == 0;
  }

  bool _isHumanPlaying() {
    return round.status == FiveHundredRoundStatus.playing &&
        !round.isOver() &&
        round.currentPlayerIndex() == 0 &&
        !showContractDialog &&
        !showJokerSuitDialog;
  }

  void handleHandCardClicked(final PlayingCard card) {
    _printd("Clicked $card, status: ${round.status}");
    if (widget.dialogVisible) {
      return;
    }
    if (_isHumanPlaying()) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        if (round.needsJokerLeadSuit(card)) {
          setState(() {
            showJokerSuitDialog = true;
          });
        } else {
          _playCard(card);
        }
      }
    } else if (_isHumanChoosingDiscards()) {
      setState(() {
        if (selectedDiscards.contains(card)) {
          selectedDiscards.remove(card);
        } else if (selectedDiscards.length < numKittyCards) {
          selectedDiscards.add(card);
        }
      });
    }
  }

  void _handleJokerSuitChosen(Suit? suit) {
    setState(() {
      showJokerSuitDialog = false;
    });
    if (suit != null) {
      _playCard(joker, jokerLeadSuit: suit);
    }
  }

  // The trump suit once it's known: from the contract, or from the winning bid
  // while the declarer is discarding.
  Suit? _trumpSuit() {
    if (round.contract != null) {
      return round.contract!.trump;
    }
    return (round.status == FiveHundredRoundStatus.declarerDiscarding) ? round.winningBid().bid!.trump : null;
  }

  Map<PlayingCard, Color> _cardBackgrounds() {
    // Tint the kitty cards while choosing discards.
    if (_isHumanChoosingDiscards()) {
      return {for (final c in round.initialKitty) c: Colors.lightBlue.shade200};
    }
    return {};
  }

  Widget _playerCards(final Layout layout) {
    if (_shouldShowEndOfRoundDialog()) {
      return const SizedBox();
    }
    final handOrdering = fiveHundredHandOrdering(_trumpSuit());
    final isChoosingDiscards = _isHumanChoosingDiscards();
    // While choosing discards, the kitty cards are shown in the player's hand.
    List<PlayingCard> humanCards = isChoosingDiscards ? round.declarerAvailableCards() : round.players[0].hand;
    List<PlayingCard> highlightedCards = [];
    if (round.status == FiveHundredRoundStatus.bidding) {
      highlightedCards = humanCards;
    } else if (isChoosingDiscards) {
      highlightedCards = humanCards.where((c) => !selectedDiscards.contains(c)).toList();
    } else if (_isHumanPlaying()) {
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
      isTrump: widget.tintTrumpCards ? fiveHundredTrumpPredicate(_trumpSuit()) : null,
      cardBackgroundColors: _cardBackgrounds(),
    );
  }

  Widget _trickCards(final Layout layout) {
    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
      isTrump: widget.tintTrumpCards ? fiveHundredTrumpPredicate(round.contract?.trump) : null,
      animationMode: animationMode,
      numPlayers: numPlayers,
      displayedHands: [DisplayedHand(playerIndex: 0, cards: round.players[0].hand)],
      handOrdering: fiveHundredHandOrdering(round.contract?.trump),
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  // When the joker is led in no trump, shows the suit the leader chose.
  Widget? _jokerLeadSuitLabel(final Layout layout) {
    final suit = round.currentJokerLeadSuit();
    if (suit == null || round.currentTrick.cards.isEmpty || animationMode == AnimationMode.movingTrickToWinner) {
      return null;
    }
    final isRed = suit == Suit.hearts || suit == Suit.diamonds;
    return Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color.fromARGB(224, 255, 255, 255),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(TextSpan(style: const TextStyle(fontSize: 16, color: Colors.black), children: [
        const TextSpan(text: "Joker led as "),
        TextSpan(text: suit.symbolChar, style: TextStyle(color: isRed ? Colors.red : Colors.black, fontSize: 20)),
      ])),
    ));
  }

  bool _shouldShowScoreOverlay() {
    return showScoreOverlay && _shouldShowScoreOverlayToggle();
  }

  bool _shouldShowScoreOverlayToggle() {
    return !widget.dialogVisible &&
        round.status == FiveHundredRoundStatus.playing &&
        !round.isOver() &&
        !_shouldShowContractDialog();
  }

  // Contract and tricks taken by each team so far, in the center of the table.
  Widget _scoreOverlay() {
    const textStyle = TextStyle(color: Color.fromARGB(224, 0, 0, 0), fontSize: 18);
    const imageHeight = 22.0;
    final contract = round.contract!;
    final tricks = round.tricksTakenByTeam();
    // A table so that the slashes and colons line up.
    TableRow teamRow(int team) => TableRow(children: [
          Align(alignment: Alignment.centerRight,
              child: _playerLabel(team, widget.catImageIndices, height: imageHeight).single),
          const Text(" / ", style: textStyle),
          Align(alignment: Alignment.centerLeft,
              child: _playerLabel(team + 2, widget.catImageIndices, height: imageHeight).single),
          Text(": ${tricks[team]} ${tricks[team] == 1 ? "trick" : "tricks"}", style: textStyle),
        ]);

    final overlay = Center(
        child: Container(
            decoration: BoxDecoration(
                color: const Color.fromARGB(208, 255, 255, 255),
                border: Border.all(color: const Color.fromARGB(128, 0, 0, 0)),
                borderRadius: const BorderRadius.all(Radius.circular(20))),
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: DefaultTextStyle.merge(style: textStyle, child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ..._playerLabel(contract.declarer, widget.catImageIndices, height: imageHeight),
                      Text(" bid ${contract.bid}", style: textStyle),
                    ]),
                    Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [teamRow(0), teamRow(1)],
                    ),
                  ],
                )))));

    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      child: overlay,
      builder: (BuildContext context, double opacity, Widget? child) {
        return Opacity(opacity: opacity, child: child);
      },
    );
  }

  // The bid dialog stays visible for the whole auction, and while an AI player
  // who won the bid is discarding.
  bool _shouldShowBidDialog() {
    return !widget.dialogVisible &&
        (round.status == FiveHundredRoundStatus.bidding ||
            (round.status == FiveHundredRoundStatus.declarerDiscarding && round.declarer() != 0));
  }

  bool _shouldShowDiscardDialog() {
    return !widget.dialogVisible && _isHumanChoosingDiscards();
  }

  bool _shouldShowContractDialog() {
    return !widget.dialogVisible && showContractDialog;
  }

  bool _shouldShowJokerSuitDialog() {
    return !widget.dialogVisible && showJokerSuitDialog;
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver() && !round.isPassedOut();
  }

  Widget _bidTable() {
    const headerStyle = TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold);
    Widget catImageCell(int playerIndex) => paddingHorizontal(12,
        Image.asset(catImageForIndex(widget.catImageIndices[playerIndex]), height: 18));
    final isBidding = round.status == FiveHundredRoundStatus.bidding && !round.isPassedOut();
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
    final jokerLabel = _jokerLeadSuitLabel(layout);

    return Stack(
      children: <Widget>[
        _playerCards(layout),
        _trickCards(layout),
        ?jokerLabel,

        if (_shouldShowBidDialog())
          FiveHundredBidDialog(
            // Recreate the dialog for each bid, so it starts at the new minimum.
            key: ValueKey(round.bidHistory.length),
            layout: layout,
            round: round,
            bidTable: _bidTable(),
            onBid: (bid) => _addBid(PlayerBid(0, bid)),
            onRedeal: () => setState(_startRound),
          ),
        if (_shouldShowDiscardDialog())
          FiveHundredDiscardDialog(
            layout: layout,
            round: round,
            selectedDiscards: selectedDiscards,
            onConfirm: _handleHumanDiscardsConfirmed,
          ),
        if (_shouldShowContractDialog())
          _MessageDialog(
            layout: layout,
            message: Column(mainAxisSize: MainAxisSize.min, children: [
              _bidTable(),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                ..._playerLabel(round.contract!.declarer, widget.catImageIndices),
                Text(" won the bid at ${round.contract!.bid}."),
              ]),
            ]),
            buttonLabel: "Start round",
            onConfirm: _handleContractDialogConfirm,
          ),
        if (_shouldShowJokerSuitDialog())
          JokerSuitDialog(layout: layout, onSuitChosen: _handleJokerSuitChosen),
        if (_shouldShowEndOfRoundDialog())
          FiveHundredEndOfRoundDialog(
            layout: layout,
            match: match,
            onContinue: () => setState(_startRound),
            onMainMenu: _showMainMenuAfterMatch,
            catImageIndices: widget.catImageIndices,
          ),
        PlayerMoods(layout: layout, moods: playerMoods),
        if (_shouldShowScoreOverlay()) _scoreOverlay(),
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

const _dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

// "You", or the player's cat image.
List<Widget> _playerLabel(int playerIndex, List<int> catImageIndices, {double height = 16}) {
  if (playerIndex == 0) {
    return [const Text("You")];
  }
  return [Image.asset(catImageForIndex(catImageIndices[playerIndex]), height: height)];
}

String _trumpLabel(Suit? suit) => suit?.symbolChar ?? "NT";

class FiveHundredBidDialog extends StatefulWidget {
  final Layout layout;
  final FiveHundredRound round;
  final Widget bidTable;
  final void Function(FiveHundredBid?) onBid;
  final void Function() onRedeal;

  const FiveHundredBidDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.bidTable,
    required this.onBid,
    required this.onRedeal,
  });

  @override
  State<FiveHundredBidDialog> createState() => _FiveHundredBidDialogState();
}

class _FiveHundredBidDialogState extends State<FiveHundredBidDialog> {
  late int tricks;
  late Suit? trump;

  FiveHundredRound get round => widget.round;

  @override
  void initState() {
    super.initState();
    // Start at the lowest bid that beats the current high bid.
    final allBids = FiveHundredBid.allBids();
    final high = highBid(round.bidHistory);
    final next = (high == null) ? allBids.first : allBids[min(allBids.indexOf(high.bid!) + 1, allBids.length - 1)];
    tricks = next.tricks;
    trump = next.trump;
  }

  FiveHundredBid get selectedBid => FiveHundredBid(tricks, trump);

  bool isHumanBidding() =>
      round.status == FiveHundredRoundStatus.bidding && !round.isPassedOut() && round.currentBidder() == 0;

  @override
  Widget build(BuildContext context) {
    const adjustBidTextStyle = TextStyle(fontSize: 18, height: 0);
    const rowPadding = 15.0;
    final isBidding = isHumanBidding();
    // Bid controls are shown (but disabled while others bid) until the human
    // player passes.
    final showBidControls = round.status == FiveHundredRoundStatus.bidding &&
        !round.isPassedOut() && !round.hasPlayerPassed(0);
    final canBid = isBidding && round.canCurrentBidderMakeBid(selectedBid);

    return Center(
        child: Transform.translate(
            offset: Offset(0, -widget.layout.displaySize.height * 0.05),
            child: Transform.scale(scale: widget.layout.dialogScale(), child: Dialog(
            backgroundColor: _dialogBackgroundColor,
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
                          onPressed: (isBidding && tricks > minimumBidTricks) ? () => setState(() {tricks -= 1;}) : null,
                          child: const Text("–", style: adjustBidTextStyle),
                        ),
                        Text(tricks.toString(), style: adjustBidTextStyle),
                        ElevatedButton(
                          onPressed: (isBidding && tricks < maximumBidTricks) ? () => setState(() {tricks += 1;}) : null,
                          child: const Text("+", style: adjustBidTextStyle),
                        ),
                      ]),
                  paddingAll(rowPadding * 0.5, SegmentedButton<int>(
                    segments: [
                      for (int i = 0; i < FiveHundredBid.suitOrder.length; i++)
                        ButtonSegment(value: i, label: Text(_trumpLabel(FiveHundredBid.suitOrder[i]))),
                    ],
                    showSelectedIcon: false,
                    selected: {FiveHundredBid.suitOrder.indexOf(trump)},
                    onSelectionChanged: isBidding ? (Set<int> s) => setState(() {
                      trump = FiveHundredBid.suitOrder[s.first];
                    }) : null,
                  )),
                  paddingAll(
                      rowPadding,
                      Row(
                          spacing: 8,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: canBid ? () => widget.onBid(selectedBid) : null,
                              child: Text("Bid $selectedBid (${selectedBid.value})"),
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

class FiveHundredDiscardDialog extends StatelessWidget {
  final Layout layout;
  final FiveHundredRound round;
  final Set<PlayingCard> selectedDiscards;
  final void Function() onConfirm;

  const FiveHundredDiscardDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.selectedDiscards,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    final halfPadding = textStyle.fontSize! * 0.5;
    final remaining = numKittyCards - selectedDiscards.length;
    // The declarer's hand has the kitty cards added and may take two rows, so
    // keep the dialog compact and move it up so it doesn't cover any cards.
    return Center(child: Transform.translate(
      offset: Offset(0, -layout.displaySize.height * 0.15),
      child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
        backgroundColor: _dialogBackgroundColor,
        child: FittedBox(fit: .scaleDown, child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: halfPadding,
          children: [
            paddingAll(halfPadding, Text(
                "You won the bid at ${round.winningBid().bid}.\n"
                "Choose $numKittyCards cards to discard.",
                style: textStyle, textAlign: TextAlign.center)),
            ElevatedButton(
              onPressed: round.isValidDiscardForDeclarer(selectedDiscards) ? onConfirm : null,
              child: Text(remaining > 0 ? "Select $remaining more" : "Start round"),
            ),
            SizedBox(height: halfPadding),
          ],
        )),
      ),
    )));
  }
}

// Choosing the suit for the joker when leading it in no trump.
class JokerSuitDialog extends StatelessWidget {
  final Layout layout;
  // Called with null if the player cancels.
  final void Function(Suit?) onSuitChosen;

  const JokerSuitDialog({super.key, required this.layout, required this.onSuitChosen});

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    return Center(child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
        backgroundColor: _dialogBackgroundColor,
        child: FittedBox(fit: .scaleDown, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            paddingAll(12, const Text("Choose the suit that other players must follow.", style: textStyle)),
            Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              for (final suit in _suitDisplayOrder(null))
                ElevatedButton(
                  onPressed: () => onSuitChosen(suit),
                  child: Text(suit.symbolChar, style: TextStyle(
                      fontSize: 20,
                      color: (suit == Suit.hearts || suit == Suit.diamonds) ? Colors.red : Colors.black)),
                ),
            ]),
            paddingAll(12, TextButton(onPressed: () => onSuitChosen(null), child: const Text("Cancel"))),
          ],
        )))));
  }
}

class _MessageDialog extends StatelessWidget {
  final Layout layout;
  final Widget message;
  final String buttonLabel;
  final void Function() onConfirm;

  const _MessageDialog({
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
        backgroundColor: _dialogBackgroundColor,
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

class FiveHundredEndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final FiveHundredMatch match;
  final Function() onContinue;
  final Function() onMainMenu;
  final List<int> catImageIndices;

  const FiveHundredEndOfRoundDialog({
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
    final tricksTaken = round.tricksTakenByTeam();
    final roundScores = round.contractScoresForTeams();
    final declarerTricks = tricksTaken[contract.declarer % numTeams];
    final madeBid = round.didDeclarerMakeContract();
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
            backgroundColor: _dialogBackgroundColor,
            child: FittedBox(fit: .scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (match.isMatchOver())
                paddingAll(10, Text(matchOverMessage(), style: const TextStyle(fontSize: 26))),
              Padding(padding: const EdgeInsets.all(10), child: Row(mainAxisSize: MainAxisSize.min, children: [
                ..._playerLabel(contract.declarer, catImageIndices, height: catImageHeight),
                Text(" bid ${contract.bid} and ${madeBid ? "made it" : "failed"} "
                    "with $declarerTricks ${declarerTricks == 1 ? "trick" : "tricks"}"),
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
                      pointsRow("Tricks taken", tricksTaken),
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
