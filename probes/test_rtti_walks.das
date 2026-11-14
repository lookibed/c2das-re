options gen2
require dastest/testing_boost public
require daslib/rtti

//! The das fact the converter's module walks rely on (`reserved_das_names` and
//! `registered_function_names`, `converter/emit.das`): the `FuncInfo` a `module_for_each_function`
//! walk hands its block, and the name in it, live only as long as the walk.

[test(description = "a name kept from a module walk without a copy dangles once the walk returns: a later walk reuses its storage, so some kept names no longer read as the function's; a copied name stays")]
def test_walk_names(t : T?) {
    t |> run("a FuncInfo name kept past its walk reads another walk's bytes; clone_string keeps the name") @(t : T?) {
        var kept, copied : array<string>
        module_for_each_function(get_module("$")) $(info) {
            kept |> push(info.name)
            copied |> push(clone_string(info.name))
        }
        var walked : array<string>
        module_for_each_function(get_module("$")) $(info) {
            walked |> push(clone_string(info.name))
        }
        var dangling = 0
        for (k, c in kept, copied) {
            if (k != c) {
                dangling++
            }
        }
        t |> success(dangling > 0, "every kept name still reads as its function's: the walk's storage outlives the walk")
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
