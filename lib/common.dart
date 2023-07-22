enum GameType {
  hearts,
  spades,
  ohHell;

  static GameType? fromString(String s) {
    for (final e in values) {
      if (e.name == s) {
        return e;
      }
    }
    return null;
  }
}
