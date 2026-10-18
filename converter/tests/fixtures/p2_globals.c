int printf(const char *, ...);
int leveltime;
static int data[4];
static int *p = &data[1];
static int ready = 7;
static int *q = &ready;
extern int later;
static int *r = &later;
int later = 5;
static int zero(void) { return 0; }
static int one(void) { return 1; }
static int (*fptr)(void) = 0;
static int (*table[2])(void) = { zero, one };
struct S { int (*fn)(void); int *at; };
static struct S s = { &zero, &data[2] };
static const char *names[] = { "AB", "CD" };
int x;
int x = 3;
int x;
static int count = 1234;
static int tick(void) {
    static int count = 4567;
    return count++;
}
static int sum(int *a, int n) {
    int *it = a;
    int total = 0;
    while (it < a + n) total += *it++;
    return total;
}
int main(void) {
    data[1] = 11;
    data[2] = 22;
    *r += 1;
    fptr = one;
    table[0] = fptr;
    printf("%d %d %d %d %d\n", leveltime, *p, *q, later, x);
    printf("%d %d %d %d %d\n", fptr(), table[0]() + table[1](), s.fn(), *s.at, fptr != 0);
    printf("%s%s %d %d %d %d\n", names[0], names[1], tick(), tick(), count, sum(data, 4));
    fptr = 0;
    return fptr == 0 ? 3 : 4;
}
