#include <stdio.h>
#include "b.h"

int weigh(B *b);

int main(void) {
    B b;
    b.a.next = 0;
    b.a.v = 7;
    printf("%d\n", weigh(&b));
    return 0;
}
