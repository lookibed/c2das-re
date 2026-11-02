/* research 01: llex.c's `next(ls)` through lzio.h's `zgetc` chain, a byte fetch from a buffer
   struct with a refill call on exhaustion, as the lexer's save_and_next loops do */
typedef struct Zio { unsigned long n; const char *p; const char *base; unsigned long size; } ZIO;
typedef struct LexState { int current; ZIO *z; } LexState;
#define zgetc(z) (((z)->n--) > 0 ? (unsigned char) (*(z)->p++) : fill(z))
#define next(ls) (ls->current = zgetc(ls->z))
#define lisdigit(c) ((c) >= '0' && (c) <= '9')
static volatile int rounds = 3000;
static char text[256];
static ZIO zio;
static LexState lex;
static int result;
static int fill(ZIO *z) {
    if (z->p == 0) return -1;
    z->p = z->base;
    z->n = z->size - 1;
    return (unsigned char) *z->p++;
}
static long long scan(LexState *ls, int n) {
    long long acc = 0;
    for (int r = 0; r < n; r++) {
        for (int k = 0; k < 200; k++) {
            next(ls);
            if (lisdigit(ls->current)) acc += ls->current - '0';
            else acc += r & 1;
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 256; k++) text[k] = (char) ('0' + (k % 13));
    zio.base = text; zio.size = 256; zio.p = text; zio.n = 256;
    lex.z = &zio; lex.current = 0;
    result = (int) (scan(&lex, rounds) & 0x7fffffff);
}
static int kernel_result(void) { return result; }
