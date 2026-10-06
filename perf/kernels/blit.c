/* P2.3 pointers: a byte blit through walking pointers over malloc'd buffers, then a
   checksum read back through pointer indexing */
void *malloc(unsigned long);
void free(void *);
typedef unsigned char byte;
static volatile int size = 262144;
static int result;
static void blit(byte *src, byte *dst, int n) { while (n--) *dst++ = *src++; }
static void kernel_run(void) {
    int n = size;
    byte *src = (byte *) malloc((unsigned long) n);
    byte *dst = (byte *) malloc((unsigned long) n);
    byte *p = src;
    byte *end = src + n;
    unsigned sum = 0;
    int i;
    while (p < end) { *p = (byte) ((p - src) * 31); p++; }
    blit(src, dst, n);
    for (i = 0; i < n; i += 7) sum = sum * 33 + dst[i];
    free(src);
    free(dst);
    result = (int) (sum & 0x7fffffff);
}
static int kernel_result(void) { return result; }
