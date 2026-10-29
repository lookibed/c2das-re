options gen2

module c_builtins public

require c_runtime/c_exit

//! The GCC builtins with a direct das meaning, as the converter maps them (the shim list,
//! `converter/ARCHITECTURE_EMITTER.md`): the bit counts over das's own `clz`, `ctz` and `popcnt`
//! at the operand's width, which C's `l` and `ll` spellings select through the argument's type,
//! the byte swaps, the sign bit, `__builtin_unreachable` as an abort and `__builtin_prefetch`
//! as nothing but its arguments' evaluation. A count of a zero operand that C leaves undefined
//! (`clz`, `ctz`) gives das's answer.

//! `__builtin_ffs`: one plus the index of the lowest set bit, 0 for 0.
def c_ffs(x : int) : int => x == 0 ? 0 : int(ctz(uint(x))) + 1

def c_ffs(x : int64) : int => x == 0l ? 0 : int(ctz(uint64(x))) + 1

//! `__builtin_ctz`: the trailing zero bits.
def c_ctz(x : uint) : int => int(ctz(x))

def c_ctz(x : uint64) : int => int(ctz(x))

//! `__builtin_clz`: the leading zero bits.
def c_clz(x : uint) : int => int(clz(x))

def c_clz(x : uint64) : int => int(clz(x))

//! `__builtin_popcount`: the set bits.
def c_popcount(x : uint) : int => int(popcnt(x))

def c_popcount(x : uint64) : int => int(popcnt(x))

//! `__builtin_parity`: the set bits modulo 2.
def c_parity(x : uint) : int => int(popcnt(x)) & 1

def c_parity(x : uint64) : int => int(popcnt(x)) & 1

//! `__builtin_clrsb`: the leading bits after the sign bit equal to it; das's `clz` of a zero
//! operand is not the width, so a zero or minus one counts every bit but the sign
def c_clrsb(x : int) : int {
    let rest = uint(x < 0 ? ~x : x)
    return rest == 0u ? 31 : int(clz(rest)) - 1
}

def c_clrsb(x : int64) : int {
    let rest = uint64(x < 0l ? ~x : x)
    return rest == 0ul ? 63 : int(clz(rest)) - 1
}

//! `__builtin_bswap16`, `32` and `64`: the bytes in reverse order.
def c_bswap16(x : uint16) : uint16 => uint16((uint(x) >> 8u) | ((uint(x) & 0xFFu) << 8u))

def c_bswap32(x : uint) : uint => (x >> 24u) | ((x >> 8u) & 0xFF00u) | ((x << 8u) & 0xFF0000u) | (x << 24u)

def c_bswap64(x : uint64) : uint64 => (uint64(c_bswap32(uint(x))) << 32ul) | uint64(c_bswap32(uint(x >> 32ul)))

//! `__builtin_signbit`: 1 when the sign bit of `x` is set (a negative zero included), else 0.
def c_signbit(x : double) : int => int(unsafe(reinterpret<uint64>(x)) >> 63ul)

def c_signbit(x : float) : int => int(unsafe(reinterpret<uint>(x)) >> 31u)

//! `__builtin_unreachable`: reaching it is undefined in C; the run ends as `abort` ends it.
def c_unreachable {
    c_abort()
}

//! `__builtin_prefetch`: a cache hint, nothing for das to do once its arguments are evaluated;
//! `[sideeffects]` keeps the call, since das drops a call to an empty function and its arguments'
//! effects with it (probes/test_functions.das)
[sideeffects]
def c_prefetch(_addr : auto; _rw : int = 0; _locality : int = 3) {
    pass
}
