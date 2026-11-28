/* every conversion group of the scalar world: value conversions, conversions to a slot's type,
   null pointer constants, operand conversions, explicit casts, default argument promotions */
int printf(const char *, ...);
typedef unsigned long ulong_t;
static short counts[4] = {1, [3] = 2};
const char *names[] = {"a", 0};
double half = 0.5;
float f32 = 0.1f;

static int add(a, b) char a; float b; { return a + (int)b; }

int pick(int (*fn)(void), int k) { return k ? fn() : 0; }

static int zero(void) { return 0; }

int main(void)
{
    ulong_t total = 0;
    unsigned u = 3;
    long l = -2147483648;
    char c = 'x';
    char buf[8] = "hi";
    int *p = 0;
    void *vp = p;
    total += u;
    c += 1;
    l = u + l;
    if (p == 0 && !c)
        return 1;
    for (int i = 0; i < 4; i++)
        counts[i] = (short)(counts[i] << 1);
    u = c ? u : l;
    p = (int *)(void *)0;
    printf("%s %d %f %c\n", buf, add(c, 1), half, c);
    switch (c) {
    case 'x':
        total = sizeof buf + sizeof(long double);
        break;
    default:
        total = (ulong_t)vp;
    }
    return pick(zero, (int)total) + (names[1] == 0) + (int)f32;
}
