/* P7.0u memory calls: a macroblock record cleared by `memset` and filled by `memcpy` per block,
   h264bsd's per-macroblock clears, with a copy of a run-time length beside them, each read back
   at indexes the compiler cannot predict so no clear is dead */
void *memset(void *, int, unsigned long);
void *memcpy(void *, const void *, unsigned long);
static volatile int blocks = 200000;
static int result;
struct macroblock {
    int coef[16][16];
    unsigned char flags[24];
    int type;
};
static void decode(struct macroblock *mb, const int *src, int k) {
    memset(mb, 0, sizeof(*mb));
    memcpy(mb->coef[k & 15], src, 16 * sizeof(int));
    memcpy(mb->flags, src, (unsigned long) ((k & 3) * 4 + 4));
    mb->type = k;
}
static void kernel_run(void) {
    int n = blocks;
    struct macroblock mb;
    int src[16];
    unsigned sum = 0;
    int i;
    int k;
    for (i = 0; i < 16; i++) src[i] = i * 7;
    for (k = 0; k < n; k++) {
        src[k & 15] += k;
        decode(&mb, src, k);
        sum = sum * 31 + (unsigned) mb.coef[(k * 7) & 15][(k * 3) & 15] + mb.flags[(k * 5) % 24] + (unsigned) mb.type;
    }
    result = (int) (sum & 0x7fffffff);
}
static int kernel_result(void) { return result; }
