options gen2
require dastest/testing_boost public
require _daslang_child

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

def sq(x : int) : int => x * x

var literal_order : array<int>

// a value recorded in `literal_order`, so a literal's items show the order they ran in
def noted(v : int) : int {
    literal_order |> push(v)
    return v
}

struct Held {
    p : int?
    n : int
}

// a `var` record parameter, as the converter declares one holding a pointer (F3), written in place
def held_n(var h : Held) : int {
    h.n++
    return h.n
}

// a compound literal at file scope: a module global, its address another's initializer
var private g_literal : Inner = Inner(a = int8(3), b = 4l)
var private g_literal_at : Inner? = unsafe(addr(g_literal))

// the converter's opaque record: an empty struct named for a C struct the unit never defines,
// reached only through pointers
struct Opaque {}

var g_handle : Opaque?
var g_handles : Opaque? [3]

def wrap_handle(var w : WithArr?) : Opaque? => unsafe(reinterpret<Opaque?>(w))

def unwrap_handle(var o : Opaque?) : WithArr? => unsafe(reinterpret<WithArr?>(o))

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
        var n1, n2 : Node
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
    t |> run("typeinfo alignof of a scalar and of an array is C's: the size, the element's") @(t : T?) {
        t |> equal(typeinfo alignof(type<double>), 8)
        t |> equal(typeinfo alignof(type<int[4]>), 4)
        t |> equal(typeinfo alignof(type<Inner>), 8)
    }
    t |> run("an empty struct is the pointee of an opaque handle: its pointers zero, compare and round-trip through reinterpret") @(t : T?) {
        t |> equal(typeinfo sizeof(type<Opaque>), 0)
        t |> equal(typeinfo alignof(type<Opaque>), 1)
        t |> equal(g_handle == null && g_handles[2] == null, true)
        var w = WithArr(id = 41)
        g_handle = wrap_handle(unsafe(addr(w)))
        g_handles[2] = g_handle
        t |> equal(g_handles[2] == g_handle, true)
        t |> equal(unwrap_handle(g_handles[2]).id, 41)
    }
    t |> run("`struct X;` is the same empty struct, not a forward declaration: a later body redefines it") @(t : T?) {
        let bare = daslang_child("bare_struct", "options gen2\nstruct X;\nvar p : X?\n[export]\ndef main \{\n    assert(p == null && typeinfo sizeof(type<X>) == 0)\n\}\n", false)
        t |> equal(bare.rc, 0, bare.out)
        child_rejects(t, "struct_then_body", daslang_child("struct_then_body", "options gen2\nstruct X;\nstruct X \{\n    v : int\n\}\n", true), "structure is already defined")
    }
}

[test]
def test_struct_literals(t : T?) {
    t |> run("a struct literal and a fixed_array evaluate their items left to right; a literal passes to a var record parameter") @(t : T?) {
        literal_order |> clear()
        let w = Inner(a = int8(noted(1)), b = int64(noted(2)))
        let a = fixed_array(noted(3), noted(4), noted(5))
        t |> equal("{literal_order}", "[ 1, 2, 3, 4, 5]")
        t |> equal(int(w.a) + a[2], 6)
        t |> equal(held_n(Held(n = 7)), 8)
        t |> equal(g_literal_at.b, 4l)
    }
    t |> run("a record's trailing bytes past its last field read through reinterpret of its address plus an offset") @(t : T?) {
        var cells : int[4]
        unsafe {
            var s = addr<WithArr?>(cells[0])
            deref(reinterpret<int?>(reinterpret<uint8?>(s) + 8) + 1) = 9
            t |> equal(cells[3], 9)
            var p = addr(deref(addr(s.vals[0]) + 2))
            t |> equal(intptr(p) - intptr(addr(cells[0])), 12ul)
        }
    }
}
