options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das
require c_runtime/c_signal

//! `signal` as the converter emits it: `c_signal(2, @@handler)`, `SIG_DFL` as
//! `default<function<(a0 : int) : void>>` and compared as `null`.

var private hits : int

def private on_interrupt(a0 : int) {
    hits += a0
}

def private on_terminate(a0 : int) {
    hits += a0 * 10
}

[test]
def test_c_signal(t : T?) {
    t |> run("signal returns the previous handler, SIG_DFL before the first call, and calls none") @(t : T?) {
        var prev : function<(a0 : int) : void> = c_signal(2, @@on_interrupt)
        t |> equal(prev == null, true)
        prev = c_signal(15, @@on_terminate)
        t |> equal(prev == null, true)
        prev = c_signal(2, default<function<(a0 : int) : void>>)
        t |> equal(prev == @@on_interrupt, true)
        prev = c_signal(2, default<function<(a0 : int) : void>>)
        t |> equal(prev == null, true)
        prev = c_signal(15, @@on_interrupt)
        t |> equal(prev == @@on_terminate, true)
        // SIG_IGN, the integer sentinel, is kept and returned like a handler
        prev = c_signal(15, unsafe(reinterpret<function<(a0 : int) : void>>(uint64(1))))
        prev = c_signal(15, default<function<(a0 : int) : void>>)
        t |> equal(prev == unsafe(reinterpret<function<(a0 : int) : void>>(uint64(1))), true)
        t |> equal(hits, 0)
    }
    t |> run("a number outside 1 to 64, where C returns SIG_ERR, panics naming it") @(t : T?) {
        for (sig in [0, 65]) {
            let r = runtime_child("signal_{sig}", "options gen2\nrequire c_runtime/c_signal\ndef h(a0 : int) \{\n    return\n\}\n[export]\ndef main : int \{\n    c_signal({sig}, @@h)\n    return 0\n\}\n", false)
            child_rejects(t, "signal_{sig}", r, "signal {sig}: no such signal number")
        }
    }
}
