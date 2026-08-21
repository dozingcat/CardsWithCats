enum GameType {
  hearts,
  spades,
  ohHell,
  scum,
  bridge,
  ;

  static GameType? fromString(String s) {
    for (final e in values) {
      if (e.name == s) {
        return e;
      }
    }
    return null;
  }
}
