struct S {
    int a;
};
int x_g(int);

int y_f(int n) {
    return n > 0 ? x_g(n - 1) : 0;
}
