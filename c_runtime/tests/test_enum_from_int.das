options gen2
require dastest/testing_boost public
require c_runtime/enum_from_int

enum mobjtype_t {
    MT_PLAYER
    MT_SHOTGUN = 5
    NUMMOBJTYPES
}

[test]
def test_enum_from_int(t : T?) {
    t |> run("an in-range int becomes the enumerator") @(t : T?) {
        var mtype = enum_from_int(type<mobjtype_t>, 5)
        t |> equal(mtype == mobjtype_t.MT_SHOTGUN, true)
        mtype = enum_from_int(type<mobjtype_t>, int(mtype) + 1)
        t |> equal(mtype == mobjtype_t.NUMMOBJTYPES, true)
    }
    t |> run("an out-of-range int survives by value and prints as enum N") @(t : T?) {
        let stray = enum_from_int(type<mobjtype_t>, 99)
        t |> equal(int(stray), 99)
        t |> equal("{stray}", "enum 99")
        t |> equal(stray == enum_from_int(type<mobjtype_t>, 99), true)
    }
}
