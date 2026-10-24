#include <stdio.h>

int e(void);
int e_read(void);
int f(void);
int g(void);
int h(void);
int k(void);

int e_x = 500;
int e_x1 = 7;

int main(void) {
    e();
    printf("%d %d\n", e(), e_read());
    f();
    printf("%d %d %d %d\n", f(), g(), h(), k());
    return 0;
}
