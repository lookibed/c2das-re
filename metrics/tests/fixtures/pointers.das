options gen2
require c_runtime/c_function
require c_runtime/c_bounds

var g = fixed_array(1, 2, 3, 4)
var gp = unsafe(addr(g[0]))
var gq = unsafe(unsafe(addr(g[0])) + 3)

[c_function]
def walk(p : int?; q : int?; n : int) : int64 {
    var a : int[4]
    var w = p
    var s = deref(p + n) + deref(w - 1) + p[2]
    w++
    w += 2
    var e = addr(a[0]) + end_index(n, 4)
    s += deref(e - 1)
    let bytes = reinterpret<uint8?>(w)
    return (p - q) + int64(s) + int64(deref(bytes))
}

def plain(p : int?) : int {
    unsafe {
        return deref(p + 1)
    }
}

def guarded(var x : int) : int => deref(unsafe(addr(x))) + deref(gp) + deref(gq)

[export]
def main {
    var x = 0
    let px = unsafe(addr(x))
    print("{walk(px, px, 0)} {plain(px)} {guarded(x)}\n")
}

var unused_global = unsafe(addr(g[1]))

def private unused_function(p : int?) : uint8? => unsafe(reinterpret<uint8?>(p))
