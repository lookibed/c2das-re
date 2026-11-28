/* record and enum bodies and function bodies: members, bit-fields, nested and anonymous records,
   enumerators, definitions old-style and prototyped, every statement */
struct S { int m; };
typedef struct { int a; } Anon;
Anon an;
enum E { E1, E2 = 4, };
int e = E1 + E2;
struct O { struct I { int x; } i; union { int u; float f; }; unsigned b : 3, : 0; int fa[]; };
int fdef(int x) { return x; }
int after = 1;
typedef int TT;
void kr(a) int a; { }
TT tt;
struct R { int r; } returns(void) { struct R v = {0}; return v; }
int stmts(int n) {
    int k = 0, j;
    static int calls;
    lab: switch (n) { case 1 ... 2: k++; __attribute__((fallthrough)); case 3: default: break; }
    for (int i = 0; i < n; i++) { if (i & 1) continue; else k += i; }
    for (j = 0; ; ) break;
    while (k > 10) k /= 2;
    do --k; while (k > 5);
    if (k < 0) goto lab;
    { typedef long L; L l = k; k = (int)l; }
    __asm__ volatile("" ::: "memory");
    return ({ int t = k; t * 2; });
}
TT last;
