#include <stdio.h>
/* references bind to the declaration clang resolved: a local hiding a static, a later block's
   local named like an earlier block's static, a block-scope extern, a C local spelled like the
   emitter's temporaries */
static int g = 40;
int x = 7;
static int hide_static(void) {
    int n = 0;
    {
        int g = 3;
        n += g;
        {
            int g = 5;
            n += g;
        }
    }
    return n + g;
}
static int static_then_local(void) {
    int t = 0;
    {
        static int s = 5;
        t += s;
        s++;
    }
    {
        int s = 1;
        t += s * 100;
    }
    {
        static int s = 9;
        t += s * 1000;
    }
    return t;
}
static int block_extern(void) {
    {
        extern int x;
        return x;
    }
}
static int temp_named(void) {
    int _t0 = 7;
    int a[2] = {1, 2};
    a[0];
    return _t0;
}
int main(void) {
    int first = static_then_local();
    printf("%d %d %d %d %d\n", hide_static(), first, static_then_local(), block_extern(), temp_named());
    return 0;
}
