#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* packed records whose packing changes only clang's alignment (Doom's `mapthing_t`, `filelump_t`,
   `wadinfo_t`): every field sits where das puts it and the size is das's, so each is a plain das
   struct aligned above clang's 1 (owner ruling 38 addendum 23); arrays of them are read where a
   byte buffer holds them at odd addresses, and a record holding one at an offset das keeps is
   plain too */
typedef struct {
    short x;
    short y;
    short angle;
    short type;
    short options;
} __attribute__((packed)) thing_t;

typedef struct {
    int filepos;
    int size;
    char name[8];
} __attribute__((packed)) lump_t;

typedef struct {
    char id[4];
    int numlumps;
    int infotableofs;
} __attribute__((packed)) header_t;

typedef struct {
    short tag;
    thing_t thing;
} holder_t;

#pragma pack(2)
typedef struct {
    int a;
    int b;
} pair2_t;
#pragma pack()

typedef struct {
    int a;
    int b;
} __attribute__((packed, aligned(2))) pair_aligned_t;

typedef struct {
    double d;
    int a;
    int b;
} __attribute__((packed)) wide_t;

typedef struct {
    thing_t t;
} wrap_t;

thing_t starts[4];

int main(void) {
    unsigned char *buf = calloc(1, 256);
    thing_t *things = (thing_t *) (buf + 1);
    for (int i = 0; i < 4; i++) {
        things[i].x = (short) (i * 100 - 50);
        things[i].options = (short) (i + 7);
    }
    starts[2] = things[3];
    lump_t *lumps = (lump_t *) (buf + 83);
    lumps[1].filepos = 123456;
    lumps[1].size = 42;
    memcpy(lumps[1].name, "E1M1", 5);
    lump_t copy = lumps[1];
    header_t header;
    memcpy(&header, "IWAD\x02\x00\x00\x00\x0c\x00\x00\x00", 12);
    holder_t h = {9, {1, 2, 3, 4, 5}};
    long sum = 0;
    for (int i = 0; i < 4; i++) {
        sum += things[i].x * 3 + things[i].options;
    }
    printf("%d %d %d %d %d\n", (int) sizeof(thing_t), (int) sizeof(lump_t), (int) sizeof(header_t), (int) sizeof(holder_t), (int) _Alignof(holder_t));
    printf("%ld %d %d %s %d %d\n", sum, starts[2].x, copy.filepos + copy.size, copy.name, header.numlumps, header.infotableofs);
    printf("%.4s %d %d\n", header.id, h.tag, h.thing.options);
    /* `_Alignof` at run time is C's alignment, not das's */
    pair2_t p2 = {1, 2};
    pair_aligned_t pa = {3, 4};
    wide_t w = {0.5, 5, 6};
    wrap_t wr = {{7, 8, 9, 10, 11}};
    printf("%d %d %d %d %d %d\n", (int) _Alignof(thing_t), (int) _Alignof(pair2_t), (int) _Alignof(pair_aligned_t), (int) _Alignof(wide_t), (int) _Alignof(wrap_t), (int) _Alignof(lump_t));
    printf("%d %d %d %d %d %d\n", (int) sizeof(pair2_t), (int) sizeof(pair_aligned_t), (int) sizeof(wide_t), (int) sizeof(wrap_t), p2.b + pa.b + w.b, wr.t.options);
    free(buf);
    return 0;
}
