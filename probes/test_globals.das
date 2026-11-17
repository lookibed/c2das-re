options gen2
require dastest/testing_boost public
require daslib/fio
require strings
require daslib/strings_boost
require _daslang_child

var leveltime : int
var data : int[4]
var p : int?
var data2 : int[4] = fixed_array(1, 2, 3, 4)
var q : int? = unsafe(addr(data2[1]))
var _str_0 : uint8[3] = fixed_array(uint8(65), uint8(66), uint8(0))
var names : uint8? [2]
var private hidden = 3

struct State {
    sprite : int
    action : function<() : void>
}

def A_Look {}

var states : State[2] = fixed_array(State(sprite = 1, action = @@A_Look), State(sprite = 2))

[init]
def _c2das_init_pointers {
    unsafe {
        p = addr(data[1])
        names[0] = addr(_str_0[0])
    }
}

def private helper : int => hidden

def forty_two : int => 42

[test]
def test_globals(t : T?) {
    t |> run("globals zero-init and an explicitly initialized global can be addressed inline") @(t : T?) {
        t |> equal(leveltime, 0)
        t |> equal(data[3], 0)
        t |> equal(deref(q), 2)
    }
    t |> run("[init] fills address-carrying globals before any test runs") @(t : T?) {
        t |> equal(p == unsafe(addr(data[1])), true)
        t |> equal(int(deref(names[0])), 65)
    }
    t |> run("function-pointer tables initialize inline and a missing member is null") @(t : T?) {
        t |> equal(states[0].action != null, true)
        t |> equal(states[1].action == null, true)
    }
    t |> run("a function value's zero is default<function<...>>, compared with null; `= null` is not a function value") @(t : T?) {
        var f : function<() : int> = default<function<() : int>>
        t |> equal(f == null, true)
        f = @@forty_two
        t |> equal(f != null, true)
        t |> equal(invoke(f), 42)
        f = default<function<() : int>>
        t |> equal(f == null, true)
    }
    t |> run("var private and def private compile and resolve inside the module") @(t : T?) {
        t |> equal(helper(), 3)
    }
}

def aot_context_cpp(t : T?; case_name, source : string) : string {
    let out_dir = test_temp_dir()
    let r = daslang_run(case_name, source, [get_das_root() + "/utils/aot/main.das", "--", "-ctx"], array<string>(), "c2das_probe_aot", [out_dir + "/"])
    t |> equal(r.rc, 0, "{case_name}: {r.out}")
    return r.rc == 0 ? fread("{out_dir}/c2das_probe_aot_{case_name}.das.cpp") : ""
}

//! The body of the generated C++ function whose definition line starts with `signature_prefix`.
def definition_body(cpp, signature_prefix : string) : string {
    var lines : array<string>
    var inside = false
    for (ln in split(cpp, "\n")) {
        if (!inside && ln |> starts_with(signature_prefix) && !(ln |> ends_with(";"))) {
            inside = true
        } elif (inside) {
            if (ln == "}") {
                break
            }
            lines |> push(ln)
        }
    }
    return join(lines, "\n")
}

let global_access_source = "options gen2\nOPTIONS_LINE\nvar g : int[4]\n[export]\ndef main : int \{\n    g[1] += 5\n    return g[1]\n\}\n"

[test]
def test_aot_globals(t : T?) {
    t |> run("the AOT context finds a module global by its mangled-name hash at every access, under solid_context at its fixed offset") @(t : T?) {
        for (case_name, options_line in ["hashed", "solid"], ["", "options solid_context = true"]) {
            let cpp = aot_context_cpp(t, case_name, global_access_source |> replace("OPTIONS_LINE", options_line))
            let body = definition_body(cpp, "inline int32_t main_")
            let solid = case_name == "solid"
            t |> equal(count(body, "das_global<TDim<int32_t,4>,0x"), solid ? 0 : 2, "{case_name}: {body}")
            t |> equal(count(body, "das_global_solid<TDim<int32_t,4>,0>"), solid ? 2 : 0, "{case_name}: {body}")
            t |> equal(cpp |> contains("das_global_zero_solid<TDim<int32_t,4>,"), case_name == "solid", "{case_name}: the initializer")
        }
    }
}

// the `let private` shapes the emitter writes for a `#define` constant (P7.0k), read by `named`, and a
// `var` of the same value read by `kept`, the control
let private constant_let_source = "options gen2\nlet private MASK = 8191\nlet private TICKS = 456 * 154\nlet private UMASK = 0xffu\nlet private WIDE = uint64(3) * uint64(4)\nlet private NEG = -7\nlet private HALF = 0.5lf\nlet private BIG = int64(1) << int64(40)\nvar private VMASK = 8191\n[export]\ndef named(a : int; b : uint; c : uint64; d : double; e : int64) : int \{\n    return (a & MASK) + TICKS + int(b & UMASK) + int(c * WIDE) + NEG + int(d * HALF) + int(e + BIG)\n\}\n[export]\ndef kept(a : int) : int \{\n    return a & VMASK\n\}\n[export]\ndef main \{\n    print(\"\{named(1, 2u, 3ul, 4.0lf, 5l)\} \{kept(5)\}\\n\")\n\}\n"

//! The JIT IR function for the das function `name` (its symbol "`name <argument types>"), its `define` line to its end.
def private jit_body(dump, name : string) : string {
    var lines : array<string>
    var inside = false
    for (l in split(dump, "\n")) {
        inside = inside || (l |> starts_with("define ") && l |> contains("`{name} "))
        if (inside) {
            lines |> push(l)
            if (l == "\}") {
                break
            }
        }
    }
    return join(lines, "\n")
}

[test]
def test_constant_let_folds(t : T?) {
    t |> run("a read of a module `let` of a constant is that constant before simulation: AOT spells the literal where a `var` reads the global (P7.0zd)") @(t : T?) {
        let cpp = aot_context_cpp(t, "constant_let", constant_let_source)
        let named = definition_body(cpp, "inline int32_t named_")
        t |> success(!(named |> contains("das_global")), named)
        for (folded in ["& 8191)", "+ 70224)", "& 0xffu)", "* UINT64_C(0xc))", "+ -7)", "* 5.00000000000000000e-01)", "+ INT64_C(1099511627776))"]) {
            t |> success(named |> contains(folded), "{folded}: {named}")
        }
        let kept = definition_body(cpp, "inline int32_t kept_")
        t |> success(kept |> contains("das_global<int32_t,0x"), kept)
    }
    t |> run("the JIT compiles the folded constant as an immediate and a `var` as a global load (P7.0zd)") @(t : T?) {
        let ir = "{temp_directory_result() as value}/c2das_probe_constant_let.ll"
        let jit = daslang_run("constant_let", constant_let_source, jit_flags(), array<string>(), "c2das_probe", ["--", "--jit-dump={ir}"])
        t |> equal(jit.out |> ends_with("70263 5\n"), true, jit.out)
        let dump = fread(ir)
        let named = jit_body(dump, "named")
        t |> success(named |> contains("and i32 %arg_value_0, 8191"), named)
        t |> success(!(named |> contains("jit_get_global")), named)
        let kept = jit_body(dump, "kept")
        t |> success(kept |> contains("jit_get_global"), kept)
        remove(ir)
    }
}

// the `let private` chain the emitter writes for a compound `#define` (P9.5): a constant over other
// constants' names, a shift count converted, read by `named`; a `var` read by `kept`, the control
let private compound_let_source = "options gen2\nlet private POS_OP = 0\nlet private SIZE_OP = 7\nlet private POS_A = POS_OP + SIZE_OP\nlet private SIZE_A = 8\nlet private POS_K = POS_A + SIZE_A\nlet private MASK_A = ~(~0u << uint(SIZE_A))\nvar private VPOS = 15\n[export]\ndef named(i : uint) : int \{\n    return int((i >> uint(POS_A)) & MASK_A) + POS_K\n\}\n[export]\ndef kept(i : uint) : int \{\n    return int(i >> uint(VPOS))\n\}\n[export]\ndef main \{\n    print(\"\{named(0x1234u)\} \{kept(65536u)\}\\n\")\n\}\n"

[test]
def test_compound_let_folds(t : T?) {
    t |> run("a module `let` over other `let`s' names, and a conversion of one, fold before simulation: AOT spells the literals where a `var` reads the global (P9.5)") @(t : T?) {
        let cpp = aot_context_cpp(t, "compound_let", compound_let_source)
        let named = definition_body(cpp, "inline int32_t named_")
        t |> success(!(named |> contains("das_global")), named)
        let kept = definition_body(cpp, "inline int32_t kept_")
        for (folded in ["BinShr(__i_rename_at_10_0,0x7u,", "& 0xffu)", "+ 15)"]) {
            t |> success(named |> contains(folded), "{folded}: {named}")
        }
        t |> success(kept |> contains("das_global<int32_t,0x"), kept)
    }
    t |> run("the JIT compiles the chained constants as immediates and the `var` as a global load (P9.5)") @(t : T?) {
        let ir = "{temp_directory_result() as value}/c2das_probe_compound_let.ll"
        let jit = daslang_run("compound_let", compound_let_source, jit_flags(), array<string>(), "c2das_probe", ["--", "--jit-dump={ir}"])
        t |> equal(jit.out |> ends_with("51 2\n"), true, jit.out)
        let dump = fread(ir)
        let named = jit_body(dump, "named")
        t |> success(!(named |> contains("jit_get_global")) && named |> contains("lshr i32 %arg_value_0, 7") && named |> contains("i32 %4, 15"), named)
        let kept = jit_body(dump, "kept")
        t |> success(kept |> contains("jit_get_global"), kept)
        remove(ir)
    }
}

// two menus, each holding a function value and a pointer: `HEAD` is the first menu's initializer,
// `GO_BODY` the body of the function it holds, `TAIL` what follows the second menu
let menu_source = "options gen2\nstruct Menu \{\n    go : function<() : void>\n    prev : Menu?\n\}\nvar current : Menu?\nvar first : Menu = HEAD\ndef go_second \{\n    GO_BODY\n\}\nvar second : Menu = Menu(prev = unsafe(addr(first)))\nTAIL\n[export]\ndef main \{\n    invoke(first.go)\n    assert(current == unsafe(addr(second)) && deref(current).prev == unsafe(addr(first)))\n\}\n"

def menus(head, go_body, tail : string) : string => menu_source |> replace("HEAD", head) |> replace("GO_BODY", go_body) |> replace("TAIL", tail)

[test]
def test_global_init_loop(t : T?) {
    t |> run("a function value in a global initializer depends on every global its body reaches, through calls too: a cycle back is error 31104") @(t : T?) {
        let direct = menus("Menu(go = @@go_second)", "unsafe \{\n        current = addr(second)\n    \}", "")
        child_rejects(t, "address in the body", daslang_child("init_loop_direct", direct, true), "global variable initialization loop")
        let called = menus("Menu(go = @@go_second)", "pick()", "def pick \{\n    unsafe \{\n        current = addr(second)\n    \}\n\}\n")
        child_rejects(t, "address in a callee", daslang_child("init_loop_called", called, true), "global variable initialization loop")
        let read = "options gen2\nstruct Menu \{\n    go : function<() : int>\n    n : int\n\}\nvar first : Menu = Menu(go = @@size, n = 3)\ndef size : int => first.n\n"
        child_rejects(t, "a read of the global itself", daslang_child("init_loop_read", read, true), "global variable initialization loop")
    }
    t |> run("the same initializer stored by an [init] function compiles and holds C's values before main") @(t : T?) {
        let stored = menus("default<Menu>", "unsafe \{\n        current = addr(second)\n    \}", "[init]\ndef init_globals \{\n    first = Menu(go = @@go_second)\n\}\n")
        let r = daslang_child("init_loop_stored", stored, false)
        t |> equal(r.rc, 0, r.out)
    }
    t |> run("a function value whose body reaches no global of the cycle stays inline") @(t : T?) {
        let acyclic = "options gen2\nstruct Menu \{\n    go : function<() : void>\n    prev : Menu?\n\}\nvar current : Menu?\nvar other : Menu = Menu()\nvar first : Menu = Menu(go = @@go_other)\ndef go_other \{\n    unsafe \{\n        current = addr(other)\n    \}\n\}\nvar second : Menu = Menu(prev = unsafe(addr(first)))\n[export]\ndef main \{\n    invoke(first.go)\n    assert(current == unsafe(addr(other)) && second.prev == unsafe(addr(first)))\n\}\n"
        let r = daslang_child("init_loop_acyclic", acyclic, false)
        t |> equal(r.rc, 0, r.out)
    }
}
