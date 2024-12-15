Comments or bug reports: [bnenning@gmail.com](mailto:bnenning@gmail.com)

## General

In both Hearts and Spades, each player is dealt 13 cards and plays them in a series of "tricks".
In each trick, one player leads by playing a card. Each other player then plays a card, in
clockwise order. You must play a card of the same suit as the card that was led if possible; if not
you may play any card. Whoever plays the highest card of the suit that was led takes the cards in
the trick and leads the next trick. If there is a trump suit, as in Spades and Oh Hell, then the
highest card in the trump suit wins the trick regardless of what other cards were played.

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
There are two teams in spades. Your partner is at the top of the screen, and your opponents are on
the sides. The goal is to reach 500 points by bidding on how many tricks you will take in each
round, and then taking that many while preventing your opponents from doing the same. Spades are
always the trump suit.

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

## License

This application is released under the GNU General Public License, version 3. Source code is
available [here](https://github.com/dozingcat/CardsWithCats).


## Credits

- Cats by [AnnaliseArt on Pixabay](https://pixabay.com/illustrations/cats-hanging-cats-kitty-cat-paw-3611310/)
- Thought bubble by [OpenClipart-Vectors on Pixabay](https://pixabay.com/vectors/balloon-bubble-speech-thought-150981/)
- Cat emojis from [Noto Emoji by Google](https://github.com/googlefonts/noto-emoji/)
- Playing cards: \
https://totalnonsense.com/open-source-vector-playing-cards/ \
Copyright 2011,2024 – Chris Aguilar – conjurenation@gmail.com \
Licensed under: LGPL 3.0 – https://www.gnu.org/licenses/lgpl-3.0.html
- Sounds by Boojie, Ginger, and Sauerkraut