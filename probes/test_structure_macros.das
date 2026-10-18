options gen2
require dastest/testing_boost public
require strings
require _probe_macros
require _daslang_child

//! A structure annotation at parse time can erase a field, rename and retype another, and add a
//! property pair whose call sites read like a field: the mechanism `c_runtime/c_bitfields`
//! stands on. Its string argument comes back as written; a type keyword is no value.

[probe_reshape(storage = "uint")]
struct Reshaped {
    keep : int8
    gone : double
    tail : int16
}

[test]
def test_structure_macros(t : T?) {
    t |> run("the annotation erased, renamed and retyped fields before layout") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Reshaped>), 8)
        t |> equal(typeinfo offsetof < tail > (type<Reshaped>), 4)
        var s : Reshaped
        s._store = 7u
        t |> equal(s._store, 7u)
    }
    t |> run("the generated property pair serves read, store and compound store") @(t : T?) {
        var s : Reshaped
        s.x = 5u
        t |> equal(s.x, 5u)
        s.x += 3u
        t |> equal(s.x, 8u)
        t |> equal(s._store, 8u)
    }
    t |> run("a bare type keyword as an annotation argument value is a syntax error") @(t : T?) {
        let r = daslang_child("keyword_value", "options gen2\n[export(storage = uint8)]\ndef main \{\n\}\n", true)
        t |> equal(r.rc != 0, true, r.out)
        t |> equal(r.out |> find("unexpected uint8") >= 0, true, r.out)
    }
}
