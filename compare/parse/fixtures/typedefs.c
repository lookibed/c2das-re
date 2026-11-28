/* the typedef table: what a name is decides a parenthesis, and the scopes and declarations that
   bind a name decide the names after them */
typedef int T;
typedef int T;
int x;
int m1 = sizeof((T)+1);
int m2 = sizeof((x)+1);
int m3 = sizeof((T)(x)), m4 = sizeof(T);
typedef int *PT;
PT q1, *q2;
void sc(int T);
T after_sc;
void sc2(T, int T);
T after_sc2;
typedef T T5;
T5 t5;
typedef T (fn_t)(T);
fn_t *pfn;
int y = sizeof(x), T6 = sizeof(y);
long T7 = sizeof(T6);
