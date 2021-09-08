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
  }

  void _startMatch() {
    match = SpadesMatch(rules, rng);
    _startRound();
  }

  void _makeBidForAiPlayer(int playerIndex) {
    int bid = chooseBid(BidRequest(
      scoresBeforeRound: round.initialScores,
      rules: round.rules,
      otherBids: [],
      hand: round.players[playerIndex].hand,
    ));
    print("P$playerIndex bids $bid");
    round.setBidForPlayer(bid: bid, playerIndex: playerIndex);
  }

  void _startRound() {
    if (round.isOver()) {
      match.finishRound();
    }
    // TODO: bidding UI.
    int bidder = (round.dealer + 1) % round.rules.numPlayers;
    while (true) {
      if (round.status == SpadesRoundStatus.playing || (aiMode == AiMode.human_player_0 && bidder == 0)) {
        break;
      }
      _makeBidForAiPlayer(bidder);
      bidder = (bidder + 1) % round.rules.numPlayers;
    }
    if (round.status == SpadesRoundStatus.playing) {
      _scheduleNextPlayIfNeeded();
    }
  }

  void _scheduleNextPlayIfNeeded() {
    if (round.isOver()) {
      print("Round done, scores: ${round.pointsTaken()}");
      setState(() {
        _startRound();
      });
    }
    if (round.currentPlayerIndex() != 0 && round.status == SpadesRoundStatus.playing) {
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

    bool isBidding = round.status == SpadesRoundStatus.bidding;

    final List<Widget> cardImages = [];
    for (final entry in rects.entries) {
      final card = entry.key;
      cardImages.add(PositionedCard(
        rect: entry.value,
        card: card,
        opacity: isBidding || highlightedCards.contains(card) ? 1.0 : 0.5,
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

  bool _shouldShowBidDialog() {
    return (
        round.status == SpadesRoundStatus.bidding &&
        aiMode == AiMode.human_player_0 &&
        round.players[0].bid == null &&
            (round.dealer == round.rules.numPlayers - 1 || round.players.last.bid != null)
    );
  }

  void makeBidForHuman(int bid) {
    print("Human bids $bid");
    setState(() {
      round.setBidForPlayer(bid: bid, playerIndex: 0);
      int bidder = 1;
      while (round.status == SpadesRoundStatus.bidding) {
        _makeBidForAiPlayer(bidder);
        bidder += 1;
      }
    });
    _scheduleNextPlayIfNeeded();
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
        if (_shouldShowBidDialog()) BidDialog(layout: layout, onBid: makeBidForHuman),
        Text("${round.dealer.toString()} ${round.status}, ${round.players.map((p) => p.bid).toList()}"),
      ],
    );
  }
}

final dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

Widget _paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

Widget _makeBidButton(int bid, void Function(int) onBid, {String? label}) {
  return _paddingAll(10, ElevatedButton(
    onPressed: () => onBid(bid),
    child: Text(label ?? bid.toString()),
  ));
}

TableRow _makeButtonRow(String title, void Function() onPressed) {
  return TableRow(children: [
    Padding(
      padding: EdgeInsets.all(8),
      child: ElevatedButton(
        // style: raisedButtonStyle,
        onPressed: onPressed,
        child: Text(title),
      ),
    ),
  ]);
}

class BidDialog extends StatelessWidget {
  final Layout layout;
  final void Function(int) onBid;

  const BidDialog({Key? key, required this.layout, required this.onBid}): super(key: key);

  @override
  Widget build(BuildContext context) {
    final maxTricks = 13;

    final bidButtonRows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]].map((rowBids) => TableRow(
        children: rowBids.map((bid) => _makeBidButton(bid, onBid)).toList(),
    )).toList();

    return Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
            child: Dialog(
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(15, Text("Choose your bid")),
                    _makeBidButton(0, onBid, label: "Nil"),
                    _paddingAll(10, Table(
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      children: bidButtonRows,
                    )),
                  ],
                )
            )
        )
    );
  }

}