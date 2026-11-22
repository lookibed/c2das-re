/* P7.5 fixture: the value of a libc function - a plain one (`strlen`, `toupper`) through its
   `<name>__fn` wrapper, a variadic one (`printf`, `fprintf`, `snprintf`) through its list-taking
   adapter. Converted output must match the native build of this file. */
#include <ctype.h>
#include <stdio.h>
#include <string.h>

static size_t (*measure)(const char *) = strlen;
static int (*print_to)(FILE *, const char *, ...) = &fprintf;

static int apply(int (*f)(int), int c) {
    return f(c);
}

int main(void) {
    int (*say)(const char *, ...) = printf;
    int (*format)(char *, size_t, const char *, ...) = snprintf;
    char buf[16];
    format(buf, sizeof buf, "<%d>", 42);
    say("%s %d %c\n", buf, (int)measure("four"), apply(toupper, 'q'));
    print_to(stdout, "%s\n", "done");
    return measure(buf) == 4 ? 0 : 1;
}
