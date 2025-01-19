import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';

const int numPlayers = 4;

enum BidType {
  pass,
  contract,
  double,
  redouble,
}

enum DoubledType {
  none,
  doubled,
  redoubled,
}

enum Vulnerability {
  neither, nsOnly, ewOnly, both;

  bool isPlayerVulnerable(int playerIndex) {
    if (playerIndex == 0 || playerIndex == 2) {
      return this == nsOnly || this == both;
    }
    else if (playerIndex == 1 || playerIndex == 3) {
      return this == ewOnly || this == both;
    }
    throw AssertionError("Bad playerIndex $playerIndex");
  }
}

bool isMinorSuit(Suit? s) => s == Suit.clubs || s == Suit.diamonds;
bool isMajorSuit(Suit? s) => s == Suit.hearts || s == Suit.spades;

int dummyIndexForDeclarer(int d) => (d + 2) % 4;

int _rankIndexForSuit(Suit? suit) {
  return switch (suit) {
    Suit.clubs => 0,
    Suit.diamonds => 1,
    Suit.hearts => 2,
    Suit.spades => 3,
    null => 4,
  };
}

class ContractBid {
  final int count;
  final Suit? trump;  // null=notrump

  ContractBid(this.count, this.trump);

  static ContractBid noTrump(int count) => ContractBid(count, null);

  @override
  int get hashCode => count << 8 + (trump != null ? trump!.index + 1 : 0);

  @override
  bool operator ==(Object other) {
    return (other is ContractBid && other.count == count && other.trump == trump);
  }

  @override
  String toString() {
    return "${count}${trump != null ? trump!.asciiChar : 'NT'}";
  }

  String symbolString() {
    return "${count}${trump != null ? trump!.symbolChar : 'NT'}";
  }

  bool isHigherThan(ContractBid other) {
    return (count > other.count || (count == other.count && _rankIndexForSuit(trump) > _rankIndexForSuit(other.trump)));
  }

  static ContractBid fromString(String s) {
    int count = int.parse(s.substring(0, 1));
    if (!(count >= 1 && count <= 7)) {
      throw Exception("Invalid bid amount: $count");
    }
    if (s.length == 2) {
      return ContractBid(count, Suit.fromChar(s[1]));
    }
    else if (s.length == 3 && s.substring(1) == "NT") {
      return noTrump(count);
    }
    throw Exception("Invalid bid string");
  }

  int get numTricksRequired => count + 6;
  bool get isGrandSlam => count == 7;
  bool get isSlam => count == 6;
}

class PlayerBid {
  int player;
  BidType bidType;
  ContractBid? contractBid;

  PlayerBid._(this.player, this.bidType, this.contractBid);

  Map<String, dynamic> toJson() {
    return {
      "player": player,
      "bidType": bidType.name,
      "contractBid": contractBid?.toString(),
    };
  }

  static PlayerBid fromJson(Map<String, dynamic> json) {
    int pnum = json["player"];
    BidType type = BidType.values.firstWhere((t) => t.name == json["bidType"]);
    return switch (type) {
      BidType.pass => pass(pnum),
      BidType.double => double(pnum),
      BidType.redouble => redouble(pnum),
      BidType.contract => contract(pnum, ContractBid.fromString(json["contractBid"])),
    };
  }

  @override
  String toString() {
    String desc = switch (bidType) {
      BidType.pass => "Pass",
      BidType.double => "Double",
      BidType.redouble => "Redouble",
      BidType.contract => contractBid.toString(),
    };
    return "Player ${player}: ${desc}";
  }

  String symbolString() {
    return switch (bidType) {
      BidType.pass => "-",
      BidType.double => "X",
      BidType.redouble => "XX",
      BidType.contract => contractBid!.symbolString(),
    };
  }

  static PlayerBid pass(int player) => PlayerBid._(player, BidType.pass, null);
  static PlayerBid double(int player) => PlayerBid._(player, BidType.double, null);
  static PlayerBid redouble(int player) => PlayerBid._(player, BidType.redouble, null);
  static PlayerBid contract(int player, ContractBid bid) => PlayerBid._(player, BidType.contract, bid);
}

class Contract {
  ContractBid bid;
  DoubledType doubled;
  int declarer;
  bool isVulnerable;

  Contract({
    required this.bid,
    required this.isVulnerable,
    required this.declarer,
    this.doubled = DoubledType.none,
  });

  Map<String, dynamic> toJson() {
    return {
      "bid": bid.toString(),
      "doubled": doubled.name,
      "declarer": declarer,
      "isVulnerable": isVulnerable,
    };
  }

  static Contract fromJson(Map<String, dynamic> json) {
    return Contract(
      bid: ContractBid.fromString(json["bid"]),
      doubled: DoubledType.values.firstWhere((t) => t.name == json["doubled"]),
      declarer: json["declarer"],
      isVulnerable: json["isVulnerable"],
    );
  }

  int get dummy => (declarer + 2) % 4;

  int scoreForTricksTaken(int numTricks) {
    final delta = numTricks - bid.numTricksRequired;
    if (delta >= 0) {
      int doubleBounus = switch (doubled) {
        DoubledType.none => 0,
        DoubledType.doubled => 50,
        DoubledType.redoubled => 100,
      };
      int doubleFactor = switch(doubled) {
        DoubledType.none => 1,
        DoubledType.doubled => 2,
        DoubledType.redoubled => 4,
      };
      int pointsPerOvertrick = switch (doubled) {
        DoubledType.none => isMinorSuit(bid.trump) ? 20 : 30,
        DoubledType.doubled => isVulnerable ? 200 : 100,
        DoubledType.redoubled => isVulnerable ? 400 : 200,
      };
      int bidTrickPoints = doubleFactor * (
          bid.count * (isMinorSuit(bid.trump) ? 20 : 30) + (bid.trump == null ? 10 : 0)
      );
      bool isGame = bidTrickPoints >= 100;
      int overtrickPoints = delta * pointsPerOvertrick;

      if (isGame) {
        int gameBonus = isVulnerable ? 500 : 300;
        return bidTrickPoints + overtrickPoints + gameBonus + _slamBonus() + doubleBounus;
      }
      else {
        return bidTrickPoints + overtrickPoints + 50 + doubleBounus;
      }
    }
    else {
      final down = -delta;
      if (doubled == DoubledType.none) {
        return -down * (isVulnerable ? 100 : 50);
      }
      else {
        int multiplier = (doubled == DoubledType.redoubled) ? 2 : 1;
        if (down == 1) {
          return -multiplier * (isVulnerable ? 200 : 100);
        }
        if (down == 2) {
          return -multiplier * (isVulnerable ? 500 : 300);
        }
        // Everything after down 3 is 300 both vulnerable and not.
        int down3Base = isVulnerable ? 800 : 500;
        return -multiplier * (down3Base + (300 * (down - 3)));
      }
    }
  }

  int _slamBonus() {
    if (bid.isGrandSlam) {
      return isVulnerable ? 1500 : 1000;
    }
    else if (bid.isSlam) {
      return isVulnerable ? 750 : 500;
    }
    return 0;
  }

}

enum BridgeRoundStatus {
  bidding,
  playing,
}

class BridgePlayer {
  List<PlayingCard> hand;

  BridgePlayer(this.hand);

  BridgePlayer copy() => BridgePlayer(List.from(hand));

  Map<String, dynamic> toJson() {
    return {
      "hand": PlayingCard.stringFromCards(hand),
    };
  }

  static BridgePlayer fromJson(Map<String, dynamic> json) {
    return BridgePlayer(PlayingCard.cardsFromString(json["hand"] as String));
  }
}

List<PlayingCard> legalPlays(List<PlayingCard> hand, TrickInProgress currentTrick) {
  if (currentTrick.cards.isEmpty) {
    return hand;
  }
  final matchingSuit = hand.where((c) => c.suit == currentTrick.cards[0].suit).toList();
  if (matchingSuit.isNotEmpty) {
    return matchingSuit;
  }
  return hand;
}

class BridgeRound {
  BridgeRoundStatus status = BridgeRoundStatus.bidding;
  late List<BridgePlayer> players;
  late int dealer;
  List<PlayerBid> bidHistory = [];
  late TrickInProgress currentTrick;
  List<Trick> previousTricks = [];
  Contract? contract;
  Vulnerability vulnerability = Vulnerability.neither;
  // Include "current" match points?

  static BridgeRound deal(int dealer, Random rng) {
    List<PlayingCard> cards = List.from(standardDeckCards());
    cards.shuffle(rng);
    List<BridgePlayer> players = [];
    int numCardsPerPlayer = cards.length ~/ numPlayers;
    for (int i = 0; i < numPlayers; i++) {
      final playerCards = cards.sublist(i * numCardsPerPlayer, (i + 1) * numCardsPerPlayer);
      players.add(BridgePlayer(playerCards));
    }

    return BridgeRound()
        ..players = players
        ..dealer = dealer
        ..currentTrick = TrickInProgress(0)  // placeholder
        ;
  }

  BridgeRound copy() {
    return BridgeRound()
      ..status = status
      ..players = players.map((p) => p.copy()).toList()
      ..dealer = dealer
      ..bidHistory = List.from(bidHistory)
      ..currentTrick = currentTrick.copy()
      ..previousTricks = Trick.copyAll(previousTricks)
      ..contract = contract
      ..vulnerability = vulnerability
    ;
  }

  Map<String, dynamic> toJson() {
    return {
      "status": status.name,
      "players": [...players.map((p) => p.toJson())],
      "dealer": dealer,
      "bidHistory": [...bidHistory.map((b) => b.toJson())],
      "currentTrick": currentTrick.toJson(),
      "previousTricks": [...previousTricks.map((t) => t.toJson())],
      "contract": contract?.toJson(),
    };
  }

  static BridgeRound fromJson(final Map<String, dynamic> json) {
    return BridgeRound()
      ..status = BridgeRoundStatus.values.firstWhere((s) => s.name == json["status"])
      ..players = [...json["players"].map((p) => BridgePlayer.fromJson(p as Map<String, dynamic>))]
      ..dealer = json["dealer"] as int
      ..bidHistory = [...json["bidHistory"].map((b) => PlayerBid.fromJson(b as Map<String, dynamic>))]
      ..currentTrick = TrickInProgress.fromJson(json["currentTrick"] as Map<String, dynamic>)
      ..previousTricks = [
        ...json["previousTricks"].map((t) => Trick.fromJson(t as Map<String, dynamic>))
      ]
      ..contract = (json["contract"] != null) ? Contract.fromJson(json["contract"]) : null
    ;
  }

  bool isOver() {
    return isPassedOut() ||  players.every((p) => p.hand.isEmpty);
  }

  bool isPassedOut() {
    return bidHistory.length == numPlayers && bidHistory.every((b) => b.bidType == BidType.pass);
  }

  int currentBidder() {
    return (dealer + bidHistory.length) % numPlayers;
  }

  void addBid(PlayerBid bid) {
    if (status != BridgeRoundStatus.bidding) {
      throw Exception("Bidding is over");
    }
    if (bid.player != currentBidder()) {
      throw Exception("Got bid from wrong player (${bid.player}, expected ${currentBidder()}");
    }
    bidHistory.add(bid);
    if (isBiddingOver(bidHistory)) {
      _endBidding();
    }
  }

  void playCard(PlayingCard card) {
    final p = currentPlayer();
    final cardIndex = p.hand.indexWhere((c) => c == card);
    p.hand.removeAt(cardIndex);
    currentTrick.cards.add(card);
    if (currentTrick.cards.length == numPlayers) {
      final lastTrick = currentTrick.finish(trump: contract!.bid.trump);
      previousTricks.add(lastTrick);
      currentTrick = TrickInProgress(lastTrick.winner);
    }
  }

  void _endBidding() {
    status = BridgeRoundStatus.playing;
    if (isPassedOut()) {
      return;
    }
    contract = contractFromBids(
      bids: bidHistory,
      vulnerability: vulnerability,
    );
    currentTrick = TrickInProgress((contract!.declarer + 1) % 4);
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % 4;
  }

  BridgePlayer currentPlayer() => players[currentPlayerIndex()];

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(currentPlayer().hand, currentTrick);
  }

  Suit? trumpSuit() {
    if (contract == null) {
      return null;
    }
    return contract!.bid.trump;
  }

  int? visibleDummy() {
    if (contract == null) {
      return null;
    }
    // Dummy is revealed only after first card of first trick is played.
    if (previousTricks.isEmpty && currentTrick.cards.isEmpty) {
      return null;
    }
    return contract!.dummy;
  }

  int numTricksWonByDeclarer() {
    if (contract == null) {
      return 0;
    }
    int declarer = contract!.declarer;
    int dummy = contract!.dummy;
    return previousTricks.where((t) => t.winner == declarer || t.winner == dummy).length;
  }

  int contractScoreForDeclarer() {
    if (!isOver()) {
      throw Exception("Round is not over");
    }
    if (isPassedOut()) {
      return 0;
    }
    return contract!.scoreForTricksTaken(numTricksWonByDeclarer());
  }

  int contractScoreForPlayer(int pnum) {
    int score = contractScoreForDeclarer();
    if (score == 0) {
      return 0;
    }
    return (pnum == contract!.declarer || pnum == contract!.dummy) ? score : -score;
  }

  int tricksTakenByDeclarerOverContract() {
    if (contract == null) {
      throw Exception("Bidding is not over");
    }
    int tricksWon = numTricksWonByDeclarer();
    return tricksWon - contract!.bid.numTricksRequired;
  }
}

PlayerBid? lastContractBid(List<PlayerBid> bids) {
  for (final b in bids.reversed) {
    if (b.bidType == BidType.contract) {
      return b;
    }
  }
  return null;
}

bool isBiddingOver(List<PlayerBid> bids) {
  // At least 4 bids, ending in 3 passes.
  int n = bids.length;
  if (n < numPlayers) {
    return false;
  }
  for (int i = 0; i < numPlayers - 1; i++) {
    if (bids[n - i - 1].bidType != BidType.pass) {
      return false;
    }
  }
  return true;
}

bool canCurrentBidderDouble(List<PlayerBid> bids) {
  if (bids.isEmpty) {
    return false;
  }
  int previousBidder = bids.last.player;
  // Find last contract bid. Double is allowed if there isn't already a double,
  // and if the bid was made by an opponent.
  for (final bid in bids.reversed) {
    if (bid.bidType == BidType.double) {
      return false;
    }
    if (bid.bidType == BidType.contract) {
      return bid.player % 2 == previousBidder % 2;
    }
  }
  return false;
}

bool canCurrentBidderRedouble(List<PlayerBid> bids) {
  if (bids.isEmpty) {
    return false;
  }
  int previousBidder = bids.last.player;
  bool hasDouble = false;
  // Find last contract bid. Redouble is allowed if there is a double but not
  // a redouble, and if the bid was made by the current bidder or partner.
  for (final bid in bids.reversed) {
    if (bid.bidType == BidType.redouble) {
      return false;
    }
    if (bid.bidType == BidType.double) {
      hasDouble = true;
    }
    if (bid.bidType == BidType.contract) {
      return hasDouble && (bid.player % 2 != previousBidder % 2);
    }
  }
  return false;
}

Contract contractFromBids({
  required List<PlayerBid> bids,
  required Vulnerability vulnerability,
}) {
  // Go backwards to find last bid and double/redouble.
  DoubledType doubled = DoubledType.none;
  late PlayerBid lastBid;
  for (PlayerBid bid in bids.reversed) {
    if (doubled == DoubledType.none) {
      doubled = switch (bid.bidType) {
        BidType.double => DoubledType.doubled,
        BidType.redouble => DoubledType.redoubled,
        _ => DoubledType.none,
      };
    }
    if (bid.contractBid != null) {
      lastBid = bid;
      break;
    }
  }
  // Find first player on declaring side to bid the contract suit.
  int lastBidPartner = (lastBid.player + 2) % 4;
  for (final b in bids) {
    if (b.player == lastBid.player || b.player == lastBidPartner) {
      if (b.contractBid != null && b.contractBid!.trump == lastBid.contractBid!.trump) {
        return Contract(
          bid: lastBid.contractBid!,
          doubled: doubled,
          declarer: b.player,
          isVulnerable: vulnerability.isPlayerVulnerable(b.player),
        );
      }
    }
  }
  throw AssertionError("Couldn't find declarer bid, this shouldn't happen");
}

class BridgeMatch {
  Random rng;
  List<BridgeRound> previousRounds = [];
  late BridgeRound currentRound;

  BridgeMatch(this.rng) {
    currentRound = BridgeRound.deal(2, rng);
  }

  Map<String, dynamic> toJson() {
    return {
      "previousRounds": [...previousRounds.map((r) => r.toJson())],
      "currentRound": currentRound.toJson(),
    };
  }

  static BridgeMatch fromJson(final Map<String, dynamic> json, Random rng) {
    return BridgeMatch(rng)
      ..previousRounds = [
        ...json["previousRounds"].map((r) => BridgeRound.fromJson(r as Map<String, dynamic>))
      ]
      ..currentRound = BridgeRound.fromJson(json["currentRound"] as Map<String, dynamic>);
  }

  void finishRound() {
    // TODO
  }

  bool isMatchOver() {
    // TODO
    return currentRound.isOver();
  }
}