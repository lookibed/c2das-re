options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_ir.das

//! `frontend/c_types.das`: per type form its table entry and clang's spelling, under both dialects;
//! the order a unit's declarations, definitions and bodies first use their types in; typedefs,
//! parameter adjustment, old-style definitions, unsized arrays sized by their initializers, the own
//! headers' declarations; and every refusal with its place.

// a table entry as one word: its key, a typedef by its name and target
def private entry(t : CirType) : string => t.k == "typedef" ? "typedef:{t.name}:{t.to}" : c_type_key(t)

// the type table of unit `text` (named `t.c`) as its entries in order, blank-separated; `error: `
// and the builder's error, or `parse error: ` and the parser's; `library` is the own headers'
// folder
def private types_of(text : string; msvc : bool = false; library : string = "") : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", msvc)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), library)
    let ok = c_ir_unit(*r, p, u)
    let listed = ok ? join([for (t in r.tu.types); entry(t)], " ") : "error: {r.err}"
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return listed
}

let SCALARS = "char a; signed char b; unsigned char c; short d; unsigned short e; int f; unsigned g; long h; unsigned long i; long long j; unsigned long long k; _Bool l; float m; double n; long double o; void q(void); short int d2; int signed f2; signed f3; long int h2; long unsigned int i2; long long int j2; unsigned char signed_twice; char unsigned c2; const volatile int cv;"

[test(description = "every builtin type keyword set as clang spells it, each width the dialect's, plain char unsigned, alternate spellings and qualifiers folding into one entry")]
def test_scalars(t : T?) {
    t |> run("linux, LP64") @(t : T?) {
        t |> equal(types_of(SCALARS), "int:8:false:char int:8:true:signed char int:8:false:unsigned char int:16:true:short int:16:false:unsigned short int:32:true:int int:32:false:unsigned int int:64:true:long int:64:false:unsigned long int:64:true:long long int:64:false:unsigned long long int:8:false:_Bool float:32 float:64:double float:64:long double void func:15::false")
    }
    t |> run("msvc, LLP64: long is 32 bits") @(t : T?) {
        t |> equal(types_of(SCALARS, true), "int:8:false:char int:8:true:signed char int:8:false:unsigned char int:16:true:short int:16:false:unsigned short int:32:true:int int:32:false:unsigned int int:32:true:long int:32:false:unsigned long int:64:true:long long int:64:false:unsigned long long int:8:false:_Bool float:32 float:64:double float:64:long double void func:15::false")
    }
    t |> run("msvc declares size_t before the unit, linux does not") @(t : T?) {
        t |> equal(types_of("size_t n; long l;", true), "int:64:false:unsigned long long int:32:true:long")
        t |> equal(types_of("size_t n;"), "parse error: t.c:1:1: expected a declaration, got 'size_t'")
    }
}

[test(description = "array sizes and index designators as integer constant expressions, through the unit's one evaluator: arithmetic, sizeof, a character constant")]
def test_constant_sizes(t : T?) {
    t |> equal(types_of("char a[2 * 3 + (1 << 2)], b[sizeof(int)], c['a' - 96]; int d[] = \{[2 + 1] = 1\};"),
               "int:8:false:char array:0:10 array:0:4 array:0:1 int:32:true:int array:4:4")
}

[test(description = "pointers, arrays and functions: each part before the type it builds, a function's result before its parameters, C's inside-out declarator reading")]
def test_derived(t : T?) {
    t |> run("a function returning a function pointer, an array of arrays of pointers, a pointer to an array") @(t : T?) {
        t |> equal(types_of("int (*f(char))(long); int *a[3][4]; int (*r)[5];"),
                   "int:32:true:int int:64:true:long func:0:1:false ptr:2 int:8:false:char func:3:4:false ptr:0 array:6:4 array:7:3 array:0:5 ptr:9")
    }
    t |> run("(void) and () are one type; variadic apart; a parameter's qualifiers and name dropped") @(t : T?) {
        t |> equal(types_of("int f(void); int g(); int h(int, ...); int k(const int x);"),
                   "int:32:true:int func:0::false func:0:0:true func:0:0:false")
    }
    t |> run("an array size in parentheses, octal, hex and suffixed") @(t : T?) {
        t |> equal(types_of("char a[(2)], b[010], c[0x10u], d[3UL], e[0];"),
                   "int:8:false:char array:0:2 array:0:8 array:0:16 array:0:3 array:0:0")
    }
}

[test(description = "typedefs: the entry after the type it names, a use adding no entry, one entry per name, a typedef of a function type declaring a function, typeof of a type name")]
def test_typedefs(t : T?) {
    t |> run("file scope") @(t : T?) {
        t |> equal(types_of("typedef unsigned long size; typedef size *sp, arr[2]; sp x; typedef int F(int); F *fp; F g; typeof(char *) tc;"),
                   "int:64:false:unsigned long typedef:size:0 ptr:0 typedef:sp:2 array:0:2 typedef:arr:4 int:32:true:int func:6:6:false typedef:F:7 ptr:7 int:8:false:char ptr:10")
    }
    t |> run("block scope: a name ends with its block, and one name keeps one entry whatever type a later block gives it") @(t : T?) {
        t |> equal(types_of("typedef short T; void f(void) \{ \{ typedef long T; T a; \} T b; \{ typedef char T; T c; \} \}"),
                   "int:16:true:short typedef:T:0 void func:2::false int:64:true:long int:8:false:char")
    }
}

[test(description = "parameters adjusted as clang adjusts them: an array, an array of unknown size, a function and an array typedef become pointers, the array never entered")]
def test_parameters(t : T?) {
    t |> equal(types_of("typedef char row[8]; void h(int a[3], int b[][4], int fn(void), row d, const int *e, ...);"),
               "int:8:false:char array:0:8 typedef:row:1 void int:32:true:int ptr:4 array:4:4 ptr:6 func:4::false ptr:8 ptr:0 func:3:5,7,9,10,5:true")
}

let BODY = "short g(long a, char *b) \{ unsigned x; \{ typedef double D; D y; \} for (float i; ; ) ; if (1) \{ long long z; \} else \{ signed char w; \} static unsigned short s; extern float e; int g2(void); short g(long, char *); switch (1) \{ case 1: \{ unsigned char c1; \} default: \{ _Bool b1; \} \} while (0) \{ long double ld; \} do \{ unsigned long ul; \} while (0); lab: \{ int *ip; \} return 0; \}"

[test(description = "a definition: its type, its parameters, then its body's declarations depth-first in source order, a block function declaration of a declared name adding nothing")]
def test_definition(t : T?) {
    t |> run("every statement form") @(t : T?) {
        t |> equal(types_of(BODY),
                   "int:16:true:short int:64:true:long int:8:false:char ptr:2 func:0:1,3:false int:32:false:unsigned int float:64:double typedef:D:6 float:32 int:32:true:int int:64:true:long long int:8:true:signed char int:16:false:unsigned short func:9::false int:8:false:unsigned char int:8:false:_Bool float:64:long double int:64:false:unsigned long ptr:9")
    }
    t |> run("an old-style definition: R (P...) with its parameters promoted, then each parameter in the identifier list's order") @(t : T?) {
        t |> equal(types_of("int k(a, b, c) char b; double a; int c[2]; \{ return 0; \}"),
                   "int:32:true:int float:64:double ptr:0 func:0:1,0,2:false int:8:false:char")
        t |> equal(types_of("int k(a, b, c) float a; unsigned short b; _Bool c; \{ return 0; \}"),
                   "int:32:true:int float:64:double func:0:1,0,0:false float:32 int:16:false:unsigned short int:8:false:_Bool")
        t |> equal(types_of("int f(x) int x __attribute__((mode(DI))); \{ return 0; \}"),
                   "error: t.c:1:31: the attribute 'mode', which changes a type, is not typed yet")
    }
    t |> run("a block declaration of a function no declaration named yet adds its type and parameters") @(t : T?) {
        t |> equal(types_of("void f(void) \{ int g(char *); \}"), "void func:0::false int:32:true:int int:8:false:char ptr:3 func:2:4:false")
    }
}

[test(description = "an unsized array takes its count from its initializer: a string literal run's bytes, escapes and universal character names counted, a list's items with index designators, a braced string, braced rows, a pointer array's string item")]
def test_unsized_arrays(t : T?) {
    t |> equal(types_of("char s[] = \"ab\\n\\x41\\101\\u00e9\" \"c\"; int v[] = \{1, 2, 3\}; char u[] = \{\"xy\"\}; int m[][2] = \{\{1, 2\}, \{3, 4\}, \{5\}\}; extern int e[]; char w[][3] = \{\"a\", \"b\"\}; int d[] = \{5, [2] = 2, 3\}; char *q[] = \{\"z\"\};"),
               "int:8:false:char array:0:9 int:32:true:int array:2:3 array:0:3 array:2:2 array:5:3 array:2:-1 array:4:2 array:2:4 ptr:0 array:10:1 array:0:2")
}

let LIBRARY = "# 1 \"/lib/h.h\" 1\ntypedef unsigned long size_t;\ntypedef _Complex double cplx;\nint puts(const char *);\nstatic int lib_def(void) \{ return 0; \}\n# 2 \"t.c\" 2\nsize_t n; int f(void) \{ int puts(const char *); int lib_def(void); return 0; \}\n"

[test(description = "the own headers' declarations add no type: their typedef names resolve, their function names count as declared, an untyped one refused where the unit uses it")]
def test_library(t : T?) {
    t |> equal(types_of(LIBRARY, false, "/lib/"), "int:64:false:unsigned long int:32:true:int func:1::false")
    t |> equal(types_of(LIBRARY + "cplx c;\n", false, "/lib/"),
               "error: t.c:3:1: the typedef name 'cplx' is not typed yet: /lib/h.h:2:9: a complex type is not typed yet")
    t |> equal(types_of(LIBRARY), "error: /lib/h.h:2:9: a complex type is not typed yet")
}

[test(description = "every construct the builder does not type yet is refused at its place")]
def test_refusals(t : T?) {
    t |> equal(types_of("_Complex double c;"), "error: t.c:1:1: a complex type is not typed yet")
    t |> equal(types_of("_Atomic int a;"), "error: t.c:1:1: an _Atomic type is not typed yet")
    t |> equal(types_of("__builtin_va_list ap;"), "error: t.c:1:1: the typedef name '__builtin_va_list' is not typed yet")
    t |> equal(types_of("typeof(1) x;"), "int:32:true:int")
    t |> equal(types_of("typeof(y) x;"), "error: t.c:1:8: the identifier 'y', which names no variable or function the builder knows, is not typed yet")
    t |> equal(types_of("_Alignas(8) int x;"), "error: t.c:1:1: an _Alignas alignment is not typed yet")
    t |> equal(types_of("int x __attribute__((mode(DI)));"), "error: t.c:1:22: the attribute 'mode', which changes a type, is not typed yet")
    t |> equal(types_of("typedef int v4 __attribute__((__vector_size__(16)));"), "error: t.c:1:31: the attribute '__vector_size__', which changes a type, is not typed yet")
    t |> equal(types_of("int __attribute__((vector_size(8))) *p;"), "error: t.c:1:20: the attribute 'vector_size', which changes a type, is not typed yet")
    t |> equal(types_of("int * __attribute__((mode(DI))) p;"), "error: t.c:1:22: the attribute 'mode', which changes a type, is not typed yet")
    t |> equal(types_of("int (__attribute__((mode(DI))) p);"), "error: t.c:1:21: the attribute 'mode', which changes a type, is not typed yet")
    t |> equal(types_of("void f(int x __attribute__((mode(DI))));"), "error: t.c:1:29: the attribute 'mode', which changes a type, is not typed yet")
    t |> equal(types_of("void f(int n) \{ int a[n]; \}"), "error: t.c:1:23: an array size other than an integer constant expression is not typed yet")
    t |> equal(types_of("int a[4294967296];"), "error: t.c:1:7: an array size below 0 or past 2^31 - 1 is not typed yet")
    t |> equal(types_of("int a[1 - 2];"), "error: t.c:1:7: an array size below 0 or past 2^31 - 1 is not typed yet")
    t |> equal(types_of("void f(int n, int (*a)[*]);"), "error: t.c:1:19: a variable-length array is not typed yet")
    t |> equal(types_of("void f(int n) \{ int a[] = \{[n] = 1\}; \}"), "error: t.c:1:28: an array index other than an integer constant expression is not typed yet")
    t |> equal(types_of("int s[] = L\"x\";"), "error: t.c:1:11: a prefixed string literal is not typed yet")
    t |> equal(types_of("char s[] = L\"x\";"), "error: t.c:1:12: a prefixed string literal is not typed yet")
    t |> equal(types_of("int s[] = (\{ 1; \});"), "error: t.c:1:11: an unsized array initialized by this expression is not typed yet")
}
[test(description = "a declaration's specifiers name one type for all its declarators: a typedef one of them binds does not change the next")]
def test_specifiers_once(t : T?) {
    t |> equal(types_of("typedef int T; void f(void) \{ typedef T T2, *T, T3; T3 x; \}"),
               "int:32:true:int typedef:T:0 void func:2::false typedef:T2:0 ptr:0 typedef:T3:0")
}

[test(description = "a redeclaration takes the composite of the earlier type: a prototype kept by a declaration with none, an array size kept by one with none, a header's prototype; any other different type refused")]
def test_redeclarations(t : T?) {
    t |> equal(types_of("int f(int); int f();"), "int:32:true:int func:0:0:false")
    t |> equal(types_of("int f(); int f(int x) \{ return x; \}"), "int:32:true:int func:0::false func:0:0:false")
    t |> equal(types_of("int f(); int f(a) int a; \{ return a; \}"), "int:32:true:int func:0::false func:0:0:false")
    t |> equal(types_of("void f(const int x); void f(int x);"), "void int:32:true:int func:0:1:false")
    t |> equal(types_of("int x; const int x;"), "error: t.c:1:18: a redeclaration of 'x' with other qualifiers is invalid C, which clang rejects")
    t |> equal(types_of("extern const int a[]; const int a[2];"), "int:32:true:int array:0:-1 array:0:2")
    t |> equal(types_of("extern int a[3]; int a[];"), "int:32:true:int array:0:3")
    t |> equal(types_of("extern int a[]; int a[2];"), "int:32:true:int array:0:-1 array:0:2")
    t |> equal(types_of("int g(int); void h(void) \{ extern int g(); \}"), "int:32:true:int func:0:0:false void func:2::false")
    t |> equal(types_of(LIBRARY + "int puts();\n", false, "/lib/"),
               "int:64:false:unsigned long int:32:true:int func:1::false int:8:false:char ptr:3 func:1:4:false")
    t |> equal(types_of("int f(int); int f(char);"),
               "error: t.c:1:17: a redeclaration of 'f' whose type differs from the earlier one's is not typed yet (its composite type waits for the Aggregates phase)")
    t |> equal(types_of("int a[2]; int a[3];"),
               "error: t.c:1:15: a redeclaration of 'a' whose type differs from the earlier one's is not typed yet (its composite type waits for the Aggregates phase)")
}

[test(description = "arrays of unknown size: one a typedef names sized by the initializer, a tentative definition completed to one element unless a later definition sizes it")]
def test_array_completion(t : T?) {
    t |> equal(types_of("typedef char A[]; A a = \"hello\";"), "int:8:false:char array:0:-1 typedef:A:1 array:0:6")
    t |> equal(types_of("typedef int V[]; V v = \{1, 2\};"), "int:32:true:int array:0:-1 typedef:V:1 array:0:2")
    t |> equal(types_of("int a[];"), "int:32:true:int array:0:1")
    t |> equal(types_of("int a[]; int a[5];"), "int:32:true:int array:0:-1 array:0:5")
    t |> equal(types_of("int a[]; int a[];"), "int:32:true:int array:0:-1 array:0:1")
    t |> equal(types_of("int b[]; extern int b[];"), "int:32:true:int array:0:1 array:0:-1")
    t |> equal(types_of("extern int e[];"), "int:32:true:int array:0:-1")
    t |> equal(types_of("int a[]; extern int a[5];"),
               "error: t.c:1:5: an array of unknown size defined tentatively and sized by a later extern declaration is not typed yet (its completion waits for the Aggregates phase)")
}

[test(description = "a typedef of void alone in a parameter list is (void), no parameter")]
def test_void_typedef(t : T?) {
    t |> equal(types_of("typedef void V; int f(V);"), "void typedef:V:0 int:32:true:int func:2::false")
    t |> equal(types_of("typedef void V; int f(const V);"), "void typedef:V:0 int:32:true:int func:2::false")
}

[test(description = "type-changing constructs are refused wherever they stand: _Atomic on a pointer or an array parameter, the __ext_vector_type__ spelling, a header typedef's trailing attribute, a designator past the largest count")]
def test_refusals_everywhere(t : T?) {
    t |> equal(types_of("int * _Atomic p;"), "error: t.c:1:7: an _Atomic type is not typed yet")
    t |> equal(types_of("void f(int a[_Atomic 2]);"), "error: t.c:1:14: an _Atomic type is not typed yet")
    t |> equal(types_of("typedef int V __attribute__((__ext_vector_type__(4))); V a;"),
               "error: t.c:1:30: the attribute '__ext_vector_type__', which changes a type, is not typed yet")
    t |> equal(types_of("# 1 \"/lib/h.h\" 1\ntypedef int V __attribute__((vector_size(16)));\n# 2 \"t.c\" 2\nV a;\n", false, "/lib/"),
               "error: t.c:2:1: the typedef name 'V' is not typed yet: /lib/h.h:1:30: the attribute 'vector_size', which changes a type, is not typed yet")
    t |> equal(types_of("int a[] = \{[2147483647] = 1\};"), "error: t.c:1:12: an array sized past 2^31 - 1 is not typed yet")
    t |> equal(types_of("int a[] = \{[2147483646] = 1\};"), "int:32:true:int array:0:2147483647")
}


[test(description = "the branches each unit reaches: the other spellings of a type-changing attribute, a parameter's parenthesised or abstract declarator, hex sizes, octal and UCN escapes by length, a designator of another kind, a size a later designator does not shrink, an unsized array inside a declarator, the boundaries of old-style promotion and of a void typedef list, a function typedef parameter")]
def test_branch_inputs(t : T?) {
    t |> equal(types_of("int x __attribute__((__mode__(DI)));"), "error: t.c:1:22: the attribute '__mode__', which changes a type, is not typed yet")
    t |> equal(types_of("typedef int V __attribute__((ext_vector_type(4))); V a;"), "error: t.c:1:30: the attribute 'ext_vector_type', which changes a type, is not typed yet")
    t |> equal(types_of("void f(int (a)[3]);"), "void int:32:true:int ptr:1 func:0:2:false")
    t |> equal(types_of("void f(int []);"), "void int:32:true:int ptr:1 func:0:2:false")
    t |> equal(types_of("typedef char row[8]; void g(row);"), "int:8:false:char array:0:8 typedef:row:1 void ptr:0 func:3:4:false")
    t |> equal(types_of("char a[0xA];"), "int:8:false:char array:0:10")
    t |> equal(types_of("char s[] = \"\\1012\";"), "int:8:false:char array:0:3")
    t |> equal(types_of("char s[] = \"\\U0001F600\";"), "int:8:false:char array:0:5")
    t |> equal(types_of("char s[] = \"\\u20ac\";"), "int:8:false:char array:0:4")
    t |> equal(types_of("char s[] = \"\\u0024\";"), "int:8:false:char array:0:2")
    t |> equal(types_of("char s[] = \"\\u00E9\";"), "int:8:false:char array:0:3")
    t |> equal(types_of("int a[] = \{.x = 1\};"), "error: t.c:1:12: a member designator of other than a struct or union is not typed yet")
    t |> equal(types_of("int a[] = \{1, 2, 3, [0] = 9\};"), "int:32:true:int array:0:3")
    t |> equal(types_of("int (*p)[];"), "int:32:true:int array:0:-1 ptr:1")
    t |> equal(types_of("int k(a) unsigned a; \{ return 0; \}"), "int:32:true:int int:32:false:unsigned int func:0:1:false")
    t |> equal(types_of("typedef int I; int f(I);"), "int:32:true:int typedef:I:0 func:0:0:false")
    t |> equal(types_of("typedef int F(int); void h(F f);"), "int:32:true:int func:0:0:false typedef:F:1 void ptr:1 func:3:4:false")
}

[test(description = "the branches of scopes, sizes and redeclarations each unit reaches: a block typedef's end restoring or erasing, a sized typedef array kept, a later extern's size through its initializer or parentheses, the result and element of a redeclaration, the prototype kept, a block variable and a block extern, an old-style body, a header's definition, _Atomic before a tag, _Alignas of a type")]
def test_branch_scopes(t : T?) {
    t |> equal(types_of("typedef short T; void f(void) \{ \{ typedef long T; \} T *b; \}"), "int:16:true:short typedef:T:0 void func:2::false int:64:true:long ptr:0")
    t |> equal(types_of("# 1 \"/lib/h.h\" 1\ntypedef struct F FILE;\n# 2 \"t.c\" 2\nvoid f(void) \{ \{ typedef int FILE; \} FILE *fp; \}\n", false, "/lib/"),
               "void func:0::false int:32:true:int typedef:FILE:2 tag:0 ptr:4")
    t |> equal(types_of("typedef char B[4]; B b = \"a\";"), "int:8:false:char array:0:4 typedef:B:1")
    t |> equal(types_of("int a[]; extern int a[] = \{1, 2\};"),
               "error: t.c:1:5: an array of unknown size defined tentatively and sized by a later extern declaration is not typed yet (its completion waits for the Aggregates phase)")
    t |> equal(types_of("int a[]; extern int (a[5]);"),
               "error: t.c:1:5: an array of unknown size defined tentatively and sized by a later extern declaration is not typed yet (its completion waits for the Aggregates phase)")
    t |> equal(types_of("int f(); long f(int);"),
               "error: t.c:1:15: a redeclaration of 'f' whose type differs from the earlier one's is not typed yet (its composite type waits for the Aggregates phase)")
    t |> equal(types_of("extern int a[]; long a[2];"),
               "error: t.c:1:22: a redeclaration of 'a' whose type differs from the earlier one's is not typed yet (its composite type waits for the Aggregates phase)")
    t |> equal(types_of("int f(int); int f(); int f();"), "int:32:true:int func:0:0:false")
    t |> equal(types_of("int a[2]; void f(void) \{ int a[3]; \}"), "int:32:true:int array:0:2 void func:2::false array:0:3")
    t |> equal(types_of("int a[3]; void f(void) \{ extern int a[]; \}"), "int:32:true:int array:0:3 void func:2::false")
    t |> equal(types_of("int k(a) int a; \{ long x; return 0; \}"), "int:32:true:int func:0:0:false int:64:true:long")
    t |> equal(types_of("# 1 \"/lib/h.h\" 1\nstatic long lib_def(void) \{ return 0; \}\n# 2 \"t.c\" 2\nint f(void) \{ long lib_def(void); return 0; \}\n", false, "/lib/"),
               "int:32:true:int func:0::false")
    t |> equal(types_of("_Atomic struct S *p;"), "error: t.c:1:1: an _Atomic type is not typed yet")
    t |> equal(types_of("_Alignas(int) int x;"), "error: t.c:1:1: an _Alignas alignment is not typed yet")
}

[test(description = "a GNU binary literal sizes an array as its base-2 value")]
def test_binary_size(t : T?) {
    t |> equal(types_of("int a[0b11];"), "int:32:true:int array:0:3")
}
