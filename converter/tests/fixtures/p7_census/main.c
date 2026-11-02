#include <stdio.h>

int a_run(int n);
int c_run(void);
int e_run(void);

int main(void) {
    printf("%d %d %d\n", a_run(3), c_run(), e_run());
    return 0;
}
