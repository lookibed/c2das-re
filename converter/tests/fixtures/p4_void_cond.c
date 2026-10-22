int printf(const char *, ...);
void abort(void);

/* a conditional of `void` type as a statement: the assert idiom, whose failing arm prints and
   aborts, an arm with no effect first and last, and calls in both arms */
#define CHECK(e) ((e) ? (void) 0 : (printf("check failed: %s\n", #e), abort()))

static int hits;

static void hit(int v) { hits += v; }

int main(void) {
    int n = 3;
    CHECK(n == 3);
    CHECK(n++ < 4);
    n > 10 ? hit(100) : (void) 0;
    n > 2 ? hit(1) : hit(2);
    n < 2 ? hit(10) : (hit(20), hit(30));
    printf("void cond %d %d\n", n, hits);
    return 0;
}
