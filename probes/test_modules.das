options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require _daslang_child

//! The das facts the source module layout relies on (`converter/ARCHITECTURE_LAYOUT.md`): each
//! case writes a tree of modules into a fresh folder and runs its `main.das` there, with the
//! c_runtime modules loaded, so the caches daslang keeps beside a run land in that folder.

// one file of a probe's tree: its name and its text
struct ProbeFile {
    name : string
    text : string
}

def private probe_file(name, text : string) : ProbeFile => ProbeFile(name = name, text = text)

// `files` written into a fresh folder named after `name`; the folder, "" when it cannot be made
def private write_tree(name : string; files : array<ProbeFile>) : string {
    var dir_error : string
    let dir = create_temp_directory("c2das_probe_{name}", dir_error)
    if (!empty(dir_error)) {
        return ""
    }
    for (f in files) {
        fwrite(path_join(dir, f.name), f.text)
    }
    return dir
}

// `daslang <flags> main.das` run inside `dir` with the c_runtime modules loaded: its exit code and
// its output, the runtime's `info` lines kept (the JIT reports its cache there)
def private run_main(dir : string; flags : array<string>) : tuple<rc : int; out : string> {
    var argv <- ["sh", "-c", "cd \"$0\" && exec \"$@\"", dir, get_das_root() + "/bin/daslang"]
    argv |> reserve(length(argv) + 2 * length(RUNTIME_MODULES) + length(flags) + 1)
    for (m in RUNTIME_MODULES) {
        argv |> push("-load_module")
        argv |> push(get_full_file_name(m))
    }
    argv |> push_from(flags)
    argv |> push("main.das")
    let level = get_env_variable("DAS_LOG_LEVEL")
    set_env_variable("DAS_LOG_LEVEL", "info")
    var out : string
    let rc = run_and_capture(argv, out, 300.0)
    set_env_variable("DAS_LOG_LEVEL", level)
    return (rc, out)
}

def private run_plain(dir : string) : tuple<rc : int; out : string> => run_main(dir, array<string>())

// a tree's run: it exits 0 and its program output is `want`
def private runs_as(t : T?; what : string; r : tuple<rc : int; out : string>; want : string) {
    t |> equal(r.rc, 0, "{what}: {r.out}")
    t |> equal(program_output(r.out), want, "{what}: {r.out}")
}

let CLUSTER = "options gen2\ninclude f1.das.inc\ninclude f2.das.inc\n"

let FRAGMENT_ONE = "struct Node \{\n    v : int\n    next : Node?\n\}\n\nvar seen : int = 0\nvar private hidden : int = 4\n\ndef f1(n : int) : int \{\n    seen++\n    return n <= 0 ? 1 : f2(n - 1) * 2\n\}\n\n[init]\ndef private init_one \{\n    print(\"init f1\\n\")\n\}\n"

let FRAGMENT_TWO = "var vals : int[3] = fixed_array(1, 2, 3)\n\ndef f2(n : int) : int => n <= 0 ? vals[0] : f1(n - 1) + hidden\n\ndef make : Node => Node(v = vals[2])\n\n[init]\ndef private init_two \{\n    print(\"init f2\\n\")\n\}\n"

[test]
def test_fragments(t : T?) {
    t |> run("an included fragment splices into its module: fragments call each other, share struct, global and private names, and their [init]s run in include order") @(t : T?) {
        let dir = write_tree("fragments", [probe_file("k_cluster.das", CLUSTER), probe_file("f1.das.inc", FRAGMENT_ONE), probe_file("f2.das.inc", FRAGMENT_TWO), probe_file("main.das", "options gen2\nrequire k_cluster\n[export]\ndef main \{\n    print(\"\{f1(3)\} \{seen\} \{make().v\}\\n\")\n\}\n")])
        // f1(3) = f2(2) * 2, f2(2) = f1(1) + 4, f1(1) = f2(0) * 2 = 2
        runs_as(t, "fragments", run_plain(dir), "init f1\ninit f2\n12 2 3\n")
        rmdir_rec(dir)
    }
}

let GLOBALS_A = "options gen2\nvar ga : int = 5\nvar gz : int\nvar ga_seen : int = 0\n\n[init]\ndef private c2das_init_globals \{\n    ga_seen = ga\n    ga = 7\n    print(\"init a\\n\")\n\}\n"

let GLOBALS_B = "options gen2\nrequire a\nvar gb : int = 1\nvar gb_read : int = ga\nvar pa : int? = unsafe(addr(ga))\nvar pz : int? = unsafe(addr(gz))\n\n[init]\ndef private c2das_init_globals \{\n    gb = ga\n    print(\"init b\\n\")\n\}\n"

let GLOBALS_MAIN = "options gen2\nrequire a\nrequire b\n[export]\ndef main \{\n    unsafe \{\n        deref(pa) += 10\n        deref(pz) = 4\n    \}\n    a::ga += 1\n    print(\"\{ga\} \{gz\} \{gb\} \{gb_read\} \{ga_seen\}\\n\")\n\}\n"

[test]
def test_module_globals(t : T?) {
    t |> run("a module's var global is read, written and has its address taken from another module, a zero-initialized one included, in a global initializer too") @(t : T?) {
        let dir = write_tree("globals", [probe_file("a.das", GLOBALS_A), probe_file("b.das", GLOBALS_B), probe_file("main.das", GLOBALS_MAIN)])
        // ga: 5, its [init] 7, +10 through b's pointer, +1 by name
        let r = run_plain(dir)
        t |> equal(r.rc, 0, r.out)
        let last = split(program_output(r.out), "\n")
        t |> equal(length(last) >= 3 ? last[2] : "", "18 4 7 5 5", r.out)
        rmdir_rec(dir)
    }
    t |> run("initialization follows require: every module's global initializers run first, the required module's before the requiring one's, then the [init] functions in the same order") @(t : T?) {
        let dir = write_tree("init_order", [probe_file("a.das", GLOBALS_A), probe_file("b.das", GLOBALS_B), probe_file("main.das", GLOBALS_MAIN)])
        // b's `gb_read = ga` reads a's initializer (5), not a's [init] (7): a's globals are set
        // before b's, and no [init] runs before every global is set; a's [init] runs first
        runs_as(t, "init order", run_plain(dir), "init a\ninit b\n18 4 7 5 5\n")
        rmdir_rec(dir)
    }
}

[test]
def test_module_names(t : T?) {
    t |> run("a module without a `module` line is required by its stem and exports its names; `def private` and `var private` of one name in two modules do not collide") @(t : T?) {
        let dir = write_tree("private", [probe_file("a.das", "options gen2\ndef private helper : int => 1\nvar private gs = 5\ndef a_value : int => helper() + gs\n"), probe_file("main.das", "options gen2\nrequire a\ndef private helper : int => 2\nvar private gs = 7\n[export]\ndef main \{\n    print(\"\{a_value()\} \{helper()\} \{gs\}\\n\")\n\}\n")])
        runs_as(t, "private", run_plain(dir), "6 2 7\n")
        rmdir_rec(dir)
    }
    t |> run("a private function collides with a public one of its name in a module it requires; a module requiring both sees the public one alone") @(t : T?) {
        let dir = write_tree("private_public", [probe_file("c.das", "options gen2\ndef foo : int => 100\n"), probe_file("a.das", "options gen2\nrequire c\ndef private foo : int => 1\ndef a_foo : int => foo()\n"), probe_file("main.das", "options gen2\nrequire a\nrequire c\n[export]\ndef main \{\n    print(\"\{a_foo()\}\\n\")\n\}\n")])
        let r = run_plain(dir)
        child_rejects(t, "private beside a required public", r, "too many matching functions or generics foo")
        fwrite(path_join(dir, "a.das"), "options gen2\nrequire c\ndef private bar : int => 1\ndef a_foo : int => bar()\n")
        fwrite(path_join(dir, "main.das"), "options gen2\nrequire a\nrequire c\n[export]\ndef main \{\n    print(\"\{a_foo()\} \{foo()\}\\n\")\n\}\n")
        runs_as(t, "public alone", run_plain(dir), "1 100\n")
        rmdir_rec(dir)
    }
    t |> run("two required modules exporting one function or one global make a bare use ambiguous; `module::name` resolves each") @(t : T?) {
        let dir = write_tree("qualified", [probe_file("a.das", "options gen2\ndef shared_name : int => 100\nvar both = 1\n"), probe_file("b.das", "options gen2\ndef shared_name : int => 200\nvar both = 2\n"), probe_file("main.das", "options gen2\nrequire a\nrequire b\n[export]\ndef main \{\n    print(\"\{shared_name()\}\\n\")\n\}\n")])
        child_rejects(t, "bare function", run_plain(dir), "too many matching functions or generics shared_name")
        fwrite(path_join(dir, "main.das"), "options gen2\nrequire a\nrequire b\n[export]\ndef main \{\n    print(\"\{both\}\\n\")\n\}\n")
        child_rejects(t, "bare global", run_plain(dir), "too many matching variables 'both'")
        fwrite(path_join(dir, "main.das"), "options gen2\nrequire a\nrequire b\n[export]\ndef main \{\n    b::both += 5\n    print(\"\{a::shared_name()\} \{b::shared_name()\} \{a::both\} \{b::both\}\\n\")\n\}\n")
        runs_as(t, "qualified", run_plain(dir), "100 200 1 7\n")
        rmdir_rec(dir)
    }
    t |> run("a struct of one module and a function of its name in another live side by side: a call is the function, a named-field construction the struct") @(t : T?) {
        let dir = write_tree("struct_function", [probe_file("c.das", "options gen2\nstruct node \{\n    v : int\n\}\n"), probe_file("f.das", "options gen2\ndef node(x : int) : int => x + 1\n"), probe_file("main.das", "options gen2\nrequire c\nrequire f\n[export]\ndef main \{\n    let n = node(v = 3)\n    print(\"\{node(4)\} \{n.v\}\\n\")\n\}\n")])
        runs_as(t, "struct and function", run_plain(dir), "5 3\n")
        rmdir_rec(dir)
    }
    t |> run("a cyclic require is refused: the fact that makes mutually dependent files one module") @(t : T?) {
        let dir = write_tree("cycle", [probe_file("x.das", "options gen2\nrequire y\ndef fx : int => 1\n"), probe_file("y.das", "options gen2\nrequire x\ndef fy : int => fx()\n"), probe_file("main.das", "options gen2\nrequire x\n[export]\ndef main \{\n    print(\"\{fx()\}\\n\")\n\}\n")])
        child_rejects(t, "cycle", run_plain(dir), "circular dependency 'x'")
        rmdir_rec(dir)
    }
}

let ANNOTATED_A = "options gen2\nrequire c_runtime/variadic\nrequire c_runtime/c_function\n\nstruct P \{\n    x, y : int\n\}\n\n[variadic]\ndef vsum(n : int; va : va_args) : int \{\n    var ap : CVaCursor\n    ap = va_begin(va)\n    var s : int = 0\n    for (i in range(n)) \{\n        s += int(va_i(ap))\n    \}\n    return s\n\}\n\n[c_function]\ndef bump(var p : int?) : int \{\n    deref(p) += 1\n    return deref(p)\n\}\n"

let ANNOTATED_B = "options gen2\nrequire a\nrequire c_runtime/c_union\nrequire c_runtime/c_bitfields\n\n[c_union]\nstruct U \{\n    p : P\n    i : int64\n\}\n\n[c_bitfields(a = 3, b = 5)]\nstruct B \{\n    a, b : uint\n    q : P\n\}\n\ndef pick : function<(var a0 : int?) : int> => @@bump\n"

let ANNOTATED_MAIN = "options gen2\nrequire a\nrequire b\nrequire c_runtime/variadic\n[export]\ndef main \{\n    var u : U\n    u.p.x = 3\n    var bb : B\n    bb.a = 5u\n    bb.b = 9u\n    bb.q.y = 4\n    var n = 1\n    unsafe \{\n        print(\"\{vsum`va(3, (1, 2, 3))\} \{u.p.x\} \{int(bb.a)\} \{int(bb.b)\} \{bb.q.y\} \{invoke(pick(), addr(n))\} \{bump(addr(n))\}\\n\")\n    \}\n\}\n"

[test]
def test_annotations_across_modules(t : T?) {
    t |> run("a struct of another module serves as a [c_union] member and beside [c_bitfields]; a [variadic] and a [c_function] function are called, and taken as a value, from other modules") @(t : T?) {
        let dir = write_tree("annotations", [probe_file("a.das", ANNOTATED_A), probe_file("b.das", ANNOTATED_B), probe_file("main.das", ANNOTATED_MAIN)])
        runs_as(t, "annotations", run_plain(dir), "6 3 5 9 4 2 3\n")
        rmdir_rec(dir)
    }
}

[test]
def test_caches(t : T?) {
    t |> run("the JIT compiles a program of several modules once and loads it from its DLL cache on the next run") @(t : T?) {
        let dir = write_tree("jit_cache", [probe_file("k_cluster.das", CLUSTER), probe_file("f1.das.inc", FRAGMENT_ONE), probe_file("f2.das.inc", FRAGMENT_TWO), probe_file("h.das", "options gen2\nrequire k_cluster\ndef h : int => f1(3)\n"), probe_file("main.das", "options gen2\nrequire h\nrequire k_cluster\n[export]\ndef main \{\n    print(\"\{h()\} \{f2(1)\}\\n\")\n\}\n")])
        let first = run_main(dir, ["-jit"])
        t |> success(first.out |> contains("DLL cache miss") && first.out |> contains("3 das-module partitions"), first.out)
        let second = run_main(dir, ["-jit"])
        t |> success(second.out |> contains("DLL cache hit"), second.out)
        t |> equal(program_output(second.out), program_output(first.out))
        rmdir_rec(dir)
    }
    t |> run("daslang's module cache serves a module whose included fragment changed from the stale cache (docs/probe-findings.md F72); a change to the including file's own text refreshes it") @(t : T?) {
        let dir = write_tree("module_cache", [probe_file("k_cluster.das", CLUSTER), probe_file("f1.das.inc", FRAGMENT_ONE), probe_file("f2.das.inc", FRAGMENT_TWO), probe_file("main.das", "options gen2\nrequire k_cluster\n[export]\ndef main \{\n    print(\"\{f1(3)\}\\n\")\n\}\n")])
        runs_as(t, "first run", run_plain(dir), "init f1\ninit f2\n12\n")
        fwrite(path_join(dir, "f1.das.inc"), FRAGMENT_ONE |> replace("* 2", "* 3"))
        // f1(3) = (f1(1) + 4) * 3 with f1(1) = 3: 21 is the edited fragment's answer
        runs_as(t, "stale", run_plain(dir), "init f1\ninit f2\n12\n")
        runs_as(t, "uncached", run_main(dir, ["-no-module-cache"]), "init f1\ninit f2\n21\n")
        fwrite(path_join(dir, "k_cluster.das"), CLUSTER + "// fragments 1\n")
        runs_as(t, "refreshed", run_plain(dir), "init f1\ninit f2\n21\n")
        rmdir_rec(dir)
    }
}

// a late-bound pair (`converter/ARCHITECTURE_LAYOUT.md`, the cycle cut): the link module's slots and
// same-named wrappers, a plain one and a variadic one forwarding its list
let LATE_LINK = "options gen2\nrequire c_runtime/variadic\nvar f_slot : function<(a0 : int) : int>\ndef f(a0 : int) : int \{\n    if (f_slot == null) \{\n        panic(\"f is late-bound and no module has set it\")\n    \}\n    return invoke(f_slot, a0)\n\}\nvar g_slot : function<(a0 : int; a1 : CVaList) : int>\n[variadic]\ndef g(a0 : int; va : va_args) : int \{\n    if (g_slot == null) \{\n        panic(\"g is late-bound and no module has set it\")\n    \}\n    return invoke(g_slot, a0, va)\n\}\n"

// the defining module: it fills the slots in its `[init]` and spells its own functions qualified
let LATE_DEFS = "options gen2\nrequire prog_link\nrequire c_runtime/variadic\ndef f(a : int) : int => a * 2\n[variadic]\ndef g(n : int; va : va_args) : int \{\n    var ap : CVaCursor\n    ap = va_begin(va)\n    var s = 0\n    for (i in range(n)) \{\n        s += int(va_i(ap))\n    \}\n    return s + __::f(1)\n\}\ndef private g_late(a0 : int; a1 : CVaList) : int => __::g`va(a0, a1)\ndef own : int => __::f(10) + __::g`va(1, (5,))\n[init]\ndef private c2das_link \{\n    f_slot = @@__::f\n    g_slot = @@g_late\n    print(\"filled\\n\")\n\}\n"

// a module that reaches the functions through the link module alone
let LATE_CALLER = "options gen2\nrequire prog_link\nrequire c_runtime/variadic\ndef use : int => f(5) + g`va(2, (3, 4)) + g`va(0, VaNone())\n"

// a module whose `[init]` calls a wrapper before the defining module's `[init]` runs
let LATE_EARLY = "options gen2\nrequire prog_link\n[init]\ndef private early_call \{\n    print(\"early \{f(1)\}\\n\")\n\}\n"

[test]
def test_late_binding(t : T?) {
    t |> run("a slot in one module, filled by another module's [init], is invoked through its same-named wrapper from a third, a variadic one with its list forwarded") @(t : T?) {
        let dir = write_tree("late", [probe_file("prog_link.das", LATE_LINK), probe_file("defs.das", LATE_DEFS), probe_file("caller.das", LATE_CALLER), probe_file("main.das", "options gen2\nrequire caller\nrequire defs\n[export]\ndef main \{\n    print(\"\{use()\} \{own()\}\\n\")\n\}\n")])
        // use: f(5) 10, g(2, 3, 4) 7 + f(1) 2, g(0) 2; own: f(10) 20, g(1, 5) 5 + 2
        runs_as(t, "late", run_plain(dir), "filled\n21 27\n")
        rmdir_rec(dir)
    }
    t |> run("in the defining module a bare name is ambiguous with the wrapper; `__::name` resolves it, and `module::name` does where the module is required") @(t : T?) {
        let dir = write_tree("late_bare", [probe_file("prog_link.das", LATE_LINK), probe_file("defs.das", LATE_DEFS |> replace("def own : int => __::f(10)", "def own : int => f(10)")), probe_file("caller.das", LATE_CALLER), probe_file("main.das", "options gen2\nrequire caller\nrequire defs\n[export]\ndef main \{\n    print(\"\{use()\} \{own()\}\\n\")\n\}\n")])
        child_rejects(t, "bare", run_plain(dir), "too many matching functions or generics f")
        fwrite(path_join(dir, "defs.das"), LATE_DEFS)
        fwrite(path_join(dir, "main.das"), "options gen2\nrequire prog_link\nrequire defs\n[export]\ndef main \{\n    print(\"\{defs::f(2)\} \{own()\}\\n\")\n\}\n")
        runs_as(t, "qualified", run_plain(dir), "filled\n4 27\n")
        rmdir_rec(dir)
    }
    t |> run("a wrapper called before the defining module's [init] fills its slot fails closed with the symbol's name") @(t : T?) {
        let dir = write_tree("late_early", [probe_file("prog_link.das", LATE_LINK), probe_file("defs.das", LATE_DEFS), probe_file("caller.das", LATE_CALLER), probe_file("early.das", LATE_EARLY), probe_file("main.das", "options gen2\nrequire early\nrequire caller\nrequire defs\n[export]\ndef main \{\n    print(\"\{use()\} \{own()\}\\n\")\n\}\n")])
        child_rejects(t, "early", run_plain(dir), "f is late-bound and no module has set it")
        rmdir_rec(dir)
    }
}
