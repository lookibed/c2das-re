int printf(const char *, ...);
#pragma pack(push, 1)
typedef struct { short width; int ofs; char tag; } disk_t;
#pragma pack(pop)
typedef struct { int ofs; short width; } natural_t;
static unsigned char lump[3 * 7 + 2];
static int sum_widths(const disk_t *entries, int n) {
    int total = 0;
    const disk_t *end = entries + n;
    while (entries < end) {
        total += entries->width + entries->ofs;
        entries++;
    }
    return total;
}
int main(void) {
    disk_t local;
    disk_t *first = (disk_t *) (lump + 2);
    int i;
    local.width = 300;
    local.ofs = 70000;
    local.tag = 'a';
    *first = local;
    for (i = 1; i < 3; i++) {
        disk_t *w = (disk_t *) (lump + 2) + i;
        w->width = (short) (300 + i);
        w->ofs = 70000 * (i + 1);
        w->tag = (char) ('a' + i);
    }
    first[1].width = 9;
    (first + 2)->ofs += 5;
    disk_t copy = *first;
    natural_t nat = { 7, 8 };
    printf("%d %d %d %d\n", (int) sizeof(disk_t), (int) sizeof(local), (int) sizeof(natural_t), (int) sizeof lump);
    printf("%d %d %c %d %d\n", copy.width, copy.ofs, copy.tag, first[1].width, first[2].ofs);
    printf("%d %d %d %d\n", sum_widths(first, 3), lump[2], lump[9], nat.ofs + nat.width);
    return (int) (lump[3] + lump[16]);
}
