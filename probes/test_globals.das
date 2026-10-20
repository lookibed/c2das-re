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
    t |> run("the AOT context finds a module global by its mangled-name hash at every access, solid_context or not") @(t : T?) {
        for (case_name, options_line in ["hashed", "solid"], ["", "options solid_context = true"]) {
            let cpp = aot_context_cpp(t, case_name, global_access_source |> replace("OPTIONS_LINE", options_line))
            let body = definition_body(cpp, "inline int32_t main_")
            t |> equal(count(body, "das_global<TDim<int32_t,4>,0x"), 2, "{case_name}: {body}")
            t |> success(!(body |> contains("das_global_solid")), "{case_name}: {body}")
            t |> equal(cpp |> contains("das_global_zero_solid<TDim<int32_t,4>,"), case_name == "solid", "{case_name}: the initializer")
        }
    }
}
