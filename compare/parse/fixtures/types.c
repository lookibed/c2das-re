/* type names and declarators: builtin types, qualifiers, typedef names, tags, pointers, arrays,
   functions, parameters, storage classes, and the types clang spells by evaluation */
typedef int T;
typedef unsigned long int UL;
char c1; signed char c2; unsigned char c3; char signed c4;
short s1; unsigned short int s2; short signed s3;
int i1; signed i2; unsigned u1; long l1; unsigned long l2; long int signed l3;
long long ll1; long long unsigned int ll2; unsigned long long ll3;
float f1; double d1; long double d2; _Bool b1;
float _Complex z1; double _Complex z2; long double _Complex z3; _Complex z4;
const int ci; volatile int vi; int const volatile cvi; _Atomic int ai; const _Atomic int cai;
T t1; const T t2; UL ul; struct S *ps; union U *pu; struct S const *cps;
int *p1, **p2, *const p3, *volatile *restrict p4, *__restrict p5;
int a1[3], a2[2][3], *a3[4], (*a4)[5], (*a5[2])[3];
int fn1(void), fn2(), fn3(int, char *, ...), (*fp1)(int), (*fp2[2])(void), *(*fp3)(int);
int (*fr(int))(char);
int (*const fq)(void);
int *(fparen)(int);
void prm(int a[], int b[4], int c[static 5], int d[const 6], int e[*], void g(int), int (*h)[7], T t, const int k);
void unnamed(int, char *, T);
static int st; extern int ex; static inline int si(void); extern int ei(int x, int y);
__thread int th; _Thread_local static int th2;
int sized[0x10], sized2[sizeof(int)], sized3[2 + 3], sized4[010];
char str[] = "abc";
int list[] = {1, 2, 3};
typeof(1 + 2) to1; __typeof__(int *) to2;
int __attribute__((unused)) at1, *__attribute__((aligned(8))) at2;
int asmlabel __asm__("other_name");
_Alignas(16) int aligned16;
