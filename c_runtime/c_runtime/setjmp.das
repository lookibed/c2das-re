options gen2

module setjmp public

require daslib/rtti

//! The setjmp/longjmp protocol over das's own unwinding (docs/lowering-examples.md "setjmp /
//! longjmp"): `c_longjmp` records the target buffer and its value and panics; the `recover` of
//! every setjmp site the unwind passes compares `c_jmp_target` with its own buffer, rethrows
//! another's, and clears it for its own. das skips `finally` on a panic, which is C's
//! no-cleanup-on-longjmp rule. A genuine das panic leaves the target null, so every site
//! rethrows it.

struct CJmpBuf {
    val : int
}

//! The buffer a longjmp in flight targets; null when no longjmp is in flight.
var c_jmp_target : CJmpBuf?

//! C `longjmp(buf, v)`: never returns; a zero value arrives as 1, as C says. Every converted
//! pointer parameter is `var` (F3), so the buffer arrives writable.
def c_longjmp(var buf : CJmpBuf?; v : int) {
    buf.val = v == 0 ? 1 : v
    c_jmp_target = buf
    panic("longjmp")
}

//! The `recover` of a setjmp site a panic passes that is not a longjmp to its own buffer: a
//! longjmp to another buffer goes on as one; any other panic (none in flight) goes on with its own
//! message, which a bare rethrow of "longjmp" would hide.
def c_jmp_rethrow {
    if (c_jmp_target != null) {
        panic("longjmp")
    }
    panic(this_context().last_exception)
}
