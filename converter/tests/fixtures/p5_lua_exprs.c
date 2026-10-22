/* The expression and statement shapes of lua 5.4.8 the P5.1 phase B conversion met, each with
   the lua line it stands for, compared against the native build. */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

typedef struct Table { int flags; int *slots; } Table;

typedef struct Cell { int *p; int tag; } Cell;

/* ltm.h:64 gfasttm: a NULL arm, first or second, of a conditional typed by its other arm */
static int *fast_slot(Table *et, int e) {
    return (et == NULL) ? NULL : ((et->flags & (1u << e)) ? NULL : et->slots + e);
}

static int *slow_slot(Table *et, int e) {
    return (et->flags & (1u << e)) ? et->slots + e : NULL;
}

/* the other positions a null takes its pointer type from: a return, a field, an initializer,
   an argument */
static int *none(void) { return NULL; }

static int count_null(int *a, int *b) { return (a == NULL) + (b == NULL); }

/* lvm.c:853 luaV_concat's `top - 1 - (base + a)`: a difference whose subtrahend is a sum */
static void differences(void) {
    int a[8];
    int *top = a + 6, *base = a + 1;
    long k = 2;
    unsigned u = 1;
    short h = 3;
    printf("diff %d %d %d %d\n", (int)(top - 1 - (base + k)), (int)(top - (base - k + 2)),
           (int)((top + 1) - (base + u)), (int)(top - (a + h)));
    printf("scaled %d %d %d\n", (int)((top - 1) - (base + 1)) / 2, top - (base + k) < 3,
           (int)((char *) top - ((char *) base + 4)));
}

/* lutf8lib.c:287 UTF8PATT: a literal with an interior NUL, by pointer and in an array */
#define PATT "[\0-\x7F\xC2-\xFD][\x80-\xBF]*"

static void interior_nul(void) {
    const char *p = PATT;
    char row[6] = "a\0b\0c";
    printf("patt %d %d %d %d\n", (int) (sizeof(PATT) / sizeof(char) - 1), p[1], p[2], p[3]);
    printf("row %d %d %d %d %d\n", row[0], row[1], row[2], row[4], row[5]);
    printf("memcmp %d\n", memcmp(p, "[\0-", 3));
}

/* lstrlib.c:598 match: `goto dflt` into the default group, from a case and from a nested
   switch's default, and `goto init` back to a label before the switch */
static int match(const char *p, int n) {
    int r = 0;
  init:
    if (*p) {
        switch (*p) {
        case '(': { r += 1; break; }
        case '$': {
            if (p[1] != 0) goto dflt;
            r += 100;
            break;
        }
        case '%': {
            switch (p[1]) {
            case 'b': { p += 2; goto init; }
            default: goto dflt;
            }
            break;
        }
        default: dflt: {
            r += 10;
            if (n-- > 0) { p++; goto init; }
            break;
        }
        }
    }
    return r;
}

/* lvm.c:1689 luaV_execute: a dispatch on an enum whose cases jump into another case's block
   (`l_tforcall`, `l_tforloop`) and into the middle of one (`ret`), and out to labels before the
   loop (`startfunc`, `returning`) */
typedef enum { OP_MOVE, OP_TFORPREP, OP_TFORCALL, OP_TFORLOOP, OP_RETURN, OP_RETURN1, OP_STOP } OpCode;

static int execute(const int *code, int fresh) {
    int pc = 0, acc = 0, depth = 0;
  startfunc:
    depth++;
  returning:
    acc += 1000;
    for (;;) {
        OpCode op = (OpCode) code[pc++];
        switch (op) {
        case OP_MOVE: { acc += 1; break; }
        case OP_TFORPREP: { acc += 10; goto l_tforcall; }
        case OP_TFORCALL: {
          l_tforcall: {
            int ra = acc % 7;
            acc += 100 + ra;
            goto l_tforloop;
          }
        }
        case OP_TFORLOOP: {
          l_tforloop: {
            acc += 1000;
            break;
          }
        }
        case OP_RETURN: { acc += 5; goto ret; }
        case OP_RETURN1: {
            if (acc > 100000) acc -= 3; else acc += 3;
          ret:
            if (depth >= fresh) return acc;
            else { depth++; goto returning; }
        }
        case OP_STOP: if (depth > 9) goto startfunc; return -acc;
        }
    }
}

/* two switches that re-dispatch, one inside a case of the other: each restarts its own */
static int nested_dispatch(int a, int b) {
    int r = 0;
    switch (a) {
    case 1:
        switch (b) {
        case 1: r += 1; goto inner_tail;
        case 2: inner_tail: r += 10; break;
        }
        goto outer_tail;
    case 2:
      outer_tail:
        r += 100;
        break;
    }
    return r;
}

/* lobject.c:520 luaO_pushvfstring's `%p`, read back as `va_arg(argp, void *)`: a void pointer among
   the trailing arguments */
static int count_set(int n, ...) {
    va_list ap;
    int set = 0;
    va_start(ap, n);
    while (n-- > 0)
        set += va_arg(ap, void *) != NULL;
    va_end(ap);
    return set;
}

int main(void) {
    int code[] = { OP_MOVE, OP_TFORPREP, OP_MOVE, OP_TFORCALL, OP_TFORLOOP, OP_RETURN, OP_RETURN1, OP_STOP };
    int slots[4] = { 10, 20, 30, 40 };
    Table t = { 2, slots };
    Cell c = { NULL, 1 };
    int *q = NULL;
    printf("fast %d %d %d\n", fast_slot(NULL, 1) == NULL, fast_slot(&t, 1) == NULL, *fast_slot(&t, 2));
    printf("slow %d %d\n", *slow_slot(&t, 1), slow_slot(&t, 2) == NULL);
    c.p = NULL;
    printf("nulls %d %d %d\n", none() == NULL, count_null(c.p, NULL), q == NULL);
    differences();
    interior_nul();
    printf("match %d %d %d %d\n", match("($a", 5), match("%bx%q", 5), match("$", 1), match("$$x", 0));
    printf("execute %d %d %d\n", execute(code, 1), execute(code, 2), execute(code + 6, 1));
    printf("nested %d %d %d\n", nested_dispatch(1, 1), nested_dispatch(1, 2), nested_dispatch(2, 0));
    printf("set %d\n", count_set(3, (void *) slots, (void *) NULL, (void *) &t));
    return 0;
}
