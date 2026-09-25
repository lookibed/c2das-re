options gen2
require dastest/testing_boost public

struct Point {
    x, y : int
}

struct Value {
    _storage : uint64
}

def operator . n(var s : Value) : double& {
    unsafe {
        return *addr<double?>(s._storage)
    }
}

def operator . i(var s : Value) : int64& {
    unsafe {
        return *addr<int64?>(s._storage)
    }
}

def operator . pt(var s : Value) : Point& {
    unsafe {
        return *addr<Point?>(s._storage)
    }
}

[test]
def test_unions(t : T?) {
    t |> run("members alias one storage: writing a double reads back as its bits") @(t : T?) {
        var v : Value
        v.n = 3.5lf
        t |> equal(v.i, int64(0x400C000000000000ul))
        t |> equal(typeinfo sizeof(type<Value>), 8)
        t |> equal(typeinfo alignof(type<Value>), 8)
    }
    t |> run("one ref-returning operator covers read, write, compound, nested field and addr-of") @(t : T?) {
        var v : Value
        v.i = 0l
        v.pt.x = 7
        v.pt.y = 9
        t |> equal(v.pt.x, 7)
        t |> equal(v.i, int64(0x0000000900000007ul))
        v.pt.x += 2
        t |> equal(v.pt.x, 9)
        var pp = unsafe(addr(v.pt))
        pp.y = 100
        t |> equal(v.pt.y, 100)
    }
}
