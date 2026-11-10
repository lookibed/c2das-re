/* P9.7: a string literal is `cstr("...")`, the c_runtime call macro; a C function of that name is
   renamed, so its call with a literal stays a call */
#include <stdio.h>

static const char *names[] = {"zero", "one", ""};

const char *cstr(const char *s) {
    return s + 1;
}

int main(void) {
    const char *p = "lit\tab";
    printf("%s %s %s [%s] %d\n", p, cstr("xyz"), names[1], names[2], (int)"abc"[1]);
    return 0;
}
