enum GameType {
  hearts,
  spades,
  ohHell,
  bridge,
  rook,
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
