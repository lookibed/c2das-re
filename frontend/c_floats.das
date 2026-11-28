options gen2
options indenting = 4

module c_floats public

require math
require strings
require daslib/strings_boost

//! A floating constant's value as Dumper A writes it (`ARCHITECTURE_EXPRS.md#c-exprs-floats`), in
//! daslang alone: the literal's exact value rounded to the nearest binary value of its type (ties
//! to even, C11 6.4.4.2 under IEEE 754), and that value printed as the C library's `%a` prints a
//! double. Big unsigned integers are arrays of 32-bit limbs, least significant first.

// `a` without its high zero limbs
def private trimmed(var a : array<uint>) {
    while (!empty(a) && a[length(a) - 1] == 0u) {
        a |> pop()
    }
}

// `a * m + add` into `a`
def private mul_add(var a : array<uint>; m, add : uint) {
    var carry = uint64(add)
    for (a_elem in a) {
        let v = uint64(a_elem) * uint64(m) + carry
        a_elem = uint(v & 0xFFFFFFFFul)
        carry = v >> 32ul
    }
    if (carry != 0ul) {
        a |> push(uint(carry))
    }
}

// the count of significant bits of `a`
def private bit_length(a : array<uint>) : int {
    for (i in range(length(a))) {
        let at = length(a) - 1 - i
        if (a[at] != 0u) {
            var top = a[at]
            var bits = 0
            while (top != 0u) {
                top >>= 1u
                bits++
            }
            return at * 32 + bits
        }
    }
    return 0
}

// bit `k` of `a`
def private bit_at(a : array<uint>; k : int) : bool => k >= 0 && k / 32 < length(a) && ((a[k / 32] >> uint(k % 32)) & 1u) != 0u

// whether any bit of `a` below bit `k` is set
def private any_below(a : array<uint>; k : int) : bool {
    for (i in range(min(k, length(a) * 32))) {
        return true if (bit_at(a, i))
    }
    return false
}

// `a` shifted left by `bits`
def private shifted(a : array<uint>; bits : int) : array<uint> {
    var out : array<uint>
    out |> resize(bits / 32)
    for (i in range(bits / 32)) {
        out[i] = 0u
    }
    let s = uint(bits % 32)
    var carry = 0u
    out |> reserve(length(out) + length(a) + 1)
    for (v in a) {
        out |> push(s == 0u ? v : (v << s) | carry)
        carry = s == 0u ? 0u : v >> (32u - s)
    }
    if (carry != 0u) {
        out |> push(carry)
    }
    trimmed(out)
    return <- out
}

// -1, 0 or 1 as `a` is below, equal to or above `b`
def private compared(a, b : array<uint>) : int {
    let la = bit_length(a)
    let lb = bit_length(b)
    return la < lb ? -1 : 1 if (la != lb)
    for (i in range((la + 31) / 32)) {
        let at = (la + 31) / 32 - 1 - i
        return a[at] < b[at] ? -1 : 1 if (a[at] != b[at])
    }
    return 0
}

// `a - b` into `a`, `b` not above `a`
def private subtract(var a : array<uint>; b : array<uint>) {
    var borrow = 0l
    for (i in range(length(a))) {
        var v = int64(a[i]) - borrow - (i < length(b) ? int64(b[i]) : 0l)
        borrow = v < 0l ? 1l : 0l
        if (v < 0l) {
            v += 4294967296l
        }
        a[i] = uint(v)
    }
    trimmed(a)
}

// bits `[from, from + count)` of `a` as an integer, `count` at most 64
def private bits_of(a : array<uint>; from, count : int) : uint64 {
    var v = 0ul
    for (i in range(count)) {
        if (bit_at(a, from + i)) {
            v |= 1ul << uint64(i)
        }
    }
    return v
}

//! A binary value `m * 2^exp` with `m` below `2^precision`; `inf` past the type's largest.
struct CBinary {
    m : uint64
    exp : int
    inf : bool
}

// the value `q * 2^-t`, plus a little more when `sticky`, rounded to `precision` bits with ties to
// even, a value below `2^emin` keeping fewer bits (a subnormal), one past `2^(emax+1)` infinite
def private rounded(q : array<uint>; t : int; sticky : bool; precision, emin, emax : int) : CBinary {
    let len = bit_length(q)
    let top = len - 1 - t
    let lsb = max(top - (precision - 1), emin - (precision - 1))
    let drop = lsb + t
    var m = 0ul
    var carried = false
    if (drop <= 0) {
        m = bits_of(q, 0, len) << uint64(-drop)
    } else {
        m = bits_of(q, drop, len - drop)
        let half = bit_at(q, drop - 1)
        let rest = sticky || any_below(q, drop - 1)
        if (half && (rest || (m & 1ul) != 0ul)) {
            m++
            // the rounding carries out of the significand: past `precision` bits, or out of all 64
            carried = m == 0ul || (precision < 64 && m == 1ul << uint64(precision))
        }
    }
    var exp = lsb
    if (carried) {
        m = 1ul << uint64(precision - 1)
        exp++
    }
    let high = m == 0ul ? exp : exp + 63 - int(clz(m))
    return CBinary(m = m, exp = exp, inf = high > emax)
}

// the decimal digits of `text` as a big integer and the count of digits after the point
def private decimal_digits(text : string; var n : array<uint>; var fraction : int&) {
    var after = false
    for (ch in text) {
        if (ch == '.') {
            after = true
        } elif (is_number(ch)) {
            mul_add(n, 10u, uint(ch - '0'))
            fraction += after ? 1 : 0
        }
    }
    trimmed(n)
}

// the decimal exponent past which every value of the types here (an x87 long double's at the
// most, 10^4932 to 10^-4951) is infinity or zero: an exponent beyond it is clamped to it, which
// gives the same rounding at once
let private DECIMAL_REACH = 5200

// the value `n * 10^exponent` rounded as `rounded` says
def private decimal_value(n : array<uint>; exponent : int; precision, emin, emax : int) : CBinary {
    let digits = bit_length(n) * 3 / 10 + 1
    let e10 = clamp(exponent, -DECIMAL_REACH - digits, DECIMAL_REACH - digits)
    if (e10 >= 0) {
        var big := n
        for (_ in range(e10)) {
            mul_add(big, 10u, 0u)
        }
        return rounded(big, 0, false, precision, emin, emax)
    }
    var den : array<uint>
    den |> push(1u)
    for (_ in range(-e10)) {
        mul_add(den, 10u, 0u)
    }
    // the quotient takes 56 or 57 bits: two past the precision decide the rounding, the remainder
    // the rest
    let t = precision + 3 - (bit_length(n) - bit_length(den))
    var num <- t >= 0 ? shifted(n, t) : clone_to_move(n)
    let divisor <- t >= 0 ? clone_to_move(den) : shifted(den, -t)
    var q : array<uint>
    for (i in range(precision + 5)) {
        let j = precision + 4 - i
        var inscope part <- shifted(divisor, j)
        mul_add(q, 2u, 0u)
        if (compared(num, part) >= 0) {
            subtract(num, part)
            if (empty(q)) {
                q |> push(1u)
            } else {
                q[0] |= 1u
            }
        }
    }
    trimmed(q)
    return rounded(q, t, !empty(num), precision, emin, emax)
}

// the value of hex-float significand digits `text` (a point among them) times `2^p` rounded
def private hex_value(text : string; p : int; precision, emin, emax : int) : CBinary {
    var n : array<uint>
    var after = false
    var fraction = 0
    for (ch in text) {
        if (ch == '.') {
            after = true
        } elif (is_hex(ch)) {
            mul_add(n, 16u, uint(is_number(ch) ? ch - '0' : (ch | 0x20) - 'a' + 10))
            fraction += after ? 1 : 0
        }
    }
    trimmed(n)
    let t = 4 * fraction - p
    return t >= 0 ? rounded(n, t, false, precision, emin, emax) : rounded(shifted(n, -t), 0, false, precision, emin, emax)
}

// the decimal exponent after `e` in `text` from `at`, 0 when none
def private exponent_of(text : string; at : int) : int {
    return 0 if (at < 0)
    var sign = 1
    var v = 0
    peek_data(text) $(bytes) {
        for (i in range(at + 1, length(bytes))) {
            let ch = int(bytes[i])
            if (ch == '-') {
                sign = -1
            } elif (is_number(ch) && v < 100000) {
                v = v * 10 + ch - '0'
            }
        }
    }
    return sign * v
}

//! The value of floating constant `spelled` (no suffix) rounded to a binary type of `precision`
//! bits whose normal exponents run from `emin` to `emax`: a decimal or a hex-float constant.
def c_float_value(spelled : string; precision, emin, emax : int) : CBinary {
    let text = to_lower(spelled)
    if (starts_with(text, "0x")) {
        let p = find(text, "p")
        return hex_value(slice(text, 2, p < 0 ? length(text) : p), exponent_of(text, p), precision, emin, emax)
    }
    let e = find(text, "e")
    var n : array<uint>
    var fraction = 0
    decimal_digits(e < 0 ? text : slice(text, 0, e), n, fraction)
    return decimal_value(n, exponent_of(text, e) - fraction, precision, emin, emax)
}

// the decimal digits of big `a`, most significant first
def private decimal_text(a : array<uint>) : string {
    var rest := a
    var digits : array<uint8>
    while (!empty(rest)) {
        var carry = 0ul
        for (i in range(length(rest))) {
            let at = length(rest) - 1 - i
            let v = (carry << 32ul) | uint64(rest[at])
            rest[at] = uint(v / 10ul)
            carry = v % 10ul
        }
        digits |> push(uint8(int(carry) + '0'))
        trimmed(rest)
    }
    return build_string() $(var w) {
        for (i in range(length(digits))) {
            w |> write_char(int(digits[length(digits) - 1 - i]))
        }
    }
}

//! Binary value `v` as clang's decimal text of it with `digits` significant digits: its exact
//! decimal expansion, cut there and rounded up when the first digit cut is 5 or more, as LLVM's
//! `APFloat::toString` does; the result as digits and a power of ten.
def c_float_decimal(v : CBinary; digits : int) : tuple<text : string; e10 : int> {
    var m : array<uint> <- [uint(v.m & 0xFFFFFFFFul), uint(v.m >> 32ul)]
    trimmed(m)
    var n <- v.exp >= 0 ? shifted(m, v.exp) : clone_to_move(m)
    var e10 = 0
    if (v.exp < 0) {
        for (_ in range(-v.exp)) {
            mul_add(n, 5u, 0u)
        }
        e10 = v.exp
    }
    var text = decimal_text(n)
    if (length(text) > digits) {
        let cut = length(text) - digits
        let up = slice(text, digits, digits + 1) >= "5"
        e10 += cut
        text = slice(text, 0, digits)
        if (up) {
            var big : array<uint>
            var none = 0
            decimal_digits(text, big, none)
            mul_add(big, 1u, 1u)
            text = decimal_text(big)
        }
    }
    return (text = text, e10 = e10)
}

//! Binary value `v` of a double as the C library's `%a` prints it: `0x1.<hex>p<exp>` with trailing
//! zero digits dropped, a subnormal `0x0.<hex>p-1022`, zero `0x0p+0`, `inf` past the largest.
def c_hex_float(v : CBinary) : string {
    return "inf" if (v.inf)
    return "0x0p+0" if (v.m == 0ul)
    let high = v.exp + 63 - int(clz(v.m))
    var lead = "1"
    var frac = 0ul
    var exp = high
    if (high < -1022) {
        lead = "0"
        frac = v.m << uint64(v.exp + 1074)
        exp = -1022
    } else {
        frac = (v.m << uint64(52 - (high - v.exp))) & 0xFFFFFFFFFFFFFul
    }
    var digits = 13
    while (digits > 0 && (frac & 0xFul) == 0ul) {
        frac >>= 4ul
        digits--
    }
    let hex = build_string() $(var w) {
        for (i in range(digits)) {
            let nib = int((frac >> uint64(4 * (digits - 1 - i))) & 0xFul)
            w |> write_char(nib < 10 ? '0' + nib : 'a' + nib - 10)
        }
    }
    let sign = exp < 0 ? "-" : "+"
    return "0x{lead}{empty(hex) ? "" : "."}{hex}p{sign}{abs(exp)}"
}

//! Floating constant `spelled` of C type `kind` (`float`, `double`, `long double` where it is a
//! double, `extended` for linux's x87 `long double`; its suffix gone) as Dumper A writes it: clang's
//! value in the type, through clang's decimal text of it (nine digits for a `float`, seventeen for
//! a double, which read back to the same double, twenty-one for x87's), read as a double, as a
//! hex-float.
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-floats")]
def c_float_literal(spelled : string; kind : string) : string {
    if (kind == "extended") {
        // the linux `long double`: x87's 64-bit significand, then clang's 21-digit text of it
        let x = c_float_value(spelled, 64, -16382, 16383)
        let dec = c_float_decimal(x, 21)
        return c_hex_float(c_float_value("{dec.text}e{dec.e10}", 53, -1022, 1023))
    }
    if (kind == "float") {
        let f = c_float_value(spelled, 24, -126, 127)
        return "inf" if (f.inf)
        let dec = c_float_decimal(f, 9)
        return c_hex_float(c_float_value("{dec.text}e{dec.e10}", 53, -1022, 1023))
    }
    return c_hex_float(c_float_value(spelled, 53, -1022, 1023))
}

//! The integer value of hex-float `hex` (as `c_hex_float` writes it) truncated toward zero, into
//! `v`; false for `inf` and a value past 63 bits.
def c_float_integer(hex : string; var v : int64&) : bool {
    let at_p = find(hex, "p")
    return false if (at_p < 0)
    let digits = slice(hex, 2, at_p)
    let dot = find(digits, ".")
    let fraction = dot < 0 ? 0 : length(digits) - dot - 1
    var m = 0ul
    for (ch in replace(digits, ".", "")) {
        m = (m << 4ul) | uint64(is_number(ch) ? ch - '0' : (ch | 0x20) - 'a' + 10)
    }
    let exponent = slice(hex, at_p + 1)
    let negative = starts_with(exponent, "-")
    let magnitude = to_int(negative || starts_with(exponent, "+") ? slice(exponent, 1) : exponent)
    let shift = (negative ? -magnitude : magnitude) - 4 * fraction
    if (shift >= 0) {
        return false if (shift > 62 || (m >> uint64(63 - shift)) != 0ul)
        v = int64(m << uint64(shift))
    } else {
        v = -shift >= 64 ? 0l : int64(m >> uint64(-shift))
    }
    return true
}

