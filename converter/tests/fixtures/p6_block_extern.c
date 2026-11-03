#include <stdio.h>

/* block-scope `extern` declarations and prototypes of names no file-scope declaration names first */
static int bump(void) {
    extern int counter;
    return ++counter;
}

static int peek(void) {
    {
        extern int counter;
        return counter;
    }
}

/* a local and a parameter of the function hide nothing: the inner `extern` reaches the global */
static int hidden(int limit) {
    int counter = 100;
    {
        extern int counter;
        extern int limit;
        counter += limit;
    }
    return counter + limit;
}

/* an array of unknown length takes the later definition's */
static int last(void) {
    extern int squares[];
    return squares[3] + (int) (&squares[3] - &squares[0]);
}

/* a prototype hides a local too, and leaves the function being dumped alone */
static int twice(int k) {
    int scale = 2;
    {
        int scale(int);
        static int calls = 0;
        calls++;
        return scale(k) * calls + scale(1);
    }
}

/* a hoisted static skips the name a later block-scope `extern` gives a global */
static int tally(void) {
    static int n = 5;
    return ++n;
}

static int tally_total(void) {
    extern int tally_n;
    return tally() + tally_n;
}

int counter = 40;
int tally_n = 7;
int limit = 2;
int squares[] = {0, 1, 4, 9};

int scale(int k) { return 10 * k; }

int main(void) {
    bump();
    printf("%d %d %d %d\n", bump(), peek(), hidden(7), last());
    printf("%d %d %d\n", twice(3), counter, tally_total());
    {
        /* declared by <stdio.h> outside the program */
        extern FILE *stdout;
        fprintf(stdout, "%d\n", twice(1));
    }
    return peek() - 44;
}
