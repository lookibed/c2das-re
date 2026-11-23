options gen2
require dastest/testing_boost public
require daslib/regex
require daslib/strings_boost
require ../../suites/gcc_torture/filter_rules.das

//! The gcc-torture import's rules (`suites/gcc_torture/filter_rules.das`): which construct each
//! text meets first, the attribute and builtin lists, and the shapes the audit found the old
//! patterns misread.

// the feature of the first rule `text` meets, "" for none
def feature_of(text : string) : string {
    var compiled <- compile_rules()
    let idx = first_rule(compiled, text)
    return idx < 0 ? "" : RULES[idx].feature
}

[test]
def test_torture_filter(t : T?) {
    t |> run("an asm statement is machine code unless it is a barrier: an empty template, no operand") @(t : T?) {
        t |> equal(feature_of("void f(void) \{ asm(\"\"); asm volatile(\"\" ::: \"memory\"); __asm__ __volatile__(\"\" : : : \"memory\"); \}"), "")
        t |> equal(feature_of("void f(void) \{ asm(\"nop\"); \}"), "inline asm")
        t |> equal(feature_of("void f(int x) \{ asm volatile (\"\" : \"+r\" (x)); \}"), "inline asm")
        t |> equal(feature_of("void f(int x) \{ __asm volatile (\"\" : : \"g\" (x) : \"memory\"); \}"), "inline asm")
        t |> equal(feature_of("register int r asm (\"r10\");"), "inline asm")
        t |> equal(feature_of("void f(void) \{ asm goto (\"\" : : : : out); out: ; \}"), "inline asm")
        t |> equal(feature_of("void f(void) \{ __asm __volatile__ (\"\" : : \"r\" (1)); \}"), "inline asm")
        t |> equal(feature_of("double f(double x) \{ __asm__ __volatile__ (\"fsqrt\" : \"=t\" (x) : \"0\" (x)); return x; \}"), "inline asm")
        t |> equal(feature_of("void f(void) \{ __asm__ __volatile__ goto (\"\" : : : : l); l: ; \}"), "inline asm")
        t |> equal(feature_of("void f(void) \{ __asm__ volatile __inline__ (\"nop\"); \}"), "inline asm")
        t |> equal(feature_of("void f(void) \{ __asm__ __volatile__ (\"\" : : : \"memory\"); \}"), "")
        t |> equal(feature_of("#include <asm/unistd.h>\nint main(void) \{ return 0; \}"), "")
    }
    t |> run("a label's address is `&&label` after an operator, never a logical and") @(t : T?) {
        t |> equal(feature_of("int f(int c, int e) \{ return c&&e; \}"), "")
        t |> equal(feature_of("void *p = &&done;"), "address of a label and local labels")
        t |> equal(feature_of("static void *t[] = \{ &&a, &&b \};"), "address of a label and local labels")
        t |> equal(feature_of("void f(void) \{ __label__ l; \}"), "address of a label and local labels")
    }
    t |> run("a test whose attributes are all dropped is not skipped; any other is, naming P7.6") @(t : T?) {
        t |> equal(feature_of("int f(void) __attribute__((noinline, __noclone__)); int g(void) __attribute__ ((pure, format(printf, 1, 2), may_alias));"), "")
        t |> equal(feature_of("typedef int SI __attribute__((mode(SI)));"), "")
        t |> equal(feature_of("struct __attribute__((packed)) s \{ char c; int i; \};"), "packed or aligned layout")
        t |> equal(feature_of("int v __attribute__((aligned(16), unused));"), "packed or aligned layout")
        t |> equal(feature_of("struct __attribute__((packed)) s \{ char c; \}; void f(void) __attribute__((constructor));"), "__attribute__")
        t |> equal(feature_of("struct S \{ int x; \} __attribute__((scalar_storage_order(\"big-endian\")));"), "__attribute__")
        t |> equal(join(attribute_names("int f(void) __attribute__((__noinline__, aligned(8))) __attribute((cold));"), ","), "noinline,aligned,cold")
    }
    t |> run("a builtin the emitter maps is no skip; an unmapped one is") @(t : T?) {
        t |> equal(feature_of("int f(unsigned x) \{ if (__builtin_expect(x, 0)) __builtin_abort(); return __builtin_ctz(x) + __builtin_bswap32(x); \}"), "")
        t |> equal(feature_of("int f(int a, int b, int *r) \{ return __builtin_add_overflow(a, b, r); \}"), "GCC overflow builtins")
        t |> equal(feature_of("void *f(void) \{ return __builtin_return_address(0); \}"), "return and frame addresses")
        t |> equal(feature_of("int f(int x) \{ return __builtin_classify_type(x); \}"), "__builtin_* calls")
    }
    t |> run("a 128-bit integer by either spelling is __int128") @(t : T?) {
        t |> equal(feature_of("typedef __uint128_t T;"), "__int128")
        t |> equal(feature_of("unsigned __int128 x;"), "__int128")
    }
    t |> run("a test asking gcc for gnu89 or -fpermissive is a permissive input") @(t : T?) {
        t |> equal(feature_of("/* \{ dg-additional-options \"-std=gnu89\" \} */\nmain() \{ return 0; \}"), "permissive input")
        t |> equal(feature_of("/* \{ dg-additional-options \"-fpermissive\" \} */\nint main(void) \{ return 0; \}"), "permissive input")
    }
}

[test]
def test_torture_filter_rows(t : T?) {
    t |> run("a complex number by any spelling is _Complex; a name that only starts like one is not") @(t : T?) {
        t |> equal(feature_of("__complex double z;"), "_Complex")
        t |> equal(feature_of("double f(__complex__ double z) \{ return __real z + __imag__ z; \}"), "_Complex")
        t |> equal(feature_of("void *p = __realloc(0, 1); double __imagine;"), "")
    }
    t |> run("a wide string literal's prefix follows a separator, never a letter or a dash inside a string; a wide character literal converts") @(t : T?) {
        t |> equal(feature_of("int f(void) \{ return g(L\"x\"); \}"), "wide string literals")
        t |> equal(feature_of("int c = L'x';"), "")
        t |> equal(feature_of("char *s = u8\"x\";"), "wide string literals")
        t |> equal(feature_of("int f(void) \{ return g((char *)&L\"abc\"[0]); \}"), "wide string literals")
        t |> equal(feature_of("char *opts[] = \{ \"-u\", \"-L\" \};"), "")
    }
    t |> run("a variable-length array in a block-scope struct is clang's refusal, before any attribute") @(t : T?) {
        t |> equal(feature_of("int f(int n) \{\n  struct S \{ int i[n]; \} __attribute__((packed));\n  return sizeof(struct S);\n\}"), "variable-length array in a struct")
        t |> equal(feature_of("int f(int size) \{\n  struct S \{\n    struct T \{ short c; \} a[size];\n  \} s;\n  return 0;\n\}"), "variable-length array in a struct")
        t |> equal(feature_of("#define bufsize 8\nstruct huge \{ short buf[bufsize]; \};"), "")
        t |> equal(feature_of("void f(int i) \{\n  struct S s = \{ arr[i] \};\n\}"), "")
    }
    t |> run("a function declared in a function body is a block-scope function declaration") @(t : T?) {
        t |> equal(feature_of("int main(void) \{\n  extern void abort (void);\n  struct t \{ int x __attribute__((aligned(8))); \};\n  return 0;\n\}"), "block-scope function declaration")
        t |> equal(feature_of("extern void abort (void);\nint main(void) \{ return 0; \}"), "")
    }
    t |> run("the rules no emulation reaches and the builtins clang does not know") @(t : T?) {
        t |> equal(feature_of("/* \{ dg-options \"-finstrument-functions\" \} */"), "-finstrument-functions")
        t |> equal(feature_of("int f(int x) \{ return __builtin_isinff(x); \}"), "GCC builtins clang does not know")
        t |> equal(feature_of("void f(void) \{ __builtin_exit(0); \}"), "permissive input")
        t |> equal(feature_of("void f(void *b) \{ if (__builtin_setjmp(b)) return; \}"), "__builtin_setjmp")
        t |> equal(feature_of("void *f(void) \{ return __builtin_apply_args(); \}"), "__builtin_* calls")
        t |> equal(feature_of("void f(void) \{ __builtin_apply(0, 0, 0); \}"), "GNU argument forwarding builtins")
    }
    t |> run("the first rule wins: a 128-bit integer before an attribute") @(t : T?) {
        t |> equal(feature_of("__int128 x __attribute__((constructor));"), "__int128")
    }
    t |> run("a function defined inside a function is clang's to refuse; one at the file's level is not") @(t : T?) {
        t |> equal(feature_of("void foo(void)\n\{\n  int jj __attribute__((aligned(16)));\n  void bar ()\n    \{\n      jj = -20;\n    \}\n  bar ();\n\}"), "nested function")
        t |> equal(feature_of("void\nfoo (void)\n\{\n  int jj = 0;\n  if (jj) \{\n    jj = 1;\n  \}\n\}"), "")
    }
    t |> run("the GNU keywords and a case range are lowered: no rule names them") @(t : T?) {
        t |> equal(feature_of("int f(int x) \{ switch (x) \{ case 1 ... 5: return (int) __alignof__(typeof(x)); \} return __extension__ 0; \}"), "")
        t |> equal(feature_of("__typeof(1) x __attribute__((constructor));"), "__attribute__")
    }
    t |> run("the skip lines leave out every id the ratchet lists, a rule matching it or not") @(t : T?) {
        var compiled <- compile_rules()
        var passing : table<string>
        passing |> insert("listed")
        let lines <- skip_lines(compiled, ["listed", "unlisted", "plain"], passing) $(id) => id == "plain" ? "int main(void) \{ return 0; \}" : "void *p = __builtin_return_address(0);"
        t |> equal(join(lines, "|"), "unlisted\treturn and frame addresses\tthe das runtime exposes no frame or return addresses; a null mapping would lie to the test\tnever")
    }
}
