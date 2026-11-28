#define A 1
#define B 2
#define assert(e) ((e) ? 0 : fail(#e))
assert(B == A+1);
#define S(e) #e
S(B == A+1);
#define T(e) (#e, (e))
T(B == A+1);
