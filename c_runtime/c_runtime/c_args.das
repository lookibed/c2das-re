options gen2

module c_args public

require crt
require daslib/clargs

//! C's `main(argc, argv)`: `c_runtime_init(name)` builds the argument vector once, in C-allocator
//! memory, from the program's own arguments (`get_user_args`: after `--` under the interpreter
//! and the JIT, after the binary in a `-exe` one), `name` the C program's name in `argv[0]`;
//! `c_argc` and `c_argv` hand it to the converted `c_main`. Every string and the vector are the
//! C program's to keep and write, so none lives on the das heap.

var private argv_vector : uint8 ??
var private argc_count = 0

// a NUL-terminated copy of `s` in C-allocator memory
def private c_string(s : string) : uint8? {
    let n = length(s)
    unsafe {
        var bytes = reinterpret<uint8?>(crt::malloc(uint64(n) + 1ul))
        if (n > 0) {
            crt::memcpy(reinterpret<void?>(bytes), reinterpret<void?>(s), uint64(n))
        }
        deref(bytes + n) = uint8(0)
        return bytes
    }
}

//! The vector `argv`: `name`, then each argument the program was given, then the null C puts at
//! `argv[argc]`; a second call keeps the first vector.
def c_runtime_init(name : string) {
    if (argv_vector != null) {
        return
    }
    let args <- get_user_args()
    argc_count = length(args) + 1
    unsafe {
        argv_vector = reinterpret<uint8 ??>(crt::malloc(uint64(argc_count + 1) * 8ul))
        deref(argv_vector) = c_string(name)
        for (idx, arg in range(1, argc_count), args) {
            deref(argv_vector + idx) = c_string(arg)
        }
        deref(argv_vector + argc_count) = null
    }
}

//! `argc`: the count `c_runtime_init` found, the name included.
def c_argc : int => argc_count

//! `argv`: the vector `c_runtime_init` built.
def c_argv : uint8 ?? => argv_vector
