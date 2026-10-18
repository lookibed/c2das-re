int printf(const char *, ...);
typedef enum { MT_PLAYER, MT_SHOTGUN = 5, NUMMOBJTYPES } mobjtype_t;
enum color { RED = -1, GREEN = 1 << 3, BLUE, CYAN = GREEN };
enum { LOOSE_A, LOOSE_B };
enum wide { W_LOW = 1, W_HIGH = 257 };
enum flags { F_LOW = 1, F_TOP = 0x80000000u };
enum fwd;
static int widen(enum flags f, enum color c) {
    unsigned long long x = f;
    double d = f;
    enum flags g = f;
    unsigned w = 0xF0000000u;
    g >>= 4;
    w >>= 28;
    return ((long) c == (long) (unsigned) RED) + (x >> 28) + (int) (d / 268435456.0) + (g == 0x08000000) + w;
}
static int tern(int c) {
    enum wide u = W_HIGH;
    enum wide t = c ? (u = W_LOW) : W_HIGH;
    enum wide n = (enum wide) (unsigned char) (c ? W_LOW : W_HIGH);
    return t + u * 1000 + n * 1000000;
}
static int lines(void) {
    enum { L_A = 7 };
    int a[W_LOW];
    int
        b[BLUE];
    static int filled[BLUE] = { 5 };
    int grid[W_LOW][BLUE];
    a[0] = 3;
    b[8] = 4;
    grid[0][8] = 6;
    return a[0] + b[8] + grid[0][8] + filled[0] + (int) (sizeof(b) / sizeof(int)) * 100 +
        L_A;
}
static int casts(enum color c, double d, int *p, mobjtype_t t) {
    enum color same = (enum color) c;
    enum color fromd = (enum color) d;
    enum neg { N_LOW = -3, N_HIGH = 4 } arr[2] = { N_HIGH };
    return same + fromd * 10 + p[t] * 100 + arr[1] * 1000;
}
static int shadow(void) {
    enum { LOOSE_B = 20 } local = LOOSE_B;
    return local + LOOSE_B;
}
static int narrow(enum wide w) {
    return ((unsigned char) w == W_LOW ? 10 : 0) + (int) (enum wide) (unsigned char) w;
}
typedef struct { int speed; int hits[BLUE]; } mobjinfo_t;
struct mobj { mobjtype_t type; enum color c; int hp; };
static mobjinfo_t mobjinfo[NUMMOBJTYPES];
static mobjtype_t order[4] = { MT_SHOTGUN, MT_PLAYER };
static struct mobj g = { MT_SHOTGUN, BLUE, 7 };
static enum color shade(int i) { return i > 0 ? GREEN : RED; }
static mobjtype_t advance(mobjtype_t t) { return t + 1; }
static int rank(enum color c) {
    if (c == RED) return 0;
    if (c != GREEN && c > RED) return 2;
    return 1;
}
int main(void) {
    struct mobj m = g;
    struct mobj *p = &m;
    mobjtype_t t = p->type;
    mobjtype_t next;
    int score = 0;
    if (t < MT_SHOTGUN) score += 100;
    if (t == MT_SHOTGUN) score += 1;
    mobjinfo[t].speed = 3;
    mobjinfo[MT_PLAYER].hits[CYAN] = 4;
    p->type = (mobjtype_t) 0;
    next = advance(t);
    t = t + 1;
    t += 1;
    t++;
    enum { INNER_X = 40, INNER_Y } inner = INNER_Y;
    enum color c = shade(score);
    if (m.type) score += 1000;
    if (!m.type) score += 2;
    score += LOOSE_B + (int) sizeof(enum color) + (int) sizeof(mobjinfo) / (int) sizeof(mobjinfo_t);
    printf("%d %d %d %d %d\n", t, next, c, rank(c), rank(RED));
    printf("%d %d %d %d\n", order[0], order[3], mobjinfo[MT_SHOTGUN].speed, mobjinfo[0].hits[8]);
    printf("%d %d %d %d\n", m.type, m.c, inner, NUMMOBJTYPES);
    printf("%d %d %d\n", shadow(), narrow(W_HIGH), narrow(W_LOW));
    printf("%d %d %d %d %d\n", widen(F_TOP, RED), widen(F_LOW, GREEN), tern(0), tern(1), lines());
    printf("%d\n", casts(GREEN, 9.7, mobjinfo[0].hits, MT_SHOTGUN));
    return score + (t == NUMMOBJTYPES ? 0 : 50) + (int) p->type;
}
