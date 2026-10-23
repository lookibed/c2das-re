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
        t |> equal(feature_of("struct __attribute__((packed)) s \{ char c; int i; \};"), "__attribute__")
        t |> equal(feature_of("typedef int SI __attribute__((mode(SI)));"), "__attribute__")
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
