options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/strings_boost
require math
require daslib/cmp
require ../pp_record.das

//! `frontend/pp_expand.das`: macro expansion over in-memory files - object-like and function-like
//! calls, `#` and `##`, the GNU variadics, rescanning with clang's context model, the builtins,
//! `_Pragma`, the macros of directive lines, and the call record.

// a preprocessor with expansion over the in-memory `files` (path, text pairs), started at `main.c`
// at the time 1000000000 (2001-09-09 01:46:40 UTC)
def private started(files : array<tuple<string; string>>; predefines : array<string> = array<string>()) : Preprocessor {
    var mem = new PpMemoryProvider()
    for (f in files) {
        mem->add(f._0, f._1)
    }
    var pp : Preprocessor
    pp_expand_start(pp, mem, "main.c", predefines, array<string>(), 1000000000l)
    return <- pp
}

// every token handed out, spelled, a blank between them and a `|` before a token that starts a line
def private stream(var pp : Preprocessor) : string {
    return build_string() $(var out) {
        var first = true
        while (pp_next_token(pp)) {
            if (!first) {
                out |> write(pp.tok.tok.at_bol ? " | " : " ")
            }
            first = false
            out |> write(pp_token_spelling(pp))
        }
    }
}

// every diagnostic, `<W|E|F> <line>:<col> <what>`, a `|` between them
def private diagnostics(pp : Preprocessor) : string {
    let parts <- [for (d in pp.diags); "{d.severity == PpSeverity.fatal ? "F" : d.severity == PpSeverity.error ? "E" : "W"} {d.line}:{d.col} {d.what}"]
    return join(parts, " | ")
}

// the stream of `main.c` holding `text`, and its diagnostics
def private expanded(text : string; files : array<tuple<string; string>> = array<tuple<string; string>>()) : tuple<out : string; diags : string> {
    var all <- [("main.c", text)]
    all |> push_from(files)
    var pp <- started(all)
    let out = stream(pp)
    return (out = out, diags = diagnostics(pp))
}

[test(description = "an object-like macro is replaced and rescanned; the first token of a replacement takes the name's place on its line, and an empty one gives it to the next token")]
def test_object_like(t : T?) {
    t |> equal(expanded("#define N 10\n#define M N + N\nint a[M];\n").out, "int a [ 10 + 10 ] ;")
    t |> equal(expanded("#define EMPTY\nEMPTY x\nq EMPTY\nr\n").out, "x | q | r")
    t |> equal(expanded("#define A x\nb\nA c\n").out, "b | x c")
}

[test(description = "a function-like macro takes its arguments across lines, the newlines read as spaces; a name with no ( after it stays")]
def test_function_like(t : T?) {
    t |> equal(expanded("#define f(x,y) [x|y]\nf(1,2) f (a, (b,c)) f\n(3,\n4) f;\n").out, "[ 1 | 2 ] [ a | ( b , c ) ] [ 3 | 4 ] f ;")
    t |> equal(expanded("#define str(s) #s\nstr(a\nb)\n").out, "\"a b\"")
    t |> equal(expanded("#define g(x) x\n#define EMPTY\ng EMPTY (1)\n").out, "g ( 1 )")
}

[test(description = "the number of arguments: an empty argument, f() of a macro of no parameter, and too few or too many - clang's error, the name handed out and the call dropped; a call the end of the unit cuts off hands out nothing")]
def test_argument_count(t : T?) {
    t |> equal(expanded("#define z() Z\n#define one(a) [a]\n#define two(a,b) a+b\nz() z( ) one() two(,) one((,))\n").out, "Z Z [ ] + [ ( , ) ]")
    let bad = expanded("#define z() Z\n#define two(a,b) a+b\nz(1) two(1) two(1,2,3) after\n")
    t |> equal(bad.out, "z two two after")
    t |> equal(bad.diags, "E 3:1 too many arguments provided to function-like macro invocation | E 3:6 too few arguments provided to function-like macro invocation | E 3:13 too many arguments provided to function-like macro invocation")
    let open = expanded("#define f(x) x\na f(1, 2\n")
    t |> equal(open.out, "a")
    t |> equal(open.diags, "E 2:3 unterminated function-like macro invocation")
}

[test(description = "the arguments of a call in a directive line end with the line: an unterminated call there is clang's error")]
def test_call_ends_with_directive_line(t : T?) {
    let r = expanded("#define f(x) x\n#line f(\n7)\n__LINE__\n")
    t |> success(find(r.diags, "E 2:7 unterminated function-like macro invocation") >= 0, r.diags)
}

[test(description = "an argument is fully expanded before substitution, but not as an operand of # or ##")]
def test_argument_pre_expansion(t : T?) {
    let defs = "#define EMPTY\n#define str(s) #s\n#define xstr(s) str(s)\n#define cat(a,b) a##b\n#define xcat(a,b) cat(a,b)\n#define xy 42\n#define N 7\n"
    t |> equal(expanded("{defs}str(N) xstr(N) xstr(EMPTY) str(EMPTY) cat(x,y) cat(N,1) xcat(N,1)\n").out, "\"N\" \"7\" \"\" \"EMPTY\" 42 N1 71")
    t |> equal(expanded("#define f(a) a*g\n#define g(a) f(a)\n#define id(x) x\nid(f(1)) id(f)(2)\n").out, "1 * g 2 * g")
}

[test(description = "# spells its argument as written: one blank where it had space, none at either end, \\ and \" escaped inside string and character literals (C11 6.10.3.2)")]
def test_stringify(t : T?) {
    t |> equal(expanded("#define str(s) #s\nstr( a  +  \"b\\n\" 'c' '\"' L\"\\\\\" ) str() str(  )\n").out, "\"a + \\\"b\\\\n\\\" 'c' '\\\"' L\\\"\\\\\\\\\\\"\" \"\" \"\"")
    t |> equal(expanded("#define str(s) # s\n#define xstr(s) str(s)\n#define f(a) a+  a\nxstr(f(1)) xstr(  f( 1 ) )\n").out, "\"1+ 1\" \"1+ 1\"")
}

[test(description = "## pastes the two spellings into one token by the lexer's rules: names, numbers, punctuators, digraphs and literal prefixes; placemarkers for empty arguments")]
def test_paste(t : T?) {
    let defs = "#define cat(a,b) a##b\n"
    t |> equal(expanded("{defs}cat(1,) cat(,2) cat(,) [cat(,)] cat(x,y) cat(+,+) cat(<<,=) cat(-,>) cat(%:,%:) cat(<,:)\n").out, "1 2 [ ] xy ++ <<= -> %:%: <:")
    t |> equal(expanded("{defs}cat(L, \"s\") cat(u8,\"t\") cat(L,'c') cat(.,5) cat(1,e) cat(1e,+) cat(0x,1F) cat(1.,e5)\n").out, "L\"s\" u8\"t\" L'c' .5 1e 1e+ 0x1F 1.e5")
    t |> equal(expanded("{defs}#define xy 42\ncat(x,y) cat(x y,z) cat(a,b c)\n").out, "42 x yz ab c")
    t |> equal(expanded("#define t(x,y,z) x ## y ## z\nt(1,2,3) t(,4,5) t(6,,7) t(8,9,) t(10,,) t(,11,) t(,,12) [t(,,)]\n").out, "123 45 67 89 10 11 12 [ ]")
    t |> equal(expanded("#define AB done\n#define J a ## b ## c\n#define K A ## B\nJ K\n").out, "abc done")
}

[test(description = "a paste that forms no single token is clang's error, and both tokens stay")]
def test_paste_error(t : T?) {
    let r = expanded("#define cat(a,b) a##b\ncat(/,/) cat(.,.) cat(cat,(1)) end\n")
    t |> equal(r.out, "/ / . . cat ( 1 ) end")
    t |> equal(r.diags, "E 2:5 pasting formed '//', an invalid preprocessing token | E 2:14 pasting formed '..', an invalid preprocessing token | E 2:23 pasting formed 'cat(', an invalid preprocessing token")
}

[test(description = "variadic macros: __VA_ARGS__, a GNU named variadic parameter, and the comma before ## __VA_ARGS__ removed only when the call wrote no variadic argument, as clang does under gnu17")]
def test_variadic(t : T?) {
    t |> equal(expanded("#define d(...) f(__VA_ARGS__)\n#define s(...) #__VA_ARGS__\nd() d(1, 2 ,3) s(a,b,  c)\n").out, "f ( ) f ( 1 , 2 , 3 ) \"a,b, c\"")
    t |> equal(expanded("#define EMPTY\n#define G(a,...) g(a , ## __VA_ARGS__)\n#define X 9\nG(1) G(1,) G(1,X) G(1,EMPTY) G(1,2,3)\n").out, "g ( 1 ) g ( 1 , ) g ( 1 , 9 ) g ( 1 , ) g ( 1 , 2 , 3 )")
    t |> equal(expanded("#define EMPTY\n#define F2(...) f(0 , ## __VA_ARGS__)\nF2() F2(1) F2(EMPTY)\n").out, "f ( 0 ) f ( 0 , 1 ) f ( 0 , )")
    t |> equal(expanded("#define H(a,args...) h(a, ##args)\nH(1) H(1,2)\n").out, "h ( 1 ) h ( 1 , 2 )")
    t |> equal(expanded("#define F(a, b, ...) f\nF(1)\n").diags, "E 2:1 too few arguments provided to function-like macro invocation")
}

[test(description = "__VA_OPT__ takes its content when the variadic argument expands to a token, as clang 22 does under gnu17, with # and ## over it")]
def test_va_opt(t : T?) {
    t |> equal(expanded("#define EMPTY\n#define F(...) [__VA_OPT__(x)]\nF() F(EMPTY) F(a) F( )\n").out, "[ ] [ ] [ x ] [ ]")
    t |> equal(expanded("#define V(a, ...) v(a __VA_OPT__(,) __VA_ARGS__)\nV(1) V(1,2) V(1,2,3) V(1,)\n").out, "v ( 1 ) v ( 1 , 2 ) v ( 1 , 2 , 3 ) v ( 1 )")
    t |> equal(expanded("#define W(...) __VA_OPT__(x ## x) end\n#define S(x, ...) #__VA_OPT__(x ## x __VA_ARGS__)\nW() W(1) S(a) S(a,b)\n").out, "end xx end \"\" \"aa b\"")
}

[test(description = "rescanning by the context model: a macro is disabled while its replacement is rescanned, a name read then is painted for good, and a context is left only when read past")]
def test_rescan_context_model(t : T?) {
    t |> equal(expanded("#define AA BB\n#define BB AA\nAA BB\n").out, "AA BB")
    t |> equal(expanded("#define foo() bar\n#define bar() foo\nfoo()()()()\n").out, "foo")
    t |> equal(expanded("#define obj(x) obj2 x\n#define obj2(x) [x] obj\nobj((1))(2)\n").out, "[ 1 ] obj ( 2 )")
    t |> equal(expanded("#define self self + 1\n#define id(x) x\nid(self) id(id(self))\n").out, "self + 1 self + 1")
    t |> equal(expanded("#define h(x) x h\n#define k(x) h(x)(k)\nk(1)(2)\n").out, "1 h ( k ) ( 2 )")
    t |> equal(expanded("#define LEFT (\n#define h(x) x h\n#define EXPAND(...) __VA_ARGS__\n#define APPLY(m, x) m LEFT x )\nAPPLY(h, 5) EXPAND(APPLY(h, 5))\n").out, "h ( 5 ) 5 h")
}

// the deferred-expansion idiom of the chibicc report: Prosser's hide sets give `1 REPEAT(1)` here
let private DEFER_DEFS = "#define EMPTY()\n#define DEFER(id) id EMPTY()\n#define OBSTRUCT(...) __VA_ARGS__ DEFER(EMPTY)()\n#define EXPAND(...) __VA_ARGS__\n#define A() 123\n#define REPEAT_INDIRECT() REPEAT\n#define REPEAT(n) n DEFER(REPEAT_INDIRECT)()(n)\n"

[test(description = "deferred recursion: EXPAND(REPEAT(1)) gives 1 1 REPEAT_INDIRECT ()(1), as clang and gcc give it")]
def test_deferred_recursion(t : T?) {
    t |> equal(expanded("{DEFER_DEFS}A ()\nDEFER(A)()\nEXPAND(DEFER(A)())\n").out, "123 | A ( ) | 123")
    t |> equal(expanded("{DEFER_DEFS}REPEAT(1)\nEXPAND(REPEAT(1))\nEXPAND(EXPAND(REPEAT(1)))\n").out, "1 REPEAT_INDIRECT ( ) ( 1 ) | 1 1 REPEAT_INDIRECT ( ) ( 1 ) | 1 1 1 REPEAT_INDIRECT ( ) ( 1 )")
}

// map-macro's MAP (William Swanson, CC0): deferred recursion under EVAL
let private MAP_DEFS = "#define EVAL0(...) __VA_ARGS__\n#define EVAL1(...) EVAL0(EVAL0(EVAL0(__VA_ARGS__)))\n#define EVAL2(...) EVAL1(EVAL1(EVAL1(__VA_ARGS__)))\n#define EVAL(...) EVAL2(EVAL2(__VA_ARGS__))\n#define MAP_END(...)\n#define MAP_OUT\n#define MAP_GET_END2() 0, MAP_END\n#define MAP_GET_END1(...) MAP_GET_END2\n#define MAP_GET_END(...) MAP_GET_END1\n#define MAP_NEXT0(test, next, ...) next MAP_OUT\n#define MAP_NEXT1(test, next) MAP_NEXT0(test, next, 0)\n#define MAP_NEXT(test, next) MAP_NEXT1(MAP_GET_END test, next)\n#define MAP0(f, x, peek, ...) f(x) MAP_NEXT(peek, MAP1)(f, peek, __VA_ARGS__)\n#define MAP1(f, x, peek, ...) f(x) MAP_NEXT(peek, MAP0)(f, peek, __VA_ARGS__)\n#define MAP(f, ...) EVAL(MAP1(f, __VA_ARGS__, ()()(), ()()(), ()()(), 0))\n"

[test(description = "map-macro's MAP over a list, Cloak's EVAL/REPEAT/WHEN and a Boost.PP-style counter: the libraries Prosser's hide sets break")]
def test_macro_libraries(t : T?) {
    t |> equal(expanded("{MAP_DEFS}#define STRING(x) char const *x##_string = #x;\nMAP(STRING, foo, bar, baz)\n").out,
               "char const * foo_string = \"foo\" ; char const * bar_string = \"bar\" ; char const * baz_string = \"baz\" ;")
    let cloak = "#define EVAL(...) EVAL1(EVAL1(EVAL1(__VA_ARGS__)))\n#define EVAL1(...) EVAL2(EVAL2(EVAL2(__VA_ARGS__)))\n#define EVAL2(...) __VA_ARGS__\n#define CAT(a, ...) a ## __VA_ARGS__\n#define IIF(c) CAT(IIF_, c)\n#define IIF_0(t, ...) __VA_ARGS__\n#define IIF_1(t, ...) t\n#define CHECK_N(x, n, ...) n\n#define CHECK(...) CHECK_N(__VA_ARGS__, 0,)\n#define PROBE(x) x, 1,\n#define NOT(x) CHECK(CAT(NOT_, x))\n#define NOT_0 PROBE(~)\n#define COMPL(b) CAT(COMPL_, b)\n#define COMPL_0 1\n#define COMPL_1 0\n#define BOOL(x) COMPL(NOT(x))\n#define IF(c) IIF(BOOL(c))\n#define DEC(x) CAT(DEC_, x)\n#define DEC_1 0\n#define DEC_2 1\n#define DEC_3 2\n#define DEC_4 3\n#define WHEN(c) IF(c)(EXPAND, EAT)\n#define EAT(...)\n#define COUNTDOWN(n) n WHEN(n)(OBSTRUCT(COUNTDOWN_INDIRECT)()(DEC(n)))\n#define COUNTDOWN_INDIRECT() COUNTDOWN\n"
    t |> equal(expanded("{DEFER_DEFS}{cloak}EVAL(COUNTDOWN(4))\n").out, "4 3 2 1 0")
    let boost = "#define PP_CAT(a, b) PP_CAT_I(a, b)\n#define PP_CAT_I(a, b) a ## b\n#define PP_INC(x) PP_CAT(PP_INC_, x)\n#define PP_INC_0 1\n#define PP_INC_1 2\n#define PP_INC_2 3\n#define PP_REPEAT(n, m) PP_CAT(PP_REPEAT_, n)(m)\n#define PP_REPEAT_0(m)\n#define PP_REPEAT_1(m) PP_REPEAT_0(m) m(0)\n#define PP_REPEAT_2(m) PP_REPEAT_1(m) m(1)\n#define PP_REPEAT_3(m) PP_REPEAT_2(m) m(2)\n#define DECL(n) int PP_CAT(x, n) = PP_INC(n);\n"
    t |> equal(expanded("{boost}PP_REPEAT(3, DECL)\n").out, "int x0 = 1 ; int x1 = 2 ; int x2 = 3 ;")
}

[test(description = "metalang99-style recursion through a trampoline of deferred calls keeps the context stack and the pools flat")]
def test_flat_memory(t : T?) {
    let defs = "{DEFER_DEFS}#define EVAL(...) EVAL1(EVAL1(EVAL1(EVAL1(__VA_ARGS__))))\n#define EVAL1(...) EVAL2(EVAL2(EVAL2(EVAL2(__VA_ARGS__))))\n#define EVAL2(...) EVAL3(EVAL3(EVAL3(EVAL3(__VA_ARGS__))))\n#define EVAL3(...) __VA_ARGS__\n#define LOOP(n) n DEFER(LOOP_INDIRECT)()(n)\n#define LOOP_INDIRECT() LOOP\n"
    let all <- [("main.c", "{defs}EVAL(LOOP(7))\n")]
    var pp <- started(all)
    var count = 0
    var pool = 0
    while (pp_next_token(pp)) {
        count++
        pool = max(pool, length(pp.expansion.text))
    }
    t |> equal(count, 92)
    t |> equal(diagnostics(pp), "")
    t |> success(pool < 64, "{pool}")
    t |> equal(length(pp.expansion.calls), 428)
}

[test(description = "the examples of C11 6.10.3.5 (1 to 7), 6.10.3.3 and 6.10.3.4, as the standard spells them")]
def test_c11_examples(t : T?) {
    t |> equal(expanded("#define hash_hash # ## #\n#define mkstr(a) # a\n#define in_between(a) mkstr(a)\n#define join(c, d) in_between(c hash_hash d)\nchar p[] = join(x, y);\n").out,
               "char p [ ] = \"x ## y\" ;")
    t |> equal(expanded("#define TABSIZE 100\nint table[TABSIZE];\n").out, "int table [ 100 ] ;")
    t |> equal(expanded("#define max(a, b) ((a) > (b) ? (a) : (b))\nmax(x, y)\n").out, "( ( x ) > ( y ) ? ( x ) : ( y ) )")
    let ex3 = "#define x 3\n#define f(a) f(x * (a))\n#undef x\n#define x 2\n#define g f\n#define z z[0]\n#define h g(~\n#define m(a) a(w)\n#define w 0,1\n#define t(a) a\n#define p() int\n#define q(x) x\n#define r(x,y) x ## y\n#define str(x) # x\nf(y+1) + f(f(z)) % t(t(g)(0) + t)(1);\ng(x+(3,4)-w) | h 5) & m\n(f)^m(m);\np() i[q()] = \{ q(1), r(2,3), r(4,), r(,5), r(,) \};\nchar c[2][6] = \{ str(hello), str() \};\n"
    t |> equal(expanded(ex3).out, "f ( 2 * ( y + 1 ) ) + f ( 2 * ( f ( 2 * ( z [ 0 ] ) ) ) ) % f ( 2 * ( 0 ) ) + t ( 1 ) ; | f ( 2 * ( 2 + ( 3 , 4 ) - 0 , 1 ) ) | f ( 2 * ( ~ 5 ) ) & f ( 2 * ( 0 , 1 ) ) ^ m ( 0 , 1 ) ; | int i [ ] = \{ 1 , 23 , 4 , 5 , \} ; | char c [ 2 ] [ 6 ] = \{ \"hello\" , \"\" \} ;")
    let ex4 = "#define str(s) # s\n#define xstr(s) str(s)\n#define debug(s, t) printf(\"x\" # s \"= %d, x\" # t \"= %s\", \\\n x ## s, x ## t)\n#define INCFILE(n) vers ## n\n#define glue(a, b) a ## b\n#define xglue(a, b) glue(a, b)\n#define HIGHLOW \"hello\"\n#define LOW LOW \", world\"\ndebug(1, 2);\nfputs(str(strncmp(\"abc\\0d\", \"abc\", '\\4') // this goes away\n == 0) str(: @\\n), s);\n#include xstr(INCFILE(2).h)\nglue(HIGH, LOW);\nxglue(HIGH, LOW)\n"
    t |> equal(expanded(ex4, [("vers2.h", "vers2_h\n")]).out, "printf ( \"x\" \"1\" \"= %d, x\" \"2\" \"= %s\" , x1 , x2 ) ; | fputs ( \"strncmp(\\\"abc\\\\0d\\\", \\\"abc\\\", '\\\\4') == 0\" \": @\\n\" , s ) ; | vers2_h | \"hello\" ; | \"hello\" \", world\"")
    let ex6 = "#define OBJ_LIKE (1-1)\n#define OBJ_LIKE /* white space */ (1-1) /* other */\n#define FUNC_LIKE(a) ( a )\n#define FUNC_LIKE( a )( /* note the white space */ \\\n a /* other stuff on this line\n */ )\n#define OBJ_LIKE (0)\n#define OBJ_LIKE (1 - 1)\n#define FUNC_LIKE(b) ( a )\n#define FUNC_LIKE(b) ( b )\n"
    t |> equal(expanded(ex6).diags, "W 7:2 'OBJ_LIKE' macro redefined | W 8:2 'OBJ_LIKE' macro redefined | W 9:2 'FUNC_LIKE' macro redefined | W 10:2 'FUNC_LIKE' macro redefined")
    let ex7 = "#define debug(...) fprintf(stderr, __VA_ARGS__)\n#define showlist(...) puts(#__VA_ARGS__)\n#define report(test, ...) ((test)?puts(#test):\\\n printf(__VA_ARGS__))\ndebug(\"Flag\");\ndebug(\"X = %d\\n\", x);\nshowlist(The first, second, and third items.);\nreport(x>y, \"x is %d but y is %d\", x, y);\n"
    t |> equal(expanded(ex7).out, "fprintf ( stderr , \"Flag\" ) ; | fprintf ( stderr , \"X = %d\\n\" , x ) ; | puts ( \"The first, second, and third items.\" ) ; | ( ( x > y ) ? puts ( \"x>y\" ) : printf ( \"x is %d but y is %d\" , x , y ) ) ;")
    t |> equal(expanded("#define f(a) a*g\n#define g(a) f(a)\nf(2)(9)\n").out, "2 * 9 * g")
}

[test(description = "__LINE__ is the presumed line of the end of the outermost call (its ), clang's rule), or of the name read in an argument; __FILE__ the presumed name, escaped")]
def test_line_and_file(t : T?) {
    t |> equal(expanded("#define f(x,y) x+y __LINE__\na f(1,\n2) b __LINE__\nf\n(3,4) e __LINE__\n").out, "a 1 + 2 3 b 3 | 3 + 4 5 e 5")
    t |> equal(expanded("#define id(x) x\n#define L2 __LINE__\nid(__LINE__\n__LINE__) __LINE__\nid(\nL2\n)\n").out, "3 4 4 | 6")
    t |> equal(expanded("__FILE__ __FILE_NAME__\n#line 100 \"dir/x\\\\y.c\"\n__LINE__ __FILE__ __FILE_NAME__\n").out, "\"main.c\" \"main.c\" | 100 \"dir/x\\\\y.c\" \"x\\\\y.c\"")
}

[test(description = "__COUNTER__ counts from 0, __INCLUDE_LEVEL__ the files open below the current, __BASE_FILE__ the main file, and __DATE__, __TIME__, __TIMESTAMP__ the start's time in UTC")]
def test_builtins(t : T?) {
    let r = expanded("__COUNTER__ __COUNTER__ __INCLUDE_LEVEL__\n#include \"h.h\"\n__DATE__ __TIME__ __TIMESTAMP__\n", [("h.h", "__INCLUDE_LEVEL__ __BASE_FILE__ __FILE__ __COUNTER__\n")])
    t |> equal(r.out, "0 1 0 | 1 \"main.c\" \"h.h\" 2 | \"Sep  9 2001\" \"01:46:40\" \"Sun Sep  9 01:46:40 2001\"")
    t |> equal(expanded("#define __LINE__ mine\n__LINE__\n").out, "mine")
    for (epoch, shown in [951782400l, 0l], ["\"Feb 29 2000\" \"00:00:00\" \"Tue Feb 29 00:00:00 2000\"", "\"Jan  1 1970\" \"00:00:00\" \"Thu Jan  1 00:00:00 1970\""]) {
        var mem = new PpMemoryProvider()
        mem->add("main.c", "__DATE__ __TIME__ __TIMESTAMP__\n")
        var pp : Preprocessor
        pp_expand_start(pp, mem, "main.c", array<string>(), array<string>(), epoch)
        t |> equal(stream(pp), shown)
    }
}

[test(description = "_Pragma's destringized operand is done as a #pragma line (C11 6.10.9): into the ledgers, once marking the file, the next token starting a line")]
def test_pragma_operator(t : T?) {
    let all <- [("main.c", "#define LISTING(x) PRAGMA(listing on #x)\n#define PRAGMA(x) _Pragma(#x)\nLISTING ( ..\\listing.dir ) a _Pragma(\"pack(push, 2)\") b _Pragma(L\"foo \\\"bar\\\" \\\\x\")\n")]
    var pp <- started(all)
    t |> equal(stream(pp), "a | b")
    t |> equal(join([for (p in pp.pragmas); p.text], " / "), "listing on \"..\\listing.dir\" / foo \"bar\" \\x")
    t |> equal(length(pp.packs), 1)
    t |> equal(pp.packs[0].current, 2)
    t |> equal(expanded("_Pragma(once) x\n").diags, "E 1:1 _Pragma takes a parenthesized string literal")
}

[test(description = "the macros of #include and #line are expanded: a string literal, or < ... > rebuilt with a blank where a token had space")]
def test_include_and_line_operands(t : T?) {
    let files <- [("a.h", "in_a\n"), ("vers2.h", "in_vers2\n")]
    let r = expanded("#define HDR \"a.h\"\n#include HDR\n#define str(s) #s\n#define xstr(s) str(s)\n#define V(n) vers ## n.h\n#include xstr(V(2))\n#define LN 50\n#line LN\n__LINE__\n#line LN \"n.c\"\n__FILE__\n", files)
    t |> equal(r.out, "in_a | in_vers2 | 50 | \"n.c\"")
    t |> equal(r.diags, "")
    let spaced = expanded("#define LT <\n#include LT a.h >\nnot_reached\n", files)
    t |> equal(spaced.out, "")
    t |> equal(spaced.diags, "F 2:2 ' a.h ' file not found; searched: ")
    let none = expanded("#define NONE\n#include NONE\nx\n", files)
    t |> equal(none.out, "x")
    t |> equal(none.diags, "E 2:2 expected \"FILENAME\" or <FILENAME>")
    t |> equal(expanded("#define HUGE 4294967296\n#line HUGE\n").diags, "E 2:2 #line directive requires a positive integer argument")
    t |> equal(expanded("#define BIG 4294967295\n#line BIG\n__LINE__\n").out, "4294967295")
}

[test(description = "an #if line is expanded with defined's operand left as written, in both spellings")]
def test_condition_lines(t : T?) {
    t |> equal(expanded("#define ONE 1\n#define EMPTY\n#if ONE\na\n#endif\n#if defined EMPTY\nb\n#endif\n#if defined(EMPTY)\nc\n#endif\n#define D defined(ONE)\n#if D\nd\n#endif\n").out, "a | b | c | d")
}

[test(description = "the predefined entries and the import's defines are macros before the first line")]
def test_predefined(t : T?) {
    let all <- [("main.c", "__GNUC__ SQ(3) X\n")]
    var pp <- started(all, ["__GNUC__=4", "SQ(x)=((x)*(x))", "X"])
    t |> equal(stream(pp), "4 ( ( 3 ) * ( 3 ) ) 1")
}

[test(description = "the call record for PP.5: each token's spelling place and call, each call's macro, name, parent call, presumed end line and argument spans")]
def test_call_record(t : T?) {
    let all <- [("main.c", "#define g(a) [a]\n#define f(x, y) g(x) y\nf(ab,\n  cd e) z\n")]
    var pp <- started(all)
    var toks : array<string>
    while (pp_next_token(pp)) {
        toks |> push("{pp_token_spelling(pp)}@{pp.tok.tok.line}:{pp.tok.tok.col}#{pp.tok.call}/{int64(pp.tok.pline)}")
    }
    t |> equal(join(toks, " "), "[@1:14#1/3 ab@3:3#1/3 ]@1:16#1/3 cd@4:3#0/3 e@4:6#0/3 z@4:9#-1/4")
    let calls & = unsafe(pp.expansion.calls)
    t |> equal(length(calls), 2)
    t |> equal("{pp_name(pp, pp.macros[calls[0].macro].name)} {calls[0].name.line}:{calls[0].name.col} parent {calls[0].parent} end {int64(calls[0].end_pline)} args {calls[0].arg_count}", "f 3:1 parent -1 end 4 args 2")
    t |> equal("{pp_name(pp, pp.macros[calls[1].macro].name)} {calls[1].name.line}:{calls[1].name.col} parent {calls[1].parent} end {int64(calls[1].end_pline)} args {calls[1].arg_count}", "g 2:17 parent 0 end 4 args 1")
    let a0 = pp.expansion.call_args[calls[0].first_arg]
    let a1 = pp.expansion.call_args[calls[0].first_arg + 1]
    t |> equal("{a0.from}-{a0.to} {a1.from}-{a1.to}", "{length("#define g(a) [a]\n#define f(x, y) g(x) y\nf(")}-{length("#define g(a) [a]\n#define f(x, y) g(x) y\nf(ab")} {length("#define g(a) [a]\n#define f(x, y) g(x) y\nf(ab,\n  ")}-{length("#define g(a) [a]\n#define f(x, y) g(x) y\nf(ab,\n  cd e")}")
    t |> equal(pp.expansion.call_args[calls[1].first_arg].from, -1)
}

[test(description = "every spelling place is readable after the token: a source argument kept through a call, a body token, a pasted name by its symbol, a stringified token in the pool until the next read")]
def test_spelling_places(t : T?) {
    var pp <- started([("main.c", "#define F(x) x body a ## b #x\nF(arg)\n")])
    var kept : array<PpOutToken>
    var now : array<string>
    while (pp_next_token(pp)) {
        kept |> push(pp.tok)
        let span = pp_token_span(pp)
        now |> push(build_string() $(var out) {
            for (i in range(span.len)) {
                out |> write_char(int(unsafe(span.data[i])))
            }
        })
    }
    t |> equal(join(now, " "), "arg body ab \"arg\"")
    t |> equal(join([for (k in kept); "{k.spelled}"], " "), "source body symbol scratch")
    t |> equal(join([for (k in kept); k.spelled == PpSpelled.scratch ? "-" : pp_spelling_of(pp, k)], " "), "arg body ab -")
}

// each token handed out for `main.c` holding `text`, spelled, at its line and column
def private token_places(text : string) : string {
    var pp <- started([("main.c", text)])
    var toks : array<string>
    while (pp_next_token(pp)) {
        toks |> push("{pp_token_spelling(pp)}@{pp.tok.tok.line}:{pp.tok.tok.col}")
    }
    return join(toks, " ")
}

[test(description = "an argument is macro-expanded once however often its parameter is used: a __COUNTER__ in it counts once (C11 6.10.3.1, as clang)")]
def test_argument_expanded_once(t : T?) {
    t |> equal(expanded("#define TWICE(x) x x\nTWICE(__COUNTER__) __COUNTER__\n").out, "0 0 1")
}

[test(description = "calls nested in arguments deeper than the invocation slots made at the start grow the slots")]
def test_deep_argument_nesting(t : T?) {
    let text = "#define id(x) x\n" + repeat("id(", 24) + "1" + repeat(")", 24)
    let r = expanded("{text}\n")
    t |> equal(r.out, "1")
    t |> equal(r.diags, "")
}

[test(description = "clang's leading-space rule seen through # of a macro's result: an empty expansion passes its space on, the first token of a replacement takes the name's, an operand of ## the parameter's, an empty argument or __VA_OPT__ passes its space to the next token")]
def test_spacing_through_stringify(t : T?) {
    let defs = "#define str(s) #s\n#define xstr(s) str(s)\n"
    t |> equal(expanded("{defs}#define E\nxstr(x E+y)\n").out, "\"x +y\"")
    t |> equal(expanded("{defs}#define N x\nxstr(+N)\n").out, "\"+x\"")
    t |> equal(expanded("{defs}#define G(x) [ x ## y ]\nxstr(G(a))\n").out, "\"[ ay ]\"")
    t |> equal(expanded("{defs}#define F(x,y) [ x#y]\nxstr(F(,b))\n").out, "\"[ \\\"b\\\"]\"")
    t |> equal(expanded("{defs}#define V(...) [ __VA_OPT__(a)x]\nxstr(V())\n").out, "\"[ x]\"")
    t |> equal(expanded("{defs}#define F(x) [ x]\nxstr(F())\n").out, "\"[ ]\"")
}

[test(description = "a placemarker stands for an empty operand of ##: no paste error comes from the token before it, and the token pasted onto it keeps its own place")]
def test_placemarker_keeps_place(t : T?) {
    let r = expanded("#define C2(a,b) [a##b]\nC2(,z)\n")
    t |> equal(r.out, "[ z ]")
    t |> equal(r.diags, "")
    t |> equal(token_places("#define C2(a,b) [a##b]\nC2(,z)\n"), "[@1:17 z@2:5 ]@1:22")
    t |> equal(token_places("#define P2(a) a ## x\nP2()\n"), "x@1:20")
}

[test(description = "the GNU comma rule is for the variadic parameter only: , ## before a named parameter pastes, with clang's error")]
def test_gnu_comma_named_parameter(t : T?) {
    t |> equal(expanded("#define M(a, ...) [x , ## a]\nM(b,1)\n").diags, "E 1:22 pasting formed ',b', an invalid preprocessing token")
}

[test(description = "the call record: f() of a macro of no parameter has no argument; a replacement's tokens report the call's presumed file; an argument spelled across a file's end, or backwards in one file, has no span")]
def test_call_record_edges(t : T?) {
    var pp <- started([("main.c", "#define z() Z\nz()\n")])
    t |> equal(stream(pp), "Z")
    t |> equal(pp.expansion.calls[0].arg_count, 0)
    var named <- started([("main.c", "#line 5 \"other.c\"\n#define A x\nA\n")])
    t |> success(pp_next_token(named))
    t |> equal(named.names[named.tok.pname], "other.c")
    var crossing <- started([("main.c", "#define f(x) [x]\n#include \"h.h\"\nb)\n"), ("h.h", "f(aaaa\n")])
    t |> equal(stream(crossing), "[ aaaa b ]")
    t |> equal(crossing.expansion.call_args[0].from, -1)
    var reversed <- started([("main.c", "#ifndef ONCE\n#define ONCE\n#define f(x) [x]\n#include \"main.c\"\nb)\n#else\nf(a\n#endif\n")])
    t |> equal(stream(reversed), "[ a b ]")
    t |> equal(reversed.expansion.call_args[0].from, -1)
}

[test(description = "__FILE__ escapes a double quote of the presumed name; with no epoch given, __DATE__ shows the start's time, not 1970")]
def test_builtin_edges(t : T?) {
    t |> equal(expanded("#line 7 \"q\\\"t.c\"\n__FILE__\n").out, "\"q\\\"t.c\"")
    var mem = new PpMemoryProvider()
    mem->add("main.c", "__DATE__\n")
    var pp : Preprocessor
    pp_expand_start(pp, mem, "main.c", array<string>(), array<string>())
    t |> success(pp_next_token(pp))
    let date = pp_token_spelling(pp)
    let year = to_int(slice(date, length(date) - 5, length(date) - 1))
    t |> success(year >= 2025, date)
}

[test(description = "_Pragma's operand keeps a backslash before any character but \\ and \"; malformed, it is clang's error and the token read in place of the (, the string or the ) is handed out, as clang recovers")]
def test_pragma_operator_edges(t : T?) {
    var pp <- started([("main.c", "_Pragma(\"a\\nb\") z\n")])
    t |> equal(stream(pp), "z")
    t |> equal(join([for (p in pp.pragmas); p.text], " / "), "a\\nb")
    let malformed = "E 1:1 _Pragma takes a parenthesized string literal"
    for (text, out in ["_Pragma(\"x\" y) z\n", "_Pragma \"x\" z\n", "_Pragma x \"y\") z\n", "_Pragma(once) x\n", "_Pragma() x\n", "_Pragma(a\nb) x\n", "_Pragma(\"x\"", "_Pragma"],
                      ["y ) z", "\"x\" z", "x \"y\" ) z", "x", "x", "b ) x", "", ""]) {
        let r = expanded(text)
        t |> equal(r.out, out, text)
        t |> equal(r.diags, malformed, text)
    }
}

[test(description = "in an #if line an argument ending with defined does not swallow the replacement's next token: F(defined) X reads as defined X, as clang reads it")]
def test_defined_from_argument(t : T?) {
    t |> equal(expanded("#define X 1\n#define F(x) x\n#if F(defined) X\nyes\n#else\nno\n#endif\n").out, "yes")
}

[test(description = "a pragma's place in the stream counts the tokens handed out: an expansion's tokens, not the call's")]
def test_pragma_place_counts_expanded_tokens(t : T?) {
    var pp <- started([("main.c", "#define F(x) x x x\nF(1)\n#pragma pack(2)\nF(2)\n#pragma foo\n")])
    t |> equal(stream(pp), "1 1 1 | 2 2 2")
    t |> equal(pp.packs[0].emitted, 3)
    t |> equal(pp.pragmas[0].emitted, 6)
}

[test(description = "an #elif line is expanded as an #if line is")]
def test_elif_line(t : T?) {
    t |> equal(expanded("#define ONE 1\n#if 0\n#elif ONE\nel\n#endif\n").out, "el")
}

[test(description = "a macro-built #include or #line refused or warned as clang does: a prefixed literal is no file name, a < with no > expects one, extra tokens warn, #import keeps its once-only reading; a #line number that is no number or no simple digit sequence, a file name that is no plain string, extra tokens")]
def test_include_and_line_operand_errors(t : T?) {
    let files <- [("a.h", "in_a\n")]
    t |> equal(expanded("#define LH L\"a.h\"\n#include LH\nx\n", files).diags, "E 2:2 expected \"FILENAME\" or <FILENAME>")
    let open = expanded("#define LT <\n#include LT a.h\nx\n", files)
    t |> equal(open.out, "x")
    t |> equal(open.diags, "E 2:2 expected '>'")
    let extra = expanded("#define H \"a.h\" extra\n#include H\n", files)
    t |> equal(extra.out, "in_a")
    t |> equal(extra.diags, "W 2:2 extra tokens at end of #include directive")
    t |> equal(expanded("#define HDR \"a.h\"\n#import HDR\n#import HDR\n", files).out, "in_a")
    t |> equal(expanded("#define X 0x10\n#line X\n").diags, "E 2:2 #line directive requires a simple digit sequence")
    t |> equal(expanded("#define X abc\n#line X\n").diags, "E 2:2 #line directive requires a positive integer argument")
    t |> equal(expanded("#define X\n#line X\n").diags, "E 2:2 #line directive requires a positive integer argument")
    t |> equal(expanded("#line \"x\"\n").diags, "E 1:7 #line directive requires a positive integer argument")
    t |> equal(expanded("#define X 5 n\n#line X\n").diags, "E 2:2 invalid filename for #line directive")
    let more = expanded("#define X 5 \"a.c\" b\n#line X\n__LINE__ __FILE__\n")
    t |> equal(more.out, "5 \"a.c\"")
    t |> equal(more.diags, "W 2:2 extra tokens at end of #line directive")
}

[test(description = "the spelling pool is emptied between tokens read at the top level: stringified and pasted tokens between source tokens do not grow it with the unit")]
def test_pool_reused(t : T?) {
    let text = "#define str(x) #x\n#define cat(a,b) a##b\n" + repeat("str(abc) ; ; cat(+,=) ; ; ", 200)
    var pp <- started([("main.c", text)])
    var pool = 0
    var count = 0
    while (pp_next_token(pp)) {
        count++
        pool = max(pool, length(pp.expansion.text))
    }
    t |> equal(count, 1200)
    t |> success(pool < 64, "{pool}")
}

[test(description = "the spelling pool stays flat over back-to-back expansions that stringify and paste")]
def test_pool_flat_back_to_back(t : T?) {
    let text = "#define str(x) #x\n#define cat(a,b) a##b\n" + repeat("str(abc) cat(+,=) ", 200)
    var pp <- started([("main.c", text)])
    var pool = 0
    var count = 0
    while (pp_next_token(pp)) {
        count++
        pool = max(pool, length(pp.expansion.text))
    }
    t |> equal(count, 400)
    t |> success(pool < 64, "{pool}")
}

[test(description = "a paste forming a name the unit already spelled allocates no string: a run of letters, digits and _ is classed without the lexer")]
def test_paste_name_allocates_no_string(t : T?) {
    let text = "#define cat(a,b) a##b\nxy\n" + repeat("cat(x,y) ", 200)
    var pp <- started([("main.c", text)])
    t |> success(pp_next_token(pp))
    let before = int(string_heap_allocation_count())
    var count = 0
    while (pp_next_token(pp)) {
        count++
    }
    t |> equal(count, 200)
    t |> equal(int(string_heap_allocation_count()) - before, 0)
}

// the pragma ledger of `main.c` holding `text`: each pragma's text and pack entry's alignment at the
// count of tokens handed out before it, in the order done, then the stream
def private pragma_places(text : string) : string {
    var pp <- started([("main.c", text)])
    let out = stream(pp)
    var places <- [for (p in pp.pragmas); (p.emitted, p.text)]
    places |> push_from([for (p in pp.packs); (p.emitted, "pack {p.current}")])
    sort(places) <| cmp_by(_._0)
    let ledger = join([for (p in places); "{p._1}@{p._0}"], " / ")
    return "{ledger} || {out}"
}

[test(description = "_Pragma's operand is read with macro expansion, as clang reads it: a macro naming the string, or one that stringifies it")]
def test_pragma_operand_expanded(t : T?) {
    t |> equal(pragma_places("#define STRINGIFY(a) #a\n#define DIAG(x) _Pragma(STRINGIFY(GCC diagnostic x))\nDIAG(push) y1\n"), "GCC diagnostic push@0 || y1")
    t |> equal(pragma_places("#define S \"pack(1)\"\na _Pragma(S) z\n"), "pack 1@1 || a | z")
    t |> equal(expanded("#define S \"pack(1)\"\n_Pragma(S) z\n").diags, "")
}

[test(description = "_Pragma in a macro argument is done at the rescan, at its place in the stream (C11 6.10.3.4p3): once per use of the argument, the token after it starting a line, none in an argument # or ## takes as written")]
def test_pragma_in_argument(t : T?) {
    let wrap = "#define WRAP(x) x\nWRAP(struct A\{char c; int i;\}; _Pragma(\"pack(1)\") struct B\{char c; int i;\};)\n"
    t |> equal(pragma_places(wrap), "pack 1@11 || struct A \{ char c ; int i ; \} ; | struct B \{ char c ; int i ; \} ;")
    t |> equal(pragma_places("#define TWICE(x) x x\nTWICE(_Pragma(\"pack(8)\") a) w\n"), "pack 8@0 / pack 8@1 || a | a w")
    t |> equal(pragma_places("#define WRAP(x) x\nWRAP(a _Pragma(\"pack(1)\") b) c\n"), "pack 1@1 || a | b c")
    t |> equal(pragma_places("#define WRAP(x) x\n#define S \"p\"\nWRAP(a _Pragma(S) b) c\n"), "p@1 || a | b c")
    t |> equal(pragma_places("#define F(x) x\n#define G(x) [x]\nG(F(_Pragma(\"p\")) q) r\n"), "p@1 || [ | q ] r")
    t |> equal(pragma_places("#define S(x) #x\n#define C(x) x ## y\nS(_Pragma(\"p\")) C(_Pragma)\n"), " || \"_Pragma(\\\"p\\\")\" _Pragmay")
    let bad = expanded("#define TWICE(x) x x\nTWICE(_Pragma(once) a) w\n")
    t |> equal(bad.out, "a a w")
    t |> equal(bad.diags, "E 2:7 _Pragma takes a parenthesized string literal")
}

[test(description = "_Pragma in an #if line is done and the rest of the line evaluated, as clang does")]
def test_pragma_in_condition(t : T?) {
    let r = expanded("#if _Pragma(\"x\") 1\nyes\n#endif\n")
    t |> equal(r.out, "yes")
    t |> equal(r.diags, "")
    t |> equal(pragma_places("#if _Pragma(\"x\") 1\nyes\n#endif\n"), "x@0 || yes")
}

[test(description = "a name of a macro disabled when a call's arguments read it is painted for good (C11 6.10.3.4p2), though the read leaves that macro's replacement")]
def test_disabled_names_painted_in_arguments(t : T?) {
    let k = expanded("#define k(x) x\n#define kk k(kk\nkk 1);\n")
    t |> equal(k.out, "kk 1 ;")
    t |> equal(k.diags, "")
    t |> equal(expanded("#define k(x) x\n#define m(a) k(m(a)\nm(1)) ;\n").out, "m ( 1 ) ;")
}

[test(description = "the call record grows geometrically: many calls make few heap blocks, not one per call")]
def test_call_record_allocations(t : T?) {
    let text = "#define cat(a,b) a##b\nxy\n" + repeat("cat(x,y) ", 2000)
    var pp <- started([("main.c", text)])
    t |> success(pp_next_token(pp))
    let heap = int(heap_allocation_count())
    var count = 0
    while (pp_next_token(pp)) {
        count++
    }
    let used = int(heap_allocation_count()) - heap
    t |> equal(count, 2000)
    t |> success(used <= 64, "{used} heap blocks over {count} calls")
}

[test(description = "a builtin's value and a paste that is no name are spelled in the pool: no string is made per token")]
def test_builtins_and_pastes_allocate_no_string(t : T?) {
    let line = "__LINE__ __COUNTER__ __FILE__ __FILE_NAME__ __DATE__ __TIME__ __TIMESTAMP__ __INCLUDE_LEVEL__ __BASE_FILE__ cat(+,=) cat(L,\"s\") ;\n"
    let text = "#define cat(a,b) a##b\nfirst\n" + repeat(line, 200)
    var pp <- started([("main.c", text)])
    t |> success(pp_next_token(pp))
    let strings = int(string_heap_allocation_count())
    var count = 0
    while (pp_next_token(pp)) {
        count++
    }
    t |> equal(count, 2400)
    t |> equal(int(string_heap_allocation_count()) - strings, 0)
}

[test(description = "in an #if line the < ... > of __has_include and __has_include_next is left as written, as defined's operand is; other operands, __has_attribute's among them, are expanded as clang does")]
def test_has_include_operand(t : T?) {
    let defs = "#define linux 1\n#define HDR <stddef.h>\n"
    t |> equal(expanded("{defs}#if __has_include(<linux/version.h>) && linux\nyes\n#endif\n").diags, "")
    t |> equal(expanded("{defs}#if __has_include_next( <linux/x.h> )\n#endif\n").diags, "")
    t |> equal(expanded("{defs}#if __has_include(HDR) + __has_attribute(linux)\n#endif\n").diags, "E 1:15 builtin feature check macro requires a parenthesized identifier")
    t |> equal(expanded("{defs}#if __has_include linux\n#endif\n").diags, "E 3:5 missing '(' after '__has_include'")
}

[test(description = "the < ... > of __has_include is a header name as written: a macro named like a path part is expanded next to it but not inside it, so the header is still found")]
def test_has_include_angled_operand_unexpanded(t : T?) {
    var mem = new PpMemoryProvider()
    mem->add("main.c", "#define linux 1\n#if __has_include(<linux/x.h>) && linux\nyes\n#endif\n")
    mem->add("inc/linux/x.h", "")
    var pp : Preprocessor
    pp_expand_start(pp, mem, "main.c", array<string>(), array<string>("inc"), 1000000000l)
    t |> equal(stream(pp), "yes")
    t |> equal(diagnostics(pp), "")
}

[test(description = "the operand of __has_feature, __has_builtin, __has_warning and __is_target_os stays as written, as clang reads it unexpanded")]
def test_query_operand_unexpanded(t : T?) {
    let defs = "#define linux 1\n#define c_atomic nope\n#define W \"-Wunused\"\n"
    t |> equal(expanded("{defs}#if __is_target_os(linux)\nos\n#endif\n#if __has_feature(c_atomic)\nfeature\n#endif\n").diags, "")
    t |> equal(expanded("{defs}#if __has_warning(W)\n#endif\n").diags, "E 4:19 expected string literal in '__has_warning'")
    t |> equal(expanded("#define B __builtin_expect\n#if __has_builtin(B) || __has_builtin B\n#endif\n").diags, "E 2:25 missing '(' after '__has_builtin'")
}

[test(description = "an include guard is the #if !defined X a file writes: one a macro produces is no guard, so a second #include reads the file again as clang does")]
def test_guard_from_macro(t : T?) {
    let header = "#if NOT_DEFINED\n#ifdef VAR\nVAR++;\n#endif\n#endif\n"
    let main = "#define NOT_DEFINED ! defined (guard)\n#include \"g.h\"\n#define guard\n#undef NOT_DEFINED\n#define NOT_DEFINED 1\n#define VAR five\n#include \"g.h\"\n"
    t |> equal(expanded(main, [("g.h", header)]).out, "five ++ ;")
}

[test(description = "a #line whose number and name come from macros, a function-like one among them, is expanded first as clang does; the name's escapes are read once")]
def test_line_operands_from_macros(t : T?) {
    let r = expanded("#define LN(n) n\n#define NAME \"d\\\\x.c\"\n#line LN(7) NAME\n__LINE__ __FILE__\n")
    t |> equal(r.out, "7 \"d\\\\x.c\"")
    t |> equal(r.diags, "")
}

[test(description = "an argument in an #if line is pre-expanded before defined reads it, as clang does: F(defined X) of a defined X hands the evaluator defined 1, clang's error there")]
def test_defined_in_argument(t : T?) {
    let r = expanded("#define X 1\n#define F(x) x\n#if F(defined X)\nyes\n#endif\nend\n")
    t |> equal(r.out, "end")
    t |> equal(r.diags, "E 1:11 macro name must be an identifier")
    t |> equal(expanded("#define F(x) x\n#if F(defined X)\nyes\n#else\nno\n#endif\n").out, "no")
}

[test(description = "__VA_OPT__ in a macro that is not variadic is clang's warning at the #define; in a function-like macro it is empty, # of it is \"\"; in an object-like one it stays")]
def test_va_opt_not_variadic(t : T?) {
    let r = expanded("#define V(x) [__VA_OPT__(x) x]\n#define W(x,y) #__VA_OPT__(x) y\n#define O __VA_OPT__(x) z\nV(1) W(1,2) O\n")
    t |> equal(r.out, "[ 1 ] \"\" 2 __VA_OPT__ ( x ) z")
    t |> equal(r.diags, "W 1:15 __VA_OPT__ can only appear in the expansion of a variadic macro | W 2:17 __VA_OPT__ can only appear in the expansion of a variadic macro | W 3:11 __VA_OPT__ can only appear in the expansion of a variadic macro")
}

[test(description = "# drops a final unescaped backslash of its string with clang's warning; an escaped one stays")]
def test_stringify_final_backslash(t : T?) {
    let r = expanded("#define q(x) #x\nq(\\) q(a \\) q('\\\\') r\n")
    t |> equal(r.out, "\"\" \"a \" \"'\\\\\\\\'\" r")
    t |> equal(r.diags, "W 2:3 invalid string literal, ignoring final '\\' | W 2:10 invalid string literal, ignoring final '\\'")
}

[test(description = "a directive line between a function-like macro's name and a ( ends the lookahead: the name is no call, as clang's -E reads it; blank lines do not")]
def test_directive_before_lparen(t : T?) {
    t |> equal(expanded("#define g(x) [x]\ng\n#define Q\n(2)\n").out, "g | ( 2 )")
    t |> equal(expanded("#define g(x) [x]\n#define G g\nG\n#if 1\n#endif\n(2) end\n").out, "g | ( 2 ) end")
    t |> equal(expanded("#define g(x) [x]\ng\n\n(2)\n").out, "[ 2 ]")
}

[test(description = "a #define or #undef of a builtin name no macro defines is clang's warning; an #undef removes the builtin, a #define and #undef of one leave the name")]
def test_builtin_undef(t : T?) {
    let r = expanded("#undef __LINE__\n__LINE__ __FILE__\n#undef _Pragma\n_Pragma(\"x\") z\n")
    t |> equal(r.out, "__LINE__ \"main.c\" | _Pragma ( \"x\" ) z")
    t |> equal(r.diags, "W 1:8 undefining builtin macro | W 3:8 undefining builtin macro")
    let d = expanded("#define __LINE__ 5\n__LINE__\n#undef __LINE__\n__LINE__\n#define __has_include x\n#undef __COUNTER__\n#undef NOT_DEFINED\n")
    t |> equal(d.out, "5 | __LINE__")
    t |> equal(d.diags, "W 1:9 redefining builtin macro | W 5:9 redefining builtin macro | W 6:8 undefining builtin macro")
}


// every diagnostic, `<line>:<col> raised <file>:<offset>:<line>:<col> <what>`, a `|` between them
def private raised(pp : Preprocessor) : string {
    let parts <- [for (d in pp.diags); "{d.line}:{d.col} raised {d.raised.file}:{d.raised.offset}:{d.raised.line}:{d.raised.col} {d.what}"]
    return join(parts, " | ")
}

[test(description = "an unterminated call is placed at its name and raised where the reader gave up: past the last byte of the unit, through a line splice, or at the token after the directive line that ends it; a diagnostic the reader meets at once is raised at the token read, the call's )")]
def test_unterminated_call_raised_at_end(t : T?) {
    var at_end <- started([("main.c", "#define f(x) x\na f(1,\n 2")])
    stream(at_end)
    t |> equal(raised(at_end), "2:3 raised 0:24:3:3 unterminated function-like macro invocation")
    var spliced <- started([("main.c", "#define f(x) x\nf(1\\\n2\n")])
    stream(spliced)
    t |> equal(raised(spliced), "2:1 raised 0:22:4:1 unterminated function-like macro invocation")
    var splice_line <- started([("main.c", "#define f(x) x\nf(1\\\n2")])
    stream(splice_line)
    t |> equal(raised(splice_line), "2:1 raised 0:21:3:2 unterminated function-like macro invocation")
    var in_line <- started([("main.c", "#define f(x) x\n#line f(\n7)\nz\n")])
    stream(in_line)
    t |> equal(raised(in_line), ("2:7 raised 0:24:3:1 unterminated function-like macro invocation | " +
                                 "2:2 raised 0:24:3:1 #line directive requires a positive integer argument"))
    var at_once <- started([("main.c", "#define z() Z\nz(1) after\n")])
    stream(at_once)
    t |> equal(raised(at_once), "2:1 raised 0:17:2:4 too many arguments provided to function-like macro invocation")
}

[test(description = "a poisoned name pasted is clang's error, and an argument's poisoned name is too; a macro defined before the poison expands to the name with none, _Pragma poisons as #pragma does, and poisoning a builtin name warns")]
def test_poison_through_expansion(t : T?) {
    let r = expanded("#define CAT(a,b) a##b\n#define BEFORE foo + 1\n#define F(x) x\n#pragma GCC poison foo __LINE__\nBEFORE CAT(fo,o) F(foo)\n_Pragma(\"GCC poison q\") q\n")
    t |> equal(r.out, "foo + 1 foo foo | q")
    t |> equal(r.diags, ("W 4:24 poisoning existing macro | E 5:12 attempt to use a poisoned identifier | " +
                         "E 5:20 attempt to use a poisoned identifier | E 6:25 attempt to use a poisoned identifier"))
}

[test(description = "a call records the physical line and column of the ) that closes it, past a line break; a call closed by a ) of a replacement takes the end of the call that handed it out; an object-like macro's end is its name")]
def test_call_end_column(t : T?) {
    var pp <- started([("main.c", "#define g(a) [a]\n#define f(x, y) g(x) y\n#define N 1\nf(ab,\n  cd e  ) N\n")])
    t |> equal(stream(pp), "[ ab ] cd e 1")
    let ends <- [for (c in pp.expansion.calls); "{pp_name(pp, pp.macros[c.macro].name)} {c.end_line}:{c.end_col}/{int64(c.end_pline)}"]
    t |> equal(join(ends, " "), "f 5:9/5 g 5:9/5 N 5:11/5")
}

[test(description = "a _Pragma operand naming a poisoned identifier is clang's error at the _Pragma, as a #pragma line's is at the name")]
def test_poison_in_pragma_operand(t : T?) {
    let r = expanded("#pragma GCC poison foo\n_Pragma(\"weird foo\")\nfoo\n")
    t |> equal(r.diags, "E 2:1 attempt to use a poisoned identifier | E 3:1 attempt to use a poisoned identifier")
}

[test(description = "a diagnostic placed at a held token is raised where the reader stood: past a #pragma GCC warning line at the next line's first token, and past the last byte at the end of the unit")]
def test_held_diagnostic_raised(t : T?) {
    var next <- started([("main.c", "#pragma GCC warning \"w\"\nz\n")])
    stream(next)
    t |> equal(raised(next), "1:13 raised 0:24:2:1 w")
    var last <- started([("main.c", "#pragma GCC warning \"w\"")])
    stream(last)
    t |> equal(raised(last), "1:13 raised 0:23:1:24 w")
}

// every token handed out for `files`, `spelling@line:col` of its expansion place (the spelling place
// for a token of the source)
def private expansion_places(files : array<tuple<string; string>>) : string {
    var pp <- started(files)
    var toks : array<string>
    while (pp_next_token(pp)) {
        let at = pp_expansion_place(pp, pp.tok)
        toks |> push("{pp_token_spelling(pp)}@{at.line}:{at.col}")
    }
    return join(toks, " ")
}

// the text of argument `k` of call `call` as written, through `pp_call_arg_text`
def private arg_text(var pp : Preprocessor; call, k : int) : string {
    var bytes : array<uint8>
    pp_call_arg_text(pp, call, k, bytes)
    return string(bytes)
}

// each call of `pp`: its macro's name, `parent`/`arg_of`.`arg_k`/`outer`, and its arguments' texts
def private call_tree(var pp : Preprocessor) : string {
    var lines : array<string>
    for (c, i in pp.expansion.calls, count()) {
        var inscope args <- [for (k in range(c.arg_count)); arg_text(pp, i, k)]
        lines |> push("{pp_name(pp, pp.macros[c.macro].name)} {c.parent}/{c.arg_of}.{c.arg_k}/{c.outer}{c.in_line ? " line" : ""} ({join(args, "|")})")
    }
    return join(lines, "; ")
}

[test(description = "the expansion place of a token is the place of the outermost call's name, through the calls a name came from and the arguments it was read in; a token of the source has its own; a call of a directive line is marked")]
def test_expansion_place(t : T?) {
    let text = "#define G(y) <y>\n#define F(x) [x]\n#define H(z) F(z) G(z)\n#define OBJ F\na\n  F(G(b)) H(c)\nOBJ(d)\n#if F(1)\n#endif\n"
    t |> equal(expansion_places([("main.c", text)]), "a@5:1 [@6:3 <@6:3 b@6:3 >@6:3 ]@6:3 [@6:11 c@6:11 ]@6:11 <@6:11 c@6:11 >@6:11 [@7:1 d@7:1 ]@7:1")
    var pp <- started([("main.c", text)])
    stream(pp)
    t |> equal(call_tree(pp), "F -1/-1.-1/0 (G(b)); G -1/0.0/0 (b); H -1/-1.-1/2 (c); F 2/-1.-1/2 (z); G 2/-1.-1/2 (z); OBJ -1/-1.-1/5 (); F 5/-1.-1/5 (d); F -1/-1.-1/7 line (1)")
    let spelled = pp_spelling_place(PpOutToken(tok = PpToken(file = 2, offset = 7, line = 3, col = 4)))
    t |> equal("{spelled.file} {spelled.offset} {spelled.line}:{spelled.col}", "2 7 3:4")
}

[test(description = "an argument's text as written: one stretch of a file as the file spells it, splices removed; written in a #define, its body tokens; split by a directive or not one stretch, its tokens as read, a blank where one had space; empty and elided ones give nothing")]
def test_argument_text(t : T?) {
    var pp <- started([("main.c", "#define F(x, y) x y\n#define V(a, ...) a\n#define B(p) F(p ,  q  + 1)\n#define OPEN F(1\nF(  aa  +\n  b\\\nb , ) B(z) V(w) OPEN, 2)\nF(c\n#define N\nd, e)\n")])
    stream(pp)
    t |> equal(call_tree(pp), "F -1/-1.-1/0 (aa  +\n  bb|); B -1/-1.-1/1 (z); F 1/-1.-1/1 (p|q + 1); V -1/-1.-1/3 (w|); OPEN -1/-1.-1/4 (); F 4/-1.-1/4 (1|2); F -1/-1.-1/6 (c d|e)")
    let kinds <- [for (a in pp.expansion.call_args); "{a.text}"]
    t |> equal(join(kinds, " "), "source empty source body body source empty pooled source pooled source")
    let body = pp_call_arg_view(pp, 2, 1)
    t |> equal("{body.data == null} {body.len}", "true 0")
    let source = pp_call_arg_view(pp, 0, 0)
    t |> equal(source.len, length("aa  +\n  bb"))
}

// each token handed out, `spelling` then `:call.k` for each argument copy it is in, innermost first
def private copy_chains(text : string) : string {
    var pp <- started([("main.c", text)])
    var toks : array<string>
    while (pp_next_token(pp)) {
        var chain = pp_token_spelling(pp)
        pp_each_copy(pp, pp.tok.copy) $(call, k) {
            chain += ":{call}.{k}"
        }
        toks |> push(chain)
    }
    return join(toks, " ")
}

[test(description = "a token knows each argument it is a copy of: #define A(x) B(x) makes a token of A(t) a copy of B's argument, then A's; a body token and a pasted or stringified one are none, an operand of ## kept whole is one")]
def test_argument_copies(t : T?) {
    t |> equal(copy_chains("#define B(y) [y y]\n#define A(x) B(x) x\nA(t u)\n"), "[ t:1.0:0.0 u:1.0:0.0 t:1.0:0.0 u:1.0:0.0 ] t:0.0 u:0.0")
    t |> equal(copy_chains("#define P(a, b) a ## b #a b ## 1 a\nP(x, y)\n"), "xy \"x\" y1 x:0.0")
    t |> equal(copy_chains("#define Q(a, b) a ## b\nQ(x z, w)\n"), "x:0.0 zw")
    t |> equal(copy_chains("#define I(x) x\n#define T(x) I(x) + x\nT(1)\n"), "1:1.0:0.0 + 1:0.0")
    var pp <- started([("main.c", "#define B(y) [y y]\n#define A(x) B(x) x\nA(t)\n")])
    var copied : array<string>
    while (pp_next_token(pp)) {
        copied |> push("{pp_is_copy_of(pp, pp.tok.copy, 0, 0)}{pp_is_copy_of(pp, pp.tok.copy, 1, 0)}")
    }
    t |> equal(join(copied, " "), "falsefalse truetrue truetrue falsefalse truefalse")
}

// the one-line text of each macro of `text`, a `|` between them
def private macro_texts(text : string) : string {
    var pp <- started([("main.c", text)])
    stream(pp)
    var lines : array<string>
    for (m in range(length(pp.macros))) {
        continue if (pp.macros[m].file == 1)
        var inscope bytes : array<uint8>
        pp_macro_text(pp, m, bytes)
        lines |> push(string(bytes))
    }
    return join(lines, " | ")
}

[test(description = "a macro's #define on one line: continuations joined, a comment or a run of blanks one blank where it separated tokens, literals kept, the parameter list as spelled")]
def test_macro_text(t : T?) {
    t |> equal(macro_texts("#define SQ(x) ((x) * (x))\n#  define  F(a,b ,c)\\\n  a/*c*/+b  // end\n#define S \"a  /* b */\" '\\''\n#define E()\n#define O\n"),
               "#define SQ(x) ((x) * (x)) | #define F(a,b ,c) a +b | #define S \"a  /* b */\" '\\'' | #define E() | #define O")
}

// `NAME=uses,...` of each function-like macro of `text`, and `!` after a name the C-IR never marks
def private macro_uses(text : string) : string {
    var pp <- started([("main.c", text)])
    stream(pp)
    var lines : array<string>
    for (m in range(length(pp.macros))) {
        continue if (!pp.macros[m].function_like)
        var inscope uses <- [for (k in range(length(pp.macros[m].params))); "{pp_macro_uses(pp, m, k)}"]
        lines |> push("{pp_name(pp, pp.macros[m].name)}{pp_macro_markable(pp, m) ? "" : "!"}={join(uses, ",")}")
    }
    return join(lines, " ")
}

[test(description = "a macro's uses of each argument: its parameter's uses in the body through the macros the body calls; -1 for a variadic macro, a parameter under # or ## or called, a callee whose use is unknown or whose name has two definitions; a macro of itself is a name")]
def test_macro_uses(t : T?) {
    let defs = "#define SQ(x) ((x) * (x))\n#define FIRST(a, b) a\n#define TAG(c) (c)->tag\n#define IS(c) (TAG(c) == 3)\n#define FOURTH(x) SQ(SQ(x))\n#define TWO(c) IS(c) || IS(c)\n#define DROP(x) FIRST(1, x)\n"
    t |> equal(macro_uses(defs), "SQ=2 FIRST=1,0 TAG=1 IS=1 FOURTH=4 TWO=2 DROP=0")
    t |> equal(macro_uses("#define APPLY(f, x) f(x) + x\n#define S(x) #x x\n#define C(x) a ## x x\n#define V(x, ...) x __VA_ARGS__\n#define R(x) R(x) x\n#define U(x) V(x, 1)\n"),
               "APPLY=-1,-1 S!=-1 C!=-1 V!=-1,-1 R=2 U=-1")
    t |> equal(macro_uses("#define G(x) x\n#define H(x) G(x)\n#undef G\n#define G(x) x x\n"), "G=1 H=-1 G=2")
    t |> equal(macro_uses("#define G(x) x\n#define H(x) G(x)\n#undef G\n#define G(x) x\n"), "G=1 H=1 G=1")
    t |> equal(macro_uses("#define A(x) B(x)\n#define B(x) A(x) x\n"), "A=-1 B=-1")
}

[test(description = "the record's readers allocate nothing: a token's expansion place and copies, an argument's text into a buffer with room; a unit of many calls whose arguments are copied grows the record geometrically")]
def test_record_readers_allocate_nothing(t : T?) {
    let text = "#define B(y) [y y]\n#define A(x, z) B(x) z\n#define S(p) A(p, q)\nfirst\n" + repeat("A(a  b, c) S(d) ", 1000)
    var pp <- started([("main.c", text)])
    t |> success(pp_next_token(pp))
    let heap = int(heap_allocation_count())
    var count = 0
    while (pp_next_token(pp)) {
        count++
    }
    let record_blocks = int(heap_allocation_count()) - heap
    t |> equal(count, 12000)
    t |> success(record_blocks <= 96, "{record_blocks} heap blocks over {length(pp.expansion.calls)} calls")
    var buffer : array<uint8>
    buffer |> reserve(64)
    let strings = int(string_heap_allocation_count())
    let before = int(heap_allocation_count())
    var lines = 0
    var copies = 0
    for (c in range(length(pp.expansion.calls))) {
        let place = pp_expansion_place(pp, c, pp.expansion.calls[c].name)
        lines += place.line
        for (k in range(pp.expansion.calls[c].arg_count)) {
            buffer |> clear()
            pp_call_arg_text(pp, c, k, buffer)
            copies += length(buffer)
        }
    }
    for (e in range(length(pp.expansion.copies))) {
        pp_each_copy(pp, e) $(call, k) {
            copies += call + k
        }
    }
    t |> equal(lines, 5 * 5000)
    t |> success(copies > 0)
    t |> equal("{int(string_heap_allocation_count()) - strings} strings, {int(heap_allocation_count()) - before} heap blocks", "0 strings, 0 heap blocks")
}
