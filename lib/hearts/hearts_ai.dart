import 'dart:math';

import 'package:hearts/cards/card.dart';
import 'package:hearts/cards/trick.dart';
import 'package:hearts/hearts/hearts.dart';

// Returns the estimated probability of the player at `player_index` eventually
// winning the match.
double matchEquityForScores(List<int> scores, int maxScore, int playerIndex) {
  if (scores.any((s) => s >= maxScore)) {
    final minScore = scores.red
  }
}