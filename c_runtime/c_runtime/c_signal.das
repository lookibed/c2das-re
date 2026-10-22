options gen2

module c_signal public

//! C's `signal` in the dialect, which has no signals (`docs/stdlib-examples.md`, "signal.h"): a
//! converted program never receives one, so `c_signal` keeps the handler of each signal number
//! and returns the one before it, `SIG_DFL` (the null function value) until the first call, and
//! never calls a handler.

//! C's `void (*)(int)`, as the converter spells a handler.
typedef CSignalHandler = function<(sig : int) : void>

//! The signal numbers a handler is kept for, 1 to 64: glibc's `_NSIG` is 65, msvc's `NSIG` 23.
let C_SIGNAL_LIMIT = 65

var private handlers : CSignalHandler[C_SIGNAL_LIMIT]

def c_signal(sig : int; handler : CSignalHandler) : CSignalHandler {
    if (sig < 1 || sig >= C_SIGNAL_LIMIT) {
        // C returns SIG_ERR here, `(void (*)(int)) -1`, which no das function value spells
        panic("signal {sig}: no such signal number")
    }
    let previous = handlers[sig]
    handlers[sig] = handler
    return previous
}
