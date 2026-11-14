#include <stdarg.h>
#include <stdio.h>

/* a pointer to a variadic function (Quake's `void (*print)(char *fmt, ...)` set to `Con_Printf` or
   `SV_ClientPrintf`): the value is the function's list-taking adapter, a call through the pointer
   passes the trailing arguments as one list; two takes of one function compare equal */
static int total;

static void to_console(char *fmt, ...) {
    va_list a;
    va_start(a, fmt);
    vprintf(fmt, a);
    va_end(a);
}

static void to_client(char *fmt, ...) {
    va_list a;
    va_start(a, fmt);
    printf("client: ");
    vprintf(fmt, a);
    va_end(a);
}

int sum(int n, ...) {
    va_list a;
    va_start(a, n);
    int s = 0;
    for (int i = 0; i < n; i++) {
        s += va_arg(a, int);
    }
    va_end(a);
    return s;
}

static void report(int console) {
    void (*print)(char *fmt, ...);
    if (console) {
        print = to_console;
    } else {
        print = to_client;
    }
    print("host: %s\n", "demo");
    print("version: %4.2f %d\n", 1.09, 7);
    print("plain\n");
    total += print == to_console;
}

int main(void) {
    report(1);
    report(0);
    int (*add)(int, ...) = sum;
    printf("%d %d %d\n", add(3, 1, 2, 3), add(0), total);
    return 0;
}
