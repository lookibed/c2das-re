/* a.c and b.c only call each other: a forward declaration of functions parts them */
int b_step(int n);

int a_run(int n) {
    return n <= 0 ? 0 : b_step(n - 1) + 1;
}
