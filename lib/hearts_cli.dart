import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/hearts/hearts.dart';
import 'package:cards_with_cats/hearts/hearts_ai.dart';

// Global counter for invalid inputs
int invalidInputCount = 0;

/// Command-line Hearts game.
/// Usage: dart run lib/hearts_cli.dart [options]
///
/// Options:
///   --replay: After the human plays, replay the same hand with AI and compare results.
///   --seed=N: Use a fixed random seed for reproducibility.
///   --pass=DIRECTION: Pass direction (left, right, across, none). Default: left.
///   --mc-rounds=N: Monte Carlo max rounds for AI. Default: 20.
///   --mc-rollouts=N: Monte Carlo rollouts per round for AI. Default: 50.
///   --replay-rounds=N: Number of replay rounds to average for AI comparison. Default: 1.
///   --output-json=PATH: Write a JSON summary of the round to the specified path.

void main(List<String> args) {
  bool replay = args.contains('--replay');
  int? seed;
  int passDirection = 1; // Default: left
  int mcRounds = 20;
  int mcRollouts = 50;
  int replayRounds = 1;
  String? outputJsonPath;

  for (final arg in args) {
    if (arg.startsWith('--seed=')) {
      seed = int.parse(arg.substring(7));
    } else if (arg.startsWith('--pass=')) {
      final dir = arg.substring(7).toLowerCase();
      switch (dir) {
        case 'left':
          passDirection = 1;
          break;
        case 'right':
          passDirection = 3;
          break;
        case 'across':
          passDirection = 2;
          break;
        case 'none':
          passDirection = 0;
          break;
        default:
          print('Invalid pass direction: $dir (use left, right, across, or none)');
          exit(1);
      }
    } else if (arg.startsWith('--mc-rounds=')) {
      mcRounds = int.parse(arg.substring(12));
    } else if (arg.startsWith('--mc-rollouts=')) {
      mcRollouts = int.parse(arg.substring(14));
    } else if (arg.startsWith('--replay-rounds=')) {
      replayRounds = int.parse(arg.substring(16));
    } else if (arg.startsWith('--output-json=')) {
      outputJsonPath = arg.substring(14);
    }
  }

  final mcParams = MonteCarloParams(maxRounds: mcRounds, rolloutsPerRound: mcRollouts);

  final rng = seed != null ? Random(seed) : Random();
  final rules = HeartsRuleSet();

  // Deal a round
  final round = HeartsRound.deal(rules, List.filled(rules.numPlayers, 0), passDirection, rng);

  // Save the initial state for replay
  final savedRoundJson = round.toJson();

  print('=== Hearts CLI ===');
  print('You are South.');
  print('');

  // Handle passing phase
  if (round.status == HeartsRoundStatus.passing) {
    handlePassingPhase(round, rules);
  }

  // Play the round
  playRound(round, rules, rng, mcParams);

  // Show results
  final points = round.pointsTaken();
  final humanPoints = points[0];
  final humanAdjusted = adjustedScoreForComparison(round, 0);
  print('');
  print('=== Round Complete ===');
  print('Points: ${List.generate(4, (i) => "${playerName(i)}: ${points[i]}").join(", ")}');
  print('Your points: $humanPoints');

  // Replay with AI if requested
  List<Map<String, dynamic>> replayResults = [];
  double? avgAiAdjusted;
  double? diff;

  if (replay) {
    print('');
    print('=== Replaying with AI ($replayRounds round${replayRounds > 1 ? "s" : ""}) ===');

    int totalAiAdjusted = 0;
    for (int r = 0; r < replayRounds; r++) {
      final replayRound = HeartsRound.fromJson(savedRoundJson);
      final replayRng = Random();

      // AI handles passing
      if (replayRound.status == HeartsRoundStatus.passing) {
        for (int i = 0; i < rules.numPlayers; i++) {
          final passReq = CardsToPassRequest(
            rules: rules,
            scoresBeforeRound: List.of(replayRound.initialScores),
            hand: replayRound.players[i].hand,
            direction: replayRound.passDirection,
            numCards: rules.numPassedCards,
          );
          final cardsToPass = chooseCardsToPass(passReq);
          replayRound.setPassedCardsForPlayer(i, cardsToPass);
        }
        replayRound.passCards();
      }

      // AI plays the round
      while (!replayRound.isOver()) {
        final cardReq = CardToPlayRequest.fromRound(replayRound);
        final result = chooseCardMonteCarlo(
            cardReq, mcParams, chooseCardAvoidingPoints, replayRng);
        replayRound.playCard(result.bestCard);
      }

      final aiPoints = replayRound.pointsTaken()[0];
      final aiAdjusted = adjustedScoreForComparison(replayRound, 0);
      totalAiAdjusted += aiAdjusted;
      replayResults.add({
        'round': r + 1,
        'aiPoints': aiPoints,
        'aiAdjusted': aiAdjusted,
      });
      if (replayRounds > 1) {
        print('  Round ${r + 1}: AI South scored $aiPoints${aiAdjusted != aiPoints ? " (adjusted: $aiAdjusted)" : ""}');
      }
    }

    avgAiAdjusted = totalAiAdjusted / replayRounds;
    diff = avgAiAdjusted - humanAdjusted;

    print('');
    if (replayRounds > 1) {
      print('AI average adjusted score for South: ${avgAiAdjusted.toStringAsFixed(1)}');
    } else {
      print('AI adjusted score for South: ${avgAiAdjusted.toInt()}');
    }
    print('');
    print('Result relative to AI (positive is good): ${diff > 0 ? "+" : ""}${diff.toStringAsFixed(2)}');
  }

  // Write JSON output if requested
  if (outputJsonPath != null) {
    final jsonOutput = {
      'humanPoints': humanPoints,
      'humanAdjusted': humanAdjusted,
      'invalidInputCount': invalidInputCount,
      if (replay) ...{
        'replay': {
          'rounds': replayResults,
          'avgAiAdjusted': avgAiAdjusted,
          'diffFromAi': diff,
        },
      },
    };
    File(outputJsonPath).writeAsStringSync(JsonEncoder.withIndent('  ').convert(jsonOutput));
    print('');
    print('Results written to $outputJsonPath');
  }
}

/// Calculate an adjusted score for comparison purposes.
/// - If the player shot the moon (0 points, others have 26), count as -26.
/// - If an opponent shot the moon (player has 26 points), count as +13.
int adjustedScoreForComparison(HeartsRound round, int playerIndex) {
  final points = round.pointsTaken();
  final playerPoints = points[playerIndex];
  final shooter = moonShooter(round.previousTricks);

  if (shooter != null) {
    if (shooter == playerIndex) {
      // Player shot the moon - great achievement
      return -26;
    } else {
      // Opponent shot the moon - bad but not as bad as 26
      return 13;
    }
  }
  return playerPoints;
}

void handlePassingPhase(HeartsRound round, HeartsRuleSet rules) {
  final passDir = round.passDirection;
  final dirDesc = passDir == 1
      ? 'to the left'
      : passDir == rules.numPlayers - 1
          ? 'to the right'
          : passDir == 2
              ? 'across'
              : 'unknown';
  print('Passing phase: Pass ${rules.numPassedCards} cards $dirDesc.');
  print('');

  // Show human's hand
  final humanHand = round.players[0].hand;
  print('Your hand:');
  printHand(humanHand);
  print('');

  // Get cards to pass from human
  final cardsToPass = getCardsToPassFromUser(humanHand, rules.numPassedCards);
  round.setPassedCardsForPlayer(0, cardsToPass);

  // AI players pass cards
  for (int i = 1; i < rules.numPlayers; i++) {
    final passReq = CardsToPassRequest(
      rules: rules,
      scoresBeforeRound: List.of(round.initialScores),
      hand: round.players[i].hand,
      direction: passDir,
      numCards: rules.numPassedCards,
    );
    final aiCardsToPass = chooseCardsToPass(passReq);
    round.setPassedCardsForPlayer(i, aiCardsToPass);
  }

  round.passCards();

  print('');
  print('Cards passed. You received: ${round.players[0].receivedCards.map((c) => c.symbolString()).join(' ')}');
  print('');
}

void printHand(List<PlayingCard> hand) {
  print(descriptionWithSuitGroups(hand));
}

const playerNames = ['South', 'West', 'North', 'East'];

String playerName(int index) => playerNames[index];

/// Parse a card from user input, accepting formats like "2S", "2♠", "AS", "A♠", "TS", "T♠"
PlayingCard? parseCard(String input, List<PlayingCard> validCards) {
  final s = input.trim().toUpperCase();
  if (s.isEmpty) return null;

  try {
    // Try parsing with PlayingCard.cardFromString which handles both ASCII and symbol suits
    final card = PlayingCard.cardFromString(s);
    if (validCards.contains(card)) {
      return card;
    }
  } catch (_) {
    // Not a valid card format
  }
  return null;
}

List<PlayingCard> getCardsToPassFromUser(List<PlayingCard> hand, int numCards) {
  while (true) {
    stdout.write('Enter $numCards cards to pass (e.g., "AS QH 2C"): ');
    final input = stdin.readLineSync();
    if (input == null) {
      exit(0);
    }

    final parts = input.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();

    if (parts.length != numCards) {
      print('Please enter exactly $numCards cards.');
      invalidInputCount++;
      continue;
    }

    final cards = <PlayingCard>[];
    bool valid = true;
    for (final part in parts) {
      final card = parseCard(part, hand);
      if (card == null) {
        print('Invalid card: $part');
        invalidInputCount++;
        valid = false;
        break;
      }
      if (cards.contains(card)) {
        print('Duplicate card: $part');
        invalidInputCount++;
        valid = false;
        break;
      }
      cards.add(card);
    }

    if (valid) {
      return cards;
    }
  }
}

void playRound(HeartsRound round, HeartsRuleSet rules, Random rng, MonteCarloParams mcParams) {
  int trickNum = 0;

  while (!round.isOver()) {
    if (round.currentTrick.cards.isEmpty) {
      trickNum++;
      print('');
      print('--- Trick $trickNum ---');
    }

    final currentPlayer = round.currentPlayerIndex();

    if (currentPlayer == 0) {
      // Human's turn
      playHumanTurn(round, rules);
    } else {
      // AI's turn
      playAiTurn(round, rng, currentPlayer, mcParams);
    }

    // Show trick result if complete
    if (round.currentTrick.cards.isEmpty && round.previousTricks.isNotEmpty) {
      final lastTrick = round.previousTricks.last;
      final winner = lastTrick.winner;
      final trickPoints = pointsForCards(lastTrick.cards, rules);
      final winnerName = winner == 0 ? 'You' : playerName(winner);
      print('$winnerName won the trick${trickPoints > 0 ? " ($trickPoints point${trickPoints > 1 ? "s" : ""})" : ""}.');
    }
  }
}

void playHumanTurn(HeartsRound round, HeartsRuleSet rules) {
  final hand = round.players[0].hand;
  final legalPlays = round.legalPlaysForCurrentPlayer();
  final trick = round.currentTrick;

  // Show current trick
  if (trick.cards.isNotEmpty) {
    print('');
    print('Current trick (led by ${playerName(trick.leader)}):');
    printTrick(trick, rules.numPlayers);
  }

  print('');
  print('Your hand:');
  printHand(hand);

  final cardToPlay = getCardToPlayFromUser(hand, legalPlays);
  round.playCard(cardToPlay);
  print('You played: ${cardToPlay.symbolString()}');
}

void printTrick(TrickInProgress trick, int numPlayers) {
  for (int i = 0; i < trick.cards.length; i++) {
    final playerIndex = (trick.leader + i) % numPlayers;
    print('  ${playerName(playerIndex)}: ${trick.cards[i].symbolString()}');
  }
}

PlayingCard getCardToPlayFromUser(List<PlayingCard> hand, List<PlayingCard> legalPlays) {
  while (true) {
    stdout.write('Enter card to play: ');
    final input = stdin.readLineSync();
    if (input == null) {
      exit(0);
    }

    final card = parseCard(input, hand);
    if (card == null) {
      print('Invalid card. Enter a card like "AS" or "A♠".');
      invalidInputCount++;
      continue;
    }

    if (!legalPlays.contains(card)) {
      print('${card.symbolString()} is not a legal play.');
      invalidInputCount++;
      continue;
    }

    return card;
  }
}

void playAiTurn(HeartsRound round, Random rng, int playerIndex, MonteCarloParams mcParams) {
  final cardReq = CardToPlayRequest.fromRound(round);
  final result = chooseCardMonteCarlo(cardReq, mcParams, chooseCardAvoidingPoints, rng);
  final card = result.bestCard;
  round.playCard(card);
  print('${playerName(playerIndex)} played: ${card.symbolString()}');
}
