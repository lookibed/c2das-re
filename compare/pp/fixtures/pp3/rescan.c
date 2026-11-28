/* rescanning: a macro is disabled while its replacement is rescanned, a name read then is painted for good */
#define AA BB
#define BB AA
AA BB
#define foo() bar
#define bar() foo
foo()()()()
#define obj(x) obj2 x
#define obj2(x) [x] obj
obj((1))(2)
#define self self + 1
#define id(x) x
id(self) id(id(self))
#define EMPTY()
#define DEFER(id) id EMPTY()
#define OBSTRUCT(...) __VA_ARGS__ DEFER(EMPTY)()
#define EXPAND(...) __VA_ARGS__
#define A() 123
A ()
DEFER(A)()
EXPAND(DEFER(A)())
#define REPEAT_INDIRECT() REPEAT
#define REPEAT(n) n DEFER(REPEAT_INDIRECT)()(n)
REPEAT(1)
EXPAND(REPEAT(1))
EXPAND(EXPAND(REPEAT(1)))
#define EVAL(...) EVAL1(EVAL1(EVAL1(__VA_ARGS__)))
#define EVAL1(...) EVAL2(EVAL2(EVAL2(__VA_ARGS__)))
#define EVAL2(...) __VA_ARGS__
#define CAT(a, ...) a ## __VA_ARGS__
#define IIF(c) CAT(IIF_, c)
#define IIF_0(t, ...) __VA_ARGS__
#define IIF_1(t, ...) t
#define CHECK_N(x, n, ...) n
#define CHECK(...) CHECK_N(__VA_ARGS__, 0,)
#define PROBE(x) x, 1,
#define NOT(x) CHECK(CAT(NOT_, x))
#define NOT_0 PROBE(~)
#define COMPL(b) CAT(COMPL_, b)
#define COMPL_0 1
#define COMPL_1 0
#define BOOL(x) COMPL(NOT(x))
#define IF(c) IIF(BOOL(c))
#define DEC(x) CAT(DEC_, x)
#define DEC_0 0
#define DEC_1 0
#define DEC_2 1
#define DEC_3 2
#define DEC_4 3
#define WHEN(c) IF(c)(EXPAND, EAT)
#define EAT(...)
#define COUNTDOWN(n) n WHEN(n)(OBSTRUCT(COUNTDOWN_INDIRECT)()(DEC(n)))
#define COUNTDOWN_INDIRECT() COUNTDOWN
EVAL(COUNTDOWN(4))
#define LEFT (
#define h(x) x h
#define APPLY(m, x) m LEFT x )
APPLY(h, 5) EXPAND(APPLY(h, 5))
#define k(x) h(x)(k)
k(1)(2)
