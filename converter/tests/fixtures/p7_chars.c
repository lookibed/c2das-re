/* P7.0i: a character literal is a das character literal where das spells one, in an expression
   and as a case label; a case a number labels, `'\0'` and a value das has no escape for stay
   numbers */
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
    return n == '\\' ? 1 : 0;
}
