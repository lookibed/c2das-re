#include <stdio.h>

/* arrays declared without a length, referenced before the definitions that give them one */
extern int table[];
extern int grid[][2];
extern const char name[];

static int *first = table;
static int *third = &table[2];

static int *at(int k) { return &table[k]; }

static int sum(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {
        s += table[i];
    }
    return s;
}

static int corner(void) { return grid[1][1] + grid[0][1]; }

int table[] = {3, 5, 7, 11};
int grid[2][2] = {{1, 2}, {3, 4}};
const char name[] = "doom";

int main(void) {
    int *p = table;
    table[1] = 6;
    printf("%d %d %d %d\n", sum(4), (int) (at(4) - at(0)), *first + *third, p[1]);
    printf("%d %s %d\n", corner(), name, (int) sizeof(table));
    return sum(2);
}
