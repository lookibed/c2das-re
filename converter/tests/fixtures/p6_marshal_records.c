int printf(const char *, ...);
#pragma pack(push, 1)
typedef struct { short originx; short originy; short patch; } mappatch_t;
typedef struct { char tag; mappatch_t first; } wrap_t;
typedef struct { char k; mappatch_t two[2]; } pair_t;
typedef struct { char name[8]; int masked; wrap_t outer; short patchcount; mappatch_t patches[1]; } maptexture_t;
#pragma pack(pop)
static unsigned char lump[1 + 4 * 27 + 8];
static int origin_sum(const mappatch_t *p) {
    return p->originx + p->originy;
}
int main(void) {
    maptexture_t *t = (maptexture_t *) (lump + 1);
    mappatch_t *mp;
    wrap_t *w;
    int i;
    t->masked = 1;
    t->outer.tag = 'W';
    t->outer.first.originx = 5;
    t->outer.first.originy = 3;
    t->outer.first.originy += 2;
    t->outer.first.patch++;
    t->patchcount = 4;
    for (i = 0; i < t->patchcount; i++) {
        t->patches[i].originx = (short) (i * 10);
        t->patches[i].originy = (short) -i;
        t->patches[i].patch = (short) (i + 100);
    }
    mp = &t->patches[1];
    mp->originy = 7;
    mp++;
    mp->originy += 8;
    w = &t->outer;
    w->first.patch += 40;
    t[3].outer.first = t->patches[3];
    (*t).patches[0] = *mp;
    mappatch_t copy = t->patches[1];
    copy.patch = 9;
    t->outer.first = copy;
    maptexture_t v = *t;
    v.masked = 77;
    v.outer.first.originy = 66;
    t[3] = v;
    t[3].outer.first.patch = 55;
    wrap_t held = t[3].outer;
    pair_t pv = {0};
    pv.two[1].originx = 31;
    pv.two[1].patch = 4;
    pv.two[1].patch += 2;
    mappatch_t picked = pv.two[1];
    pv.two[0] = held.first;
    mappatch_t inner = t->outer.first;
    printf("%d %c %d %d %d\n", t->masked, t->outer.tag, t->outer.first.originx, t->outer.first.originy, t->outer.first.patch);
    printf("%d %d %d %d\n", t->patches[0].originx, t->patches[0].originy, t->patches[2].originy, t->patches[3].patch);
    printf("%d %d %d %d\n", t[3].outer.first.originx, t[3].outer.first.patch, t[3].masked, t[3].outer.first.originy);
    printf("%d %d %d %d\n", origin_sum(&t->outer.first), origin_sum(&t->patches[2]), origin_sum(&t[3].outer.first), origin_sum(t->patches));
    printf("%d %d %d %d %d\n", (int) sizeof(t->outer), (int) sizeof(t->patches[0]), (int) sizeof(maptexture_t), (int) (&t->patches[3] - t->patches), (int) ((unsigned char *) &t->outer.first - lump));
    printf("%c %d %d\n", held.tag, held.first.patch, inner.originy);
    printf("%d %d %d %d %d\n", picked.originx, picked.patch, pv.two[0].patch, pv.two[i % 2].originx, (int) sizeof(t->patches));
    return (t->patches[2].originx + v.outer.first.originy) % 256;
}
