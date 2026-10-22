options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das
require c_runtime/c_signal
require crt
require strings

//! `signal` as the converter emits it: `c_signal(2, @@handler)`, `SIG_DFL` as
//! `default<function<(a0 : int) : void>>` and compared as `null`, `SIG_IGN` and `SIG_ERR` the integer
//! sentinels 1 and -1 a function value holds.

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
    t |> run("a number the dialect's C library refuses returns SIG_ERR with errno EINVAL and keeps nothing") @(t : T?) {
        let sig_err = unsafe(reinterpret<function<(a0 : int) : void>>(0xfffffffffffffffful))
        for (sig in [0, 9, 19, 32, 33, 65, -1]) {
            crt::c_set_errno(0)
            t |> equal(c_signal(sig, @@on_interrupt) == sig_err, true, "{sig}")
            t |> equal(crt::c_errno(), 22, "{sig}")
        }
        t |> equal(c_signal(64, @@on_interrupt) == null, true)
        c_signal_msvc = true
        crt::c_set_errno(0)
        t |> equal(c_signal(13, @@on_interrupt) == sig_err, true)
        t |> equal(crt::c_errno(), 22)
        t |> equal(c_signal(22, @@on_interrupt) == null, true)
        t |> equal(c_signal(21, @@on_interrupt) == null, true)
        c_signal_msvc = false
        crt::c_set_errno(0)
        t |> equal(hits, 0)
    }
    t |> run("SIG_IGN and SIG_DFL reach the host: an ignored signal leaves the process running, a default one ends it") @(t : T?) {
        // SIGUSR1 (10) from a shell whose parent is the child's process
        let body = "options gen2\nrequire crt\nrequire c_runtime/c_signal\ndef h(a0 : int) \{\n    return\n\}\n[export]\ndef main : int \{\n    let kill = \"kill -USR1 $PPID\"\n    c_signal(10, unsafe(reinterpret<function<(a0 : int) : void>>(1ul)))\n    unsafe \{\n        crt::system(reinterpret<uint8?>(kill))\n    \}\n    print(\"ignored\\n\")\n    c_signal(10, @@h)\n    c_signal(10, default<function<(a0 : int) : void>>)\n    unsafe \{\n        crt::system(reinterpret<uint8?>(kill))\n    \}\n    print(\"survived\\n\")\n    return 0\n\}\n"
        let r = runtime_child("signal_host", body, false)
        t |> equal(r.out |> find("ignored\n") >= 0, true, r.out)
        t |> equal(r.out |> find("survived") >= 0, false, r.out)
        t |> equal(r.rc != 0, true, r.out)
    }
}
