/* P7.0zc: a case whose body does nothing joins the next case's labels (an NDEBUG assert, a `;`, a
   discarded read, an empty block, a run of them); a default among the two groups, a C label, a
   declaration, a volatile read, a `break`, a step, a call and a comma keep their forms (a case label in
   a nested block spells the switch open before any grouping) */
#define NDEBUG
#include <assert.h>
int printf(const char *, ...);
enum State { NORMAL, STOP, IME, HALT };
static int asserted(enum State s) {
    int r = 0;
    switch (s) {
    case NORMAL:
        assert(0);
    case STOP:
        r = 1;
        break;
    case IME:
        r = 2;
        break;
    case HALT:
        return 3;
    }
    return r;
}
static int run_of_inert(int x) {
    int r = 0;
    switch (x) {
    case 1:
        ;
    case 2:
        (void)x;
    case 3: {
        ;
    }
    case 4:
        r = 4;
        break;
    case 5:
        r = 5;
        break;
    }
    return r;
}
static int inert_before_default(int x) {
    int r = 0;
    switch (x) {
    case 1:
        (void)0;
    default:
        r = 9;
        break;
    case 2:
        r = 2;
        break;
    }
    return r;
}
static int default_inert(int x) {
    int r = 0;
    switch (x) {
    default:
        ;
    case 2:
        r = 2;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int labelled(int x) {
    int r = 0;
    switch (x) {
    case 1:
    here:
        ;
    case 2:
        r += 2;
        if (r < 6) goto here;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int declared(int x) {
    int r = 0;
    switch (x) {
    case 1: {
        int k;
        (void)k;
    }
    case 2:
        r = 2;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static volatile int port;
static int volatile_read(int x) {
    int r = 0;
    switch (x) {
    case 1:
        (void)port;
    case 2:
        r = 2;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int nested_label(int x) {
    int r = 0;
    switch (x) {
    case 1: {
        (void)0;
    case 2:
        r = 2;
    }
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int break_only(int x) {
    int r = 0;
    switch (x) {
    case 1:
        break;
    case 2:
        r += 10;
        break;
    }
    return r;
}
static int bumps;
static int bump(void) {
    return ++bumps;
}
static int stepped(int x) {
    int r = 0, n = 0;
    switch (x) {
    case 1:
        n++;
    case 2:
        r = 2 + n;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int called(int x) {
    int r = 0;
    switch (x) {
    case 1:
        (void)bump();
    case 2:
        r = 2 + bumps;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int comma(int x) {
    int r = 0, n = 4;
    switch (x) {
    case 1:
        (void)(n, 0);
    case 2:
        r = 2 + n;
        break;
    case 3:
        r = 3;
        break;
    }
    return r;
}
static int last_join(int x) {
    int r = 0;
    switch (x) {
    case 1:
        r = 1;
        break;
    case 2:
        (void)0;
    case 3:
        r = 3;
    }
    return r;
}
int main(void) {
    int i;
    for (i = 0; i < 5; i++) {
        printf("%d %d %d %d %d %d %d %d\n", asserted((enum State)i), run_of_inert(i + 1), inert_before_default(i), default_inert(i + 1), labelled(i), declared(i), volatile_read(i), nested_label(i));
        printf("%d %d %d %d %d\n", break_only(i), stepped(i), called(i), comma(i), last_join(i));
    }
    return 0;
}
