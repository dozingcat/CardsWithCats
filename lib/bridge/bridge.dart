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

class ContractBid {
  final int count;
  final Suit? trump;  // null=notrump

  ContractBid(this.count, this.trump);

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

  int get numTricksRequired => count + 6;
  bool get isGrandSlam => count == 7;
  bool get isSlam => count == 6;
}

class PlayerBid {
  int player;
  BidType bidType;
  ContractBid? contractBid;

  PlayerBid._(this.player, this.bidType, this.contractBid);

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
}

List<PlayingCard> legalPlays(List<PlayingCard> hand, TrickInProgress currentTrick) {
  if (currentTrick.cards.isEmpty) {
    return hand;
  }
  return hand.where((c) => c.suit == currentTrick.cards[0].suit).toList();
}

class BridgeRound {
  BridgeRoundStatus status = BridgeRoundStatus.bidding;
  late List<BridgePlayer> players;
  late int dealer;
  List<PlayerBid> bidHistory = [];
  late TrickInProgress currentTrick;
  List<Trick> previousTricks = [];
  late Contract contract;
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
      final lastTrick = currentTrick.finish(trump: contract.bid.trump);
      previousTricks.add(lastTrick);
      currentTrick = TrickInProgress(lastTrick.winner);
    }
  }

  void _endBidding() {
    status = BridgeRoundStatus.playing;
    if (isPassedOut()) return;
    contract = contractFromBids(
        bids: bidHistory,
        vulnerability: vulnerability,
    );
  }

  int currentPlayerIndex() {
    return (currentTrick.leader + currentTrick.cards.length) % 4;
  }

  BridgePlayer currentPlayer() => players[currentPlayerIndex()];

  List<PlayingCard> legalPlaysForCurrentPlayer() {
    return legalPlays(currentPlayer().hand, currentTrick);
  }

  int numTricksWonByDeclarer() {
    if (contract == null) {
      return 0;
    }
    int declarer = contract.declarer;
    int dummy = contract.dummy;
    return previousTricks.where((t) => t.winner == declarer || t.winner == dummy).length;
  }

  int contractScoreForDeclarer() {
    if (!isOver()) {
      throw Exception("Round is not over");
    }
    if (isPassedOut()) {
      return 0;
    }
    return contract.scoreForTricksTaken(numTricksWonByDeclarer());
  }

  int contractScoreForPlayer(int pnum) {
    int score = contractScoreForDeclarer();
    return (pnum == contract.declarer || pnum == contract.dummy) ? score : -score;
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
  late ContractBid lastBid;
  for (PlayerBid bid in bids.reversed) {
    if (doubled == DoubledType.none) {
      doubled = switch (bid.bidType) {
        BidType.double => DoubledType.doubled,
        BidType.redouble => DoubledType.redoubled,
        _ => DoubledType.none,
      };
    }
    if (bid.contractBid != null) {
      lastBid = bid.contractBid!;
      break;
    }
  }
  PlayerBid firstBidOfSuit = bids.firstWhere(
          (b) => b.contractBid != null && b.contractBid!.trump == lastBid.trump);
  int declarer = firstBidOfSuit.player;
  return Contract(
    bid: lastBid,
    doubled: doubled,
    declarer: declarer,
    isVulnerable: vulnerability.isPlayerVulnerable(declarer),
  );
}

class BridgeMatch {
  Random rng;
  List<BridgeRound> previousRounds = [];
  late BridgeRound currentRound;

  BridgeMatch(this.rng) {
    currentRound = BridgeRound.deal(0, rng);
  }
}