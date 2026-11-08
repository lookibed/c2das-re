/* P7.0w: functions that are no pure helper under `inline_helpers`, each refused by one rule, so
   every call below stays a call; against native */
int printf(const char *, ...);
int abs(int);
enum E { E0, E1 };
static int sq(int a) { return a * a; }
static int r_preinc(int a) { return ++a; }
static int r_assign(int a) { return a = 5; }
static int r_comma(int a, int b) { return (a, b); }
static long r_cast(int a) { return a + (long) (char *) 0; }
static int r_three(int n) {
    if (n > 9)
        n = 9;
    if (n < 0)
        n = 0;
    return n;
}
static int r_first_expr(int n) {
    n = n * 2;
    return n;
}
static int r_ret_sum(int n) {
    if (n > 9)
        n = 9;
    return n + 1;
}
static int r_two_assign(int n) {
    if (n > 9) {
        n = 9;
        n = n - 1;
    }
    return n;
}
static int r_compound(int n) {
    if (n > 9)
        n += 1;
    return n;
}
static int r_other(int n, int m) {
    if (n > 9)
        m = 9;
    return n;
}
static int r_else_block(int n) {
    if (n > 9)
        n = 9;
    else {
        n = 0;
        n = 1;
    }
    return n;
}
static int r_else_step(int n) {
    if (n > 9)
        n = 9;
    else
        n += 2;
    return n;
}
static int r_clamp_call(int n) {
    if (n > sq(3))
        n = 9;
    return n;
}
static int r_kr(a) char a; { return a + 1; }
static int r_bool(_Bool b) { return b + 1; }
static _Bool r_bool_ret(int a) { return a > 1; }
static int r_enum(enum E e) { return e + 1; }
static int r_ptr(const int *p) { return 1; }
static int r_libc(int a) { return abs(a); }
static int r_even(int n);
static int r_odd(int n) { return n == 0 ? 0 : r_even(n - 1); }
static int r_even(int n) { return n == 0 ? 1 : r_odd(n - 1); }
static int r_gtaken(int a) { return a + 2; }
static int (*gp)(int) = r_gtaken;
int r_extern(int a) { return a + 3; }
static int r_var(int a, ...) { return a + 4; }
static int r_five(int a, int b, int c, int d, int e) { return a + b + c + d + e; }
int main(void) {
    int k = 12, s = 0;
    s += r_preinc(k) + r_assign(k) + r_comma(k, 2) + (int) r_cast(k);
    s += r_three(k) + r_first_expr(k) + r_ret_sum(k) + r_two_assign(k) + r_compound(k) + r_other(k, 1);
    s += r_else_block(k) + r_else_step(k) + r_clamp_call(k) + r_kr(k) + r_bool(k) + r_bool_ret(k);
    s += r_enum(E1) + r_ptr(&k) + r_libc(-k) + r_odd(5) + r_gtaken(k) + gp(1) + r_extern(k) + r_var(k, 1) + r_var(k) + r_five(1, 2, 3, 4, k);
    printf("%d\n", s);
    return 0;
}
