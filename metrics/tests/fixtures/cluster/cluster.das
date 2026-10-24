options gen2
require c_runtime/c_function

// a cluster module: its own text counts one reinterpret, its fragment's two pointer steps
include part.das.inc

def own(p : int?) : uint8? => unsafe(reinterpret<uint8?>(p))

[export]
def main {
    var a = fixed_array(1, 2, 3)
    let p = unsafe(addr(a[0]))
    print("{fragment_sum(p)} {own(p) != null}\n")
}
