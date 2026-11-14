options gen2
require dastest/testing_boost public
require daslib/rtti

//! The das fact the converter's module walks rely on (`reserved_das_names` and
//! `registered_function_names`, `converter/emit.das`): the `FuncInfo` a `module_for_each_function`
//! walk hands its block lives only as long as the walk, and a `clone_string` of its name outlives
//! it. The name kept without a copy dangles; that half reads freed memory and lives as a repro in
//! lookibed/daScript#62, not here.

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
