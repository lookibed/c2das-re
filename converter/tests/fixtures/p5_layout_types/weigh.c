#include "b.h"

int weigh(B *b) {
    return b->a.v * 6 + (b->a.next == 0);
}
