options gen2

module c_signal public

require crt

//! C's `signal` in the dialect (`docs/stdlib-examples.md`, "signal.h"): a converted handler never
//! runs, since das code cannot run from a host signal, so `c_signal` keeps the handler of each
//! signal number and returns the one before it, `SIG_DFL` (the null function value) until the
//! first call. `SIG_IGN` and `SIG_DFL` are applied to the host process for real, so a signal the
//! program ignores (`SIGPIPE`) does not end it; a signal the host delivers to a number with a
//! converted handler takes the host's disposition. A number the dialect's C library refuses
//! returns `SIG_ERR` with `errno` EINVAL.

//! C's `void (*)(int)`, as the converter spells a handler.
typedef CSignalHandler = function<(sig : int) : void>

//! The signal numbers a handler is kept for, 1 to 64: glibc's `_NSIG` is 65, msvc's `NSIG` 23.
let C_SIGNAL_LIMIT = 65

//! `SIG_IGN` and `SIG_ERR` as the emitter spells them, the integer sentinels a function value
//! holds: `(void (*)(int)) 1` and `(void (*)(int)) -1`.
let C_SIG_IGN_BITS = 1ul
let C_SIG_ERR_BITS = 0xfffffffffffffffful

//! C's EINVAL, 22 under both dialects.
let C_EINVAL = 22

//! The dialect's C library is msvc's, whose signal numbers are its own: the converted module's
//! dialect `[init]` sets it.
var c_signal_msvc = false

var private handlers : CSignalHandler[C_SIGNAL_LIMIT]

// glibc refuses SIGKILL (9), SIGSTOP (19) and the two numbers its threads reserve (32, 33); msvc
// knows SIGINT, SIGILL, SIGABRT_COMPAT, SIGFPE, SIGSEGV, SIGTERM, SIGBREAK and SIGABRT
def private accepted(sig : int) : bool {
    if (c_signal_msvc) {
        return sig == 2 || sig == 4 || sig == 6 || sig == 8 || sig == 11 || sig == 15 || sig == 21 || sig == 22
    }
    return sig >= 1 && sig < C_SIGNAL_LIMIT && sig != 9 && sig != 19 && sig != 32 && sig != 33
}

// the host's number of the dialect's signal `sig`, 0 for one the host has none of: msvc's SIGABRT
// is 22 and its SIGBREAK 21, where linux numbers SIGTTOU and SIGTTIN
def private host_signal(sig : int) : int {
    if (!c_signal_msvc) {
        return sig
    }
    return sig == 22 ? 6 : (sig == 21 ? 0 : sig)
}

def c_signal(sig : int; handler : CSignalHandler) : CSignalHandler {
    if (!accepted(sig)) {
        crt::c_set_errno(C_EINVAL)
        return unsafe(reinterpret<CSignalHandler>(C_SIG_ERR_BITS))
    }
    let bits = unsafe(reinterpret<uint64>(handler))
    let host = host_signal(sig)
    if (host != 0 && (bits == 0ul || bits == C_SIG_IGN_BITS)) {
        crt::c_signal_host(host, bits == C_SIG_IGN_BITS)
    }
    let previous = handlers[sig]
    handlers[sig] = handler
    return previous
}
