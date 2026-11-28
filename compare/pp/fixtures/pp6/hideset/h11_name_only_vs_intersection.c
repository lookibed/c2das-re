/* separates Prosser's HS(name) ∩ HS(')') from HS(name) alone: clang, gcc and chibicc give `1 f`, the name-only rule `1 X` */
#define X f
#define f(a) a X
X(1)
