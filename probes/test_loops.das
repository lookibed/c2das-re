options gen2
require dastest/testing_boost public

var trace : array<int>

def cond(i : int) : bool {
    trace |> push(i)
    return i < 4
}

def note(v : int) : int {
    trace |> push(v)
    return v
}

[test]
def test_loops(t : T?) {
    t |> run("do-while first-pass flag: condition skipped on entry, tested after every pass including continue") @(t : T?) {
        trace |> clear()
        var i = 0
        var first_pass = true
        var work : array<int>
        while (first_pass || cond(i)) {
            first_pass = false
            i++
            if (i == 2) {
                continue
            }
            work |> push(i)
        }
        t |> equal(i, 4)
        t |> equal("{trace}", "[ 1, 2, 3, 4]")
        t |> equal("{work}", "[ 1, 3, 4]")
    }
    t |> run("for increment-first flag: continue runs the increment, break skips it, test follows increment") @(t : T?) {
        var order : array<string>
        var k = 0
        var passed_once = false
        while (true) {
            if (passed_once) {
                k++
                order |> push("inc")
            }
            passed_once = true
            order |> push("test{k}")
            if (!(k < 3)) {
                break
            }
            if (k == 1) {
                order |> push("cont")
                continue
            }
            if (k == 2) {
                order |> push("brk")
                break
            }
            order |> push("body")
        }
        t |> equal(k, 2)
        t |> equal("{order}", "[ test0, body, inc, test1, cont, inc, test2, brk]")
    }
    t |> run("body-block finally runs per iteration and on continue") @(t : T?) {
        var runs = 0
        var j = 0
        while (j < 3) {
            {
                if (j == 1) {
                    j += 100
                    continue
                }
            } finally {
                j++
                runs++
            }
        }
        t |> equal(j, 102)
        t |> equal(runs, 2)
    }
    t |> run("body-block finally also runs on break, unlike a C for-increment") @(t : T?) {
        var runs = 0
        var q = 0
        while (q < 3) {
            {
                if (q == 1) {
                    break
                }
            } finally {
                q++
                runs++
            }
        }
        t |> equal(q, 2)
        t |> equal(runs, 2)
    }
}

[test]
def test_range_loops(t : T?) {
    t |> run("a range loop of each counting type counts from its start to below its end, empty when the start is past it") @(t : T?) {
        var seen : array<int>
        seen |> reserve(8)
        for (i in range(2, 5)) {
            seen |> push(i)
        }
        for (i in range(3)) {
            seen |> push(i * 10)
        }
        for (_i in range(7, 2)) {
            seen |> push(-1)
        }
        var wide = 0l
        for (k in range64(int64(1), 4l)) {
            wide += k
        }
        var unsigned_sum = 0u
        for (v in urange(3u)) {
            unsigned_sum += v
        }
        var big = 0ul
        for (v in urange64(2ul, 4ul)) {
            big += v
        }
        t |> equal("{seen}", "[ 2, 3, 4, 0, 10, 20]")
        t |> equal(wide, 6l)
        t |> equal(unsigned_sum, 3u)
        t |> equal(big, 5ul)
    }
    t |> run("a range loop evaluates its start and its end once, start first, and continue goes to the next value") @(t : T?) {
        trace |> clear()
        var visited : array<int>
        for (i in range(note(1), note(4))) {
            if (i == 2) {
                continue
            }
            visited |> push(i)
        }
        t |> equal("{trace}", "[ 1, 4]")
        t |> equal("{visited}", "[ 1, 3]")
    }
}

