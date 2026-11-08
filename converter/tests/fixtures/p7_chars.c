/* P7.0i: a character literal is a das character literal, in an expression and as a case label;
   das reads C's escapes, so `'\0'`, `'\a'` and `'\xff'` (under the tests' unsigned char) keep
   them; a case a number labels and a multi-character constant stay numbers; a wide `L'x'` is an
   `int` on linux and keeps its spelling */
#include <stdio.h>
#include <string.h>
static int kind(int c) {
    switch (c) {
    case 's': return 1;
    case '%': return 2;
    case '\n': return 3;
    case '\\': return 4;
    case '\'': return 5;
    case 37 + 1: return 6;
    case '\a': return 7;
    default: return 0;
    }
}
int main(void) {
    const char *fmt = "a%s{b}\n\a";
    const char *e = strchr(fmt, '%');
    char q = '\'';
    int n = 0;
    for (const char *p = fmt; *p != '\0'; p++) {
        n += kind(*p);
        if (*p == '{' || *p == '}') n += 10;
    }
    printf("%d %d %c %d %d %d\n", (int)(e - fmt), n, q, '\t', kind('&'), '\x7f');
    int digit = fmt[0] == 'a' ? '7' - '0' : 0;
    printf("%d %d %d %d\n", '\xff', 'ab', (int)L'x', digit);
    return n == '\\' ? 1 : 0;
}
