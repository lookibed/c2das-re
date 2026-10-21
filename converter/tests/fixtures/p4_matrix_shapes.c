int printf(const char *, ...);
void exit(int);

/* a struct the unit declares and never defines, reached only through pointers: the handle
   idiom, a real record behind it */
struct opaque;
struct real { int v; };
static struct opaque *keep;
struct opaque *slots[3];
static struct real backing = { 41 };
static struct opaque *wrap(struct real *r) { return (struct opaque *) r; }
static int unwrap(struct opaque *o) { return ((struct real *) o)->v; }
static int is_none(struct opaque *o) { return o == 0; }
static void opaque_handles(void) {
    printf("opaque %d %d", is_none(keep), is_none(slots[1]));
    keep = wrap(&backing);
    slots[2] = keep;
    printf(" %d %d %d\n", is_none(keep), unwrap(slots[2]), slots[2] == keep);
}

/* `_Alignof` of a record, a scalar, an array and a record whose bitfield units align below
   clang (F5) */
struct S { char c; double d; };
struct BF { unsigned a : 3; int b : 5; short e; };
static void align_of(void) {
    printf("alignof %d %d %d %d\n", (int) _Alignof(struct S), (int) _Alignof(double), (int) _Alignof(int[4]), (int) _Alignof(struct BF));
}

/* rows of char arrays from string literals: full rows, a row the literal fills with no NUL, a
   partial list whose missing rows are zero, three dimensions, a record's field, a union's
   member stored after the declaration, one evaluated ahead of a call in the same list */
static const char s4_2[2][4] = { "1234", "5678" };
struct named { char name[6]; int id; };
static struct named nm = { "abc", 3 };
static void show_row(const char *row, int n) {
    for (int i = 0; i < n; i++) {
        printf(" %d", row[i]);
    }
}
union text4 { char s[4]; unsigned w; };
struct holder { union text4 t; int n; };
static int bumps;
static int bump(void) { return ++bumps; }
static void char_rows(void) {
    char part[3][4] = { "ab" };
    char cube[2][2][3] = { { "a", "bc" }, { "de" } };
    union text4 tx = { "abc" };
    struct holder h = { { "xy" }, bump() };
    printf("rows");
    show_row(s4_2[0], 4);
    show_row(s4_2[1], 4);
    for (int r = 0; r < 3; r++) {
        show_row(part[r], 4);
    }
    show_row(&cube[0][0][0], 12);
    show_row(tx.s, 4);
    show_row(h.t.s, 4);
    printf(" %d %s %d\n", h.n, nm.name, nm.id);
}

/* `_Alignas` on a field already at its alignment: the layout law places the record */
struct aligned_nat { _Alignas(4) int x; char c; };
static void align_as(void) {
    struct aligned_nat an = { 7, 2 };
    printf("alignas %d %d %d\n", (int) sizeof(struct aligned_nat), an.x, an.c);
}

/* `~` and binary `^` */
static void bit_ops(unsigned u, int i) {
    printf("bits %u %d %u %d\n", ~u, ~i, u ^ 0xf0u, i ^ ~i);
}

/* `restrict` pointers */
static void copy_r(int *restrict dst, const int *restrict src, int n) {
    for (int k = 0; k < n; k++) {
        dst[k] = src[k] * 2;
    }
}

/* K&R parameters: each arrives promoted and converts to its declared type on entry */
enum level { LOW, HIGH };
static int knr(a, b, s, f, e, ok)
int a;
char b;
short s;
float f;
enum level e;
_Bool ok;
{
    s += 1;
    return a * 10 + b + s + (int) (f * 2) + (int) e * 100 + ok * 1000;
}

/* `inline` */
static inline int sq(int v) { return v * v; }

/* `long double`, which the dialect computes as `double` */
static long double half(long double x) { return x / 2.0L; }

/* `volatile` on a plain field */
struct vol { volatile int ticks; int other; };
static struct vol clock_v;

/* the comma operator's value */
static int comma_value(int a, int b) {
    int x = (a++, b + a);
    return x;
}

/* `exit` from a few frames down */
static void deep_exit(int depth) {
    if (depth == 0) {
        printf("exit from deep\n");
        exit(3);
    }
    deep_exit(depth - 1);
}

int main(void) {
    opaque_handles();
    align_of();
    char_rows();
    align_as();
    bit_ops(5u, 6);
    int src[3] = { 1, 2, 3 };
    int dst[3];
    copy_r(dst, src, 3);
    printf("restrict %d %d %d\n", dst[0], dst[1], dst[2]);
    printf("knr %d %d inline %d\n", knr(4, 2, 70000, 1.25f, HIGH, 5), knr(1, 258, -1, 0.5f, LOW, 0), sq(9));
    printf("long double %.2f\n", (double) half(5.0L));
    clock_v.ticks = 3;
    clock_v.ticks += 2;
    printf("volatile %d %d\n", clock_v.ticks, clock_v.other);
    printf("comma %d\n", comma_value(1, 10));
    deep_exit(3);
    printf("not reached\n");
    return 0;
}
