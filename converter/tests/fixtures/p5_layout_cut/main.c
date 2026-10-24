#include <stdio.h>
#include "cut.h"

int main(int argc, char **argv) {
    struct box b = b_make(argc + 6);
    printf("%d %d %d %d\n", a_run(argc + 2), b_open(&b), b_count, argv[argc] == 0);
    return 0;
}
