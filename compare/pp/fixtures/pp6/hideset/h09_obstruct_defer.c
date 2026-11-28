/* deferred expansion: the classic EMPTY/DEFER/OBSTRUCT idiom */
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
