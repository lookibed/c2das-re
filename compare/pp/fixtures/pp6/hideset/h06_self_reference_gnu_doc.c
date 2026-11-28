/* the cpp manual's self-referential macros */
#define foo (4 + foo)
#define x (4 + y)
#define y (2 * x)
foo x y
#define EPERM EPERM
EPERM
