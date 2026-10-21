/* P4.4 va_list: a variadic sum called in a hot loop whose list is copied with va_copy and both
   copies forwarded to a consumer taking a va_list, and a format helper forwarding its list to
   vsnprintf */
typedef __builtin_va_list va_list;
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type) __builtin_va_arg(ap, type)
#define va_copy(dst, src) __builtin_va_copy(dst, src)
#define va_end(ap) __builtin_va_end(ap)
int vsnprintf(char *, unsigned long, const char *, va_list);
static volatile int rounds = 40000;
static int result;
static int sum_list(int n, va_list ap) {
    int s = 0;
    while (n-- > 0) s += va_arg(ap, int);
    return s;
}
static int weighted(int n, ...) {
    va_list ap;
    va_list again;
    int plain;
    int twice;
    va_start(ap, n);
    va_copy(again, ap);
    plain = sum_list(n, ap);
    twice = sum_list(n, again);
    va_end(again);
    va_end(ap);
    return plain * 3 + twice;
}
static int format(char *buf, unsigned long size, const char *fmt, ...) {
    va_list ap;
    int len;
    va_start(ap, fmt);
    len = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return len;
}
static void kernel_run(void) {
    int n = rounds;
    unsigned acc = 0;
    char buf[32];
    int i;
    for (i = 0; i < n; i++) {
        acc = acc * 31 + (unsigned) weighted(4, i, i + 1, i * 3, 7);
        if ((i & 63) == 0) acc += (unsigned) format(buf, sizeof buf, "%d:%x", i, acc) + (unsigned) buf[1];
    }
    result = (int) (acc & 0x7fffffff);
}
static int kernel_result(void) { return result; }
