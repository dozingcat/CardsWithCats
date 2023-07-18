enum MatchType {
  hearts,
  spades,
  ohHell;

  static MatchType? fromString(String s) {
    for (final e in values) {
      if (e.name == s) {
        return e;
      }
    }
    return null;
  }
}
