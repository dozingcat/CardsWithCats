import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hearts/cards/rollout.dart';
import 'package:hearts/hearts/hearts.dart';
import 'package:hearts/hearts/hearts_ai.dart';

import 'cards/card.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CatTricks',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'CatTricks'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AnimationMode {
  none,
  playing_trick_card,
  moving_trick_to_winner,
}

class Layout {
  late Size displaySize;
  late double edgePx;

  Rect cardArea() {
    return Rect.fromLTRB(edgePx, edgePx, displaySize.width - edgePx, displaySize.height - edgePx);
  }

  Rect areaForTrickCard(int playerIndex) {
    final ca = cardArea();
    final cardHeight = ca.height * 0.4;
    final cardWidth = ca.width * 0.3;
    final centerXFrac = (playerIndex == 1) ?
        0.25 :
        (playerIndex == 3) ? 0.75 : 0.5;
    final centerYFrac = (playerIndex == 0) ?
        0.75 :
        (playerIndex == 2) ? 0.25 : 0.5;
    final centerX = ca.left + ca.width * centerXFrac;
    final centerY = ca.top + ca.height * centerYFrac;
    return Rect.fromLTWH(centerX - cardWidth / 2, centerY - cardHeight / 2, cardWidth, cardHeight);
  }
}

class _MyHomePageState extends State<MyHomePage> {
  final rng = Random();
  final rules = HeartsRuleSet();
  var animationMode = AnimationMode.none;
  late HeartsRound round;

  @override void initState() {
    round = HeartsRound.deal(rules, List.filled(4, 0), 0, rng);
    Future.delayed(Duration(milliseconds: 500), () => _playNextCard());
  }

  void _playNextCard() {
    if (round.isOver()) {
      round = HeartsRound.deal(rules, List.filled(4, 0), 0, rng);
    }
    // Do this in a separate thread/isolate.
    final card = chooseCardMonteCarlo(
        CardToPlayRequest.fromRound(round),
        MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
        chooseCardAvoidingPoints,
        rng);
    setState(() {
      round.playCard(card);
    });
    Future.delayed(Duration(milliseconds: 500), () => _playNextCard());
  }

  Widget _cardForPlayer(final Layout layout, final PlayingCard card, int playerIndex) {
    final cardRect = layout.areaForTrickCard(playerIndex);
    final cardImagePath = "assets/cards/${card.toString()}.webp";
    return Positioned(
      left: cardRect.left,
      top: cardRect.top,
      width: cardRect.width,
      height: cardRect.height,
      child: Container(
          child: Image(
              image: AssetImage(cardImagePath),
              fit: BoxFit.contain,
              alignment: Alignment.center,
      )));
  }

  Widget _trickCards(final Layout layout) {
    List<Widget> cardWidgets = [];
    if (round.currentTrick.cards.isNotEmpty) {
      for (int i = 0; i < round.currentTrick.cards.length; i++) {
        int p = (round.currentTrick.leader + i) % round.rules.numPlayers;
        cardWidgets.add(_cardForPlayer(layout, round.currentTrick.cards[i], p));
      }
    }
    else if (round.previousTricks.isNotEmpty) {
      final trick = round.previousTricks.last;
      for (int i = 0; i < trick.cards.length; i++) {
        int p = (trick.leader + i) % round.rules.numPlayers;
        cardWidgets.add(_cardForPlayer(layout, trick.cards[i], p));
      }
    }
    return Stack(children: cardWidgets);
  }

  Widget _aiPlayerWidget(final Layout layout, int playerIndex) {
    final imagePath = "assets/cats/cat${playerIndex + 1}.png";
    final imageAspectRatio = 156 / 112;
    final displaySize = layout.displaySize;
    final playerSize = layout.edgePx;

    final rect = (() {
      switch (playerIndex) {
        case 0:
          return Rect.fromLTWH(0, displaySize.height - playerSize, displaySize.width, playerSize);
        case 1:
          return Rect.fromLTWH(0, 0, playerSize, displaySize.height);
        case 2:
          return Rect.fromLTWH(0, 0, displaySize.width, playerSize);
        case 3:
          return Rect.fromLTWH(displaySize.width - playerSize, 0, playerSize, displaySize.height);
        default:
          return Rect.fromLTWH(0, 0, 0, 0);
      }
    })();
    final angle = (playerIndex - 2) * pi / 2;
    final scale = (playerIndex == 1 || playerIndex == 3) ? imageAspectRatio : 1.0;

    return Positioned(
      top: rect.top,
      left: rect.left,
      width: rect.width,
      height: rect.height,

      child: Container(
        color: Colors.white70,
        width: rect.width,
        height: rect.height,
        // The image won't naturally take up the full width If rotated 90 degrees,
        // so in that case scale by the aspect ratio.
        child: Transform.scale(scale: scale, child: Transform.rotate(angle: angle, child: Image(
          image: AssetImage(imagePath),
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ))),
      ),

      // child: Text("Hello $playerNum"),
    );
  }

  Layout computeLayout() {
    final ds = MediaQuery.of(context).size;
    return Layout()
        ..displaySize = ds
        ..edgePx = max(ds.width / 20, ds.height / 15)
        ;
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout();

    return Scaffold(
      body: Stack(
          children: <Widget>[
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.green,
            ),
            ...[0, 1, 2, 3].map((i) => _aiPlayerWidget(layout, i)),
            _trickCards(layout),

          ],
        ),
    );
  }
}
