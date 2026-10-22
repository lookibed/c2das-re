int printf(const char *, ...);

/* functions named like the ones the `main` wrapper calls (`c_argc`, `c_argv`, `c_runtime_init`
   and `c_main`, which C `main` becomes) take free names; a call, an address taken and the
   wrapper's own calls each reach the right one */
int c_argc(void) { return 99; }

char **c_argv(void) { return 0; }

void c_runtime_init(const char *what) { printf("init %s\n", what); }

int c_main(int x) { return x + 1; }

static int (*counted)(void) = c_argc;

int main(int argc, char **argv) {
    c_runtime_init("own");
    printf("%d %d %d %d %d %d\n", argc, c_argc(), c_argv() == 0, c_main(argc), counted(), argv[0] != 0);
    return 0;
}
