options gen2
// the pipeline parses clang's JSON dump below the test's own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../pipeline.das
require ../cir.das
require ../summaries.das

//! The program-wide summaries (`converter/summaries.das`) over `p9_summaries.c`: what each function
//! may store to, transitively, through a call chain, a pointer, an out-parameter, libc and a cycle;
//! whether it surely returns; which parameters keep no pointer; which locals' addresses escape.

let FIXTURE = "converter/tests/fixtures/p9_summaries.c"

var res : ConvertResult
var tu : CirTu
var error : string
var s : Summaries
var pointed : table<string>
var defined : table<string>

// the effects of a call of function `name`
def fx(name : string) : int => s.function_index?[name] ?? s.libc_index?[name] ?? s.unknown

def body_of(name : string) : CirStmt const? {
    for (d in tu.decls) {
        if (d.k == "func" && d.name == name && d.body != null) {
            return d.body
        }
    }
    return null
}

def kept_nothing(es : Summaries; name : string; k : int) : bool => es.noescape[es.function_index?[name] ?? 0][k]

def params_noescape(name : string) : string {
    let f = s.function_index?[name] ?? -1
    return f < 0 ? "none" : join([for (v in s.noescape[f]); v ? "1" : "0"], "")
}

[test]
def test_summaries(t : T?) {
    var dir_error : string
    let out = create_temp_directory("c2das_summaries", dir_error)
    if (!empty(dir_error)) {
        t |> failure(dir_error)
        return
    }
    delete res
    res <- convert(FIXTURE, out, "linux")
    unsafe {
        delete tu
    }
    tu <- read_cir(res.cir_text, error)
    // the variables a pointer reaches by name in the fixture: `&lim_out`'s initializer, gx's array
    // decay, the locals whose address main and the reversals take
    delete pointed
    pointed <- {"lim_out", "gx", "local", "l", "text", "buf", "flag", "r", "from", "b"}
    defined |> clear()
    for (d in tu.decls) {
        if (d.k == "global" && !d.is_extern) {
            defined |> insert(d.name)
        }
    }
    delete s
    s <- summarize(tu, pointed, defined, false)
    t |> equal(res.ok, true, res.error)
    effect_cases(t)
    escape_cases(t, out)
}

// the fixture's effects: a call chain, a pointer, an out-parameter, libc, a cycle, a reader
def effect_cases(t : T?) {
    t |> run("a store two levels down reaches the caller; the other chain stores another global") @(t : T?) {
        t |> equal(stores_global(s, s.effects[fx("mid_a")], "lim_a"), true)
        t |> equal(stores_global(s, s.effects[fx("mid_b")], "lim_b"), false)
        t |> equal(stores_global(s, s.effects[fx("mid_b")], "other"), true)
        t |> equal(s.effects[fx("mid_b")].through || s.effects[fx("mid_b")].all || s.effects[fx("mid_b")].pointed_global, false)
    }
    t |> run("a call through a pointer does what every function whose address the program takes does") @(t : T?) {
        t |> equal(stores_global(s, s.effects[s.indirect], "lim_fp"), true)
        t |> equal(stores_global(s, s.effects[s.indirect], "calls"), true)
        t |> equal(stores_global(s, s.effects[s.indirect], "lim_ro"), false)
        t |> equal(s.effects[s.indirect].returns, false)
        t |> equal(stores_global(s, s.effects[fx("pointers")], "lim_fp"), true)
    }
    t |> run("an out-parameter stores through a pointer; a store to a global a pointer reaches is marked so") @(t : T?) {
        t |> equal(s.effects[fx("set_out")].through, true)
        t |> equal(s.effects[fx("set_out")].all, false)
        t |> equal(s.effects[fx("deep_a")].pointed_global, false)
        t |> equal(s.effects[fx("keep_len")].through, true)
    }
    t |> run("libc: memset, memcpy and strcpy store through a pointer, strlen does not, printf does output, getenv is in no table") @(t : T?) {
        for (name in ["memset", "memcpy", "strcpy"]) {
            t |> equal(s.effects[fx(name)].through, true, name)
        }
        t |> equal(s.effects[fx("strlen")].through || s.effects[fx("strlen")].io, false)
        t |> equal(s.effects[fx("printf")].io, true)
        t |> equal(s.effects[fx("getenv")].all, true)
        t |> equal(s.effects[fx("libc_calls")].all, true)
        t |> equal(s.effects[fx("exit")].returns, false)
    }
    t |> run("a recursive cycle shares its stores and never surely returns") @(t : T?) {
        t |> equal(stores_global(s, s.effects[fx("ping")], "lim_rec"), true)
        t |> equal(stores_global(s, s.effects[fx("ping2")], "lim_rec"), false)
        t |> equal(stores_global(s, s.effects[fx("cycles")], "lim_norec"), false)
        t |> equal(s.effects[fx("ping2")].returns, false)
        t |> equal(s.effects[fx("cycles")].returns, false)
    }
    t |> run("a reader stores nothing and returns; a callee that may exit two levels down does not return") @(t : T?) {
        let peek = fx("peek")
        t |> equal(s.effects[peek].through || s.effects[peek].all || s.effects[peek].io || s.effects[peek].pointed_global, false)
        t |> equal(stores_global(s, s.effects[peek], "lim_ro"), false)
        t |> equal(s.effects[peek].returns, true)
        t |> equal(s.effects[fx("twice")].returns, true)
        t |> equal(s.effects[fx("twice")].io, false)
        t |> equal(s.effects[fx("quit1")].returns, false)
        t |> equal(s.effects[fx("inclusive")].returns, true)
        t |> equal(s.effects[fx("waits")].returns, false)
        t |> equal(s.effects[fx("waits")].io, true)
    }
}

// which parameters keep nothing and which locals' addresses escape, in the fixture and in small
// functions of each shape; the stores' types under strict aliasing
def escape_cases(t : T?; out : string) {
    t |> run("noescape: tolstr stores through len and keeps nothing, checklstr passes it on, keep_len keeps it") @(t : T?) {
        t |> equal(params_noescape("tolstr"), "01")
        t |> equal(params_noescape("checklstr"), "01")
        t |> equal(params_noescape("keep_len"), "0")
        t |> equal(params_noescape("set_out"), "1")
        t |> equal(params_noescape("put_f"), "1")
        t |> equal(params_noescape("waits"), "1")
        t |> equal(address_escapes(s, body_of("reverse"), "l"), false)
        t |> equal(address_escapes(s, body_of("reverse_kept"), "l"), true)
        t |> equal(address_escapes(s, body_of("out_params"), "local"), false)
        t |> equal(address_escapes(s, body_of("libc_calls"), "tmp"), false)
    }
    t |> run("a pointer escapes when it is kept, returned, stepped into a global or its own address taken") @(t : T?) {
        let source = "int *g; int **gg; struct s \{ int *p; \} gs;\nint *ret(int *p) \{ return p + 1; \}\nvoid keep(int *p) \{ gs.p = p; \}\nvoid step(int *p) \{ p++; g = p; \}\nvoid self(int *p) \{ gg = &p; \}\nvoid cond(int *p, int c) \{ g = c ? p : 0; \}\nint cmp(int *p, int *q) \{ return p < q && *p == 1 && p[1] == 2; \}\nint *pass(int *p) \{ return ret(p); \}\nvoid copy(char *d, const char *s) \{ while (*s) *d++ = *s++; \}\nchar *found(char *s) \{ return __builtin_strchr(s, 'a'); \}\nint main(void) \{ return 0; \}\n"
        let c_path = path_join(out, "escapes.c")
        fwrite(c_path, source)
        let small <- convert(c_path, path_join(out, "escapes"), "linux")
        t |> equal(small.ok, true, small.error)
        var unit <- read_cir(small.cir_text, error)
        let none : table<string>
        let es <- summarize(unit, none, none, false)
        t |> equal(kept_nothing(es, "ret", 0), false)
        t |> equal(kept_nothing(es, "keep", 0), false)
        t |> equal(kept_nothing(es, "step", 0), false)
        t |> equal(kept_nothing(es, "self", 0), false)
        t |> equal(kept_nothing(es, "cond", 0), false)
        t |> equal(kept_nothing(es, "cmp", 0) && kept_nothing(es, "cmp", 1), true)
        t |> equal(kept_nothing(es, "pass", 0), false)
        t |> equal(kept_nothing(es, "copy", 0) && kept_nothing(es, "copy", 1), true)
        t |> equal(kept_nothing(es, "found", 0), false)
        delete_tu(unit)
    }
    t |> run("under strict aliasing the types of the stores through a pointer are kept, a libc store's as every type") @(t : T?) {
        let strict <- summarize(tu, pointed, defined, true)
        let put = fx("put_f")
        t |> equal(length(strict.effects[put].through_types), 1)
        t |> equal(key_exists(strict.effects[put].through_types, -1), false)
        t |> equal(key_exists(strict.effects[fx("memset")].through_types, -1), true)
        t |> equal(length(s.effects[fx("put_f")].through_types), 0)
    }
}
