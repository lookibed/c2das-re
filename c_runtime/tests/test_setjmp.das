options gen2
require dastest/testing_boost public
require c_runtime/setjmp
require daslib/rtti
require strings

//! The setjmp protocol as the converter emits it: a contained site is `try` around the first
//! run and `recover` around the longjmp return, which checks the target buffer and rethrows.

var outer : CJmpBuf
var depth_reached : int

def deep(n : int; var target : CJmpBuf?; v : int) {
    depth_reached = n
    if (n == 0) {
        c_longjmp(target, v)
    }
    deep(n - 1, target, v)
}

// `if (setjmp(buf) == 0) { A } else { B }`
def protected_call(fail_at : int; value : int) : int {
    var buf : CJmpBuf
    var status : int = 0
    try {
        if (fail_at != 0) {
            deep(fail_at, unsafe(addr(buf)), value)
        }
        status = 100
    } recover {
        if (c_jmp_target != unsafe(addr(buf))) {
            c_jmp_rethrow()
        }
        c_jmp_target = null
        status = -1
    }
    return status + depth_reached + buf.val
}

def targeted(to_outer : bool) : int {
    var inner : CJmpBuf
    var log : int = 0
    try {
        if (to_outer) {
            deep(2, unsafe(addr(outer)), 3)
        }
        deep(1, unsafe(addr(inner)), 5)
        log = 999
    } recover {
        if (c_jmp_target != unsafe(addr(inner))) {
            c_jmp_rethrow()
        }
        c_jmp_target = null
        log = 10 + inner.val
    }
    return log
}

[test]
def test_setjmp(t : T?) {
    t |> run("the first run returns through the try, the longjmp through the recover with its value") @(t : T?) {
        t |> equal(protected_call(0, 1), 100)
        t |> equal(protected_call(3, 7), 6)
        t |> equal(c_jmp_target == null, true)
    }
    t |> run("a longjmp to an outer buffer passes an inner site by rethrow") @(t : T?) {
        var r = 0
        try {
            r = targeted(true)
        } recover {
            if (c_jmp_target != unsafe(addr(outer))) {
                panic("longjmp")
            }
            c_jmp_target = null
            r = 1000 + outer.val
        }
        t |> equal(r, 1003)
        t |> equal(targeted(false), 15)
    }
    t |> run("a zero value arrives as 1, and a genuine panic keeps a null target") @(t : T?) {
        var buf : CJmpBuf
        var seen = 0
        try {
            c_longjmp(unsafe(addr(buf)), 0)
        } recover {
            seen = c_jmp_target == unsafe(addr(buf)) ? buf.val : -1
            c_jmp_target = null
        }
        t |> equal(seen, 1)
        var genuine = false
        try {
            panic("genuine")
        } recover {
            genuine = c_jmp_target == null
        }
        t |> equal(genuine, true)
    }
    t |> run("a genuine panic passing a site goes on with its own message, not as a longjmp") @(t : T?) {
        var message = ""
        try {
            protected_or_panic()
        } recover {
            message = this_context().last_exception
        }
        t |> success(message |> find("index out of range") >= 0, message)
        t |> equal(c_jmp_target == null, true)
    }
}

var short_row : int[2]
var row_at = 2

// a site whose body panics on its own (an index past its array), not by longjmp
def protected_or_panic {
    var buf : CJmpBuf
    try {
        short_row[row_at] = 1
    } recover {
        if (c_jmp_target != unsafe(addr(buf))) {
            c_jmp_rethrow()
        }
        c_jmp_target = null
    }
}
