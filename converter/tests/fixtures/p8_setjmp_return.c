/* setjmp sites whose arms return: every shape returns from inside the `try` or `recover` arm
   the lowering builds, which das refuses (error 30299), so the arm is a block that answers
   whether it returned */
#include <setjmp.h>
#include <stdio.h>

struct pair {
    int a;
    int b;
};

static jmp_buf outer_buf;
static jmp_buf inner_buf;
static int trace;

static void jump(jmp_buf b, int v) {
    longjmp(b, v);
}

/* the idiom: the longjmp return leaves at once */
static int idiom(int fail) {
    if (setjmp(outer_buf)) return -1;
    if (fail) jump(outer_buf, 3);
    return 7;
}

/* a return inside the longjmp arm and another after it, a loop holding a return in the tail */
static int both_arms(int fail, int stop) {
    volatile int seen = 0;
    if (setjmp(outer_buf) != 0) {
        seen++;
        if (seen > 1) return 100 + seen;
    }
    for (int i = 0; i < 10; i++) {
        if (i == stop) return i;
        if (fail && i == 2 && seen < 2) jump(outer_buf, 1);
    }
    return 50 + seen;
}

/* the contained site, both branches returning */
static int contained(int fail) {
    if (setjmp(outer_buf) == 0) {
        if (fail) jump(outer_buf, 9);
        return 1;
    } else {
        return 2;
    }
}

/* nested sites: the inner one's return leaves the outer arm too */
static int nested(int depth) {
    if (setjmp(outer_buf)) return -10;
    trace = 0;
    if (setjmp(inner_buf)) {
        trace += 1;
        if (depth > 1) jump(outer_buf, 4);
        return -20 - trace;
    }
    if (depth > 0) jump(inner_buf, 2);
    return 30;
}

/* a void function returning early from both arms */
static void void_return(int fail, int *out) {
    if (setjmp(outer_buf)) {
        *out += 1000;
        return;
    }
    *out += 1;
    if (fail) jump(outer_buf, 1);
    if (*out > 5) return;
    *out += 10;
}

/* a record returned from the arms */
static struct pair pair_of(int fail) {
    struct pair p = { 1, 2 };
    if (setjmp(outer_buf)) {
        struct pair q = { 7, 8 };
        return q;
    }
    if (fail) jump(outer_buf, 1);
    p.b = 5;
    return p;
}

/* the general form: the setjmp read as a value and returned */
static int general(int fail) {
    int r = setjmp(outer_buf);
    if (r == 0 && fail) jump(outer_buf, fail);
    return r * 3;
}

/* the flat site: the first-run branch returns, the tail after the site calls nothing */
static int flat(int fail) {
    int n = 4;
    if (!setjmp(outer_buf)) {
        if (fail) return n * 2;
        n = 5;
    }
    n += 1;
    return n;
}

int main(void) {
    int out = 0, out2 = 0;
    struct pair a = pair_of(0), b = pair_of(1);
    printf("idiom %d %d\n", idiom(0), idiom(1));
    printf("both %d %d %d %d\n", both_arms(0, 4), both_arms(1, 99), both_arms(1, 1), both_arms(0, 99));
    printf("contained %d %d\n", contained(0), contained(1));
    printf("nested %d %d %d\n", nested(0), nested(1), nested(2));
    void_return(0, &out);
    void_return(1, &out2);
    printf("void %d %d\n", out, out2);
    printf("pair %d %d %d %d\n", a.a, a.b, b.a, b.b);
    printf("general %d %d\n", general(0), general(2));
    printf("flat %d %d\n", flat(0), flat(1));
    return idiom(1) + 2;
}
