/* P7.5 fixture: the value of a libc function - a plain one (`strlen`, `toupper`) through its
   `<name>__fn` wrapper, a variadic one (`printf`, `fprintf`, `snprintf`, `sscanf`, `fscanf`)
   through its list-taking adapter, and stream functions whose `FILE *` the wrapper passes and
   returns as a direct call does (`tmpfile`, `fputs`, `fseek`, `fclose`). Converted output must
   match the native build of this file. */
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
    int (*scan)(const char *, const char *, ...) = sscanf;
    int (*read_from)(FILE *, const char *, ...) = fscanf;
    FILE *(*open_temp)(void) = tmpfile;
    int (*put)(const char *, FILE *) = fputs;
    int (*seek)(FILE *, long, int) = fseek;
    int (*close)(FILE *) = fclose;
    char buf[16];
    int a = 0, b = 0, c = 0;
    format(buf, sizeof buf, "<%d>", 42);
    scan("3 4", "%d %d", &a, &b);
    say("%s %d %c %d\n", buf, (int)measure("four"), apply(toupper, 'q'), a + b);
    FILE *f = open_temp();
    put("17\n", f);
    print_to(f, "%d\n", 25);
    seek(f, 0L, SEEK_SET);
    read_from(f, "%d", &c);
    read_from(f, "%d", &a);
    close(f);
    print_to(stdout, "%d %d\n", c, a);
    return measure(buf) == 4 ? 0 : 1;
}
