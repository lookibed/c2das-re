// research 01: the converted next_fetch module hand-edited into the helper-call form (inline)
options gen2
options indenting = 4
options stack = 8388608
require c_runtime/c_function
require c_runtime/c_volatile
require c_runtime/printf
require crt

[init]
def private c2das_dialect {
    c_long_bits = 64
}

struct Zio {
    n : uint64
    p, base : uint8?
    size : uint64
}

struct LexState {
    current : int
    z : Zio?
}

[init]
def private c2das_layout_check {
    static_assert(typeinfo sizeof(type<Zio>) == 32 && typeinfo alignof(type<Zio>) == 8, "Zio: clang lays it out as size 32, align 8")
    static_assert(typeinfo offsetof < n > (type<Zio>) == 0, "Zio.n: clang puts it at 0")
    static_assert(typeinfo offsetof < p > (type<Zio>) == 8, "Zio.p: clang puts it at 8")
    static_assert(typeinfo offsetof < base > (type<Zio>) == 16, "Zio.base: clang puts it at 16")
    static_assert(typeinfo offsetof < size > (type<Zio>) == 24, "Zio.size: clang puts it at 24")
    static_assert(typeinfo sizeof(type<LexState>) == 16 && typeinfo alignof(type<LexState>) == 8, "LexState: clang lays it out as size 16, align 8")
    static_assert(typeinfo offsetof < current > (type<LexState>) == 0, "LexState.current: clang puts it at 0")
    static_assert(typeinfo offsetof < z > (type<LexState>) == 8, "LexState.z: clang puts it at 8")
}

var private next_fetch__rounds : int = 3000
var private next_fetch__text : uint8[256]
var private next_fetch__zio : Zio
var private next_fetch__lex : LexState
var private next_fetch__result : int
var private next_fetch__c2das_sink : int

[c_function]
def private next_fetch__fill(var z : Zio?) : int {
    if (z.p == null) {
        return -1
    }
    z.p = z.base
    z.n = z.size - uint64(1)
    var _t0 = z.p
    z.p = z.p + 1
    return int(uint8(deref(_t0)))
}

// the function-like macros of the kernel as one def each (research 01)
[c_function, inline]
def private zgetc(var z : Zio?) : int {
    let n = z.n
    z.n--
    if (n > uint64(0)) {
        let p = z.p
        z.p = z.p + 1
        return int(uint8(deref(p)))
    }
    return next_fetch__fill(z)
}

[c_function, inline]
def private next(var ls : LexState?) {
    ls.current = zgetc(ls.z)
}

[c_function]
def private next_fetch__scan(var ls : LexState?; n : int) : int64 {
    var acc : int64 = int64(0)
    for (r in range(n)) {
        for (k in range(200)) {
            next(ls)
            if (ls.current >= 48 && ls.current <= 57) {
                acc += int64(ls.current - 48)
            } else {
                acc += int64(r & 1)
            }
        }
    }
    return acc
}

[c_function]
def private next_fetch__kernel_run {
    for (k in range(256)) {
        next_fetch__text[k] = uint8(48 + k % 13)
    }
    next_fetch__zio.base = addr(next_fetch__text[0])
    next_fetch__zio.size = uint64(256)
    next_fetch__zio.p = addr(next_fetch__text[0])
    next_fetch__zio.n = uint64(256)
    next_fetch__lex.z = addr(next_fetch__zio)
    next_fetch__lex.current = 0
    next_fetch__result = int(next_fetch__scan(addr(next_fetch__lex), c_volatile_load(next_fetch__rounds)) & int64(2147483647))
}

def private next_fetch__kernel_result : int {
    return next_fetch__result
}

[c_function]
def c_main : int {
    var budget : double = 0.5lf
    var n : int64 = int64(1)
    var total : double = 0.0lf
    {
        while (true) {
            var t0 : int64 = crt::c_monotonic_ns()
            for (i in range64(n)) {
                next_fetch__kernel_run()
                c_volatile_store(next_fetch__c2das_sink, next_fetch__kernel_result())
            }
            total = double(crt::c_monotonic_ns() - t0) / 1000000000.0lf
            if (total >= budget || n >= 1000000000l) {
                break
            }
            var per : double = total / double(n) > 1e-09lf ? total / double(n) : 1e-09lf
            var next : int64 = int64(budget / per * 1.2lf)
            if (next > int64(100) * n) {
                next = int64(100) * n
            }
            if (next < n + int64(1)) {
                next = n + int64(1)
            }
            n = next < 1000000000l ? next : 1000000000l
        }
    }
    printf(reinterpret<uint8?>("%.9f %ld %d\n"), total / double(n), n, next_fetch__kernel_result())
    return 0
}

[export]
def main : int {
    return c_main()
}
