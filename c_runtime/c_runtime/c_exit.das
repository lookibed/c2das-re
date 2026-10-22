options gen2

module c_exit public

require daslib/fio
require crt

//! The C process-exit protocol: `c_atexit` registers, the handlers run once in LIFO order
//! either on the normal return from `main` (the `[finalize]` walker) or inside `c_exit`,
//! which then ends the process with `exit_now` so the code reaches the parent; `c_abort`
//! ends it with code 3 and runs no handler, which is C's rule and the MSVC baseline's code. The
//! return from `main` also flushes every C stream while the context lives: a buffer the program
//! handed `setvbuf` is das memory, which libc's own flush at process exit would read freed.

var private atexit_list : array<function<() : void>>
var private atexit_ran = false

def c_atexit(f : function<() : void>) : int {
    atexit_list |> push(f)
    return 0
}

def c_run_atexit {
    if (atexit_ran) {
        return
    }
    atexit_ran = true
    var i = length(atexit_list) - 1
    while (i >= 0) {
        invoke(atexit_list[i])
        i--
    }
}

def c_exit(code : int) {
    c_run_atexit()
    unsafe(exit_now(code))
}

def c_abort {
    unsafe(exit_now(3))
}

[finalize]
def private c_shutdown {
    c_run_atexit()
    unsafe(crt::fflush(null))
}
