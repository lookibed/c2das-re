options gen2
require dastest/testing_boost public

// lookibed/daScript#49 (docs/probe-findings.md F103): a small callee whose range loop returns early, called
// directly, runs its caller about 1.8x slower under the interpreter on abf1d40e35 than the same callee under
// [hint(noinline)]; the results agree. The timing repro (a `while` counter, 14000-wide, best of 5) is the issue's inl.das
def private isprime(n : int) : int {
    for (i in range(2, n)) {
        if (n % i == 0) {
            return 0
        }
    }
    return 1
}

[hint(noinline)]
def private isprime_noinline(n : int) : int {
    for (i in range(2, n)) {
        if (n % i == 0) {
            return 0
        }
    }
    return 1
}

def private count_direct(n : int) : int {
    var count = 0
    for (i in range(2, n + 1)) {
        if (isprime(i) != 0) {
            count++
        }
    }
    return count
}

def private count_noinline(n : int) : int {
    var count = 0
    for (i in range(2, n + 1)) {
        if (isprime_noinline(i) != 0) {
            count++
        }
    }
    return count
}

[test]
def test_inline_early_return(t : T?) {
    t |> run("an early-return range loop gives the same result called directly and under [hint(noinline)] (F103)") @(t : T?) {
        t |> equal(count_direct(2000), 303)
        t |> equal(count_noinline(2000), 303)
    }
}
