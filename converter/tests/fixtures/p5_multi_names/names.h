#ifndef NAMES_H
#define NAMES_H

enum shade { RED, GREEN, BLUE = 5 };

int foo(void);
double average(int n, ...);

/* `counter` is an external in one unit and a static in the other, so each unit keeps its copy */
static int get(void) {
    return counter;
}

/* `foo` likewise */
static inline int wrap(void) {
    return foo() * 10;
}

#endif
