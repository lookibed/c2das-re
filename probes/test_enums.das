options gen2
require dastest/testing_boost public

enum mobjtype_t {
    MT_PLAYER
    MT_SHOTGUN = 5
    NUMMOBJTYPES
    MT_ALIAS = 5
}

struct Info {
    speed : int
}

var mobjinfo : Info[int(mobjtype_t.NUMMOBJTYPES)]

[test]
def test_enums(t : T?) {
    t |> run("equality is direct; relational and index go through int()") @(t : T?) {
        let tt = mobjtype_t.MT_SHOTGUN
        t |> equal(tt == mobjtype_t.MT_SHOTGUN, true)
        t |> equal(tt != mobjtype_t.MT_PLAYER, true)
        t |> equal(int(tt) < int(mobjtype_t.NUMMOBJTYPES), true)
        mobjinfo[int(tt)].speed = 3
        t |> equal(mobjinfo[5].speed, 3)
    }
    t |> run("the count enumerator const-folds as a fixed-array dimension") @(t : T?) {
        t |> equal(typeinfo dim(mobjinfo), 6)
    }
    t |> run("int to enum is an unsafe reinterpret; out-of-range values survive by value") @(t : T?) {
        unsafe {
            let e = reinterpret<mobjtype_t>(6)
            t |> equal(e == mobjtype_t.NUMMOBJTYPES, true)
            let bad = reinterpret<mobjtype_t>(99)
            t |> equal(int(bad), 99)
            t |> equal("{bad}", "enum 99")
            t |> equal(bad == reinterpret<mobjtype_t>(99), true)
        }
    }
    t |> run("duplicate enumerator values alias and print the first-declared name") @(t : T?) {
        t |> equal(mobjtype_t.MT_ALIAS == mobjtype_t.MT_SHOTGUN, true)
        t |> equal("{mobjtype_t.MT_ALIAS}", "MT_SHOTGUN")
    }
}
