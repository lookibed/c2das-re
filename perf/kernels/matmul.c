/* P2.2 arrays: a 96x96 integer matrix product over two-dimensional arrays and row sums */
#define N 96
static volatile int seed = 7;
static int a[N][N];
static int b[N][N];
static int c[N][N];
static int result;
static void kernel_run(void) {
    int s = seed;
    int i, j, k;
    for (i = 0; i < N; i++) {
        for (j = 0; j < N; j++) {
            a[i][j] = (i * s + j) & 15;
            b[i][j] = (i - j * s) & 15;
        }
    }
    for (i = 0; i < N; i++) {
        for (j = 0; j < N; j++) {
            int acc = 0;
            for (k = 0; k < N; k++) acc += a[i][k] * b[k][j];
            c[i][j] = acc;
        }
    }
    {
        int trace = 0;
        for (i = 0; i < N; i++) trace += c[i][i] + c[i][N - 1 - i];
        result = trace;
    }
}
static int kernel_result(void) { return result; }
