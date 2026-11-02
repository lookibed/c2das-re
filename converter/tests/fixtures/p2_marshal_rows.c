int printf(const char *, ...);
#pragma pack(push, 1)
typedef struct { short x; short bbox[2][4]; unsigned short children[2]; } node_t;
#pragma pack(pop)
static unsigned char lump[1 + 2 * 22];
int main(void) {
    node_t *nodes = (node_t *) (lump + 1);
    int i, j, k, total = 0;
    for (i = 0; i < 2; i++) {
        nodes[i].x = (short) (10 * i);
        lump[1 + 22 * i + 20] = (unsigned char) (64 + i);
        lump[1 + 22 * i + 21] = 156;
    }
    for (i = 0; i < 2 * 22; i++) {
        if (i % 22 >= 2 && i % 22 < 18) {
            lump[1 + i] = (unsigned char) (i % 2 == 0 ? i : 0);
        }
    }
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 2; j++) {
            for (k = 0; k < 4; k++) {
                total += nodes[i].bbox[j][k] * (k + 1);
            }
        }
    }
    node_t copy = nodes[1];
    printf("%d %d %d %d %d\n", (int) sizeof(node_t), total, copy.bbox[1][3], copy.children[1], nodes[1].x);
    return copy.bbox[0][1] % 256;
}
