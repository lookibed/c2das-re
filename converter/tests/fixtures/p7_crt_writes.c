/* CRT calls that write through a pointer argument, each made in a helper on a local of its
   caller: every write must reach the caller under every tier (docs/probe-findings.md F85) */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void copy4(unsigned char *dst, const unsigned char *src) { memcpy(dst, src, 4); }
static void shift4(unsigned char *dst, const unsigned char *src) { memmove(dst, src, 4); }
static void fill4(unsigned char *dst) { memset(dst, 9, 4); }
static void name(char *dst, const char *src) { strcpy(dst, src); }
static void append(char *dst, const char *src) { strcat(dst, src); }
static void format(char *dst, int v) { snprintf(dst, 8, "%d", v); }
static long parse(const char *s, char **end) { return strtol(s, end, 10); }
static double mantissa(double v, int *e) { return frexp(v, e); }
static double fraction(double v, double *ip) { return modf(v, ip); }

int main(void) {
    unsigned char b[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    char s[16];
    char n[8];
    const char *digits = "12x";
    char *end = 0;
    int e = 0;
    double ip = 0.0;
    copy4(b + 4, b);
    printf("memcpy %d %d\n", b[4], b[7]);
    shift4(b + 1, b);
    printf("memmove %d %d\n", b[1], b[4]);
    fill4(b);
    printf("memset %d %d\n", b[0], b[3]);
    name(s, "abc");
    append(s, "de");
    printf("strcpy strcat %s %d\n", s, (int) strlen(s));
    format(n, 42);
    printf("snprintf %s\n", n);
    long v = parse(digits, &end);
    printf("strtol %ld %d\n", v, (int) (end - digits));
    double m = mantissa(12.0, &e);
    printf("frexp %.2f %d\n", m, e);
    double f = fraction(2.5, &ip);
    printf("modf %.2f %.2f\n", f, ip);
    return 0;
}
