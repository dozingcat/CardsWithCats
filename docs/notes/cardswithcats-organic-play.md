---
name: cardswithcats-organic-play
description: Cards With Cats must never auto-resolve or skip play; every trick and hand plays out on screen like a real card game.
metadata: 
  node_type: memory
  pinned: false
  originSessionId: 935c7fb4-c17a-4808-bcea-a8b9e5a58827
  modified: 2026-09-06T09:01:04.781Z
---

# Cards With Cats never fast-forwards play

In the `crhy/CardsWithCats` project (local clone at `/home/rhy/ScumWithCats`),
rhY wants every hand to "play out organically like it would in a real card game
with real people." Shortcuts that resolve cards without showing them are a
regression, not an optimization.

The concrete correction: the upstream code had a "claim remaining tricks"
feature that, once the leader was mathematically guaranteed the rest of the
round, popped a dialog and then called `claimRemainingTricks()` to play every
remaining card instantly. When asked to fix this (GitHub issues #14 and #16), I
first kept the shortcut and merely animated the playout faster. That was not
what was wanted — the answer was to delete the claim mechanism outright so the
bots and the player actually play each remaining trick at normal pace.

The same principle drove the related fixes: a completed trick gets an explicit
hold phase so the card that closed it (often a bot's ace) is visibly on the
table before the trick is swept away, and the end-of-round score dialog waits
for those animations instead of appearing the instant the last card lands.

When touching this game's turn scheduling, assume the default is to show
everything and never to skip ahead, even when the outcome is already
determined.
