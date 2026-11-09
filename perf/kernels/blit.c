/* P2.3 pointers: a byte blit through walking pointers over malloc'd buffers, then a
   checksum read back through pointer indexing. The buffers are allocated on the first call
   and kept, so no rep times the allocator (perf/ARCHITECTURE.md section 1) */
void *malloc(unsigned long);
typedef unsigned char byte;
static volatile int size = 262144;
static int result;
static byte *src_buf;
static byte *dst_buf;
static void blit(byte *src, byte *dst, int n) { while (n--) *dst++ = *src++; }
static void kernel_run(void) {
    int n = size;
    if (!src_buf) {
        src_buf = (byte *) malloc((unsigned long) n);
        dst_buf = (byte *) malloc((unsigned long) n);
    }
    byte *src = src_buf;
    byte *dst = dst_buf;
    byte *p = src;
    byte *end = src + n;
    unsigned sum = 0;
    int i;
    while (p < end) { *p = (byte) ((p - src) * 31); p++; }
    blit(src, dst, n);
    for (i = 0; i < n; i += 7) sum = sum * 33 + dst[i];
    result = (int) (sum & 0x7fffffff);
}
static int kernel_result(void) { return result; }
