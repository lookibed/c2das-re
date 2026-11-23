#include <stdio.h>

struct S { int a; };
typedef float same1;
typedef float same2;
enum color { red, green };

static int steps;
static int step(void) { return ++steps; }

/* the trait and the choice as constants: an array bound, a file-scope initializer */
static char sized[__builtin_types_compatible_p(int, const int) + 1];
static int chosen_global = __builtin_choose_expr(sizeof(long long) == 8, 64, 32);

#define SAME(a, b) __builtin_types_compatible_p(typeof(a), typeof(b))
#define CLASS(x) __builtin_classify_type(x)
#define PICK(x) __builtin_choose_expr(SAME(x, double), "double", "other")
/* two calls spelled from one token of `CLASS`, which clang values alike */
#define CLASSES(a, b) (CLASS(a) * 100 + CLASS(b))

int main(void) {
    int i = 5;
    double d = 2.5;
    char *p = 0;
    struct S s = { 1 };
    printf("compatible %d %d %d %d\n", __builtin_types_compatible_p(int, const int), __builtin_types_compatible_p(int[5], int[]),
           __builtin_types_compatible_p(same1, same2), SAME(red, i));
    printf("incompatible %d %d %d %d\n", __builtin_types_compatible_p(char *, const char *), __builtin_types_compatible_p(struct S, int),
           __builtin_types_compatible_p(enum color, char), SAME(i, d));
    /* the operand is never evaluated */
    printf("classify %d %d %d %d %d %d\n", CLASS(i), CLASS(d), CLASS(p), CLASS(s), CLASS(step()), CLASSES(i, steps));
    /* the operand not chosen is never evaluated */
    printf("choose %d %d %s %s\n", __builtin_choose_expr(0, step(), 7), __builtin_choose_expr(-2, 8, step()), PICK(d), PICK(i));
    /* the chosen operand is the expression itself: an lvalue, a statement; the trait as one is nothing */
    __builtin_choose_expr(1, i, d) = 9;
    __builtin_choose_expr(0, i, step());
    __builtin_types_compatible_p(int, long);
    printf("%d %d %d %d\n", i, steps, (int) sizeof sized, chosen_global);
    return 0;
}
