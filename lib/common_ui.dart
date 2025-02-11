import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import 'cards/card.dart';
import 'cards/trick.dart';
import 'common.dart';

enum AnimationMode {
  none,
  movingTrickCard,
  movingTrickToWinner,
}

enum AiMode {
  allAi,
  humanPlayer0,
}

const cardAspectRatio = 521.0 / 726;

class Layout {
  late Size displaySize;
  late double playerHeight;

  Rect cardArea() {
    final border = playerHeight * 0.9;
    return Rect.fromLTRB(border, border, displaySize.width - border, displaySize.height - border);
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

  double dialogScale() {
    return (displaySize.shortestSide / 350).clamp(1.0, 2.0);
  }
}

Rect centeredSubrectWithAspectRatio(Rect parentRect, double aspectRatio) {
  final parentAspect = parentRect.width / parentRect.height;
  if (parentAspect > aspectRatio) {
    // Parent is wider, move in from left and right.
    final subrectWidth = parentRect.height * aspectRatio;
    return Rect.fromCenter(center: parentRect.center, width: subrectWidth, height: parentRect.height);
  }
  else {
    // Parent is taller, move in from top and bottom.
    final subrectHeight = parentRect.width / aspectRatio;
    return Rect.fromCenter(center: parentRect.center, width: parentRect.width, height: subrectHeight);
  }
}

class PositionedCard extends StatelessWidget {
  final Rect rect;
  final PlayingCard card;
  final double opacity;
  final bool isTrump;
  final void Function(PlayingCard) onCardClicked;

  const PositionedCard({
    Key? key,
    required this.rect,
    required this.card,
    required this.onCardClicked,
    this.opacity = 1.0,
    this.isTrump = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardImagePath = isTrump && opacity == 1 ?
        "assets/cards/transparent/${card.toString()}.webp" :
        "assets/cards/solid/${card.toString()}.webp";
    const backgroundImagePath = "assets/cards/black.webp";
    const trumpOverlayImagePath = "assets/cards/gold.webp";
    final cardRect = centeredSubrectWithAspectRatio(rect, cardAspectRatio);

    final cardStack = <Widget>[];
    if (opacity < 1) {
      cardStack.add(const Center(
          child: Image(
            image: AssetImage(backgroundImagePath),
            fit: BoxFit.contain,
            alignment: Alignment.center,
          )));
    }
    else if (isTrump) {
      cardStack.add(const Center(
          child: Image(
            image: AssetImage(trumpOverlayImagePath),
            fit: BoxFit.contain,
            alignment: Alignment.center,
          )));
    }
    cardStack.add(Center(
        child: Image(
          color: Color.fromRGBO(255, 255, 255, opacity),
          colorBlendMode: BlendMode.modulate,
          image: AssetImage(cardImagePath),
        )));

    // The card images don't have an edge border so we draw it manually.
    // Width of 0 makes the border one physical pixel.
    cardStack.add(Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color.fromRGBO(64, 64, 64, 1),
          width: 0,
        ),
        borderRadius: BorderRadius.circular(cardRect.width * 0.05),
      ),
    ));

    return Positioned.fromRect(
        rect: cardRect,
        child: GestureDetector(
            onTapDown: (tap) => onCardClicked(card),
            child: Stack(children: cardStack)));
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
    final playerSize = layout.playerHeight;

    final rect = (() {
      switch (playerIndex) {
        case 0:
          return Rect.fromLTWH(0, displaySize.height - playerSize, displaySize.width, playerSize);
        case 1:
          return Rect.fromLTWH(1, 0, playerSize, displaySize.height);
        case 2:
          return Rect.fromLTWH(0, 1, displaySize.width, playerSize);
        case 3:
          return Rect.fromLTWH(
              displaySize.width - playerSize - 1, 0, playerSize, displaySize.height);
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
              child: Image.asset(imagePath, fit: BoxFit.contain),
            )),
      ),
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
    final playerHeight = layout.playerHeight;
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
            // Center the message in the content part of the bubble, which is
            // the upper ~73%. Except for player 2 where it's the lower 73%.
            Positioned(
                width: imageWidth,
                height: imageHeight * 0.73,
                top: (playerIndex == 2) ? 0.27 * imageHeight : 0,
                child: Center(child:
                  Text(message, style: TextStyle(fontSize: fontSize, height: 1)))
            ),
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
    final playerHeight = layout.playerHeight;
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
    final p1Offset = Offset(0, layout.playerHeight * 0.75 + approxContainerHeights[1] / 2);
    final p3Offset = Offset(0, layout.playerHeight * 0.75 + approxContainerHeights[3] / 2);
    final overlays = Column(children: [
      Row(children: [
        spacer,
        makeTextContainer(messages[2], Offset(0, layout.playerHeight)),
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
        makeTextContainer(messages[0], Offset(0, -layout.playerHeight / 2)),
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
  final Suit? trumpSuit;

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
    this.trumpSuit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (animationMode == AnimationMode.movingTrickToWinner) {
      return _trickCardsAnimatingToWinner(layout, previousTricks.last);
    }
    List<Widget> cardWidgets = [];
    if (currentTrick.cards.isNotEmpty) {
      if (animationMode == AnimationMode.movingTrickCard) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, currentTrick.leader, numPlayers, currentTrick.cards));
      } else {
        cardWidgets
            .addAll(_staticTrickCards(layout, currentTrick.leader, numPlayers, currentTrick.cards));
      }
    } else if (previousTricks.isNotEmpty) {
      final trick = previousTricks.last;
      if (animationMode == AnimationMode.movingTrickCard) {
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
    return PositionedCard(
        rect: cardRect,
        card: card,
        isTrump: card.suit == trumpSuit,
        onCardClicked: (_) => {},
    );
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
      startRect =
          playerHandCardRects(layout, previousHandCards, humanPlayerSuitOrder!)[cards.last]!;
    }

    cardWidgets.add(TweenAnimationBuilder(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        onEnd: onTrickCardAnimationFinished,
        builder: (BuildContext context, double frac, Widget? child) {
          Rect animRect = Rect.lerp(startRect, endRect, frac)!;
          // Starting size for human player is determined by where the card was shown before.
          // For AI players make the card grow as it comes from their card origin.
          if (animPlayer != 0) {
            final scale = 0.25 + (0.75 * frac);
            animRect = Rect.fromCenter(center: animRect.center, width: startRect.width * scale, height: startRect.height * scale);
          }
          return PositionedCard(
              rect: animRect,
              card: cards.last,
              isTrump: cards.last.suit == trumpSuit,
              onCardClicked: (_) => {},
          );
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
            final scale = (t < 0) ? 1 : 1 - 0.75 * t;
            Rect animRect =
                Rect.fromCenter(center: center, width: endRect.width * scale, height: endRect.height * scale);
            cardWidgets.add(
                PositionedCard(
                    rect: animRect,
                    card: trick.cards[i],
                    isTrump: trick.cards[i].suit == trumpSuit,
                    onCardClicked: (_) => {},
                ));
          }
          return Stack(children: cardWidgets);
        });
  }
}

class GameTypeDropdown extends StatelessWidget {
  final GameType gameType;
  final Function(GameType?) onChanged;
  final TextStyle textStyle;

  const GameTypeDropdown({
    super.key,
    required this.gameType,
    required this.onChanged,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton(
      value: gameType,
      items: [
        DropdownMenuItem(value: GameType.hearts, child: Text('Hearts', style: textStyle)),
        DropdownMenuItem(value: GameType.spades, child: Text('Spades', style: textStyle)),
        DropdownMenuItem(value: GameType.ohHell, child: Text('Oh Hell', style: textStyle)),
      ],
      onChanged: onChanged,
    );
  }
}

Widget paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

class ClaimRemainingTricksDialog extends StatelessWidget {
  final Function() onOk;
  final bool isHuman;
  final int? catImageIndex;

  const ClaimRemainingTricksDialog({
    super.key,
    required this.onOk,
    this.isHuman = false,
    this.catImageIndex,
  });

  @override
  Widget build(BuildContext context) {
    Layout layout = computeLayout(context);
    const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

    final dialog = Center(
        child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: dialogBackgroundColor,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            paddingAll(15, Text("Remaining tricks claimed")),
            paddingAll(
                15,
                ElevatedButton(
                  onPressed: onOk,
                  child: const Text("OK"),
                )),
          ])
        ))
    );

    return dialog;
  }
}

class PlayerHandCards extends StatelessWidget {
  final Layout layout;
  final List<Suit> suitDisplayOrder;
  final List<PlayingCard> cards;
  final Iterable<PlayingCard> highlightedCards;
  final void Function(PlayingCard) onCardClicked;
  final List<PlayingCard>? animateFromCards;
  final Suit? trumpSuit;

  const PlayerHandCards({
    Key? key,
    required this.layout,
    required this.suitDisplayOrder,
    required this.cards,
    required this.highlightedCards,
    this.animateFromCards,
    this.trumpSuit,
    required this.onCardClicked,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    final rects = playerHandCardRects(layout, cards, suitDisplayOrder);

    if (animateFromCards != null) {
      final previousRects = playerHandCardRects(layout, animateFromCards!, suitDisplayOrder);
      return TweenAnimationBuilder(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 200),
          builder: (BuildContext context, double fraction, Widget? child) {
            final List<Widget> cardImages = [];
            for (final entry in rects.entries) {
              final card = entry.key;
              final startRect = previousRects[card]!;
              final endRect = entry.value;
              cardImages.add(PositionedCard(
                rect: Rect.lerp(startRect, endRect, fraction)!,
                card: card,
                isTrump: card.suit == trumpSuit,
                opacity: highlightedCards.contains(card) ? 1.0 : 0.5,
                onCardClicked: onCardClicked,
              ));
            }
            return Stack(children: cardImages);
          });
    }

    final List<Widget> cardImages = [];
    for (final entry in rects.entries) {
      final card = entry.key;
      cardImages.add(PositionedCard(
        rect: entry.value,
        card: card,
        isTrump: card.suit == trumpSuit,
        opacity: highlightedCards.contains(card) ? 1.0 : 0.5,
        onCardClicked: onCardClicked,
      ));
    }
    return Stack(children: cardImages);
  }
}

LinkedHashMap<PlayingCard, Rect> playerHandCardRects(
    Layout layout, List<PlayingCard> cards, List<Suit> suitOrder) {
  final rects = LinkedHashMap<PlayingCard, Rect>();
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
    ..playerHeight = ds.shortestSide * 0.125;
}
