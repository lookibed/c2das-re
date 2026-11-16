options gen2

//! Pointer comparisons as the converter writes them (`probes/test_pointer_compare.das` runs this
//! program under each tier): `==` and `!=` between two data pointers of one type as das's own
//! operators, a relation (`<`, `<=`, `>`, `>=`) over both addresses read as `uint64` through
//! `reinterpret`, and a difference as das's `p - q`. Each `cmp_*` packs the six results into one
//! mask beside what C says of the same pair; `main` prints the masks.

struct Node {
    v : int
    next : Node?
}

var g_ints : int[16]
var g_nodes : Node[8]
var g_anchor : Node

// bit 0 `==`, 1 `!=`, 2 `<`, 3 `<=`, 4 `>`, 5 `>=`
def cmp_ints(p, q : int?) : int {
    var r = 0
    unsafe {
        r |= p == q ? 1 : 0
        r |= p != q ? 2 : 0
        r |= reinterpret<uint64>(p) < reinterpret<uint64>(q) ? 4 : 0
        r |= reinterpret<uint64>(p) <= reinterpret<uint64>(q) ? 8 : 0
        r |= reinterpret<uint64>(p) > reinterpret<uint64>(q) ? 16 : 0
        r |= reinterpret<uint64>(p) >= reinterpret<uint64>(q) ? 32 : 0
    }
    return r
}

def cmp_nodes(p, q : Node?) : int {
    var r = 0
    unsafe {
        r |= p == q ? 1 : 0
        r |= p != q ? 2 : 0
        r |= reinterpret<uint64>(p) < reinterpret<uint64>(q) ? 4 : 0
        r |= reinterpret<uint64>(p) <= reinterpret<uint64>(q) ? 8 : 0
        r |= reinterpret<uint64>(p) > reinterpret<uint64>(q) ? 16 : 0
        r |= reinterpret<uint64>(p) >= reinterpret<uint64>(q) ? 32 : 0
    }
    return r
}

def cmp_void(p, q : void?) : int {
    var r = 0
    unsafe {
        r |= p == q ? 1 : 0
        r |= p != q ? 2 : 0
        r |= reinterpret<uint64>(p) < reinterpret<uint64>(q) ? 4 : 0
        r |= reinterpret<uint64>(p) >= reinterpret<uint64>(q) ? 32 : 0
    }
    return r
}

// the circular list of Doom's thinkers: walk from the anchor until the anchor comes round again
def walk(var start : Node?) : int {
    var n = 0
    var p = start.next
    while (p != unsafe(addr(g_anchor))) {
        n += p.v
        p = p.next
    }
    return n
}

// R_FindPlane's scan: `for (check = base; check < last; check++) if (check == want) break;`
def find_slot(var base : int?; last, want : int?) : int {
    var steps = 0
    unsafe {
        while (reinterpret<uint64>(base) < reinterpret<uint64>(last)) {
            if (base == want) {
                break
            }
            base++
            steps++
        }
    }
    return steps
}

// a `let` copy of a pointer and a field read through a `let` pointer compare with a `var` one
def through_let(s : Node?; var q : Node?) : int {
    let c = q
    return (c == q ? 1 : 0) | (s.next == q ? 2 : 0) | (s.next != c ? 4 : 0)
}

[export]
def main : int {
    unsafe {
        var a : int? = addr(g_ints[0])
        var b : int? = addr(g_ints[0]) + 3
        var end : int? = addr(g_ints[0]) + 16
        print("ints {cmp_ints(a, b)} {cmp_ints(b, a)} {cmp_ints(a, a)} {cmp_ints(end, b)} {cmp_ints(a, null)} {cmp_ints(null, null)}\n")
        var n0 : Node? = addr(g_nodes[0])
        var n5 : Node? = addr(g_nodes[5])
        print("nodes {cmp_nodes(n0, n5)} {cmp_nodes(n5, n0)} {cmp_nodes(n5, addr(g_nodes[0]) + 5)}\n")
        print("void {cmp_void(reinterpret<void?>(a), reinterpret<void?>(b))} {cmp_void(reinterpret<void?>(b), reinterpret<void?>(a))} {cmp_void(reinterpret<void?>(n0), addr<void?>(g_nodes[0]))}\n")
        g_anchor.next = addr(g_nodes[0])
        for (i in range(4)) {
            g_nodes[i].v = i + 1
            g_nodes[i].next = i == 3 ? addr(g_anchor) : addr(g_nodes[i + 1])
        }
        print("walk {walk(addr(g_anchor))}\n")
        print("find {find_slot(a, end, b)} {find_slot(a, end, null)} {find_slot(b, a, b)}\n")
        g_nodes[6].next = n5
        print("let {through_let(addr(g_nodes[6]), n5)} {through_let(addr(g_nodes[6]), n0)}\n")
        print("diff {b - a} {a - b} {n5 - n0} {end - end}\n")
    }
    return 0
}
