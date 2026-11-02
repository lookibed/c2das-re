/* x.c's record holds a pointer to y.c's record: the edge x -> y carries that type beside its call
   of y_f, and no cut takes it; x.c spells struct S only in that field */
struct S;
struct T {
    struct S *p;
    int k;
};
static struct T t;
int y_f(int);

int x_g(int n) {
    return y_f(n) + t.k;
}
