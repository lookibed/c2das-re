/* setjmp sites in a loop whose arms hold loops of their own: a `break` and a `continue` that stay
   inside the arm are the arm's own, unlike one that leaves the site's loop, which is refused */
#include <setjmp.h>
#include <stdio.h>

static jmp_buf b;

static void jump(int v) {
    longjmp(b, v);
}

static int arm_loops(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {
        if (setjmp(b) == 0) {
            for (int j = 0; j < 10; j++) {
                if (j == 3) break;
                if (j == 1) continue;
                s += j;
            }
            if (i == 2) jump(5);
            s++;
        } else {
            int k = 0;
            while (1) {
                if (++k > 2) break;
                s += 100;
            }
        }
    }
    return s;
}

int main(void) {
    printf("%d %d\n", arm_loops(5), arm_loops(1));
    return 0;
}
