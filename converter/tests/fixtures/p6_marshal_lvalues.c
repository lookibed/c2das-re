int printf(const char *, ...);
#pragma pack(push, 1)
typedef struct { char tag; char name[8]; short bbox[2][3]; const char code[4]; } lump_t;
typedef struct { short width; int columnofs[1]; } pic_t;
#pragma pack(pop)
static unsigned char lump[1 + 2 * 25];
static int pic_bytes[4];
static int name_sum(const char *s) {
    int total = 0;
    while (*s) {
        total += *s++;
    }
    return total;
}
int main(void) {
    lump_t *l = (lump_t *) (lump + 1);
    pic_t *pic = (pic_t *) pic_bytes;
    int i;
    char *walk;
    short *cell;
    short (*rows)[3];
    char (*whole)[8];
    l->tag = 'L';
    for (i = 0; i < 7; i++) {
        l->name[i] = (char) ('a' + i);
    }
    l->name[7] = 0;
    l[1].name[0] = 'z';
    l[1].name[1] += 1;
    l->name[6]++;
    walk = l->name;
    walk++;
    *walk = 'B';
    for (i = 0; i < 6; i++) {
        l->bbox[i / 3][i % 3] = (short) (100 * i);
    }
    cell = &l->bbox[1][2];
    *cell += 7;
    rows = l->bbox;
    rows[0][1] = -4;
    whole = &l->name;
    (*whole)[0] = 'A';
    ((char *) l->code)[2] = 'q';
    lump_t *lp = l;
    (lp++)->name[2] += 1;
    lp--->bbox[0][0]++;
    pic->width = 3;
    for (i = 0; i < 3; i++) {
        pic->columnofs[i] = 10 * (i + 1);
    }
    int *col = &pic->columnofs[2];
    printf("%s %d %c %d\n", l->name, name_sum(l->name), l->name[1], l[1].name[1]);
    printf("%d %d %d %d %d %d\n", (int) (lp - l), l[1].bbox[0][0], l->bbox[0][1], l->bbox[1][2], *cell, l[1].name[0]);
    printf("%c %c %d %d %d\n", l->code[2], lump[1 + 23], pic->columnofs[1], *col, (int) (&l->name[8] - l->name));
    return name_sum(l->name) % 256;
}
