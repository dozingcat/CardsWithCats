Comments or bug reports: [bnenning@gmail.com](mailto:bnenning@gmail.com)

## General

In all games, each player is dealt a hand of cards and plays them in a series of "tricks".
In each trick, one player leads by playing a card. Each other player then plays a card, in
clockwise order. You must play a card of the same suit as the card that was led if possible; if not
you may play any card. Whoever plays the highest card of the suit that was led takes the cards in
the trick and leads the next trick. If there is a trump suit, as in Spades and bridge, then the
highest card in the trump suit wins the trick regardless of what other cards were played.

Hearts and Oh Hell are individual games against three other players; the other games have two
teams of partners. In those games your partner is at the top of the screen and your opponents are on
the sides.

## Hearts

### Rules
The goal is to have the lowest score by avoiding points. A match consists of multiple rounds and
ends when one player reaches 100 points. Points are scored by taking hearts and the queen of spades.

After the cards are dealt for each round, there is usually a passing step. In this step each player
selects three cards to pass to an opponent. The pass direction cycles between left, right, across,
and then a round without passing.

The player with the two of clubs leads it for the first trick. After that, whoever takes each
trick leads the next one. You cannot lead hearts unless a heart has been played on a previous trick.
The first trick of a round is "safe"; players are not allowed to play hearts or the queen of spades,
even if they have no clubs.

### Scoring
When a round is over, each player scores 1 point for each heart they took, and 13 points for taking
the queen of spades. The match is over when one or more players have taken at least 100 points, and
the player with the lowest score wins. This means that you generally want to avoid taking
points, but there is a special rule: if a player takes all 13 hearts and the queen of spades, that
player score zero points and all their opponents score 26. This is called "shooting the moon".

### Optional rules
These rules can be configured in the Preferences screen from the main menu.
- **J♦ is -10 points**: If enabled, the player who takes the jack of diamonds scores -10 points at the
end of the round.
- **Q♠ breaks hearts**: Normally, you cannot lead a heart to start a trick unless hearts have been
"broken" by being played on a previous trick. If this option is enabled, playing the queen of spades
also allows hearts to be led in subsequent tricks.
- **Allow points on first trick**: Normally, points (hearts and the queen of spades) cannot be played on
the first trick of a round. If this option is enabled, they can be.


## Spades

### Rules
In Spades, the goal is to reach 500 points by bidding on how many tricks your team will take, and
then taking that many while preventing the opposing from doing the same. Spades are always the trump
suit.

A round starts with each player making a bid, which is a declaration of how many tricks they expect
to win. Bids of zero (called "nil") are treated specially; see the Scoring section. After all
players have made a bid, the first bidder (this rotates every round) leads the first trick.

### Scoring
If you and your partner make your combined bid, you score 10 points for each trick that you bid.
(It doesn't matter how many tricks you individually take, only whether the total number of tricks
is at least the total bid). If you fail to make your combined bid, you lose 10 points for each
trick that you bid.

If a player bids nil and successfully takes no tricks, their team scores 100 points. But if the nil
bidder takes one or more tricks, their team loses 100 points.

### Optional rules
These rules can be configured in the Preferences screen from the main menu.
- **Penalize sandbags**: If enabled, then for each trick that a team takes over the bid amount, 1 point
is scored. These points are called "bags" or "sandbags", and if a team accumulates 10 or more bags
they lose 110 points. This discourages being overly cautious when bidding.
- **No leading spades until broken**: If enabled, players cannot lead a spade until a spade has been
played on a previous trick.


## Oh Hell

### Rules
The goal is to bid on how many tricks you will take, and take **exactly** that number. A match
consists of a fixed number of rounds, and in each round players receive a number of cards according
to a sequence (by default, starting at ten, decreasing to one, and increasing back up to ten).
After hands are dealt, a trump suit is chosen; by default the suit of the last card dealt is trump.

Each player then makes a bid of how many tricks they intend to take. After all players have bid,
the first bidder leads the first trick.

### Scoring
If you take exactly the number of tricks that you bid, you score 10 points. By default you also
score 1 point for each trick you take, whether or not you make your bid. For example, if you bid
2 and successfully take 2 tricks, you would score 12 points; if you instead take 3 tricks you would
score only 3.

### Optional rules
These rules can be configured in the Preferences screen from the main menu.
- **Total bids can't equal tricks**: If enabled, then the last player to bid may not choose the number
that causes the total bids to equal the total number of tricks. This ensures that not all players
will be able to make their bids exactly.
- **Dealer's last card is trump**: If enabled, the last card the dealer receives is the trump suit.
If not enabled, the trump suit is determined by the next card after all players have received
their hands.
- **Number of tricks sequence**: Sets the sequence of how many cards each player receives in each round.
If "Always 13", the match lasts until one player reaches 100 points rather than a fixed number
of rounds.
- **Score 1 point per trick**: Can be set to have players score 1 point per trick always, never, or
only when they make their exact bid.


## Bridge

Bridge is played by two teams of partners. A round begins with an "auction", where players bid to
set the trump suit (or to have no trump suit, "NT") and to say how many tricks they will win with
that trump. During play, the player who first bid the trump suit is the "declarer" and their partner
is the "dummy". The dummy's cards are turned face up for all players to see, and the declarer
chooses the cards to play. If your partner is the declarer, you will switch positions and play your
partner's hand, with your original hand as the dummy.

See [here](https://www.acbl.org/learn/) for more detailed rules.

### Bidding
The bidding system that the AI players use is mostly [Standard American Yellow Card](https://www.bridgebum.com/sayc.php) (SAYC),
including:
- 5-card majors with limit raises and Jacoby 2NT
- Negative doubles
- Weak opening two-bids, strong 2♣
- Weak jump overcalls
- 1NT opening with 15-17 points, Stayman, and Jacoby transfers
- Blackwood and Gerber

You can see the meaning of a bid that a player (including yourself) has made by tapping it in the
bid table. If you make a bid that's not interpreted how you expected, you can use the "Undo last bid"
button to rewind the auction to your most recent action.

The AI players do not currently use any conventions for playing cards (e.g. playing high then low to
indicate an even number of cards in the suit).

### Scoring
Matches are scored as "duplicate teams". Each hand you play is also played separately by AI. The
difference between your score for the hand and the score that the AI player gets for the same
hand is converted to [International Match Points](https://en.wikipedia.org/wiki/International_Match_Points) (IMPs). 

For example, suppose you bid and make a contract of 2♠, while in the duplicate hand the player in
your position also bids 2♠ but fails to make it by one trick. Your score is +110, and your AI
counterpart's score is -50. The difference is 160 points in your favor, which translates to +4 IMPs.

After each round ends, you can review the bidding and play for both your hand and the duplicate
hand. The "double dummy" result for your hand is also shown; this is what the result would be if all
players played perfectly and with full knowledge of where all the cards are.

The length of a match is set in the preferences and can be 1, 4, or 8 hands. The winner of the match
is determined by the IMPs accumulated over all hands.

### Preferences
In the Preferences screen, you can set the length of a match and control whether the dummy is always
at the top of the screen (your position will be rotated as needed).


## Rook

In Rook, the goal is to bid on how many point cards your team will win, and then take at least that
many. The point cards are the joker (20 points), aces and tens (10 points each), and fives
(5 points each). There are a total of 120 points.

The deck contains 41 cards, including a joker; The 2s, 3s, and 4s are removed. Each player is dealt
nine cards, and the remaining five cards go into the "nest".

### Bidding
Each player can bid a number of points that their team will take (minimum of 70, exceeding the last
bid in 5 point increments), or pass. After passing, a player cannot bid again. The highest bidder
takes the nest cards and chooses any five cards to discard back to the nest. After discarding, the
high bidder chooses the trump suit.

### Play
The player to the left of the dealer leads the first trick. The joker is considered the highest
trump, and unlike other trumps can be played at any time, even if the player could follow suit.
When a player leads the joker, other players must play the trump suit if possible. The team that
wins the final trick also collects the cards in the nest and scores any point cards that are there.

### Scoring
Each team scores the amount of point cards in the tricks that they took. However, if the high
bidder's team fails to take at least the number of points in the bid, they instead lose the amount
that they bid. The first team to reach 300 points wins.


## 500

In 500, players bid on how many tricks their team will take with a trump suit, and then try to take
that many or prevent the other team from doing so. The deck contains 43 cards including a joker; the
2s, 3s, and black 4s are removed. Each player receives ten cards; the remaining three cards are the
"kitty".

### Bidding
Each player in turn either makes a bid higher than the previous bid or passes. A bid is the number
of tricks the bidder's team will take (6 through 10) and the trump suit or "no trump". To be higher
than the previous bid, a new bid must either be for more tricks or the same number of tricks in a
higher suit; the suit order from low to high is spades, clubs, diamonds, hearts, and no trump. A
player cannot bid again after passing. The high bidder takes the three cards from the kitty and then
discards any three cards, so they're left with ten.

### Play
The high bidder leads the first trick. If there is a trump suit, the joker is the highest trump,
followed by the jack of the trump suit, then the jack of the same-color suit, then the remaining
trumps descending from ace. For example, if hearts are trump, then the trump order is joker, jack of
hearts, jack of diamonds, ace of hearts, king of hearts, and so on. (Jacks that are not trumps are
treated normally and ranked below queens).

If the bid is no trump, the joker is still considered a trump and wins any trick in which it's
played. It can only be played on an existing trick if the owner has no cards of the suit that was
led. A player can lead the joker at no trump, in which case they specify the suit that other players
must follow if possible.

### Scoring
If the bidding team makes their contract, they score points according to the table below. If they do
not make the contract, they lose that number of points instead. The non-bidding team always scores
10 points for each trick they take.

| Tricks | ♠/♣/♦/♥/NT          |
|--------|---------------------|
| 6      | 40/60/80/100/120    |
| 7      | 140/160/180/200/220 |
| 8      | 240/260/280/300/320 |
| 9      | 340/360/380/400/420 |
| 10     | 440/460/480/500/520 |

Also, if the bidding team takes all ten tricks (a "slam"), they score 250 points if that's higher
than the normal contract value.

A team wins when either they reach 500 points, or their opponents fall to negative 500 or lower.

## License

This application is released under the GNU General Public License, version 3. Source code is
available [here](https://github.com/dozingcat/CardsWithCats).


## Credits

- Cats by [AnnaliseArt on Pixabay](https://pixabay.com/illustrations/cats-hanging-cats-kitty-cat-paw-3611310/)
- Thought bubble by [OpenClipart-Vectors on Pixabay](https://pixabay.com/vectors/balloon-bubble-speech-thought-150981/)
- Cat emojis from [Noto Emoji by Google](https://github.com/googlefonts/noto-emoji/)
- Playing cards:
  - Default set: https://totalnonsense.com/open-source-vector-playing-cards/ \
Copyright 2011,2024 – Chris Aguilar – conjurenation@gmail.com \
Licensed under [LGPL 3.0](https://www.gnu.org/licenses/lgpl-3.0.html)
  - "Original" set: https://code.google.com/archive/p/vector-playing-cards/, public domain
  - "Large text" and "Large 4 color" sets: https://www.me.uk/cards/ \
© Copyright 2018 Adrian Kennard \
Licensed under [CC0 Public Domain License](https://creativecommons.org/publicdomain/zero/1.0/legalcode)
- dds double dummy solver: https://github.com/dds-bridge/dds \
(c) Bo Haglund 2006-2014, (c) Bo Haglund / Soren Hein 2014-2018
Licensed under Apache 2.0 - https://www.apache.org/licenses/LICENSE-2.0
- Sounds by Boojie, Ginger, and Sauerkraut