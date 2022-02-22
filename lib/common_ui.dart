import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cards/card.dart';
import 'cards/trick.dart';

enum AnimationMode {
  none,
  moving_passed_cards,
  moving_trick_card,
  moving_trick_to_winner,
}

enum AiMode {
  all_ai,
  human_player_0,
}

class Layout {
  late Size displaySize;
  late double edgePx;

  Rect cardArea() {
    return Rect.fromLTRB(edgePx, edgePx, displaySize.width - edgePx, displaySize.height - edgePx);
  }

  Size baseCardSize() {
    final ca = cardArea();
    return Size(ca.width * 0.4, ca.height * 0.4);
  }

  Rect trickCardAreaForPlayer(int playerIndex) {
    final ca = cardArea();
    final cs = baseCardSize();
    final centerXFrac = (playerIndex == 1)
        ? 0.25
        : (playerIndex == 3)
            ? 0.75
            : 0.5;
    final centerYFrac = (playerIndex == 0)
        ? 0.75
        : (playerIndex == 2)
            ? 0.25
            : 0.5;
    final centerX = ca.left + ca.width * centerXFrac;
    final centerY = ca.top + ca.height * centerYFrac;
    return Rect.fromLTWH(centerX - cs.width / 2, centerY - cs.height / 2, cs.width, cs.height);
  }

  Rect cardOriginAreaForPlayer(int playerIndex) {
    final w = displaySize.width;
    final h = displaySize.height;
    final ca = cardArea();
    final cardHeight = ca.height * 0.4;
    final cardWidth = ca.width * 0.4;
    switch (playerIndex) {
      case 0:
        return Rect.fromCenter(
            center: Offset(w / 2, h + cardHeight / 2), width: cardWidth, height: cardHeight);
      case 1:
        return Rect.fromCenter(
            center: Offset(-cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      case 2:
        return Rect.fromCenter(
            center: Offset(w / 2, -cardHeight / 2), width: cardWidth, height: cardHeight);
      case 3:
        return Rect.fromCenter(
            center: Offset(w + cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      default:
        throw Exception("Bad player index: $playerIndex");
    }
  }

  double dialogBaseFontSize() {
    final baseSize = displaySize.shortestSide / 30;
    return baseSize.clamp(14, 20);
  }

  double dialogHeaderFontSize() {
    final baseSize = displaySize.shortestSide / 20;
    return baseSize.clamp(18, 50);
    return max(26, displaySize.shortestSide / 20);
  }
}

class PositionedCard extends StatelessWidget {
  final Rect rect;
  final PlayingCard card;
  final double opacity;
  final void Function(PlayingCard) onCardClicked;

  const PositionedCard({
    Key? key,
    required this.rect,
    required this.card,
    required this.onCardClicked,
    this.opacity = 1.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardImagePath = "assets/cards/${card.toString()}.webp";
    const backgroundImagePath = "assets/cards/black.webp";
    return Positioned.fromRect(
        rect: rect,
        child: GestureDetector(
            onTapDown: (tap) => onCardClicked(card),
            child: Stack(children: [
              if (opacity < 1)
                const Center(child: Image(
                  image: AssetImage(backgroundImagePath),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                )),
              Center(child: Image(
                color: Color.fromRGBO(255, 255, 255, opacity),
                colorBlendMode: BlendMode.modulate,
                image: AssetImage(cardImagePath),
              )),
            ])));
  }
}

String catImageForIndex(int index) => "assets/cats/cat${index + 1}.png";

class AiPlayerImage extends StatelessWidget {
  final Layout layout;
  final int playerIndex;
  final int? catImageIndex;

  const AiPlayerImage({
    Key? key,
    required this.layout,
    required this.playerIndex,
    this.catImageIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageIndex = (catImageIndex != null) ? catImageIndex! : playerIndex;
    final imagePath = catImageForIndex(imageIndex);
    const imageAspectRatio = 156 / 112;
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
          return const Rect.fromLTWH(0, 0, 0, 0);
      }
    })();
    final angle = (playerIndex - 2) * pi / 2;
    final scale = (playerIndex == 1 || playerIndex == 3) ? imageAspectRatio : 1.0;

    return Positioned.fromRect(
      rect: rect,
      child: Container(
        color: Colors.transparent,
        width: rect.width,
        height: rect.height,
        // The image won't naturally take up the full width if rotated 90 degrees,
        // so in that case scale by the aspect ratio.
        child: Transform.scale(
            scale: scale,
            child: Transform.rotate(
                angle: angle,
                child: Image.asset(imagePath),
            )
        ),
      ),

      // child: Text("Hello $playerNum"),
    );
  }
}

class SpeechBubble extends StatelessWidget {
  final Layout layout;
  final int playerIndex;
  final String message;
  final double widthFraction;
  static const imageAspectRatio = 640.0 / 574;
  static const imagePath = "assets/misc/speech_bubble.png";

  const SpeechBubble({
    Key? key,
    required this.layout,
    required this.playerIndex,
    required this.message,
    this.widthFraction = 0.2,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var transform = Matrix4.identity();
    final dh = layout.displaySize.height;
    final dw = layout.displaySize.width;
    final playerHeight = layout.edgePx;
    final imageWidth = min(playerHeight * 1.5, widthFraction * dw);
    final imageHeight = imageWidth / imageAspectRatio;
    final fontSize = imageHeight / 2;
    var top = 0.0;
    var left = 0.0;
    switch (playerIndex) {
      case 1:
        left = playerHeight / 2;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        break;
      case 2:
        transform = Matrix4.rotationX(pi);
        left = dw / 2;
        top = playerHeight * 1.1;
        break;
      case 3:
        transform = Matrix4.rotationY(pi);
        left = dw - playerHeight / 2 - imageWidth;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        break;
      case 0:
        left = dw / 2 - playerHeight / 2;
        top = dh - playerHeight - imageHeight;
        break;
    }

    return Positioned(
        top: top,
        left: left,
        width: imageWidth,
        height: imageHeight,
        child: Stack(
          children: [
            SizedBox(
              width: imageWidth,
              height: imageHeight,
              child: Transform(
                  alignment: Alignment.center,
                  transform: transform,
                  child: const Image(
                    image: AssetImage(imagePath),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  )),
            ),
            Center(
                child: Column(children: [
              SizedBox(height: imageHeight * (playerIndex == 2 ? 0.33 : 0.06)),
              Text(message, style: TextStyle(fontSize: fontSize)),
            ])),
          ],
        ));
  }
}

enum Mood { happy, veryHappy, mad }

class MoodBubble extends StatelessWidget {
  final Layout layout;
  final int playerIndex;
  final Mood mood;
  final double widthFraction;
  static const bubbleImageAspectRatio = 619.0 / 640;
  static const moodImageHeightFraction = 0.42;
  static const bubbleImagePath = "assets/misc/thought_bubble.png";
  static const moodImagePathPrefix = "assets/cats/";

  const MoodBubble({
    Key? key,
    required this.layout,
    required this.playerIndex,
    required this.mood,
    this.widthFraction = 0.2,
  }) : super(key: key);

  String _moodImagePath() {
    switch (mood) {
      case Mood.happy:
        return moodImagePathPrefix + "emoji_happy_u1f63a.png";
      case Mood.veryHappy:
        return moodImagePathPrefix + "emoji_grin_u1f638.png";
      case Mood.mad:
        return moodImagePathPrefix + "emoji_mad_u1f63e.png";
    }
  }

  @override
  Widget build(BuildContext context) {
    var transform = Matrix4.identity();
    final dh = layout.displaySize.height;
    final dw = layout.displaySize.width;
    final playerHeight = layout.edgePx;
    final imageWidth = min(playerHeight * 1.5, widthFraction * dw);
    final imageHeight = imageWidth / bubbleImageAspectRatio;
    var top = 0.0;
    var left = 0.0;
    var moodXFrac = 0.0;
    var moodYFrac = 0.0;
    final moodSize = imageHeight * moodImageHeightFraction;
    switch (playerIndex) {
      case 1:
        left = playerHeight / 2;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        moodXFrac = 0.30;
        moodYFrac = 0.15;
        break;
      case 2:
        transform = Matrix4.rotationX(pi);
        left = dw / 2;
        top = playerHeight * 1.1;
        moodXFrac = 0.33;
        moodYFrac = 0.48;
        break;
      case 3:
        transform = Matrix4.rotationY(pi);
        left = dw - playerHeight / 2 - imageWidth;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        moodXFrac = 0.30;
        moodYFrac = 0.15;
        break;
      case 0:
        left = dw / 2 - playerHeight / 2;
        top = dh - playerHeight - imageHeight;
        moodXFrac = 0.33;
        moodYFrac = 0.12;
        break;
    }

    return Positioned(
        top: top,
        left: left,
        width: imageWidth,
        height: imageHeight,
        child: Opacity(
            opacity: 0.8,
            child: Stack(
              children: [
                SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: Transform(
                      alignment: Alignment.center,
                      transform: transform,
                      child: Image.asset(bubbleImagePath, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: moodYFrac * imageHeight,
                  left: moodXFrac * imageWidth,
                  width: moodSize,
                  height: moodSize,

                  child: Image.asset(_moodImagePath(), fit: BoxFit.contain),
                ),
              ],
            )));
  }
}

class PlayerMoods extends StatelessWidget {
  final Layout layout;
  final Map<int, Mood> moods;

  const PlayerMoods({Key? key, required this.layout, required this.moods}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (moods.isEmpty) return Container();
    final nonHuman = moods.entries.where((elem) => elem.key != 0);
    final moodWidgets = Stack(children: [
      ...nonHuman.map((elem) => MoodBubble(
            layout: layout,
            playerIndex: elem.key,
            mood: elem.value,
          ))
    ]);

    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: moodWidgets,
      builder: (context, double val, child) => Opacity(opacity: val, child: child),
    );
    return moodWidgets;
  }
}

class PlayerMessagesOverlay extends StatelessWidget {
  final Layout layout;
  final List<String> messages;

  const PlayerMessagesOverlay({Key? key, required this.layout, required this.messages})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget makeTextContainer(String msg, Offset offset) {
      return Transform.translate(
          offset: offset,
          child: Container(
              decoration: BoxDecoration(
                  color: const Color.fromARGB(208, 255, 255, 255),
                  border: Border.all(
                    color: const Color.fromARGB(128, 0, 0, 0),
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(20))),
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(msg,
                      style: const TextStyle(
                        color: Color.fromARGB(224, 0, 0, 0),
                        fontSize: 18,
                      )))));
    }

    const spacer = Expanded(child: SizedBox());
    // Get approximate height of the containers so we can position them accurately.
    final messageLineCounts = [...messages.map((m) => m.split("\n").length)];
    final approxContainerHeights = [...messageLineCounts.map((n) => 24 + 20 * n)];
    final p1Offset = Offset(0, layout.edgePx * 0.75 + approxContainerHeights[1] / 2);
    final p3Offset = Offset(0, layout.edgePx * 0.75 + approxContainerHeights[3] / 2);
    final sidePushdownPx = layout.edgePx * 0.75 + 32;
    final overlays = Column(children: [
      Row(children: [
        spacer,
        makeTextContainer(messages[2], Offset(0, layout.edgePx)),
        spacer,
      ]),
      Expanded(
          child: Row(children: [
        const SizedBox(width: 5),
        makeTextContainer(messages[1], p1Offset),
        spacer,
        makeTextContainer(messages[3], p3Offset),
        const SizedBox(width: 5),
      ])),
      Row(children: [
        spacer,
        makeTextContainer(messages[0], Offset(0, -layout.edgePx / 2)),
        spacer,
      ]),
    ]);

    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      child: overlays,
      builder: (BuildContext context, double opacity, Widget? child) {
        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}

class TrickCards extends StatelessWidget {
  final Layout layout;
  final TrickInProgress currentTrick;
  final List<Trick> previousTricks;
  final AnimationMode animationMode;
  final int numPlayers;
  final void Function() onTrickCardAnimationFinished;
  final void Function() onTrickToWinnerAnimationFinished;
  final List<PlayingCard>? humanPlayerHand;
  final List<Suit>? humanPlayerSuitOrder;

  const TrickCards({
    Key? key,
    required this.layout,
    required this.currentTrick,
    required this.previousTricks,
    required this.animationMode,
    required this.numPlayers,
    required this.onTrickCardAnimationFinished,
    required this.onTrickToWinnerAnimationFinished,
    this.humanPlayerHand,
    this.humanPlayerSuitOrder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (animationMode == AnimationMode.moving_trick_to_winner) {
      return _trickCardsAnimatingToWinner(layout, previousTricks.last);
    }
    List<Widget> cardWidgets = [];
    if (currentTrick.cards.isNotEmpty) {
      if (animationMode == AnimationMode.moving_trick_card) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, currentTrick.leader, numPlayers, currentTrick.cards));
      } else {
        cardWidgets
            .addAll(_staticTrickCards(layout, currentTrick.leader, numPlayers, currentTrick.cards));
      }
    } else if (previousTricks.isNotEmpty) {
      final trick = previousTricks.last;
      if (animationMode == AnimationMode.moving_trick_card) {
        cardWidgets
            .addAll(_trickCardsWithLastAnimating(layout, trick.leader, numPlayers, trick.cards));
      } else {
        // Finished animating trick to winner, don't show any cards.
      }
    }
    return Stack(children: cardWidgets);
  }

  Widget _trickCardForPlayer(final Layout layout, final PlayingCard card, int playerIndex) {
    final cardRect = layout.trickCardAreaForPlayer(playerIndex);
    return PositionedCard(rect: cardRect, card: card, onCardClicked: (_) => {});
  }

  List<Widget> _staticTrickCards(
      final Layout layout, int leader, int numPlayers, List<PlayingCard> cards) {
    List<Widget> cardWidgets = [];
    for (int i = 0; i < cards.length; i++) {
      int p = (leader + i) % numPlayers;
      cardWidgets.add(_trickCardForPlayer(layout, cards[i], p));
    }
    return cardWidgets;
  }

  List<Widget> _trickCardsWithLastAnimating(
      final Layout layout, int leader, int numPlayers, List<PlayingCard> cards) {
    final cardsWithoutLast = cards.sublist(0, cards.length - 1);
    List<Widget> cardWidgets =
        List.of(_staticTrickCards(layout, leader, numPlayers, cardsWithoutLast));
    final animPlayer = (leader + cards.length - 1) % numPlayers;
    final endRect = layout.trickCardAreaForPlayer(animPlayer);
    var startRect = layout.cardOriginAreaForPlayer(animPlayer);
    if (animPlayer == 0 && humanPlayerHand != null) {
      // We want to know where the card was drawn in the player's hand. It's not
      // there now, so we have to compute the card rects as if it were.
      final previousHandCards = [...humanPlayerHand!, cards.last];
      startRect = playerHandCardRects(layout, previousHandCards, humanPlayerSuitOrder!)[cards.last]!;
    }

    cardWidgets.add(TweenAnimationBuilder(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        onEnd: onTrickCardAnimationFinished,
        builder: (BuildContext context, double frac, Widget? child) {
          final animRect = Rect.lerp(startRect, endRect, frac)!;
          return PositionedCard(rect: animRect, card: cards.last, onCardClicked: (_) => {});
        }));

    return cardWidgets;
  }

  Widget _trickCardsAnimatingToWinner(final Layout layout, final Trick trick) {
    // Negative animation value means not moving. It might be better to have
    // a separate state for "waiting to move trick", but that would make state
    // transition logic more complex.
    return TweenAnimationBuilder(
        tween: Tween(begin: -3.0, end: 1.0),
        duration: const Duration(milliseconds: 1000),
        onEnd: onTrickToWinnerAnimationFinished,
        builder: (BuildContext context, double t, Widget? child) {
          final List<Widget> cardWidgets = [];
          final endRect = layout.cardOriginAreaForPlayer(trick.winner);
          for (int i = 0; i < trick.cards.length; i++) {
            int p = (trick.leader + i) % trick.cards.length;
            final startRect = layout.trickCardAreaForPlayer(p);
            final center = startRect.center + (endRect.center - startRect.center) * max(0, t);
            Rect animRect =
                Rect.fromCenter(center: center, width: endRect.width, height: endRect.height);
            cardWidgets.add(
                PositionedCard(rect: animRect, card: trick.cards[i], onCardClicked: (_) => {}));
          }
          return Stack(children: cardWidgets);
        });
  }
}

LinkedHashMap<PlayingCard, Rect> playerHandCardRects(
    Layout layout, List<PlayingCard> cards, List<Suit> suitOrder) {
  final rects = LinkedHashMap<PlayingCard, Rect>();
  const cardAspectRatio = 500.0 / 726;
  const cardHeightFrac = 0.2;
  const cardOverlapFraction = 1.0 / 3;
  const upperRowHeightFracStart = 0.69;
  const lowerRowHeightFracStart = 0.79;
  const singleRowHeightFracStart = 0.74;
  final ds = layout.displaySize;
  final cardHeight = ds.height * cardHeightFrac;
  final cardWidth = cardHeight * cardAspectRatio;
  final pxBetweenCards = cardWidth * (1 - cardOverlapFraction);
  final maxAllowedTotalWidth = 0.95 * ds.width;

  double widthOfNCards(int n) => cardWidth + (n - 1) * pxBetweenCards;

  List<PlayingCard> sortedCards = [];
  for (Suit suit in suitOrder) {
    sortedCards.addAll(sortedCardsInSuit(cards, suit));
  }
  final oneRowWidth = widthOfNCards(sortedCards.length);
  if (oneRowWidth < maxAllowedTotalWidth) {
    // Show all cards in a single row.
    final startX = (ds.width - oneRowWidth) / 2;
    final startY = singleRowHeightFracStart * ds.height;
    for (int i = 0; i < sortedCards.length; i++) {
      final x = startX + i * pxBetweenCards;
      final r = Rect.fromLTWH(x, startY, cardWidth, cardHeight);
      rects[sortedCards[i]] = r;
    }
    return rects;
  }
  final numLowerCards = sortedCards.length ~/ 2;
  final numUpperCards = sortedCards.length - numLowerCards;
  double twoRowWidth = widthOfNCards(numUpperCards);
  // Lower row is offset by half of cardOverlapFraction, so if it has the same
  // number of cards as the top row it extends the total width.
  if (numLowerCards == numUpperCards) {
    twoRowWidth += pxBetweenCards / 2;
  }
  final topStartX = (ds.width - twoRowWidth) / 2;
  final bottomStartX = topStartX + pxBetweenCards / 2;
  final scale = min(1.0, maxAllowedTotalWidth / twoRowWidth);
  final scaledCardWidth = scale * cardWidth;
  final scaledCardHeight = scale * cardHeight;
  final topStartY = upperRowHeightFracStart * ds.height + (cardHeight - scaledCardHeight);
  final bottomStartY = lowerRowHeightFracStart * ds.height + (cardHeight - scaledCardHeight) / 2;
  final midX = ds.width / 2;
  for (int i = 0; i < numUpperCards; i++) {
    double baseLeft = topStartX + i * pxBetweenCards;
    double scaledLeft = midX + (baseLeft - midX) * scale;
    // adjust Y for scale?
    final r = Rect.fromLTWH(scaledLeft, topStartY, scaledCardWidth, scaledCardHeight);
    rects[sortedCards[i]] = r;
  }
  for (int i = 0; i < numLowerCards; i++) {
    double baseLeft = bottomStartX + i * pxBetweenCards;
    double scaledLeft = midX + (baseLeft - midX) * scale;
    // adjust Y for scale?
    final r = Rect.fromLTWH(scaledLeft, bottomStartY, scaledCardWidth, scaledCardHeight);
    rects[sortedCards[numUpperCards + i]] = r;
  }
  return rects;
}

Layout computeLayout(BuildContext context) {
  final ds = MediaQuery.of(context).size;
  return Layout()
    ..displaySize = ds
    ..edgePx = ds.shortestSide * 0.125;
}
