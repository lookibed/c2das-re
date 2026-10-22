/* P4.9 matrix leftovers: compound literals as call arguments (a struct by value, an array as a
   pointer, a struct's address) and as assigned values in a hot loop, an `_Alignof` in the
   arithmetic, a pointer to a record the unit never defines passed through, a 2-D char table read
   through its rows, and a flexible array member filled and summed */
void *malloc(unsigned long);
void free(void *);
struct vec { int x, y; };
struct handle;
struct samples { int n; int data[]; };
static volatile int rounds = 60000;
static int result;
static const char names[4][6] = { "alpha", "beta", "gamma", "delta" };
static int dot(struct vec a, struct vec b) { return a.x * b.x + a.y * b.y; }
static int sum3(const int *v) { return v[0] + v[1] + v[2]; }
static int len2(const struct vec *v) { return v->x * v->x + v->y * v->y; }
static struct handle *wrap(struct samples *s) { return (struct handle *) s; }
static int first(struct handle *h) { return ((struct samples *) h)->data[0]; }
static int row_sum(const char *row) {
    int s = 0;
    while (*row) {
        s += *row++;
    }
    return s;
}
static unsigned mix(int n) {
    struct samples *s = malloc(sizeof(struct samples) + 64 * sizeof(int));
    struct vec acc = { 0, 0 };
    unsigned sum = 0;
    int i, k;
    s->n = 64;
    for (k = 0; k < s->n; k++) {
        s->data[k] = k * 3 + 1;
    }
    for (i = 0; i < n; i++) {
        acc = (struct vec){ acc.x + (i & 7), acc.y ^ i };
        sum = sum * 31 + (unsigned) dot((struct vec){ i, 3 }, acc);
        sum += (unsigned) sum3((int[]){ i, i >> 1, (int) _Alignof(struct vec) * 2 });
        sum ^= (unsigned) len2(&(struct vec){ i & 15, 5 });
        sum += (unsigned) row_sum(names[i & 3]);
        s->data[i & 63] += i & 1;
        sum += (unsigned) first(wrap(s));
    }
    for (k = 0; k < s->n; k++) {
        sum += (unsigned) s->data[k];
    }
    free(s);
    return sum;
}
static void kernel_run(void) { result = (int) (mix(rounds) & 0x7fffffff); }
static int kernel_result(void) { return result; }
