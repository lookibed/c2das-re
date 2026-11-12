/* P9.24: a counting `for` whose bound reads a global or a member stays a range loop over a body with
   calls when the program-wide summaries prove no callee stores to the bound, and a `<=` loop when
   every callee returns; each case beside the one that must keep the while form */
int printf(const char *, ...);
void exit(int);
void *memset(void *, int, unsigned long);
void *memcpy(void *, const void *, unsigned long);
char *strcpy(char *, const char *);
unsigned long strlen(const char *);
char *getenv(const char *);

int lim_a = 4, lim_b = 4, lim_fp = 4, lim_ro = 4, lim_rec = 4, lim_norec = 4, lim_out = 4, lim_env = 4, lim_libc = 3;
int other = 0, calls = 0;
int *out_target = &lim_out;                                          /* lim_out is pointed at */
unsigned long *saved_len;
union cell { char s[8]; int n; } gx = { .s = {5} };
struct rec { int n; char name[8]; };
struct box { int n; float f[8]; };

/* two levels down, a store to the bound; the other chain stores to another global */
void deep_a(void) { lim_a--; }
void mid_a(void) { deep_a(); calls++; }
void deep_b(void) { other++; }
void mid_b(void) { deep_b(); calls++; }

int two_levels(void) {
    int t = 0;
    for (int i = 0; i < lim_a; i++) { t += i; mid_a(); }               /* while: deep_a stores lim_a */
    for (int i = 0; i < lim_b; i++) { t += i; mid_b(); }               /* range */
    return t;
}

/* through a pointer: every function whose address the program takes */
void cut_fp(void) { lim_fp--; }
void count_fp(void) { calls++; }
void (*hook)(void) = count_fp;

int pointers(void (*f)(void)) {
    int t = 0;
    for (int i = 0; i < lim_fp; i++) { t += i; f(); }                 /* while: cut_fp stores lim_fp */
    for (int i = 0; i < lim_ro; i++) { t += i; f(); hook(); }         /* range */
    return t;
}

/* an out-parameter: a store through a pointer reaches a global a pointer reaches */
void set_out(int *out) { *out = 1; }

int out_params(void) {
    int t = 0, local = 0;
    for (int i = 0; i < lim_out; i++) { t += i; set_out(out_target); } /* while: lim_out is pointed at */
    for (int i = 0; i < lim_b; i++) { set_out(&local); t += local; }   /* range: no pointer reaches lim_b */
    return t;
}

/* libc functions storing into the bound's object, and ones that cannot reach it */
int libc_calls(struct rec *r, const struct rec *from, int *buf) {
    int t = 0;
    for (int i = 0; i < gx.n; i++) { t += i; strcpy(gx.s, "\2"); }    /* while: strcpy into the bound */
    for (int i = 0; i < r->n; i++) { t += i; memset(r, 0, sizeof *r); }        /* while: memset */
    r->n = 5;
    for (int i = 0; i < r->n; i++) { t += i; memcpy(r, from, sizeof *r); }     /* while: memcpy */
    for (int i = 0; i < lim_libc; i++) {                                         /* range */
        char tmp[8];
        strcpy(tmp, "ab");
        t += (int) strlen(tmp);
        memset(buf, 0, 4);
    }
    for (int i = 0; i < lim_env; i++) { t += i; if (getenv("C2DAS_P9_NONE")) t = 0; }  /* while: getenv is in no table */
    return t;
}

/* a recursive cycle */
int ping(int n);
int pong(int n) { if (n > 0) return ping(n - 1); lim_rec--; return 0; }
int ping(int n) { return n > 0 ? pong(n - 1) : 0; }
int ping2(int n);
int pong2(int n) { if (n > 0) return ping2(n - 1); calls++; return 0; }
int ping2(int n) { return n > 0 ? pong2(n - 1) : 0; }

int cycles(void) {
    int t = 0;
    for (int i = 0; i < lim_rec; i++) { t += i; ping(3); }             /* while: pong stores lim_rec */
    for (int i = 0; i < lim_norec; i++) { t += i; ping2(3); }          /* range */
    return t;
}

/* a callee that only reads the bound */
int peek(void) { return lim_ro + calls; }

int reads(void) {
    int t = 0;
    for (int i = 0; i < lim_ro; i++) t += peek();                      /* range */
    return t;
}

/* str_reverse: the length's address goes only to parameters that store through it and keep nothing */
const char *tolstr(int idx, unsigned long *len) {
    if (len != 0) *len = 3 + (unsigned long) idx;
    return "abcdef";
}

const char *checklstr(int arg, unsigned long *len) {
    const char *s = tolstr(arg, len);
    if (!s) exit(1);
    return s;
}

int reverse(char *p) {
    unsigned long l, i;
    const char *s = checklstr(1, &l);
    for (i = 0; i < l; i++) p[i] = s[l - i - 1];                       /* range */
    p[l] = 0;
    return (int) l;
}

/* a callee keeps the length's address in a global, through which the body stores */
const char *keep_len(unsigned long *len) {
    saved_len = len;
    *len = 4;
    return "wxyz";
}

int reverse_kept(char *p) {
    unsigned long l, i;
    const char *s = keep_len(&l);
    for (i = 0; i < l; i++) { p[i] = s[l - i - 1]; if (i == 1) *saved_len = 2; }  /* while */
    p[i] = 0;
    return (int) l;
}

/* a float store through a callee: apart from an int member bound only under strict aliasing */
void put_f(float *f) { *f = 0.5f; }

int aliasing(struct box *b) {
    int t = 0;
    for (int i = 0; i < b->n; i++) { t += i; put_f(&b->f[i]); }       /* while; range under strict aliasing */
    return t;
}

/* `<=` with calls: a callee that returns, one that may exit two levels down */
int twice(int v) { calls++; return v * 2; }
void quit2(int t) { printf("quit %d\n", t); exit(0); }
void quit1(int t) { quit2(t); }

int inclusive(int n) {
    int t = 0;
    for (int i = 0; i <= n; i++) t += twice(i);                        /* range */
    return t;
}

void inclusive_quit(int n) {
    int t = 0;
    for (int i = 0; i <= n; i++) { t += i; if (i == 3) quit1(t); }    /* while: quit1 exits */
}

/* a loop testing a volatile object may run forever: its function does not surely return */
int waits(volatile int *flag) {
    int n = 0;
    while (*flag) n++;
    return n;
}

int main(void) {
    char text[16];
    int buf[2] = {7, 7};
    volatile int flag = 0;
    struct rec r = {3, "x"}, from = {2, "y"};
    struct box b = {3, {0}};
    int v = two_levels();
    printf("%d %d\n", v, lim_a);
    v = pointers(cut_fp);
    printf("%d %d\n", v, lim_fp);
    v = out_params();
    printf("%d %d\n", v, lim_out);
    v = libc_calls(&r, &from, buf);
    printf("%d %d %d %d\n", v, gx.n, r.n, buf[0]);
    v = cycles();
    printf("%d %d\n", v, lim_rec);
    v = reads();
    printf("%d\n", v);
    v = reverse(text);
    printf("%d %s\n", v, text);
    v = reverse_kept(text);
    printf("%d %s\n", v, text);
    v = aliasing(&b);
    printf("%d %d\n", v, (int) (b.f[1] * 10));
    v = inclusive(lim_libc);
    printf("%d %d %d\n", v, calls, waits(&flag));
    inclusive_quit(2147483647);
    return 1;
}
