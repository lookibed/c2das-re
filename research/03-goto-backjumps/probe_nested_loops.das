options gen2
// research 03: the shape the proposal emits for luaV_execute's frame - a `private` function
// whose body is an outer `while (true)` ending in an inner `while (true)` that holds a `return`
// - never returns under the interpreter (the converter writes every static C function as
// `def private`). The same function public, or `options optimize = false`, or any statement
// after the inner loop (`probe_nested_loops_pad.das`), or the `return` moved after the inner
// loop, runs to completion and prints 2129000. Found 2026-11-02; filed as lookibed/daScript#33.

var code : int[64]

def private run(acc0 : int) : int {
    var acc = acc0
    var frames : int[8]
    var depth = 0
    var pc = 0
    frames[0] = 0
    while (true) {
        pc = frames[depth]
        while (true) {
            let i = code[pc]
            pc++
            if (i == 1) {  // call: open a frame
                if (depth < 3) {
                    frames[depth] = pc
                    depth++
                    frames[depth] = 0
                    break
                }
                acc += 41
            } elif (i == 2) {  // return: close a frame
                acc -= 42
                if (depth == 0) {
                    return acc
                }
                depth--
                break
            } else {
                acc += i
            }
        }
    }
    return 0
}

[export]
def main {
    for (i in range(64)) {
        code[i] = (i * 7) % 18 == 10 ? 1 : (i * 7) % 18 == 11 ? 2 : 3
    }
    var acc = 0
    for (r in range(2000)) {
        acc = run(acc + r)
    }
    print("{acc}\n")
}
