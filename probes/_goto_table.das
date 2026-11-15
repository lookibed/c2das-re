options gen2

//! The dense switch as the converter writes it under `switch_dispatch` `table`
//! (`probes/test_goto_table.das` runs this program under each tier): `goto <table>?[cond - lo] ??
//! <default's label>`, the table a `let private` global fixed array of label numbers, a value of
//! [lo, hi] no case holds at the default's label. Each `sw_*` stands beside the structural `ref_*`
//! that says what C's switch does; `main` prints the count of values on which they differ.

enum Op {
    A
    B
    C
    D
    E
    F
}

// switch (x) { case 0: r += 1;  /* falls */  case 1: case 2: r += 10; break;
//              case 3: r += 100; if (x2) goto in5; break;
//              default: r += 1000; break;  /* default in the middle; 4 is a hole */
//              case 5: r += 5; in5: r += 50000; break;
//              case 6: r += 6;  /* falls off the end */ }
let private TAB_basic = fixed_array<int>(1, 2, 2, 3, 4, 5, 7)

def sw_basic(x : int; x2 : bool) : int {
    var r = 0
    goto TAB_basic?[x] ?? 4
    label 1:  // case 0
    r++
    label 2:  // case 1, case 2
    r += 10
    goto label 8
    label 3:  // case 3
    r += 100
    if (x2) {
        goto label 6
    }
    goto label 8
    label 4:  // default
    r += 1000
    goto label 8
    label 5:  // case 5
    r += 5
    label 6:  // in5
    r += 50000
    goto label 8
    label 7:  // case 6
    r += 6
    label 8:  // the switch's end
    return r
}

def ref_basic(x : int; x2 : bool) : int {
    if (x == 0) {
        return 11
    } elif (x == 1 || x == 2) {
        return 10
    } elif (x == 3) {
        return x2 ? 50100 : 100
    } elif (x == 5) {
        return 50005
    } elif (x == 6) {
        return 6
    }
    return 1000
}

// cases -2 .. 3, no default: the index is `x + 2`, every miss lands on the end label; the
// table's labels number after a C label of the function (label 1) and out of order
let private TAB_bias = fixed_array<int>(14, 13, 12, 12, 11, 10)

def sw_bias(x : int) : int {
    var r = 0
    var n = 0
    label 1:  // a C label: again
    n++
    goto TAB_bias?[x + 2] ?? 20
    label 14:  // case -2
    r += 2
    label 13:  // case -1: falls from -2
    r++
    goto label 20
    label 12:  // case 0, case 1
    r += 100
    goto label 20
    label 11:  // case 2: a goto to the neighbouring case 3
    r += 20
    goto label 10
    label 10:  // case 3
    r += 3000
    if (n < 2) {
        goto label 1
    }
    label 20:  // the switch's end
    return r
}

def ref_bias(x : int) : int {
    if (x == -2) {
        return 3
    } elif (x == -1) {
        return 1
    } elif (x == 0 || x == 1) {
        return 100
    } elif (x == 2) {
        // case 2 runs, jumps to case 3, which loops back once: again case 2 and case 3
        return 2 * (20 + 3000)
    } elif (x == 3) {
        return 2 * 3000
    }
    return 0
}

// the switch in a loop body: `continue` and `break` of the loop from a case, the subject an enum
let private TAB_loop = fixed_array<int>(1, 2, 3, 3, 4)

def sw_loop(ops : array<Op>) : int {
    var r = 0
    for (op in ops) {
        goto TAB_loop?[int(op)] ?? 5
        label 1:  // case A: falls into B
        r++
        label 2:  // case B
        r += 10
        goto label 6
        label 3:  // case C, case D
        r += 100
        continue
        label 4:  // case E
        break
        label 5:  // default
        r += 1000
        label 6:  // the switch's end
        r *= 2
    }
    return r
}

def ref_loop(ops : array<Op>) : int {
    var r = 0
    for (op in ops) {
        if (op == Op.A) {
            r += 11
        } elif (op == Op.B) {
            r += 10
        } elif (op == Op.C || op == Op.D) {
            r += 100
            continue
        } elif (op == Op.E) {
            break
        } else {
            r += 1000
        }
        r *= 2
    }
    return r
}

// an int64, a uint and a uint64 subject index the table in their own type, with no narrowing to
// int; a uint8 one through `int`
let private TAB_wide = fixed_array<int>(1, 2, 3)

def sw_int64(x : int64) : int {
    goto TAB_wide?[x - 10l] ?? 4
    label 1:
    return 10
    label 2:
    return 11
    label 3:
    return 12
    label 4:
    return -1
}

def sw_uint(x : uint) : int {
    goto TAB_wide?[x - 10u] ?? 4
    label 1:
    return 10
    label 2:
    return 11
    label 3:
    return 12
    label 4:
    return -1
}

def sw_uint64(x : uint64) : int {
    goto TAB_wide?[x - 10ul] ?? 4
    label 1:
    return 10
    label 2:
    return 11
    label 3:
    return 12
    label 4:
    return -1
}

def sw_uint8(x : uint8) : int {
    goto TAB_wide?[int(x) - 10] ?? 4
    label 1:
    return 10
    label 2:
    return 11
    label 3:
    return 12
    label 4:
    return -1
}

// two switches in one function, one nested in a case of the other: two tables, one label space
let private TAB_outer = fixed_array<int>(1, 2, 3)
let private TAB_inner = fixed_array<int>(5, 6)

def sw_nested(x, y : int) : int {
    var r = 0
    goto TAB_outer?[x] ?? 4
    label 1:  // case 0
    r++
    goto label 9
    label 2:  // case 1: the inner switch
    goto TAB_inner?[y] ?? 7
    label 5:  // inner case 0: falls
    r += 10
    label 6:  // inner case 1
    r += 100
    goto label 8
    label 7:  // inner default: a goto into the outer switch's case 2
    goto label 3
    label 8:  // the inner switch's end: falls into the outer case 2
    label 3:  // case 2
    r += 1000
    goto label 9
    label 4:  // default
    r = -1
    label 9:
    return r
}

def ref_nested(x, y : int) : int {
    if (x == 0) {
        return 1
    } elif (x == 1) {
        return y == 0 ? 1110 : y == 1 ? 1100 : 1000
    } elif (x == 2) {
        return 1000
    }
    return -1
}

[export]
def main : int {
    var bad = 0
    let xs = fixed_array<int>(int(0x80000000), int(0x80000001), -1000, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 100, 0x7ffffffe, 0x7fffffff)
    for (x in xs) {
        for (x2 in fixed_array(false, true)) {
            if (sw_basic(x, x2) != ref_basic(x, x2)) {
                print("basic {x} {x2}: {sw_basic(x, x2)} != {ref_basic(x, x2)}\n")
                bad++
            }
        }
        if (sw_bias(x) != ref_bias(x)) {
            print("bias {x}: {sw_bias(x)} != {ref_bias(x)}\n")
            bad++
        }
        for (y in xs) {
            if (sw_nested(x, y) != ref_nested(x, y)) {
                print("nested {x} {y}: {sw_nested(x, y)} != {ref_nested(x, y)}\n")
                bad++
            }
        }
        let want = x >= 10 && x <= 12 ? x : -1
        if (sw_int64(int64(x)) != want || sw_int64(int64(x) + 4294967296l) != -1 || sw_int64(int64(x) - 4294967296l) != -1) {
            print("int64 {x}\n")
            bad++
        }
        if (sw_uint(uint(x)) != want) {
            print("uint {x}\n")
            bad++
        }
        if (sw_uint64(uint64(uint(x))) != want || sw_uint64(uint64(int64(x))) != want || sw_uint64(uint64(uint(x)) + 4294967296ul) != -1) {
            print("uint64 {x}\n")
            bad++
        }
    }
    for (b in range(256)) {
        if (sw_uint8(uint8(b)) != (b >= 10 && b <= 12 ? b : -1)) {
            print("uint8 {b}\n")
            bad++
        }
    }
    let ops <- [Op.A, Op.B, Op.C, Op.F, Op.D, Op.A, Op.E, Op.B]
    if (sw_loop(ops) != ref_loop(ops)) {
        print("loop: {sw_loop(ops)} != {ref_loop(ops)}\n")
        bad++
    }
    print("basic {sw_basic(0, false)} {sw_basic(3, true)} {sw_basic(4, false)} {sw_basic(-1, false)} {sw_basic(7, false)} bias {sw_bias(-2)} {sw_bias(2)} {sw_bias(-3)} loop {sw_loop(ops)} nested {sw_nested(1, 0)} {sw_nested(1, 9)} bad {bad}\n")
    return bad
}
