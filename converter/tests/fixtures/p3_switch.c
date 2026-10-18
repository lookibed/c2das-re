int printf(const char *, ...);
typedef enum { MT_PLAYER, MT_SHOTGUN = 5, NUMMOBJTYPES } mobjtype_t;
static int tier1(int x) {
    int r = 0;
    switch (x) {
    case 1: r = 10; break;
    case 2:
    case 3: r = 20; break;
    case -4: { int k = x * 2; r = k; break; }
    default: r = -1; break;
    }
    return r;
}
static int tail_default_first(unsigned u) {
    switch (u) {
    default: return 99;
    case 1u: return 1;
    case 7u: return 7;
    }
}
static const char *name(mobjtype_t t) {
    switch (t) {
    case MT_PLAYER: return "player";
    case MT_SHOTGUN: return "shotgun";
    default: return "other";
    }
}
static int fallthrough(int x, int *trace) {
    int n = 0;
    switch (x) {
    case 1: trace[n++] = 1; break;
    case 5: trace[n++] = 5;
    case 9: trace[n++] = 9; break;
    default: trace[n++] = 0;
    }
    return n;
}
static int mid_break(int x, int y) {
    int r = 0;
    switch (x) {
    case 1:
        r += 1;
        if (y) break;
        r += 10;
        break;
    case 2:
        r += 100;
    }
    return r;
}
static int continue_in_switch(void) {
    int seen = 0, i;
    for (i = 0; i < 6; i++) {
        switch (i % 3) {
        case 1: continue;
        case 2: seen += 100;
        default: seen += 1;
        }
        seen += 1000;
    }
    return seen;
}
static int nested(int a, int b) {
    int r = 0;
    switch (a) {
    case 1:
        switch (b) {
        case 1: r = 11; break;
        default: r = 19;
        }
        break;
    case 2:
        while (b > 0) {
            if (b == 2) break;
            b--;
        }
        r = 20 + b;
        break;
    default:
        r = 'x';
    }
    return r;
}
static long wide(long v) {
    switch (v) {
    case 1L << 33: return 1;
    case 'a': return 2;
    case 3 + 4: return 3;
    }
    return 0;
}
int main(void) {
    int trace[4] = { 0, 0, 0, 0 };
    int i, n;
    printf("%d %d %d %d %d\n", tier1(1), tier1(3), tier1(-4), tier1(8), tier1(2));
    printf("%d %d %d %s %s %s\n", tail_default_first(1), tail_default_first(7), tail_default_first(3), name(MT_PLAYER), name(MT_SHOTGUN), name(NUMMOBJTYPES));
    n = fallthrough(5, trace);
    printf("%d %d %d | %d %d %d %d\n", n, trace[0], trace[1], fallthrough(1, trace), fallthrough(9, trace), fallthrough(2, trace), trace[0]);
    printf("%d %d %d %d\n", mid_break(1, 1), mid_break(1, 0), mid_break(2, 0), mid_break(3, 0));
    printf("%d %d %d %d %d\n", continue_in_switch(), nested(1, 1), nested(1, 2), nested(2, 5), nested(3, 0));
    printf("%d %d %d %d\n", (int) wide(1L << 33), (int) wide(97), (int) wide(7), (int) wide(8));
    for (i = 0; i < 3; i++) {
        switch (i) {
        case 0: printf("zero ");
        case 1: printf("one "); break;
        case 2: printf("two\n");
        }
    }
    return tier1(1) + mid_break(1, 0);
}
