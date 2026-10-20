options gen2
require c_runtime/enum_from_int

enum Color {
    RED
    GREEN = 7
    BLUE
    NEGATIVE = -9
}

let LIMIT = 42
let ALSO_SEVEN = 7
let ONE = 1
var not_named = 13

def sizes() : int64 {
    let a = 7u8
    let b = int8(8)
    let c = int16(42)
    let d = uint16(7)
    let e = 8l
    let f = 42ul
    let g = 7u
    let h = -9
    let none = 99
    let folded = int(Color.GREEN) + int(int8(Color.BLUE))
    let small = 0 + 1 - 1 + ONE
    return int64(a) + int64(b) + int64(c) + int64(d) + e + int64(f) + int64(g) + int64(h + none + small + not_named + folded)
}

def color_of(v : int) : Color => enum_from_int(type<Color>, v)

[export]
def main {
    print("{sizes()} {color_of(LIMIT)} {ALSO_SEVEN}\n")
}
