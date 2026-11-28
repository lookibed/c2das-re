options gen2
require dastest/testing_boost public
require strings
require ../c_floats.das

//! `frontend/c_floats.das`: floating constants rounded to their type and printed as Dumper A
//! writes them, each expectation clang's value text read back by the C library's `strtod` and
//! printed by `%a`, as Dumper A does: halfway cases both ways, subnormals, the largest finite,
//! overflow to infinity, underflow to zero, hex floats with many digits, and `float` constants
//! through clang's nine-digit decimal text.

// literal `spelled` with its suffix as Dumper A writes its value
def private written(spelled : string) : string {
    let last = to_lower(slice(spelled, length(spelled) - 1))
    let kind = last == "f" ? "float" : last == "l" ? "long double" : "double"
    return c_float_literal(kind == "double" ? spelled : slice(spelled, 0, length(spelled) - 1), kind)
}

[test(description = "double and long double constants: halfway cases to even, subnormals and their halfway cases, the largest finite, overflow and underflow, hex floats with many digits")]
def test_doubles(t : T?) {
    t |> equal(written("0.1"), "0x1.999999999999ap-4")
    t |> equal(written("1.5"), "0x1.8p+0")
    t |> equal(written("4.9e-324"), "0x0.0000000000001p-1022")
    t |> equal(written("2.4703282292062327e-324"), "0x0p+0")
    t |> equal(written("2.4703282292062328e-324"), "0x0.0000000000001p-1022")
    t |> equal(written("1.7976931348623157e308"), "0x1.fffffffffffffp+1023")
    t |> equal(written("1.7976931348623158e308"), "0x1.fffffffffffffp+1023")
    t |> equal(written("1e-400"), "0x0p+0")
    t |> equal(written("1e400"), "inf")
    t |> equal(written("9007199254740993.0"), "0x1p+53")
    t |> equal(written("9007199254740995.0"), "0x1.0000000000002p+53")
    t |> equal(written("0x1.fffffffffffff8p0"), "0x1p+1")
    t |> equal(written("0x1.000000000000000000001p0"), "0x1p+0")
    t |> equal(written("0x.8p1"), "0x1p+0")
    t |> equal(written("0x1p-1074"), "0x0.0000000000001p-1022")
    t |> equal(written("0x1p-1075"), "0x0p+0")
    t |> equal(written("0x1.8p-1075"), "0x0.0000000000001p-1022")
    t |> equal(written("2.2250738585072011e-308"), "0x0.fffffffffffffp-1022")
    t |> equal(written("123456789012345678901234567890e-30"), "0x1.f9add3746f65fp-4")
    t |> equal(written("0.0"), "0x0p+0")
    t |> equal(written("1e23"), "0x1.52d02c7e14af6p+76")
    t |> equal(written("5e-324"), "0x0.0000000000001p-1022")
    t |> equal(written("1.5L"), "0x1.8p+0")
    t |> equal(written("0.1L"), "0x1.999999999999ap-4")
}

[test(description = "float constants: rounded to float, then through clang's nine-digit decimal text to a double; the largest, the smallest subnormal, a halfway case, overflow and underflow")]
def test_floats(t : T?) {
    t |> equal(written("0.1f"), "0x1.999999de51c94p-4")
    t |> equal(written("3.4028235e38f"), "0x1.fffffe091ff3dp+127")
    t |> equal(written("1e-45f"), "0x1.ffffffe57d2bcp-150")
    t |> equal(written("1.17549435e-38f"), "0x1.fffffff9fdba8p-127")
    t |> equal(written("16777217.0f"), "0x1p+24")
    t |> equal(written("0.3f"), "0x1.333334015bc21p-2")
    t |> equal(written("1e40f"), "inf")
    t |> equal(written("7e-46f"), "0x0p+0")
}

[test(description = "a linux long double: rounded to x87's 64-bit significand, then through clang's 21-digit text to a double, which can round otherwise than the source straight to a double")]
def test_extended(t : T?) {
    t |> equal(c_float_literal("0x1.00000000000008001p0", "extended"), "0x1p+0")
    t |> equal(c_float_literal("0x1.00000000000008001p0", "long double"), "0x1.0000000000001p+0")
    t |> equal(c_float_literal("2.5", "extended"), "0x1.4p+1")
    t |> equal(c_float_literal("1e5000", "extended"), "inf")
}

[test(description = "a hex-float's integer value truncated toward zero; inf and a value past 63 bits have none")]
def test_float_integer(t : T?) {
    var v = 0l
    t |> success(c_float_integer("0x1.8p+1", v) && v == 3l)
    t |> success(c_float_integer("0x1p-1", v) && v == 0l)
    t |> success(c_float_integer("0x0p+0", v) && v == 0l)
    t |> success(c_float_integer("0x1p+62", v) && v == 4611686018427387904l)
    t |> success(!c_float_integer("0x1p+63", v))
    t |> success(!c_float_integer("inf", v))
}

[test(description = "a decimal constant whose exponent is far past any type's range saturates to inf or underflows to 0 at once, as clang gives it", timeout = 30)]
def test_huge_exponents(t : T?) {
    t |> equal(written("1e9999999999"), "inf")
    t |> equal(written("1e-9999999999"), "0x0p+0")
    t |> equal(written("1e9999999999L"), "inf")
}
