/* P4.8 scope fidelity: assignments read as values - a fill whose stored byte feeds the sum
   through an index the store steps, `sum += (text[i++] = b)`, and a NUL-terminated copy whose
   loop tests the byte it stored, `while ((*d++ = *s++))` */
static volatile int rounds = 64;
static int result;
static unsigned char text[4097];
static unsigned char copy[4097];
static unsigned copy_text(unsigned char *d, const unsigned char *s) {
    unsigned n = 0;
    while ((*d++ = *s++)) n++;
    return n;
}
static unsigned work(int r) {
    unsigned sum = 0;
    int k;
    for (k = 0; k < r; k++) {
        int i = 0;
        unsigned v = (unsigned) k;
        while (i < 4096) {
            v = v * 1103515245u + 12345u;
            sum += (text[i++] = (unsigned char) (1 + (v >> 16) % 255));
        }
        text[i] = 0;
        sum += copy_text(copy, text);
        sum = sum * 33 + copy[(k * 13) & 4095];
    }
    return sum;
}
static void kernel_run(void) { result = (int) (work(rounds) & 0x7fffffff); }
static int kernel_result(void) { return result; }
