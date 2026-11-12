options gen2

module summaries public

require strings
require cir
require layout

//! What each function of a program may do to the objects a caller reads, computed once from the
//! program's C-IR before any module is spelled (`ARCHITECTURE_EMITTER_LOOPS.md`): the
//! globals it may store to and whether it stores through a pointer (mod-ref), whether it may do
//! input or output, whether it surely returns, and which of its parameters keep no pointer they
//! are given (noescape). In program mode the C-IR holds every unit, so a callee the program
//! defines is read, never guessed. Analysis only: nothing here changes the `CirTu`.

//! What a call may do, its callees' effects included: stores (`all`, `globals`, `pointed_global`,
//! `through`, `through_types`), input or output (`io`) and whether it surely returns (`returns`).
struct CallEffects {
    // it may store to any object: a function neither the program nor `LIBC_EFFECTS` describes
    all : bool
    // the globals it stores to by name, one bit per global (`Summaries.global_bit`)
    globals : array<uint64>
    // it stores by name to a global some pointer may reach
    pointed_global : bool
    // it stores through a pointer, and the C type of each such store (-1 for every type)
    through : bool
    through_types : table<int>
    // it may read or write a file or access a volatile object
    io : bool
    // it returns to its caller on every path: no `exit`, `longjmp` or `abort`, no recursion, no
    // `goto` and no loop C does not let the implementation assume ends (`may_run_forever`)
    returns : bool
}

//! The summaries of a program: a function's effects by `function_index`, a libc function's by
//! `libc_index`, a call through a pointer's at `indirect`, an unknown callee's at `unknown`;
//! `noescape` by function and parameter.
struct Summaries {
    global_bit : table<string; int>
    function_index : table<string; int>
    libc_index : table<string; int>
    effects : array<CallEffects>
    indirect : int
    unknown : int
    noescape : array<array<bool>>
}

// a libc function: whether it stores through its pointer arguments, may read or write a file,
// returns, and returns a pointer into its first argument. It keeps no pointer it is given
struct private LibcCall {
    writes : bool
    io : bool
    returns : bool
    result_arg : bool
}

// the libc functions the converter maps (`CRT_CALLS`, `C_RUNTIME_CALLS`) whose effects are
// known; any other callee the program does not define may store to every object
let private PURE = LibcCall(returns = true)
let private SCAN = LibcCall(returns = true, result_arg = true)
let private FILL = LibcCall(writes = true, returns = true, result_arg = true)
let private STORE = LibcCall(writes = true, returns = true)
let private PRINT = LibcCall(io = true, returns = true)
let private READ = LibcCall(writes = true, io = true, returns = true)
let private STOP = LibcCall(io = true)

let private LIBC_EFFECTS <- {
    "strlen" => PURE, "strcmp" => PURE, "strncmp" => PURE, "memcmp" => PURE, "strspn" => PURE,
    "strcoll" => PURE, "abs" => PURE, "llabs" => PURE, "atoi" => PURE, "atol" => PURE, "atof" => PURE,
    "isalpha" => PURE, "isdigit" => PURE, "isalnum" => PURE, "isspace" => PURE, "isupper" => PURE,
    "islower" => PURE, "isxdigit" => PURE, "ispunct" => PURE, "isprint" => PURE, "iscntrl" => PURE,
    "isgraph" => PURE, "toupper" => PURE, "tolower" => PURE, "malloc" => PURE, "calloc" => PURE,
    "rand" => PURE, "srand" => PURE, "difftime" => PURE, "fabs" => PURE, "floor" => PURE,
    "ceil" => PURE, "sqrt" => PURE, "sin" => PURE, "cos" => PURE, "tan" => PURE, "asin" => PURE,
    "acos" => PURE, "atan" => PURE, "atan2" => PURE, "exp" => PURE, "log" => PURE, "log2" => PURE,
    "log10" => PURE, "pow" => PURE, "fmod" => PURE, "ldexp" => PURE, "hypot" => PURE, "cbrt" => PURE,
    "expm1" => PURE, "log1p" => PURE, "copysign" => PURE, "remainder" => PURE, "trunc" => PURE,
    "round" => PURE, "fma" => PURE, "nextafter" => PURE, "alloca" => PURE, "__builtin_alloca" => PURE,
    "__builtin_expect" => PURE, "__builtin_ffs" => PURE, "__builtin_clz" => PURE,
    "__builtin_ctz" => PURE, "__builtin_popcount" => PURE, "__builtin_bswap16" => PURE,
    "__builtin_bswap32" => PURE, "__builtin_bswap64" => PURE,
    "memchr" => SCAN, "strchr" => SCAN, "strrchr" => SCAN, "strstr" => SCAN, "strpbrk" => SCAN,
    "memset" => FILL, "memcpy" => FILL, "memmove" => FILL, "strcpy" => FILL, "strncpy" => FILL,
    "strcat" => FILL, "strncat" => FILL, "realloc" => FILL,
    "free" => STORE, "sprintf" => STORE, "snprintf" => STORE, "vsprintf" => STORE,
    "vsnprintf" => STORE, "sscanf" => STORE, "vsscanf" => STORE, "frexp" => STORE, "modf" => STORE,
    "__builtin_va_start" => STORE, "__builtin_c23_va_start" => STORE, "__builtin_va_end" => STORE,
    "__builtin_va_copy" => STORE,
    "printf" => PRINT, "fprintf" => PRINT, "vprintf" => PRINT, "vfprintf" => PRINT, "fputs" => PRINT,
    "fwrite" => PRINT, "fflush" => PRINT, "fclose" => PRINT, "fseek" => PRINT, "ftell" => PRINT,
    "feof" => PRINT, "ferror" => PRINT, "clock" => PRINT,
    "fread" => READ, "getc" => READ, "ungetc" => READ, "fgets" => LibcCall(writes = true, io = true, returns = true, result_arg = true),
    "exit" => STOP, "abort" => STOP, "__assert_fail" => STOP, "longjmp" => STOP, "_longjmp" => STOP,
    "__builtin_trap" => STOP, "__builtin_unreachable" => STOP
}

// the libc entry callee `name` takes: its own, or the one of its `__builtin_` spelling's libc name
def private libc_key(name : string) : string {
    if (key_exists(LIBC_EFFECTS, name)) {
        return name
    }
    let plain = name |> starts_with("__builtin_") ? slice(name, length("__builtin_")) : ""
    return !empty(plain) && key_exists(LIBC_EFFECTS, plain) ? plain : ""
}

//! The index in `s.effects` of what call `x` may do: the function the program defines, the libc
//! function, `s.indirect` for a call through a pointer, `s.unknown` for any other callee.
def callee_effects(s : Summaries; x : CirExpr const?) : int {
    let name = called_name(*x)
    if (empty(name)) {
        return s.indirect
    }
    return s.function_index?[name] ?? s.libc_index?[libc_key(name)] ?? s.unknown
}

// whether call `x` keeps no pointer it passes as argument `k`: a parameter the defined callee
// keeps nothing of, or any argument of a libc function `LIBC_EFFECTS` lists
def private noescape_arg(s : Summaries; x : CirExpr const?; k : int) : bool {
    let name = called_name(*x)
    let f = s.function_index?[name] ?? -1
    if (f >= 0) {
        return k < length(s.noescape[f]) && s.noescape[f][k]
    }
    return !empty(name) && !empty(libc_key(name))
}

// whether call `x` returns a pointer into its first argument (`LibcCall.result_arg`)
def private result_into_first(x : CirExpr const?) : bool {
    let key = libc_key(called_name(*x))
    return !empty(key) && LIBC_EFFECTS?[key]?.result_arg ?? false && !empty(x.args)
}

// how a pointer of interest is reached: the value of parameter `name`, or for `storage` the
// address of variable `name`
struct private Leak {
    name : string
    storage : bool
}

// the casts that keep a pointer's value: a pointer one, a qualifier's, and the load of the
// parameter itself
def private same_pointer(x : CirExpr const?; k : Leak) : bool =>
    x.e == "cast" && (x.cast_kind == "NoOp" || x.cast_kind == "BitCast" || (x.cast_kind == "LValueToRValue" && !k.storage))

// whether expression `x`'s value is a pointer derived from the one of interest
def private derived(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    var at = x
    while (at != null && same_pointer(at, k)) {
        at = at.a
    }
    if (at == null) {
        return false
    }
    if (at.e == "ref") {
        return !k.storage && at.name == k.name
    }
    if ((at.e == "un" && at.op == "addr") || (at.e == "cast" && at.cast_kind == "ArrayToPointerDecay")) {
        return based_on(s, k, at.a)
    }
    if (at.e == "bin" && (at.op == "add" || at.op == "sub")) {
        return derived(s, k, at.a) || derived(s, k, at.b)
    }
    if (at.e == "un" && (at.op == "preinc" || at.op == "predec" || at.op == "postinc" || at.op == "postdec")) {
        return derived(s, k, at.a)
    }
    if (at.e == "assign") {
        return derived(s, k, at.b) || (at.op != "" && derived(s, k, at.a))
    }
    if (at.e == "cond") {
        return derived(s, k, at.a) || derived(s, k, at.b)
    }
    if (at.e == "comma") {
        return derived(s, k, at.b)
    }
    return at.e == "call" && result_into_first(at) && derived(s, k, at.args[0])
}

// whether lvalue `x` lies in the object the pointer of interest points into
def private based_on(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    let at = below_casts(x)
    if (at == null) {
        return false
    }
    if (at.e == "ref") {
        return k.storage && at.name == k.name
    }
    if (at.e == "member") {
        return at.arrow ? derived(s, k, at.base) : based_on(s, k, at.base)
    }
    if (at.e == "index") {
        return derived(s, k, at.base)
    }
    return at.e == "un" && at.op == "deref" && derived(s, k, at.a)
}

// whether `x`, whose value is consumed and kept nowhere, lets the pointer of interest escape
def private used(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    if (x == null) {
        return false
    }
    return derived(s, k, x) ? chain_leaks(s, k, x) : leaks(s, k, x)
}

// whether the parts of derived pointer `x` off its derivation let the pointer escape
def private chain_leaks(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    var at = x
    while (same_pointer(at, k)) {
        at = at.a
    }
    if (at.e == "ref") {
        return false
    }
    if ((at.e == "un" && at.op == "addr") || (at.e == "cast" && at.cast_kind == "ArrayToPointerDecay")) {
        return based_leaks(s, k, at.a)
    }
    if (at.e == "bin" || at.e == "cond" || at.e == "comma") {
        return used(s, k, at.c) || used(s, k, at.a) || used(s, k, at.b)
    }
    if (at.e == "un") {
        return lvalue_leaks(s, k, at.a)
    }
    if (at.e == "assign") {
        // the pointer goes back into the parameter itself, or into memory
        let target = below_casts(at.a)
        let into_self = !k.storage && target != null && target.e == "ref" && target.name == k.name
        return !into_self || used(s, k, at.b)
    }
    var leak = false
    for (idx, arg in count(), at.args) {
        leak ||= idx == 0 ? chain_leaks(s, k, arg) : arg_leaks(s, k, at, idx)
    }
    return leak
}

// the parts of lvalue `x`, which lies in the object of interest (`based_on`), off its derivation
def private based_leaks(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    let at = below_casts(x)
    if (at.e == "ref") {
        return false
    }
    if (at.e == "member") {
        return at.arrow ? chain_leaks(s, k, at.base) : based_leaks(s, k, at.base)
    }
    if (at.e == "index") {
        return chain_leaks(s, k, at.base) || leaks(s, k, at.i)
    }
    return chain_leaks(s, k, at.a)
}

// whether lvalue `x`, stored to, stepped or addressed, lets the pointer of interest escape
def private lvalue_leaks(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    let at = below_casts(x)
    if (at == null || at.e == "ref") {
        return false
    }
    if (at.e == "member") {
        return at.arrow ? used(s, k, at.base) : lvalue_leaks(s, k, at.base)
    }
    if (at.e == "index") {
        return used(s, k, at.base) || leaks(s, k, at.i)
    }
    return at.e == "un" && at.op == "deref" ? used(s, k, at.a) : leaks(s, k, at)
}

// whether argument `idx` of call `x` lets the pointer of interest escape
def private arg_leaks(s : Summaries; k : Leak; x : CirExpr const?; idx : int) : bool {
    let arg = x.args[idx]
    if (derived(s, k, arg)) {
        return !noescape_arg(s, x, idx) || chain_leaks(s, k, arg)
    }
    return leaks(s, k, arg)
}

// whether expression `x`, whose value may be kept, lets the pointer of interest escape
def private leaks(s : Summaries; k : Leak; x : CirExpr const?) : bool {
    if (x == null) {
        return false
    }
    if (derived(s, k, x)) {
        return true
    }
    if (x.e == "un" && x.op == "addr" && !k.storage) {
        // the address of the parameter itself lets anyone read the pointer
        let target = below_casts(x.a)
        if (target != null && target.e == "ref" && target.name == k.name) {
            return true
        }
    }
    if (x.e == "un") {
        return x.op == "addr" || x.op == "preinc" || x.op == "predec" || x.op == "postinc" || x.op == "postdec" ? lvalue_leaks(s, k, x.a) : used(s, k, x.a)
    }
    if (x.e == "member") {
        return x.arrow ? used(s, k, x.base) : leaks(s, k, x.base)
    }
    if (x.e == "index") {
        return used(s, k, x.base) || leaks(s, k, x.i)
    }
    if (x.e == "bin") {
        let consumes = x.op == "eq" || x.op == "ne" || x.op == "lt" || x.op == "gt" || x.op == "le" || x.op == "ge" || x.op == "land" || x.op == "lor"
        return consumes ? used(s, k, x.a) || used(s, k, x.b) : leaks(s, k, x.a) || leaks(s, k, x.b)
    }
    if (x.e == "assign") {
        return lvalue_leaks(s, k, x.a) || leaks(s, k, x.b)
    }
    if (x.e == "cond") {
        return used(s, k, x.c) || leaks(s, k, x.a) || leaks(s, k, x.b)
    }
    if (x.e == "comma") {
        return used(s, k, x.a) || leaks(s, k, x.b)
    }
    if (x.e == "cast") {
        return x.cast_kind == "PointerToBoolean" || x.cast_kind == "ToVoid" ? used(s, k, x.a) : leaks(s, k, x.a)
    }
    if (x.e == "call") {
        var leak = called_name(*x) == "" && leaks(s, k, x.fn)
        for (idx in range(length(x.args))) {
            leak ||= arg_leaks(s, k, x, idx)
        }
        return leak
    }
    var leak = leaks(s, k, x.init) || leaks(s, k, x.list)
    for (item in x.init_items) {
        leak ||= leaks(s, k, item.v)
    }
    return leak
}

// whether function body `body` lets the pointer of interest escape: keeps it in an object,
// returns it, or passes it to a callee that may keep it
def private body_leaks(s : Summaries; k : Leak; body : CirStmt const?) : bool {
    var leak = false
    each_stmt(body) $(st) {
        if (!leak) {
            leak = st.s == "expr" ? used(s, k, st.e) : st.s == "return" ? leaks(s, k, st.e) : st.s == "decl" ? leaks(s, k, st.init) : used(s, k, st.cond) || used(s, k, st.inc)
        }
    }
    return leak
}

//! Whether a pointer to variable `name` may outlive the statements of `body` that form it: an
//! `&` of it (or of a part of it) or its array's decay that `body` keeps in an object, returns,
//! or passes to a callee whose parameter may keep it (`Summaries.noescape`); a pointer passed only
//! to parameters that keep nothing dies with the call.
def address_escapes(s : Summaries; body : CirStmt const?; name : string) : bool => body_leaks(s, Leak(name = name, storage = true), body)

// the direct facts of a function body and what it calls
struct private BodyFacts {
    effects : CallEffects
    callees : table<int>
    // the effects of the callees inside a loop, by `Summaries.effects` index
    loop_callees : table<int>
    // a `goto`, a loop C may let run forever or a callee no table describes
    stops : bool
}

// whether expression `x` loads an object (an lvalue under `LValueToRValue`); false for a missing one
def reads_object(x : CirExpr const?) : bool {
    var found = false
    each_subexpr(x) $(sub) {
        found ||= sub.e == "cast" && sub.cast_kind == "LValueToRValue"
    }
    return found
}

// whether loop test `x` is the literal 0, a loop that runs its body at most once (`do { } while (0)`)
def private false_test(x : CirExpr const?) : bool {
    let at = below_casts(x)
    return at != null && at.e == "int_lit" && at.v == "0"
}

// whether the access of lvalue `x` is volatile
def private volatile_access(x : CirExpr const?) : bool =>
    (x.e == "ref" || x.e == "member" || x.e == "index" || (x.e == "un" && x.op == "deref")) && x.vol

//! Whether loop `st` (a `while`, `do` or `for`) may run forever as defined C, which the
//! implementation may not assume ends (C11 6.8.5p6): a test that loads no object (none, a
//! constant but 0, `while (!0)`, an enumerator), or a test, body or step that accesses a volatile
//! object or calls a function that may do input or output or not return.
def may_run_forever(s : Summaries; st : CirStmt const?) : bool {
    var forever = !reads_object(st.cond) && !false_test(st.cond)
    for (part in fixed_array<CirExpr const?>(st.cond, st.inc)) {
        each_subexpr(part) $(x) {
            forever ||= volatile_access(x) || (x.e == "call" && (s.effects[callee_effects(s, x)].io || !s.effects[callee_effects(s, x)].returns))
        }
    }
    each_expr(st.body_s) $(x) {
        forever ||= volatile_access(x) || (x.e == "call" && (s.effects[callee_effects(s, x)].io || !s.effects[callee_effects(s, x)].returns))
    }
    return forever
}

def private set_bit(var bits : array<uint64>; idx : int) {
    bits[idx >> 6] |= 1ul << uint64(idx & 63)
}

//! Whether `effects` stores to global `name` by name.
def stores_global(s : Summaries; effects : CallEffects; name : string) : bool {
    let idx = s.global_bit?[name] ?? -1
    return idx >= 0 && (effects.globals[idx >> 6] & (1ul << uint64(idx & 63))) != 0ul
}

// `into` gains every effect of `from` but `returns`
def private merge_effects(var into : CallEffects; from : CallEffects) {
    into.all ||= from.all
    for (idx in range(length(into.globals))) {
        into.globals[idx] |= from.globals[idx]
    }
    into.pointed_global ||= from.pointed_global
    into.through ||= from.through
    for (t in keys(from.through_types)) {
        into.through_types |> insert(t)
    }
    into.io ||= from.io
}

def private blank_effects(words : int) : CallEffects {
    var effects = CallEffects(returns = true)
    effects.globals |> resize(words)
    return <- effects
}

//! The type the aliasing rule sees lvalue `x` accessed as: its own, or -1, which aliases every type,
//! for a member of a union anywhere in its path, since C reads one union member through another.
def access_type(tu : CirTu; x : CirExpr const?) : int {
    var at = x
    while (at != null && (at.e == "member" || at.e == "index" || at.e == "cast")) {
        if (at.e == "member") {
            let rec = at.arrow && type_kind(tu, at.base.t) == "ptr" ? tu.types[at.base.t].to : at.base.t
            if (type_kind(tu, rec) == "union") {
                return -1
            }
        }
        at = at.e == "cast" ? at.a : at.base
    }
    return x.t
}

def private type_kind(tu : CirTu; t : int) : string => t >= 0 && t < length(tu.types) ? tu.types[t].k : ""

// the direct facts of function `d`: its stores by name to globals and through pointers, its volatile accesses, its loops and its callees
def private body_facts(s : Summaries; tu : CirTu; d : CirDecl; pointed : table<string>; defined_globals : table<string>; strict : bool; var facts : BodyFacts) {
    each_stmt(d.body) $(st) {
        facts.stops ||= st.s == "goto"
        if (st.s == "while" || st.s == "do" || st.s == "for") {
            facts.stops ||= !reads_object(st.cond) && !false_test(st.cond)
            each_expr(st) $(x) {
                facts.stops ||= volatile_access(x)
                if (x.e == "call") {
                    facts.loop_callees |> insert(callee_effects(s, x))
                }
            }
        }
    }
    each_expr(d.body) $(x) {
        facts.effects.io ||= volatile_access(x)
        if (x.e == "assign" || (x.e == "un" && (x.op == "preinc" || x.op == "predec" || x.op == "postinc" || x.op == "postdec"))) {
            let target = below_casts(x.a)
            let root = storage_root(target)
            if (empty(root)) {
                facts.effects.through = true
                if (strict) {
                    facts.effects.through_types |> insert(access_type(tu, target))
                }
            } elif (key_exists(s.global_bit, root)) {
                // a local named like a global counts as the global: the C-IR names both alike
                set_bit(facts.effects.globals, s.global_bit?[root] ?? 0)
                facts.effects.pointed_global ||= key_exists(pointed, root) || !key_exists(defined_globals, root)
            }
        } elif (x.e == "call") {
            let callee = callee_effects(s, x)
            facts.callees |> insert(callee)
            facts.stops ||= callee == s.unknown
        }
    }
}

// the effects of a callee no table describes: every store, input or output, no return
def private unknown_effects(words : int) : CallEffects {
    var effects = blank_effects(words)
    effects.all = true
    effects.through = true
    effects.through_types |> insert(-1)
    effects.pointed_global = true
    effects.io = true
    effects.returns = false
    return <- effects
}

// whether an object of type `t` holds a function pointer: one itself, or in an element or a field
def private holds_function_pointer(tu : CirTu; t : int) : bool {
    var seen : table<int>
    var pending <- [t]
    while (!empty(pending)) {
        let at = pending |> back()
        pending |> pop()
        if (at < 0 || at >= length(tu.types) || key_exists(seen, at)) {
            continue
        }
        seen |> insert(at)
        let k = tu.types[at].k
        if (k == "func") {
            return true
        }
        if (k == "ptr" || k == "typedef") {
            pending |> push(tu.types[at].to)
        } elif (k == "array") {
            pending |> push(tu.types[at].elem)
        } else {
            pending |> reserve(length(pending) + length(tu.types[at].fields))
            for (f in tu.types[at].fields) {
                pending |> push(f.t)
            }
        }
    }
    return false
}

// the functions whose address the program takes: a reference to a function anywhere but as a
// direct call's callee, in a body or a global's initializer
def private address_taken(tu : CirTu) : table<string> {
    var functions : table<string>
    for (d in tu.decls) {
        if (d.k == "func") {
            functions |> insert(d.name)
        }
    }
    var callees : table<uint64>
    var taken : table<string>
    for (d in tu.decls) {
        var roots : array<CirExpr const?>
        if (d.k == "func") {
            each_expr(d.body) $(x) {
                roots |> push(x)
            }
        } elif (d.k == "global") {
            each_subexpr(d.init) $(x) {
                roots |> push(x)
            }
        }
        // a node comes before its operands, so a call marks its callee before the walk meets it
        for (x in roots) {
            if (x.e == "call") {
                let target = x.fn != null && x.fn.e == "cast" && x.fn.cast_kind == "FunctionToPointerDecay" ? x.fn.a : x.fn
                callees |> insert(intptr(target))
            } elif (x.e == "ref" && key_exists(functions, x.name) && !key_exists(callees, intptr(x))) {
                taken |> insert(x.name)
            }
        }
    }
    return <- taken
}

//! The summaries of program `tu`, after `unshadow_locals`: `pointed` the variables some pointer
//! may reach by name (`mark_pointed`), `defined_globals` the globals the program defines, `strict`
//! the sidecar's `strict_aliasing` (the stores' types are kept only then). The effects are a least
//! fixpoint over the call graph's strongly connected components, callees first; a function in a
//! cycle never surely returns; `noescape` is the greatest fixpoint of `address_escapes`'s rule over
//! the parameters.
// the effects of every libc function `LIBC_EFFECTS` lists, appended to `s.effects`
def private add_libc_effects(var s : Summaries; words : int) {
    for (name, call in keys(LIBC_EFFECTS), values(LIBC_EFFECTS)) {
        s.libc_index[name] = length(s.effects)
        var effects = blank_effects(words)
        effects.through = call.writes
        if (call.writes) {
            effects.through_types |> insert(-1)
        }
        effects.io = call.io
        effects.returns = call.returns
        s.effects |> emplace(effects)
    }
}

// the effects of each function the program defines, its callees' merged in: the call graph's
// components callees first (`components_of`), one set per component; `facts[n]` and `edges[n]`
// are the call through a pointer's
def private merge_components(var s : Summaries; facts : array<BodyFacts>; edges : array<table<int>>; words : int) {
    let order <- components_of(edges)
    for (comp in order) {
        var merged = blank_effects(words)
        let cycle = length(comp) > 1 || key_exists(edges[comp[0]], comp[0])
        for (f in comp) {
            merge_effects(merged, facts[f].effects)
            for (callee in keys(facts[f].callees)) {
                merge_effects(merged, s.effects[callee])
            }
            for (callee in keys(edges[f])) {
                merge_effects(merged, s.effects[callee])
            }
        }
        for (f in comp) {
            var returns = !cycle && !facts[f].stops
            for (callee in keys(facts[f].callees)) {
                returns &&= s.effects[callee].returns
            }
            for (callee in keys(facts[f].loop_callees)) {
                returns &&= !s.effects[callee].io
            }
            s.effects[f] := merged
            s.effects[f].returns = returns
        }
    }
}

// `s.noescape`: every parameter keeps nothing until its function's body is seen to keep it, with
// the callees' parameters as they stand, until no answer changes (the greatest fixpoint)
def private settle_noescape(var s : Summaries; bodies : array<CirDecl const?>) {
    s.noescape |> resize(length(bodies))
    for (f, d in count(), bodies) {
        s.noescape[f] |> resize(length(d.params))
        for (idx in range(length(d.params))) {
            s.noescape[f][idx] = true
        }
    }
    var changed = true
    while (changed) {
        changed = false
        for (f, d in count(), bodies) {
            for (idx, p in count(), d.params) {
                if (s.noescape[f][idx] && body_leaks(s, Leak(name = p.name), d.body)) {
                    s.noescape[f][idx] = false
                    changed = true
                }
            }
        }
    }
}

[arch(at="ARCHITECTURE_EMITTER_LOOPS.md#summaries")]
def summarize(tu : CirTu; pointed : table<string>; defined_globals : table<string>; strict : bool) : Summaries {
    var s : Summaries
    for (d in tu.decls) {
        if (d.k == "global" && !key_exists(s.global_bit, d.name)) {
            s.global_bit[d.name] = length(s.global_bit)
        }
    }
    let words = (length(s.global_bit) + 63) >> 6
    var bodies : array<CirDecl const?>
    for (d in tu.decls) {
        if (d.k == "func" && d.body != null && !key_exists(s.function_index, d.name)) {
            s.function_index[d.name] = length(bodies)
            bodies |> push(unsafe(reinterpret<CirDecl const?>(d)))
            s.effects |> emplace(blank_effects(words))
        }
    }
    let n = length(bodies)
    s.indirect = n
    s.effects |> emplace(blank_effects(words))
    s.unknown = n + 1
    s.effects |> emplace(unknown_effects(words))
    add_libc_effects(s, words)
    // the graph: a function to each function it calls, a call through a pointer to the indirect
    // node, which reaches every function whose address the program takes
    var facts : array<BodyFacts>
    facts |> resize(n + 1)
    var edges : array<table<int>>
    edges |> resize(n + 1)
    for (f in range(n)) {
        facts[f].effects := s.effects[f]
        body_facts(s, tu, *bodies[f], pointed, defined_globals, strict, facts[f])
        for (callee in keys(facts[f].callees)) {
            if (callee <= n) {
                edges[f] |> insert(callee)
            }
        }
    }
    facts[n].effects := s.effects[n]
    facts[n].stops = true
    // a function pointer the program reads from an object it does not define (a unit converted
    // alone, `extern void (*hook)(void);`) may reach a function no summary describes
    for (d in tu.decls) {
        if (d.k == "global" && !key_exists(defined_globals, d.name) && holds_function_pointer(tu, d.t)) {
            facts[n].callees |> insert(s.unknown)
        }
    }
    let taken <- address_taken(tu)
    for (name in keys(taken)) {
        let callee = s.function_index?[name] ?? s.libc_index?[libc_key(name)] ?? s.unknown
        if (callee < n) {
            edges[n] |> insert(callee)
        } else {
            facts[n].callees |> insert(callee)
        }
    }
    merge_components(s, facts, edges, words)
    settle_noescape(s, bodies)
    return <- s
}
