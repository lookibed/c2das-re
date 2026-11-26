options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/strings_boost
require math
require ../pp_expand.das

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

[test(description = "the number of arguments: an empty argument, f() of a macro of no parameter, and too few or too many - clang's error, the name handed out and the call dropped")]
def test_argument_count(t : T?) {
    t |> equal(expanded("#define z() Z\n#define one(a) [a]\n#define two(a,b) a+b\nz() z( ) one() two(,) one((,))\n").out, "Z Z [ ] + [ ( , ) ]")
    let bad = expanded("#define z() Z\n#define two(a,b) a+b\nz(1) two(1) two(1,2,3) after\n")
    t |> equal(bad.out, "z two two after")
    t |> equal(bad.diags, "E 3:1 too many arguments provided to function-like macro invocation | E 3:6 too few arguments provided to function-like macro invocation | E 3:13 too many arguments provided to function-like macro invocation")
    let open = expanded("#define f(x) x\nf(1, 2\n")
    t |> equal(open.out, "f")
    t |> equal(open.diags, "E 2:1 unterminated function-like macro invocation")
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
