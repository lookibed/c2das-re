/* P9.12: C switch as c_runtime's `switch` shape macro */
#include <stdio.h>

enum color { RED, GREEN = 2, BLUE };
struct shape { int kind; int size; };

static int calls;
static int next(int *k) { calls++; return (*k)++; }

/* the value is read once: a call, a field through a pointer */
static int read_once(int *k, const struct shape *s) {
    int r = 0;
    switch (next(k)) {
    case 0: r = 1;
    case 1: r += 10; break;
    default: r = -1;
    }
    switch (s->kind) {
    case 3: r += 300; break;
    case 4: r += 400; break;
    }
    return r;
}

/* every arm returns and one is the default: no trailing return */
static const char *tone(enum color c) {
    switch (c) {
    case RED: return "warm";
    case GREEN: case BLUE: return "cool";
    default: return "none";
    }
}

/* an arm ending in an if whose arms return falls into the next for the macro (lobject.c's
   luaO_rawarith): the flag loop, after which the function keeps its zero return */
static int arm_if(int op, int a) {
    switch (op) {
    case 1: {
        int x = a;
        if (x) return 1;
        else return 0;
    }
    case 2: return 5;
    default: return 7;
    }
}

/* an enum value with no enumerator keeps the spelled lowering */
static int odd_enum(enum color c) {
    switch (c) {
    case RED: return 1;
    case (enum color)1: return 7;
    default: return 0;
    }
}

/* nested switches in a loop: the inner one's continue reaches the loop through the outer one */
static int nested(int n) {
    int acc = 0, i;
    for (i = 0; i < n; i++) {
        switch (i & 1) {
        case 0:
            switch (i % 3) {
            case 0: continue;
            case 1: acc += 10; break;
            default: acc += 20;
            case 5: acc += 1;
            }
            acc += 100;
        default:
            acc += 1000;
        }
        acc += 10000;
    }
    return acc;
}

/* a switch in a do with a continue, a loop's break inside an arm */
static int in_do(int n) {
    int i = 0, acc = 0, k;
    do {
        i++;
        switch (i) {
        case 2: continue;
        case 4:
            for (k = 0; k < 10; k++) {
                if (k == 3) break;
                acc += 100;
            }
        case 7: return acc + i;
        default: acc += i;
        }
        acc += 1000;
    } while (i < n);
    return acc;
}

/* `_`, the macro's default, as a C name */
static int names(int fallthrough, int _) {
    switch (fallthrough) {
    case 'a': fallthrough = _; break;
    case 'b': _ = fallthrough;
    default: fallthrough += _;
    }
    return fallthrough;
}

int main(void) {
    int k = 0;
    struct shape s = { 3, 1 };
    int a = read_once(&k, &s);
    int b = read_once(&k, &s);
    s.kind = 4;
    int c = read_once(&k, &s);
    printf("%d %d %d %d %d\n", a, b, c, k, calls);
    printf("%s %s %s %s\n", tone(RED), tone(GREEN), tone(BLUE), tone((enum color)9));
    printf("%d %d %d\n", odd_enum(RED), odd_enum((enum color)1), odd_enum(BLUE));
    printf("%d %d %d %d\n", arm_if(1, 3), arm_if(1, 0), arm_if(2, 0), arm_if(9, 0));
    printf("%d %d %d %d\n", nested(7), in_do(3), in_do(5), in_do(9));
    printf("%d %d %d\n", names('a', 5), names('b', 5), names('z', 5));
    return 0;
}
