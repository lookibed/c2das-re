/* A `for` whose body continues, never leaves the loop and puts a das label in its block or in a
   plain block under it, in every dispatch mode: a switch spelled open for a case label below its
   level (`below`), an unused C label at the body's level (`unused`) and in a block that keeps its
   braces (`unused_in_block`). The interpreter lands a label of a block with a `finally` section
   one statement early (lookibed/daScript#63), so each steps by the increment-first flag. A label
   in an `if` arm or in a nested loop of the body (`in_arm_and_loop`: an open switch in the arm,
   a dense one in the loop, flat under `table`) is not at the body's level: that `for` keeps its
   `finally` block and runs as native. main prints
   every result and the count of steps */
#include <stdio.h>

static int steps;

static int below(int n) {
    int r = 0;
    for (int i = 0; i < n; i++, steps++) {
        int k = i * 2;
        r += k;
        switch (i & 3) {
        case 0: r += 1;
            if (k > 4) {
        case 1: r += 10;
            }
            break;
        case 2: r += 100; break;
        }
        if (i == 5) continue;
        r += 1000;
    }
    return r;
}

static int unused(int n) {
    int r = 0;
    for (int i = 0; i < n; i++, steps++) {
        int k = i * 2;
        if (k == 4) continue;
        r += k;
    never:
        r += 1;
    }
    return r;
}

static int unused_in_block(int n) {
    int r = 0;
    for (int i = 0; i < n; i++, steps++) {
        int k = i * 2;
        if (k == 4) continue;
        {
            int q = k + 1;
            r += q;
        never:
            r += 1;
        }
    }
    return r;
}

static int in_arm_and_loop(int n) {
    int r = 0;
    for (int i = 0; i < n; i++, steps++) {
        int k = i * 2;
        if (i == 5) continue;
        if (k > 2) {
            int q = k + 1;
            switch (i & 3) {
            case 0: r += q;
                if (k > 8) {
            case 1: r += 10;
                }
                break;
            case 2: r += 100; break;
            }
        }
        for (int j = 0; j < 2; j++) {
            int m = j + k;
            switch (i) {
            case 1: r += m; break;
            case 2: r += 2;
            case 3: r += 3; break;
            case 4: case 5: r += 4; break;
            case 6: r += 6; break;
            case 7: r += 7;
            case 8: r += 8; break;
            default: r += 1; break;
            }
        }
        r += 1000;
    }
    return r;
}

int main(void) {
    for (int n = 0; n < 10; n++) {
        int a = below(n);
        int b = unused(n);
        int c = unused_in_block(n);
        int d = in_arm_and_loop(n);
        printf("%d %d %d %d %d %d\n", n, a, b, c, d, steps);
    }
    return 0;
}
