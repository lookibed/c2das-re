/* P7.0b lua's string hash (lstring.c luaS_hash): the bytes of a string read through a `char *`, an
   unsigned seed mixed with shifts per byte */
static volatile int rounds = 20000;
static char text[64];
static int result;
static unsigned hash(const char *str, unsigned long l, unsigned seed) {
    unsigned h = seed ^ (unsigned) l;
    for (; l > 0; l--) h ^= ((h << 5) + (h >> 2) + (unsigned char) (str[l - 1]));
    return h;
}
static void kernel_run(void) {
    for (int k = 0; k < 63; k++) text[k] = (char) ('a' + k % 26);
    unsigned acc = 0;
    int n = rounds;
    for (int r = 0; r < n; r++) acc += hash(text, 63, (unsigned) r);
    result = (int) (acc & 0x7fffffff);
}
static int kernel_result(void) { return result; }
