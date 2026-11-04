/* P8.4 r: vfprintf, which quakegeneric's `Sys_Error` reaches through glibc's inline `vprintf`:
   a forwarded va_list written to a stream, in order with printf's bytes */
#include <stdarg.h>
#include <stdio.h>

static int report(FILE *f, const char *fmt, ...) {
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vfprintf(f, fmt, ap);
    va_end(ap);
    return n;
}

int main(void) {
    printf("before ");
    int n = report(stdout, "%d-%s %5.2f\n", 42, "go", 1.5);
    printf("after %d\n", n);
    return 0;
}
