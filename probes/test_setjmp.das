options gen2
require dastest/testing_boost public

struct CJmpBuf {
    val : int
}

var _c_jmp_target : CJmpBuf?
var outer_buf : CJmpBuf
var inner_buf : CJmpBuf
var finally_ran = false

def c_longjmp(var buf : CJmpBuf; v : int) {
    buf.val = v == 0 ? 1 : v
    _c_jmp_target = unsafe(addr(buf))
    panic("longjmp")
}

def deep(n : int; var target : CJmpBuf) {
    if (n == 0) {
        c_longjmp(target, 7)
    }
    deep(n - 1, target)
}

def inner_site(var log : array<string>; jump_outer : bool) {
    try {
        {
            if (jump_outer) {
                deep(3, outer_buf)
            } else {
                deep(3, inner_buf)
            }
        } finally {
            finally_ran = true
        }
    } recover {
        if (_c_jmp_target != unsafe(addr(inner_buf))) {
            panic("longjmp")
        }
        _c_jmp_target = null
        log |> push("inner caught {inner_buf.val}")
    }
}

[test]
def test_setjmp(t : T?) {
    t |> run("the nearest site catches its own buffer with the value; finally is skipped on panic") @(t : T?) {
        var log : array<string>
        finally_ran = false
        try {
            inner_site(log, false)
            log |> push("continued")
        } recover {
            log |> push("outer ran")
        }
        t |> equal("{log}", "[ inner caught 7, continued]")
        t |> equal(finally_ran, false)
    }
    t |> run("a targeted jump passes an inner recover by rethrow") @(t : T?) {
        var log : array<string>
        try {
            inner_site(log, true)
        } recover {
            if (_c_jmp_target != unsafe(addr(outer_buf))) {
                panic("longjmp")
            }
            _c_jmp_target = null
            log |> push("outer caught {outer_buf.val}")
        }
        t |> equal("{log}", "[ outer caught 7]")
    }
    t |> run("a genuine panic passes through with a null target") @(t : T?) {
        var log : array<string>
        try {
            try {
                panic("genuine")
            } recover {
                if (_c_jmp_target != unsafe(addr(inner_buf))) {
                    panic("rethrow")
                }
                log |> push("wrong")
            }
        } recover {
            log |> push("passed target_null={_c_jmp_target == null}")
        }
        t |> equal("{log}", "[ passed target_null=true]")
    }
    t |> run("longjmp value 0 coerces to 1") @(t : T?) {
        var zero : CJmpBuf
        try {
            c_longjmp(zero, 0)
        } recover {
            _c_jmp_target = null
        }
        t |> equal(zero.val, 1)
    }
}
