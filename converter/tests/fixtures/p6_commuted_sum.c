int printf(const char *, ...);
#pragma pack(push, 1)
typedef struct { char tag; short v; } cell_t;
#pragma pack(pop)
typedef struct { int a; char b; } rec_t;
typedef enum { S_A, S_B, S_C, S_D, S_E, S_F } st_t;
typedef struct { st_t flash; } info_t;
typedef struct { const rec_t *state; } psp_t;
static rec_t states[8];
static info_t info = { S_B };
static int ia[6] = { 1, 2, 3, 4, 5, 6 };
static char cs[] = "abcdef";
static unsigned char cells[4 * 3];
static st_t last;
static void set(st_t s) {
    last = s;
}
int main(void) {
    psp_t psp = { &states[S_C] };
    cell_t *cp = (cell_t *) cells;
    int i = 2;
    unsigned u = 3;
    long n = 1;
    int *ip = 1 + ia;
    char *sp = i + cs;
    const rec_t *rp = n + states;
    cell_t *third = 2 + cp;
    third->v = 77;
    (i + cp)->tag = 'z';
    printf("%d %d %c %c %d\n", *ip, *(i + ia), *sp, *(u + cs), (int) (rp - states));
    printf("%d %c %d\n", (1 + cp + 1)->v, cells[2 * 3], (int) (third - cp));
    printf("%d %d\n", *(ia + i), *(cs + u));
    /* a dereferenced sum is the pointer index but for a marshal-only record's pointer or a difference */
    cell_t whole = *(cp + 2);
    printf("%d %d\n", whole.v, *(ia + 5 - i));
    /* p_pspr.c: the state an enum offset past another, converted back to the enum */
    set(info.flash + psp.state - &states[S_A]);
    printf("%d\n", (int) last);
    return 0;
}
