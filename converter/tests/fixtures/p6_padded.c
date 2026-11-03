int printf(const char *, ...);

/* array members indexed one element past either end, into the members beside them: Doom's
   visplane_t writes `top[minx - 1]` and `top[maxx + 1]` into its pad bytes. The sidecar lists the
   arrays under `padded`, so their accesses take no range check; `shade` is unlisted and keeps it */
struct plane {
    int minx;
    int maxx;
    char pad1;
    char top[8];
    char pad2;
    char pad3;
    char bottom[8];
    char pad4;
    char shade[4];
};

typedef struct {
    short lo;
    short clip[4];
    short hi;
} clip_t;

static int spans(const struct plane *pl) {
    int sum = 0;
    for (int x = pl->minx; x <= pl->maxx + 1; x++) {
        sum += pl->top[x - 1] + pl->bottom[x - 1];
    }
    return sum;
}

int main(void) {
    struct plane pl = { 0 };
    pl.minx = 0;
    pl.maxx = 7;
    for (int i = 0; i < 8; i++) {
        pl.top[i] = (char) i;
        pl.bottom[i] = (char) (10 + i);
    }
    pl.top[pl.maxx + 1] = 99;
    pl.top[pl.minx - 1] = 77;
    pl.bottom[-1] = 5;
    pl.bottom[8] = 6;
    pl.top[3] += 40;
    pl.shade[2] = 1;
    printf("pads %d %d %d %d\n", pl.pad1, pl.pad2, pl.pad3, pl.pad4);
    printf("reads %d %d %d %d %d\n", pl.top[-1], pl.top[8], pl.bottom[-1], pl.bottom[8], pl.top[3]);
    printf("spans %d\n", spans(&pl));
    clip_t c = { 1, { 2, 3, 4, 5 }, 6 };
    int k = -1;
    c.clip[k] = -300;
    k = 4;
    c.clip[k] += 1000;
    printf("clip %d %d %d %d\n", c.lo, c.hi, c.clip[-1], c.clip[k]);
    return 0;
}
