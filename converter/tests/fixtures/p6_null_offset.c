#include <stddef.h>
int printf(const char *, ...);
#pragma pack(push, 1)
typedef struct { char tag; short v; } cell_t;
typedef struct { char kind; int count; cell_t cells[4]; } lump_t;
#pragma pack(pop)
typedef struct { char c; short s; } cmd_t;
typedef union { int i; double d; } num_t;
typedef struct { int checksum; char retrans; char numtics; cmd_t cmds[12]; struct { short x, y; } at; int grid[3][5]; num_t n; } data_t;
static data_t buf;
static data_t *nb = &buf;
static unsigned char bytes[64];
/* d_net.c: the size of a packet holding `numtics` commands */
static int netsize(void) {
    return (int) (long long) &(((data_t *) 0)->cmds[nb->numtics]);
}
int main(void) {
    lump_t *l = (lump_t *) bytes;
    unsigned long long n = 2;
    int i = 3;
    nb->numtics = 5;
    l->count = 2;
    printf("%d %d %d\n", netsize(), (int) (long long) &(((data_t *) 0)->retrans), (int) (size_t) &((data_t *) 0)->cmds[3]);
    printf("%d %d %d\n", (int) (size_t) &((data_t *) 0)->at.y, (int) (size_t) &((data_t *) 0)->grid[1][i], (int) (size_t) &((data_t *) 0)->n.d);
    printf("%d %d\n", (int) (long) &((data_t *) (void *) 0)->cmds[n].s, (int) (unsigned) (size_t) &((data_t *) 0)->cmds[n]);
    /* a marshal record: clang's packed offsets and element size */
    printf("%d %d %d\n", (int) (size_t) &((lump_t *) 0)->count, (int) (size_t) &((lump_t *) 0)->cells[2].v, (int) (size_t) &((lump_t *) 0)->cells[l->count]);
    /* the standard macro beside the idiom */
    printf("%d %d %d %d\n", (int) offsetof(data_t, cmds), (int) offsetof(data_t, n), (int) offsetof(lump_t, count), (int) offsetof(lump_t, cells));
    return 0;
}
