/* P5.1's review shapes: a goto into another case whose switch condition can hold any value, a
   label reached from its own case too, nested and lvm-shaped re-dispatch, a parameter or local
   named like a standard stream, a stdout buffer from the program, signal's SIG_ERR, SIG_IGN on
   the host, labels before a statement the optimizer folds, libc records by value and under
   sizeof, errno after a libm call whose result is dropped, two offsetofs in one expansion */
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wchar.h>

/* the condition takes every value, the one past the largest case too */
static int past_case(int x) {
    int r = 0;
    switch (x) {
    case 1:
        r += 1;
        goto L;
    case 2:
        r += 2;
    L:
        r += 10;
        break;
    default:
        r += 100;
    }
    return r;
}

/* a label under a case and one under `default`, each the target of a goto from case 1 */
static int under_case(int c, int n) {
    int r = 0;
    switch (c) {
    case 1:
        if (n)
            goto mid;
        r += 1;
        break;
    case 5:
        r += 10;
    mid:
        r += 100;
        break;
    }
    return r;
}

static int under_default(int c, int n) {
    int r = 0;
    switch (c) {
    case 1:
        if (n)
            goto mid;
        r += 1;
        break;
    default:
        r += 10;
    mid:
        r += 100;
        break;
    }
    return r;
}

/* nested switches, each re-dispatched, with gotos from the inner one to both */
static int nested(int a, int b, int n) {
    int r = 0;
top:
    r += 1;
    if (r > 40)
        return -r;
    switch (a) {
    case 1:
        switch (b) {
        case 1:
            if (n & 1)
                goto ib;
            if (n & 2)
                goto oa;
            r += 2;
            break;
        case 2:
            r += 3;
        ib:
            r += 4;
            if (n & 4) {
                n = 0;
                goto top;
            }
            break;
        default:
            goto od;
        }
        r += 5;
        break;
    case 2:
        r += 6;
    oa:
        r += 7;
        break;
    default:
        r += 8;
    od:
        r += 9;
        break;
    }
    return r;
}

/* luaV_execute's shape over an enum: gotos out of the loop and into other cases */
enum op { OP_CALL, OP_RET, OP_RETURN, OP_TFORPREP, OP_TFORCALL, OP_TFORLOOP, OP_SIX, OP_SEVEN };
static enum op code[] = {OP_TFORPREP, OP_TFORCALL, OP_TFORLOOP, OP_RET, OP_CALL, OP_RETURN, OP_SIX, OP_SEVEN};
static int execute(int pc0, int depth) {
    int r = 0, pc = pc0, calls = 0;
    int stack[8];
    int sp = 0;
startfunc:
    r += 1000;
returning:
    r += 1;
    for (;;) {
        enum op o = code[pc++ & 7];
        switch (o) {
        case OP_CALL:
            r += 10;
            if (depth > 0 && calls < 2) {
                calls++;
                stack[sp++] = pc;
                pc = 5;
                goto startfunc;
            }
            break;
        case OP_RET:
            r += 20;
            goto ret;
        case OP_RETURN: {
            r += 30;
        ret:
            if (sp == 0)
                return r;
            pc = stack[--sp];
            goto returning;
        }
        case OP_TFORPREP:
            r += 40;
            goto l_tforcall;
        case OP_TFORCALL: {
        l_tforcall: {
            r += 50;
            goto l_tforloop;
        }
        }
        case OP_TFORLOOP: {
        l_tforloop: {
            r += 60;
            break;
        }
        }
        default:
            r += 70;
            if (r > 100000)
                return r;
        }
    }
}

/* one label reached by a goto from another case and by a goto from its own case */
static int shared_label(int c, int n) {
    int r = 0;
    switch (c) {
    case 1:
        if (n > 5)
            goto loop;
        r += 1;
        break;
    case 2:
    loop:
        r += 10;
        if (n-- > 0)
            goto loop;
        break;
    }
    return r;
}

/* a parameter and a local named like the standard streams are the program's own */
static int stream_named(const char *stdin) {
    int n = 0;
    while (stdin[n])
        n++;
    return n;
}

/* a label before a statement the optimizer folds away, in a branch that is no loop's body */
#define DEBUG 0
static int folded_if(int x) {
    int r = 1;
    if (x > 0) {
        if (x > 5)
            goto L;
        r = 2;
    L:
        if (DEBUG) {
            r = 3;
        }
    }
    return r;
}

static int empty_then(int x) {
    int r = 1;
    if (x > 0) {
        if (x > 5)
            goto L;
        r = 2;
    L:
        if (x > 100) {
        }
    }
    return r;
}

static int false_while(int x) {
    int r = 1;
    if (x > 0) {
        if (x > 5)
            goto L;
        r = 2;
    L:
        while (0) {
            r = 3;
        }
    }
    return r;
}

/* a program record holding a libc record by value, and one reached only under sizeof */
struct stamped {
    int k;
    struct tm t;
};

/* lobject.h's udatamemoffset: two offsetofs of different records in one expansion */
struct udata0 {
    int k;
    double bindata;
};
struct udata {
    int k;
    char x;
    int uv[4];
};
#define udatamemoffset(nuv) ((nuv) == 0 ? offsetof(struct udata0, bindata) : offsetof(struct udata, uv) + (sizeof(int) * (nuv)))

/* a function whose only crt use is errno */
static int errno_now(void) {
    return errno;
}

/* a label after a declaration the switch carries, which a goto from another case reaches */
static int carried_label(int c) {
    int r = 0;
    switch (c) {
    case 0:
        goto L;
    case 1:;
        int k = 2;
        r += k;
    L:
        k = 7;
        r += k;
        break;
    case 2:
        k = 3;
        r += k * 100;
        break;
    }
    return r;
}

/* <math.h> beyond das math, each through the crt */
static void exotica(double x) {
    double ip = 0.0;
    double frac = modf(x + 0.25, &ip);
    printf("%.17g %.17g %.17g %.17g %.17g %.17g\n", frac, ip, nextafter(x, 2.0 * x), hypot(x, 4.0), cbrt(x * 9.0), expm1(x / 7.0));
    printf("%.17g %.17g %.17g %.17g %.17g\n", log1p(x / 3.0), copysign(x, -1.0), remainder(x * 7.0, 2.0), trunc(-x * 2.7), round(x * 2.5));
    printf("%.17g %.17g %.17g %.17g %.17g\n", erf(x / 5.0), erfc(x / 5.0), tgamma(x + 2.0), lgamma(x + 7.5), fma(x, 3.0, 1.0));
}

static void handler(int s) {
    (void)s;
}

static char out_buf[4096];

int main(int argc, char **argv) {
    (void)argv;
    setvbuf(stdout, out_buf, _IOFBF, sizeof out_buf);
    printf("%d %d %d %d\n", past_case(1), past_case(2), past_case(3), past_case(4));
    printf("%d %d %d | %d %d %d\n", under_case(6, 0), under_case(1, 1), under_case(5, 0), under_default(2, 0), under_default(1, 1), under_default(9, 0));
    for (int n = 0; n < 8; n++)
        printf("%d ", nested(1, 1, n));
    printf("| %d %d %d %d\n", nested(1, 2, 4), nested(1, 3, 0), nested(2, 0, 0), nested(3, 0, 0));
    printf("%d %d %d\n", execute(0, 1), execute(3, 0), execute(6, 1));
    printf("%d %d %d\n", shared_label(1, 7), shared_label(2, 2), shared_label(1, 0));
    const char *stderr = "hello";
    printf("%d %c\n", stream_named(stderr), stderr[1]);
    printf("%d %d %d %d %d %d\n", folded_if(7), folded_if(1), empty_then(7), empty_then(1), false_while(7), false_while(1));
    /* signal: SIG_ERR with EINVAL for a number glibc refuses, SIG_IGN applied to the process */
    errno = 0;
    printf("kill=%d stop=%d zero=%d 32=%d 33=%d 65=%d errno=%d\n", signal(SIGKILL, handler) == SIG_ERR, signal(SIGSTOP, handler) == SIG_ERR, signal(0, handler) == SIG_ERR, signal(32, handler) == SIG_ERR, signal(33, handler) == SIG_ERR, signal(65, handler) == SIG_ERR, errno);
    printf("segv dfl=%d\n", signal(SIGSEGV, handler) == SIG_DFL);
    signal(SIGPIPE, SIG_IGN);
    system("kill -PIPE $PPID");
    printf("alive after SIGPIPE\n");
    /* libc records */
    struct stamped s;
    s.k = 2;
    time_t z = 0;
    struct tm *g = gmtime(&z);
    char raw[sizeof(struct tm)];
    memcpy(raw, g, sizeof *g);
    struct tm *after = g + 1;
    mbstate_t st;
    memset(&st, 0, sizeof st);
    div_t dv;
    dv.quot = 3;
    dv.rem = 1;
    printf("%d %d %d %d %d %d %d\n", s.k, (int)sizeof s, (int)sizeof *g, (int)((char *)after - (char *)g), (int)sizeof st, dv.quot, dv.rem);
    /* errno after a libm call whose result is dropped */
    double one = argc, zero = argc - 1;
    double d;
    errno = 0;
    d = fmod(one, zero);
    printf("fmod errno=%d\n", errno);
    errno = 0;
    d = ldexp(one, 5000);
    printf("ldexp errno=%d\n", errno);
    (void)d;
    printf("%d %d\n", (int)udatamemoffset(argc - 1), (int)udatamemoffset(argc));
    errno = 0;
    strtol("99999999999999999999", 0, 10);
    printf("errno %d\n", errno_now() == ERANGE);
    printf("%d %d %d\n", carried_label(0), carried_label(1), carried_label(2));
    exotica(argc);
    return 0;
}
