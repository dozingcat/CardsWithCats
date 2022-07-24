import 'dart:math';

import 'package:just_audio/just_audio.dart';

class SoundEffectPlayer {
  final rng = Random();
  final madSoundPlayers = <AudioPlayer>[];
  bool enabled = false;
  bool soundsLoaded = false;

  void init() async {
    soundsLoaded = false;
    madSoundPlayers.clear();

    madSoundPlayers.add(await _makePlayer('sauerkraut_mad_1.wav'));
    madSoundPlayers.add(await _makePlayer('sauerkraut_mad_2.wav'));

    soundsLoaded = true;
  }

  void playMadSound() {
    if (!enabled || !soundsLoaded) {
      return;
    }
    final index = rng.nextInt(madSoundPlayers.length);
    madSoundPlayers[index].play();
  }
}

Future<AudioPlayer> _makePlayer(String filename) async {
  final player = AudioPlayer();
  await player.setAsset('assets/audio/$filename');
  return player;
}