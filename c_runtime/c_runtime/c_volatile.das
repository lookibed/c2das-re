options gen2

module c_volatile public

require crt

//! C's volatile access: `c_volatile_load(x)` reads object `x` and `c_volatile_store(x, v)` writes
//! it, each once per call, through the `crt` forwarders that access it through a `volatile`
//! pointer, so neither the JIT nor the AOT host's clang++ folds a read or drops a write. The object
//! comes by reference, so a converted module spells the access with no `addr`. One overload per C
//! scalar width, `bool` (C's `_Bool`) through its byte, and a pointer or function value through
//! its eight bytes.

def c_volatile_load(x : int8 const&) : int8 => unsafe(crt::c_volatile_load_i8(unsafe(addr(x))))
def c_volatile_load(x : uint8 const&) : uint8 => unsafe(crt::c_volatile_load_u8(unsafe(addr(x))))
def c_volatile_load(x : int16 const&) : int16 => unsafe(crt::c_volatile_load_i16(unsafe(addr(x))))
def c_volatile_load(x : uint16 const&) : uint16 => unsafe(crt::c_volatile_load_u16(unsafe(addr(x))))
def c_volatile_load(x : int const&) : int => unsafe(crt::c_volatile_load_i32(unsafe(addr(x))))
def c_volatile_load(x : uint const&) : uint => unsafe(crt::c_volatile_load_u32(unsafe(addr(x))))
def c_volatile_load(x : int64 const&) : int64 => unsafe(crt::c_volatile_load_i64(unsafe(addr(x))))
def c_volatile_load(x : uint64 const&) : uint64 => unsafe(crt::c_volatile_load_u64(unsafe(addr(x))))
def c_volatile_load(x : float const&) : float => unsafe(crt::c_volatile_load_f32(unsafe(addr(x))))
def c_volatile_load(x : double const&) : double => unsafe(crt::c_volatile_load_f64(unsafe(addr(x))))

def c_volatile_load(x : bool const&) : bool {
    unsafe {
        return crt::c_volatile_load_u8(addr<uint8 const?>(x)) != 0u8
    }
}

//! A pointer or a function value read once through its bits; the type rides through the reinterpret.
def c_volatile_load(x : auto(TT) const&) : TT -const -& {
    static_assert(typeinfo sizeof(type<TT>) == 8, "c_volatile_load: a scalar, a pointer or a function value")
    // the bits land in a local first: the interpreter refuses a reinterpret of the extern call's
    // result itself ("typed eval on wrong extern return kind")
    unsafe {
        let bits = crt::c_volatile_load_u64(addr<uint64 const?>(x))
        return reinterpret<TT -const -&>(bits)
    }
}

def c_volatile_store(var x : int8&; v : int8) => unsafe(crt::c_volatile_store_i8(unsafe(addr(x)), v))
def c_volatile_store(var x : uint8&; v : uint8) => unsafe(crt::c_volatile_store_u8(unsafe(addr(x)), v))
def c_volatile_store(var x : int16&; v : int16) => unsafe(crt::c_volatile_store_i16(unsafe(addr(x)), v))
def c_volatile_store(var x : uint16&; v : uint16) => unsafe(crt::c_volatile_store_u16(unsafe(addr(x)), v))
def c_volatile_store(var x : int&; v : int) => unsafe(crt::c_volatile_store_i32(unsafe(addr(x)), v))
def c_volatile_store(var x : uint&; v : uint) => unsafe(crt::c_volatile_store_u32(unsafe(addr(x)), v))
def c_volatile_store(var x : int64&; v : int64) => unsafe(crt::c_volatile_store_i64(unsafe(addr(x)), v))
def c_volatile_store(var x : uint64&; v : uint64) => unsafe(crt::c_volatile_store_u64(unsafe(addr(x)), v))
def c_volatile_store(var x : float&; v : float) => unsafe(crt::c_volatile_store_f32(unsafe(addr(x)), v))
def c_volatile_store(var x : double&; v : double) => unsafe(crt::c_volatile_store_f64(unsafe(addr(x)), v))

def c_volatile_store(var x : bool&; v : bool) {
    unsafe {
        crt::c_volatile_store_u8(addr<uint8?>(x), v ? 1u8 : 0u8)
    }
}

//! A pointer or a function value written once through its bits.
def c_volatile_store(var x : auto(TT)&; v : TT) {
    static_assert(typeinfo sizeof(type<TT>) == 8, "c_volatile_store: a scalar, a pointer or a function value")
    unsafe {
        crt::c_volatile_store_u64(addr<uint64?>(x), reinterpret<uint64>(v))
    }
}
