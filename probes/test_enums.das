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

enum NoZero {
    A = 3
    B = 7
}

// the int32 edges the emitter spells into an enum
enum Edge {
    NEG = -1
    LO = -2147483647 - 1
    HI = 2147483647
}

struct Holder {
    e : NoZero
    n : int
}

var mobjinfo : Info[int(mobjtype_t.NUMMOBJTYPES)]
var zero_scalar : NoZero
var zero_array : NoZero[4]
var zero_holder : Holder

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
    t |> run("an enum without a zero enumerator still zero-initializes as a global, an array element and a struct field") @(t : T?) {
        t |> equal(int(zero_scalar), 0)
        t |> equal(int(zero_array[1]), 0)
        t |> equal(int(zero_holder.e), 0)
        let literal = Holder()
        t |> equal(int(literal.e), 0)
        t |> equal(zero_holder.e == unsafe(reinterpret<NoZero>(0)), true)
    }
    t |> run("an enum holds INT_MIN spelled `-2147483647 - 1`, negative enumerators, and is 4 bytes, 4-aligned") @(t : T?) {
        t |> equal(int(Edge.LO), -2147483647 - 1)
        t |> equal(int(Edge.NEG), -1)
        t |> equal(int(Edge.HI), 2147483647)
        t |> equal(uint(int(Edge.LO)), 0x80000000)
        t |> equal(typeinfo sizeof(type<Edge>), 4)
        t |> equal(typeinfo alignof(type<Edge>), 4)
    }
    t |> run("duplicate enumerator values alias and print the first-declared name") @(t : T?) {
        t |> equal(mobjtype_t.MT_ALIAS == mobjtype_t.MT_SHOTGUN, true)
        t |> equal("{mobjtype_t.MT_ALIAS}", "MT_SHOTGUN")
    }
}
