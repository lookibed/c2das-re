/* P9.25: which pointer parameters of a folded def are `var` (classification row 9): written
   through, passed on to a call or to a nested def's `var` parameter, stored, or the result;
   read only, through a cast too, they are not */
int printf(const char *, ...);

struct tv {
    int tt;
    int v;
    struct tv *next;
};

struct sv {
    struct tv val;
};

static int g_seen;
static struct tv *g_last;

/* read only: a field, a loaded pointer's field, a null test, a cast read */
#define RAWTT(o) ((o)->tt)
#define CHECKTAG(o, t) (RAWTT(o) == (t))
#define ISINT(o) CHECKTAG(o, 3)
#define NEXTTT(o) ((o)->next->tt)
#define ISNULL(o) ((o) == 0)
#define CASTREAD(o) (((const struct sv *)(o))->val.v)
/* var: written through, after a cast too */
#define SETTT(o, t) ((o)->tt = (t))
#define CASTWRITE(o, x) (((struct sv *)(o))->val.v = (x))
/* var: the result, an address into it */
#define S2V(o) (&(o)->val)
/* var: passed to a C function */
#define NOTE(o) note(o)
/* var: stored into a global, into a local the body writes through */
#define REMEMBER(o) (g_last = (o))
#define SETV(obj, x) do { struct tv *io = (obj); io->v = (x); io->tt = 3; } while (0)
/* var through a nested def: SETTT's parameter is var, ISINT's is not */
#define MARK(o) SETTT(o, 3)
#define S2VTT(o) (S2V(o)->tt)

static void note(struct tv *p) {
    g_seen += p->v;
}

int main(void) {
    struct tv a = {3, 10, 0};
    struct tv b = {5, 20, &a};
    struct sv s = {{3, 30, 0}};
    struct tv *pa = &a;
    struct tv *pb = &b;
    struct sv *ps = &s;
    int sum = 0;
    sum += ISINT(pa) + ISINT(pb) * 2 + NEXTTT(pb) + ISNULL(pb) + CASTREAD(pa);
    SETTT(pb, 7);
    CASTWRITE(pa, 11);
    sum += S2V(ps)->v + S2VTT(ps);
    NOTE(pb);
    REMEMBER(pa);
    SETV(pb, 40);
    MARK(pa);
    printf("%d %d %d %d %d %d %d\n", sum, b.tt, b.v, a.v, a.tt, g_seen, g_last->tt);
    return 0;
}
