/* a part the tree cannot spell is `?` alone, the type around it spelled: typeof in a parameter
   and under a declarator, a tag with no name, an `_Atomic` pointer spelled out */
int f(typeof(1) a, int b);
typeof(1) *ta[3];
struct { int x; } *un;
int *_Atomic ap;
int *_Atomic *apq;
const int *const _Atomic cap;
int (*_Atomic afp)(void);
int n;
int vla_size[sizeof(int) * 2];
