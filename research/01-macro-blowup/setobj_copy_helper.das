// research 01: the converted setobj_copy module hand-edited into the helper-call form (helper)
options gen2
options indenting = 4
options stack = 8388608
require c_runtime/c_function
require c_runtime/c_union
require c_runtime/c_volatile
require c_runtime/printf
require crt

[init]
def private c2das_dialect {
    c_long_bits = 64
}

[c_union]
struct Value {
    i : int64
    n : double
    gc : void?
}

struct TValue {
    value_ : Value
    tt_ : uint8
}

struct StackValue {
    val : TValue
}

[init]
def private c2das_layout_check {
    static_assert(typeinfo sizeof(type<Value>) == 8 && typeinfo alignof(type<Value>) == 8, "Value: clang lays it out as size 8, align 8")
    static_assert(typeinfo offsetof < _storage > (type<Value>) == 0, "Value: every member sits at 0")
    static_assert(typeinfo sizeof(type<TValue>) == 16 && typeinfo alignof(type<TValue>) == 8, "TValue: clang lays it out as size 16, align 8")
    static_assert(typeinfo offsetof < value_ > (type<TValue>) == 0, "TValue.value_: clang puts it at 0")
    static_assert(typeinfo offsetof < tt_ > (type<TValue>) == 8, "TValue.tt_: clang puts it at 8")
    static_assert(typeinfo sizeof(type<StackValue>) == 16 && typeinfo alignof(type<StackValue>) == 8, "StackValue: clang lays it out as size 16, align 8")
    static_assert(typeinfo offsetof < val > (type<StackValue>) == 0, "StackValue.val: clang puts it at 0")
}

var private setobj_copy__rounds : int = 4000
var private setobj_copy__stack : StackValue[64]
var private setobj_copy__konst : TValue[8]
var private setobj_copy__result : int
var private setobj_copy__c2das_sink : int

// the function-like macros of the kernel as one def each (research 01)
[c_function]
def private s2v(var o : StackValue?) : TValue? {
    return addr(o.val)
}

[c_function]
def private setobj(var io1 : TValue?; io2 : TValue?) {
    io1.value_ = io2.value_
    io1.tt_ = io2.tt_
}

[c_function]
def private setobjs2s(var o1 : StackValue?; var o2 : StackValue?) {
    setobj(s2v(o1), s2v(o2))
}

[c_function]
def private setobj2s(var o1 : StackValue?; o2 : TValue?) {
    setobj(s2v(o1), o2)
}

[c_function]
def private ttisinteger(o : TValue?) : bool {
    return int(o.tt_) == 3
}

[c_function]
def private ivalue(o : TValue?) : int64 {
    return o.value_.i
}

[c_function]
def private setobj_copy__shuffle(var base : StackValue?; var k : TValue?; n : int) : int64 {
    var acc : int64 = int64(0)
    for (r in range(n)) {
        for (a in range(1, 64)) {
            setobjs2s(base + a, base + a + -(1))
            setobj2s(base + (a & 7), k + (a & 7))
            var ra : TValue? = s2v(base + a)
            if (ttisinteger(ra)) {
                acc += ivalue(ra) + int64(r)
            }
        }
    }
    return acc
}

[c_function]
def private setobj_copy__kernel_run {
    for (a in range(64)) {
        setobj_copy__stack[a].val.value_.i = int64(a)
        setobj_copy__stack[a].val.tt_ = uint8((a & 1) != 0 ? 3 : 19)
    }
    for (a in range(8)) {
        setobj_copy__konst[a].value_.i = int64(a * 7)
        setobj_copy__konst[a].tt_ = uint8(3)
    }
    setobj_copy__result = int(setobj_copy__shuffle(addr(setobj_copy__stack[0]), addr(setobj_copy__konst[0]), c_volatile_load(setobj_copy__rounds)) & int64(2147483647))
}

def private setobj_copy__kernel_result : int {
    return setobj_copy__result
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
                setobj_copy__kernel_run()
                c_volatile_store(setobj_copy__c2das_sink, setobj_copy__kernel_result())
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
    printf(reinterpret<uint8?>("%.9f %ld %d\n"), total / double(n), n, setobj_copy__kernel_result())
    return 0
}

[export]
def main : int {
    return c_main()
}
