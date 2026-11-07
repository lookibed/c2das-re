options gen2
require c_runtime/enum_from_int
require c_runtime/c_volatile
require c_runtime/cstr_array

enum Color {
    RED
    GREEN = 7
}

var level = 3

// a C label's statement: the optimizer keeps a [sideeffects] call after the label
[sideeffects]
def private c_label_end {
    pass
}

def step(v : int) : Color {
    var n = c_volatile_load(level)
    c_volatile_store(level, n + v)
    let name = cstr_array("ab", 8)
    var i = 0
    label 0:
    c_label_end()
    i++
    if (i < 2) {
        goto label 0
    }
    let spelled = unsafe(reinterpret<Color>(n))
    return v > int(name[0]) ? spelled : enum_from_int(type<Color>, n + 7)
}

[export]
def main {
    print("{step(1)}\n")
}
