/* CRT calls that write through a pointer argument, each made in a helper on a local of its
   caller, and a read of the same memory on both sides of a write in one function, through the
   same pointer or a second one: every write must reach every read under every tier
   (docs/probe-findings.md F85) */
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

/* the length of `s` read through `p`, the same memory, before and after each writer family */
static void reread(char *s, char *p) {
    int a = (int) strlen(p);
    strcpy(s, "x");
    printf("strcpy %d %d\n", a, (int) strlen(p));
    a = (int) strlen(p);
    memset(s, 'm', 3);
    printf("memset %d %d\n", a, (int) strlen(p));
    a = (int) strlen(p);
    memcpy(s, "ab", 3);
    printf("memcpy %d %d\n", a, (int) strlen(p));
    a = (int) strlen(p);
    strcat(s, "cd");
    printf("strcat %d %d\n", a, (int) strlen(p));
    a = (int) strlen(p);
    snprintf(s, 8, "%d", 123456);
    printf("snprintf %d %d %d\n", a, (int) strlen(p), atoi(p));
    a = strcmp(p, "7");
    sscanf("7", "%s", s);
    printf("sscanf %d %d\n", a, strcmp(p, "7"));
}

/* the same reads through the written pointer itself */
static void reread_own(char *s) {
    int a = (int) strlen(s);
    strcpy(s, "xyz");
    int b = (int) strlen(s);
    memset(s, 0, 1);
    printf("own %d %d %d\n", a, b, (int) strlen(s));
}

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
    char t[16] = "abc";
    reread(t, t);
    char u[16] = "hello";
    reread_own(u);
    return 0;
}
