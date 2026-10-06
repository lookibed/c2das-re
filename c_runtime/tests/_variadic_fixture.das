options gen2

module _variadic_fixture public

require c_runtime/variadic public

[variadic]
def fixture_sum(n : int; va : va_args) : int64 {
    var acc = 0l
    var cursor = 0
    for (_k in range(n)) {
        acc += va[cursor] as i
        cursor++
    }
    return acc
}
