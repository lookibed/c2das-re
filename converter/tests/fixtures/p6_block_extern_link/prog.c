#include <stdio.h>

/* every name data.c defines is declared here only inside a block */
static int *slot(int k) {
    extern int table[];
    return &table[k];
}

int main(void) {
    extern int count;
    {
        int total(int);
        extern int table[];
        table[0] = 1;
        count += total(5);
        printf("%d %d %d\n", count, table[4], (int) (slot(4) - slot(0)));
    }
    return count;
}
