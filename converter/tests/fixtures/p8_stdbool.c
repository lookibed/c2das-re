/* `bool` from <stdbool.h> (P8.4, behind wasm3's include gap): once a diagnostic has formatted a
   type with the macro in scope (here the `const` the initialization of `shown` discards), clang's
   dump spells every `_Bool` as `bool`, a prototype's parameter among them */
#include <stdbool.h>
#include <stdio.h>

void set_flag(bool *flag, bool value);

void set_flag(bool *flag, bool value) {
    *flag = value;
}

static bool both(bool a, bool b) {
    return a && b;
}

int main(void) {
    const char *name = "flag";
    char *shown = name;
    bool f = false;
    set_flag(&f, 7);
    printf("%s %d %d %d\n", shown, f, both(f, true), both(f, false));
    return f ? 0 : 1;
}
