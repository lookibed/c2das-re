options gen2
require dastest/testing_boost public
require daslib/rtti
require _daslang_child
require strings

// a walk whose block keeps the info's name: `NAME` is what it pushes
let private KEEP_SOURCE = "options gen2\nrequire daslib/rtti\n\n[export]\ndef main \{\n    var kept : array<string>\n    module_for_each_function(get_module(\"$\")) $(info) \{\n        kept |> push(NAME)\n    \}\n    module_for_each_global(get_module(\"math\")) $(info) \{\n        kept |> push(NAME)\n    \}\n\}\n"

//! The das fact the converter's module walks rely on (`reserved_das_names` and
//! `registered_function_names`, `converter/emit.das`): the `FuncInfo` a `module_for_each_function`
//! walk hands its block lives only as long as the walk, and a `clone_string` of its name outlives
//! it. The walk hands its block a temporary info, so the name kept without a copy is a compile
//! error (lookibed/daScript#62, fixed upstream).

[test(description = "a clone_string of a module walk's name stays the function's name after later walks reuse the walk's storage")]
def test_walk_names(t : T?) {
    t |> run("each name copied out of a walk reads the same after another walk") @(t : T?) {
        var copied, walked : array<string>
        module_for_each_function(get_module("$")) $(info) {
            copied |> push(clone_string(info.name))
        }
        module_for_each_function(get_module("$")) $(info) {
            walked |> push(clone_string(info.name))
        }
        t |> success(length(copied) > 100, "the `$` module binds its functions")
        t |> equal(length(walked), length(copied))
        var moved = 0
        for (w, c in walked, copied) {
            if (w != c) {
                moved++
            }
        }
        t |> equal(moved, 0)
    }
}

[test(description = "a module walk's name kept without a copy is a compile error; its clone_string compiles")]
def test_walk_name_is_temporary(t : T?) {
    t |> run("`push(info.name)` in a function or a global walk is error 30341, `push(clone_string(info.name))` compiles (F112)") @(t : T?) {
        child_rejects(t, "kept_name", daslang_child("kept_name", KEEP_SOURCE |> replace("NAME", "info.name"), true), "30341")
        let copied = daslang_child("copied_name", KEEP_SOURCE |> replace("NAME", "clone_string(info.name)"), true)
        t |> equal(copied.rc, 0, copied.out)
    }
}
