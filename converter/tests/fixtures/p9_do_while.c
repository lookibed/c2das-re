/* P9.11: a `do { body } while (c)` whose test hoists nothing is `do_while (c) { body }`,
   c_runtime's shape macro; a `continue`, a `break`, a `return` and a `goto` in the body keep C's
   meaning, and a test that hoists statements keeps the spelled loop */
#include <stdio.h>

static int calls = 0;

static int next(int *p) {
    calls++;
    return ++*p;
}

/* the bottom test, a `break` and a `return` in the body */
static int sum_to(int n, int stop, int bail) {
    int i = 0, acc = 0;
    do {
        i++;
        if (i == stop)
            break;
        if (i == bail)
            return -1;
        acc += i;
    } while (i < n);
    return acc;
}

/* a `continue` of the loop reaches the test; an inner do's `continue` reaches its own */
static int skip_even(int n) {
    int i = 0, acc = 0;
    do {
        i++;
        if ((i & 1) == 0)
            continue;
        int j = 0;
        do {
            j++;
            if (j == 1)
                continue;
            acc += 100;
        } while (j < 2);
        acc += i;
    } while (i < n);
    return acc;
}

/* a switch in the body: its `break` leaves the switch, its `continue` reaches the do's test */
static int dispatch(int n) {
    int i = 0, acc = 0;
    do {
        i++;
        switch (i % 4) {
        case 0:
            continue;
        case 1:
            acc += 10;
            break;
        case 2:
            acc += 20;
        default:
            acc += 1;
            break;
        }
        acc += 1000;
    } while (i < n);
    return acc;
}

/* a pointer and a char test, as C's string loops write them */
static int count_to_nl(const char *s) {
    int c, n = 0;
    do {
        c = *s++;
        n++;
    } while (c != '\n' && c != 0);
    return n;
}

/* a call in the test is an expression: the macro holds it; a step in the test hoists statements,
   so the spelled loop stays, with and without `continue` */
static int effects(int n) {
    int k = 0, passes = 0;
    do {
        passes++;
    } while (next(&k) < n);
    int j = 0;
    do {
        passes += 2;
    } while (j++ < n);
    int m = 0, q = 2 * n;
    do {
        m += 2;
        if (m == 4)
            continue;
        passes += 10;
    } while (--q > 0);
    return passes * 1000 + k * 100 + j * 10 + q;
}

/* a body that always leaves takes no test; `while (0)` with a `break` stays a one-pass loop */
static int leaves(int n) {
    int r = 0;
    do {
        r = n * 2;
        break;
    } while (n > 0);
    do {
        if (n > 3)
            break;
        r += 7;
    } while (0);
    return r;
}

/* a goto out of the body */
static int jumps(int n) {
    int i = 0, acc = 0;
    do {
        i++;
        if (i == 3)
            goto out;
        acc += i;
    } while (i < n);
    return acc;
out:
    return -acc;
}

int main(void) {
    printf("%d %d %d %d\n", sum_to(3, 100, 100), sum_to(0, 100, 100), sum_to(10, 7, 100), sum_to(10, 100, 5));
    printf("%d %d\n", skip_even(5), skip_even(0));
    printf("%d %d\n", dispatch(9), dispatch(0));
    printf("%d %d\n", count_to_nl("abc\ndef"), count_to_nl(""));
    printf("%d %d\n", effects(3), effects(0));
    printf("%d\n", calls);
    printf("%d %d\n", leaves(2), leaves(5));
    printf("%d %d\n", jumps(2), jumps(5));
    return 0;
}
