#include <setjmp.h>

int printf(const char *, ...);

/* Lua's ldo.c error recovery under LUA_USE_POSIX: a `struct lua_longjmp` holding the jmp_buf
   and the status, chained through `previous` from the state's handler; the protected runner's
   single-branch `if (_setjmp((c)->b) == 0) { a }` (flat: its tail calls nothing) and the throw's
   `_longjmp((c)->b, 1)` through the pointer, the status carried in the record, not in the
   longjmp value */
struct lua_longjmp {
    struct lua_longjmp *previous;
    jmp_buf b;
    volatile int status;
};

typedef struct State {
    struct lua_longjmp *errorJmp;
    int calls;
} State;

typedef void (*Pfunc)(State *L, void *ud);

#define LUAI_THROW(L,c) _longjmp((c)->b, 1)
#define LUAI_TRY(L,c,a) if (_setjmp((c)->b) == 0) { a }

static void throw_status(State *L, int errcode) {
    if (L->errorJmp) {
        L->errorJmp->status = errcode;
        LUAI_THROW(L, L->errorJmp);
    }
    printf("unprotected %d\n", errcode);
}

static int run_protected(State *L, Pfunc f, void *ud) {
    int old_calls = L->calls;
    struct lua_longjmp lj;
    lj.status = 0;
    lj.previous = L->errorJmp;
    L->errorJmp = &lj;
    LUAI_TRY(L, &lj,
        (*f)(L, ud);
    );
    L->errorJmp = lj.previous;
    L->calls = old_calls;
    return lj.status;
}

static int deepest;

/* three frames below the runner */
static void level3(State *L, int code) {
    L->calls++;
    deepest = L->calls;
    if (code) throw_status(L, code);
}
static void level2(State *L, int code) { L->calls++; level3(L, code); }
static void deep(State *L, void *ud) { L->calls++; level2(L, *(int *) ud); }

/* an inner protected call that catches its own error and goes on */
static void nested_caught(State *L, void *ud) {
    int inner = 5;
    int status = run_protected(L, deep, &inner);
    *(int *) ud = status * 10;
}

/* an inner protected call whose error is rethrown to the outer runner */
static void nested_rethrown(State *L, void *ud) {
    int inner = 6;
    int status = run_protected(L, deep, &inner);
    (void) ud;
    if (status != 0) throw_status(L, status + 100);
}

/* an error after an inner protected call returned normally reaches the outer runner */
static void after_inner(State *L, void *ud) {
    int none = 0;
    int status = run_protected(L, deep, &none);
    throw_status(L, 40 + status + *(int *) ud);
}

int main(void) {
    State st = { 0, 0 };
    State *L = &st;
    int code = 0;
    int out = 0;
    printf("ok %d calls %d\n", run_protected(L, deep, &code), st.calls);
    code = 3;
    printf("caught %d calls %d deepest %d chain %d\n", run_protected(L, deep, &code), st.calls, deepest, L->errorJmp == 0);
    int nested = run_protected(L, nested_caught, &out);
    printf("nested %d inner %d\n", nested, out);
    printf("rethrown %d\n", run_protected(L, nested_rethrown, &out));
    code = 2;
    printf("after %d chain %d\n", run_protected(L, after_inner, &code), L->errorJmp == 0);
    throw_status(L, 9);
    return st.calls;
}
