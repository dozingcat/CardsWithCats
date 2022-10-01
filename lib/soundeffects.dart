import 'dart:math';

import 'package:just_audio/just_audio.dart';

class SoundEffectPlayer {
  final rng = Random();
  final madSoundPlayers = <AudioPlayer>[];
  final happySoundPlayers = <AudioPlayer>[];
  bool enabled = false;
  bool soundsLoaded = false;

  void init() async {
    soundsLoaded = false;

    madSoundPlayers.clear();
    madSoundPlayers.add(await _makePlayer('sauerkraut_mad_1.mp3'));
    madSoundPlayers.add(await _makePlayer('sauerkraut_mad_2.mp3'));
    madSoundPlayers.add(await _makePlayer('sauerkraut_mad_3.mp3'));
    madSoundPlayers.add(await _makePlayer('ginger_mad_1.mp3'));
    madSoundPlayers.add(await _makePlayer('ginger_mad_2.mp3'));

    happySoundPlayers.clear();
    happySoundPlayers.add(await _makePlayer('boojie_happy_1.mp3'));
    happySoundPlayers.add(await _makePlayer('boojie_happy_2.mp3'));
    happySoundPlayers.add(await _makePlayer('boojie_happy_3.mp3'));
    happySoundPlayers.add(await _makePlayer('boojie_happy_4.mp3'));

    soundsLoaded = true;
  }

  int loopIndex = 0;

  void _playRandomSoundFrom(final List<AudioPlayer> players) async {
    if (!enabled || !soundsLoaded) {
      return;
    }
    final index = rng.nextInt(players.length);
    await players[index].seek(Duration.zero);
    await players[index].play();
  }

  void playMadSound() async {
    _playRandomSoundFrom(madSoundPlayers);
  }

  void playHappySound() async {
    _playRandomSoundFrom(happySoundPlayers);
  }
}

Future<AudioPlayer> _makePlayer(String filename) async {
  final player = AudioPlayer();
  await player.setAsset('assets/audio/$filename');
  return player;
}