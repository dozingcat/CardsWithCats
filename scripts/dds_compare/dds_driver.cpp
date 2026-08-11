// Batch driver for cross-checking lib/bridge/dd_solver.dart against the
// established dds-bridge/dds solver (tested with v2.9.0).
//
// Build (from a checkout of dds-bridge/dds at tag v2.9.0):
//   clang++ -O2 -std=c++11 -DDDS_THREADS_STL -I<dds>/include \
//       scripts/dds_compare/dds_driver.cpp <dds>/src/*.cpp -o dds_driver
//
// Protocol: one position per input line, all numbers decimal:
//   trump first ntrick [suit rank]*ntrick m00 m01 ... m33
// where trump is 0=S 1=H 2=D 3=C 4=NT, first is the leader of the current
// trick (0=N 1=E 2=S 3=W), ntrick in 0..3 is the number of cards already
// played to the trick (suit/rank pairs in play order, rank 2..14), and mHS
// is the DDS bitmask (bits 2..14) of hand H's remaining cards in suit S,
// suits in DDS order S,H,D,C.
// Output: one line per position with the maximum tricks for the side of
// the player to move, or "ERR <code>".

#include <cstdio>
#include <string>
#include "dll.h"

int main() {
  SetMaxThreads(1);
  struct deal dl;
  struct futureTricks fut;
  int trump, first, ntrick;
  while (scanf("%d %d %d", &trump, &first, &ntrick) == 3) {
    dl.trump = trump;
    dl.first = first;
    for (int i = 0; i < 3; i++) {
      dl.currentTrickSuit[i] = 0;
      dl.currentTrickRank[i] = 0;
    }
    for (int i = 0; i < ntrick; i++) {
      if (scanf("%d %d", &dl.currentTrickSuit[i], &dl.currentTrickRank[i]) != 2) {
        return 1;
      }
    }
    for (int h = 0; h < DDS_HANDS; h++) {
      for (int s = 0; s < DDS_SUITS; s++) {
        if (scanf("%u", &dl.remainCards[h][s]) != 1) {
          return 1;
        }
      }
    }
    const int res = SolveBoard(dl, /*target=*/-1, /*solutions=*/1,
                               /*mode=*/1, &fut, /*threadIndex=*/0);
    if (res != RETURN_NO_FAULT) {
      printf("ERR %d\n", res);
    } else {
      printf("%d\n", fut.score[0]);
    }
    fflush(stdout);
  }
  return 0;
}
