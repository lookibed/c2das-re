/* P9.16: a scalar local the function never writes is `let`; a written, stepped or addressed one,
   a pointer, a record and an array stay `var` */
#include <stdio.h>

enum color { RED, GREEN, BLUE };
struct pair { int a, b; };

static int twice(int v) { return 2 * v; }

static int scalars(int x, const char *s) {
    int fixed = twice(x) + 1;
    const int limit = 7;
    double half = x / 2.0;
    enum color c = x > 2 ? BLUE : GREEN;
    char first = s[0];
    _Bool big = x > limit;
    int sum = 0;
    for (int i = 0; i < x; i++) {
        int sq = i * i;
        sum += sq;
    }
    return fixed + limit + (int)half + (int)c + first + big + sum;
}

static int written(int x) {
    int stepped = x;
    stepped++;
    int stored = 1;
    stored = stored * 3 + x;
    int late;
    late = x - 1;
    int seen = 4;
    int *at = &seen;
    *at += x;
    int n = x;
    {
        int n = 5;
        stepped += n;
    }
    n += 2;
    return stepped + stored + late + seen + n;
}

static int aggregates(int x) {
    int arr[3] = { x, x + 1, x + 2 };
    struct pair p = { x, 2 * x };
    int *row = arr;
    return row[1] + p.b + arr[2];
}

int main(void) {
    printf("%d %d\n", scalars(3, "a"), scalars(9, "z"));
    printf("%d %d\n", written(3), written(-2));
    printf("%d\n", aggregates(4));
    return 0;
}
