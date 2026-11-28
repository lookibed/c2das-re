/* declarations only, whose expressions bring no type of their own first */
typedef unsigned long ulong_t;
static short counts[4];
char *names[2];
long (*pick(int which))(double);

int main(void)
{
    ulong_t total;
    {
        typedef float real;
        real r;
    }
    for (unsigned char c = 0; c < 2; c++) {
        static signed char seen;
        extern long long big;
        int helper(char *, ...);
    }
    return 0;
}
