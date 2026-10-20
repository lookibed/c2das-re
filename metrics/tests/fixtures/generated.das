options gen2
require c_runtime/c_function
require c_runtime/c_union
require c_runtime/variadic

[c_union]
struct Pun {
    i : int
    f : float
}

[c_function, variadic]
def sum(var p_in : int?; va : va_args) : int {
    var p = p_in
    var ap : CVaCursor
    ap = va_begin(va)
    p = p + 1
    return deref(p) + int(va_i(ap))
}

def as_bits(x : auto(T)) : T => unsafe(reinterpret<T>(x))

def uncalled(x : auto) {
    unsafe {
        let y = reinterpret<int?>(x)
        print("{y}\n")
    }
}

[export]
def main {
    var pun : Pun
    pun.i = 3
    var a = fixed_array(1, 2, 3)
    var pa = unsafe(addr(a[0]))
    print("{pun.f} {sum(pa, 1)} {sum(pa, 1, 2.0)} {as_bits(4)} {as_bits(5u)}\n")
}
