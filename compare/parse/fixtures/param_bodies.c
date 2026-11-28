/* tag bodies inside declarators: those clang lists beside the declaration are compared, those it
   keeps out of its JSON (a function's own parameters, anything inside a function body) are counted
   as not compared */
int f(struct S { int a; } p);
int g(enum E { A = 1, B = 2 } q);
int (*fp)(struct P5 { int e; } q);
typedef int T(struct W { int w; } a);
int x = sizeof(struct Q { int a; });
struct M { int (*mf)(struct MP { int mp; } a); int m; };
void v(void) { int y = sizeof(struct Q3 { int c; }); (void)y; }
