// r06: DEFER/OBSTRUCT/EXPAND (gcc's context model, not Prosser): a deferred self call expands on the next EXPAND
#define EMPTY()
#define DEFER(id) id EMPTY()
#define OBSTRUCT(...) __VA_ARGS__ DEFER(EMPTY)()
#define EXPAND(...) __VA_ARGS__
#define A() 123
DEFER(A)();
EXPAND(DEFER(A)());
#define REPEAT_INDIRECT() REPEAT
#define REPEAT(n) n OBSTRUCT(REPEAT_INDIRECT)()(n)
EXPAND(REPEAT(1));
EXPAND(EXPAND(REPEAT(1)));
