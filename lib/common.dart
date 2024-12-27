enum GameType {
  hearts,
  spades,
  ohHell,
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
