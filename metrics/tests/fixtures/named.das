options gen2

enum Mode {
    OFF
    EIGHT = 8
}

var private cn__LIMIT : int = 42
var BIG : int64 = int64(77)
var private cn__TWELVE : int = 12
var private cn__MINUS_EIGHT : int = -8
let ZERO_NAMED = 0
let ONE_NAMED = 1
let MINUS_ONE_NAMED = -1
var limit_seen = 0
var private written_global : int = 99

[init]
def private c2das_dialect {
    limit_seen = 42
}

def uses(x : int) : int64 {
    written_global = x
    let a = 42 + x + 99
    let b = int64(77) + int64(x)
    let c = 5 + 7 + x
    let d = -int(Mode.EIGHT) + x
    let e = (1 << 3) + x
    let f = 8 * x
    let z = 0 + x * 1 - 1 + x * -1
    return int64(a + c + d + e + f + z + cn__LIMIT + cn__TWELVE + cn__MINUS_EIGHT + ZERO_NAMED + ONE_NAMED + MINUS_ONE_NAMED + limit_seen) + b + BIG
}

[export]
def main {
    print("{uses(limit_seen)}\n")
}
