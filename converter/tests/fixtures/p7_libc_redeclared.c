/* P7.5 fixture: a libc function declared with another result than the library's (C99 6.2.7
   leaves it undefined; clang calls the library function and converts its result): the call
   keeps the library's result, converted to the declared type. Converted output must match the
   native build of this file. */
int strlen(char *);
short strspn(const char *, const char *);

int main(void) {
    char *p = "hello";
    return strlen(p) - 5 + strspn("aab", "a") - 2;
}
