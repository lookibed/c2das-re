int printf(const char *, ...);
void *malloc(unsigned long);
void free(void *);
void *memset(void *, int, unsigned long);
void *memcpy(void *, const void *, unsigned long);
typedef unsigned char byte;
static void blit(byte *src, byte *dst, int n) { while (n--) *dst++ = *src++; }
static int twice(int x) { return 2 * x; }
static int thrice(int x) { return 3 * x; }
static int apply(int (*f)(int), int x) { return f(x) + (*f)(1); }
static int (*table[2])(int) = { twice, thrice };
static void swap(int **a, int **b) { int *t = *a; *a = *b; *b = t; }
static long span(const int *lo, const int *hi) { return hi - lo; }
int main(void) {
    byte src[8] = "abcdefg";
    byte dst[8];
    int nums[5] = { 1, 2, 3, 4, 5 };
    int *p = &nums[3];
    int *q = nums;
    int x = 10, y = 20;
    int *px = &x, *py = &y;
    void *raw = malloc(16);
    int *cells = (int *) raw;
    int (*fp)(int) = thrice;
    blit(src, dst, 8);
    memset(raw, 0, 16);
    memcpy(cells, nums, 8);
    cells[2] = p[-2] + q[1];
    swap(&px, &py);
    printf("%s %d %d %ld\n", dst, p[-2], cells[2], span(q, p));
    printf("%d %d %d %d\n", apply(twice, 5), apply(fp, 5), table[1](4), *px + *py * 2);
    printf("%d %d %d %d\n", p > q, !raw, (int) (sizeof(*p) + sizeof(byte *)), (int) ((long) p - (long) q));
    free(raw);
    return (int) (p - q) + (fp == thrice);
}
