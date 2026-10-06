int printf(const char *, ...);
struct S { int id; int vals[4]; };
int full[3] = {1, 2, 3};
int part[6] = {1, 2};
int sparse[40] = {[5] = 9, [37] = 2};
char name[8] = "abc";
int m[2][3] = {{1, 2, 3}, {4, 5, 6}};
int *ptrs[2] = {&full[1], 0};
struct S arr_s[2] = {{1, {1, 2}}, {2}};
static int total(int *a, int n) { int s = 0; int i; for (i = 0; i < n; i++) s += a[i]; return s; }
static int rowsum(int (*row)[3]) { return (*row)[0] + (*row)[1] + (*row)[2]; }
int main(void) {
    int (*row)[3] = &m[1];
    int local[4] = {0};
    int big[64] = {[63] = 5, [1] = 7};
    char greet[6] = "hi";
    int i;
    local[2] = full[0] + part[1];
    for (i = 0; i < 3; i++) m[0][i] *= 2;
    printf("%d %d %d %d\n", (*row)[2], local[2] + local[3], arr_s[1].vals[0] + arr_s[0].vals[1], sparse[5] + sparse[37] + sparse[20]);
    printf("%d %d %d %d\n", total(full, 3), total(part, 6), total(&m[0][0], 6), rowsum(row));
    printf("%d %d %c%c %d\n", *ptrs[0], ptrs[1] == 0, name[0], greet[1], (int) sizeof(m) + (int) sizeof(name));
    printf("%d %d %d\n", big[63] + big[1] + big[40], arr_s[0].id + arr_s[1].id, (int) (sizeof(sparse) / sizeof(sparse[0])));
    return total(local, 4) + m[0][2];
}
