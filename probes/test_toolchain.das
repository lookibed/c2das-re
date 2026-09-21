options gen2
require dastest/testing_boost public
require cbind

struct Pair {
    x : int
    y : int16
}

struct Mixed {
    a : int8
    b : int64
    c : double
}

[test]
def test_toolchain(t : T?) {
    t |> run("cbind loads and libclang answers") @(t : T?) {
        let idx = clang_createIndex(0, 0)
        t |> success(idx != null, "clang_createIndex")
        clang_disposeIndex(idx)
    }
    t |> run("small-int arithmetic computes in int and truncates on store") @(t : T?) {
        var b : int8 = int8(127)
        b = int8(int(b) + 1)
        t |> equal(int(b), -128)
    }
    t |> run("signed division, remainder and shift match C99 on x86") @(t : T?) {
        t |> equal(-7 / 2, -3)
        t |> equal(-7 % 2, -1)
        t |> equal(-8 >> 1, -4)
    }
    t |> run("goto to a lexically enclosing label") @(t : T?) {
        var n = 0
        goto label 1
        n = 100
        label 1:
        n++
        t |> equal(n, 1)
    }
    t |> run("struct layout matches clang for natural shapes") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Pair>), 8)
        t |> equal(typeinfo sizeof(type<Mixed>), 24)
        t |> equal(typeinfo offsetof < b > (type<Mixed>), 8)
        t |> equal(typeinfo offsetof < c > (type<Mixed>), 16)
    }
}
