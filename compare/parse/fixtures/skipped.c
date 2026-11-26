/* constructs this slice of the parser refuses: each is skipped, the names it binds are bound, and
   the declarations after it are compared */
struct S { int m; };
typedef struct { int a; } Anon;
Anon an;
enum E { E1, E2 };
int e = E1 + E2;
int fdef(int x) { return x; }
int after = 1;
typedef int TT;
void kr(a) int a; { }
TT tt;
struct R { int r; } returns(void) { struct R v = {0}; return v; }
TT last;
