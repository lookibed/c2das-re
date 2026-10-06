options gen2
require dastest/testing_boost public

struct Inner {
    a : int8
    b : int64
}

struct WithArr {
    id : int
    vals : int[4]
    inner : Inner
}

struct Node {
    v : int
    next : Node?
}

struct Thinker {
    fn : int
    prev : Thinker?
}

struct Mobj {
    thinker : Thinker
    x, y : int
}

var g_tab : WithArr[2] = fixed_array(WithArr(id = 1), WithArr(id = 2, vals = fixed_array(1, 2, 3, 4)))

def write_param(var s : WithArr) {
    s.id = 99
}

def callee_copy(s_in : WithArr) : int {
    var s = s_in
    s.id = 42
    return s.id
}

def make() : WithArr {
    var r : WithArr
    r.id = 5
    r.vals[2] = 7
    return r
}

def sq(x : int) : int {
    return x * x
}

// the layout law checked at compile time from an [init] body: the converter's generated
// modules assert clang's layout this way at zero run-time cost
[init]
def private layout_at_init {
    static_assert(typeinfo sizeof(type<Mobj>) == 24 && typeinfo alignof(type<Mobj>) == 8, "Mobj: size 24, align 8")
    static_assert(typeinfo offsetof < x > (type<Mobj>) == 16, "Mobj.x at 16")
}

[test]
def test_structs(t : T?) {
    t |> run("plain = deep-copies POD including fixed-array and nested members") @(t : T?) {
        var a = WithArr(id = 3, vals = fixed_array(1, 2, 3, 4))
        a.inner.b = 77l
        var b = a
        b.vals[0] = 100
        b.inner.b = 1l
        t |> equal(a.vals[0], 1)
        t |> equal(a.inner.b, 77l)
        t |> equal(b.vals[0], 100)
        var f2 : int[3]
        let f1 = fixed_array(1, 2, 3)
        f2 = f1
        f2[0] = 9
        t |> equal(f1[0], 1)
        t |> equal(f2[0], 9)
    }
    t |> run("a var struct param is a reference; C by-value needs a callee copy") @(t : T?) {
        var a : WithArr
        write_param(a)
        t |> equal(a.id, 99)
        t |> equal(callee_copy(a), 42)
        t |> equal(a.id, 99)
    }
    t |> run("struct return by value and partial init zero the rest") @(t : T?) {
        let m = make()
        t |> equal(m.id, 5)
        t |> equal(m.vals[2], 7)
        let partial = WithArr(id = 4)
        t |> equal(partial.vals[1], 0)
        t |> equal(partial.inner.b, 0l)
    }
    t |> run("a global table of struct literals initializes inline") @(t : T?) {
        t |> equal(g_tab[1].vals[3], 4)
        t |> equal(g_tab[0].vals[3], 0)
    }
    t |> run("self-referential struct and function-pointer invoke") @(t : T?) {
        var n1 : Node
        var n2 : Node
        n2.v = 2
        n1.next = unsafe(addr(n2))
        t |> equal(n1.next.v, 2)
        let fp = @@sq
        t |> equal(invoke(fp, 6), 36)
    }
    t |> run("prefix punning and container_of through reinterpret") @(t : T?) {
        var mo : Mobj
        mo.x = 11
        unsafe {
            let th = addr<Thinker?>(mo)
            let back = reinterpret<Mobj?>(th)
            t |> equal(back.x, 11)
            let thp = addr(mo.thinker)
            let m2 = reinterpret<Mobj?>(intptr(thp) - uint64(typeinfo offsetof < thinker > (type<Mobj>)))
            t |> equal(m2.x, 11)
        }
    }
}
