options gen2
require dastest/testing_boost public

var leveltime : int
var data : int[4]
var p : int?
var data2 : int[4] = fixed_array(1, 2, 3, 4)
var q : int? = unsafe(addr(data2[1]))
var _str_0 : uint8[3] = fixed_array(uint8(65), uint8(66), uint8(0))
var names : uint8? [2]
var private hidden = 3

struct State {
    sprite : int
    action : function<() : void>
}

def A_Look {}

var states : State[2] = fixed_array(State(sprite = 1, action = @@A_Look), State(sprite = 2))

[init]
def _c2das_init_pointers {
    unsafe {
        p = addr(data[1])
        names[0] = addr(_str_0[0])
    }
}

def private helper : int => hidden

def forty_two : int => 42

[test]
def test_globals(t : T?) {
    t |> run("globals zero-init and an explicitly initialized global can be addressed inline") @(t : T?) {
        t |> equal(leveltime, 0)
        t |> equal(data[3], 0)
        t |> equal(deref(q), 2)
    }
    t |> run("[init] fills address-carrying globals before any test runs") @(t : T?) {
        t |> equal(p == unsafe(addr(data[1])), true)
        t |> equal(int(deref(names[0])), 65)
    }
    t |> run("function-pointer tables initialize inline and a missing member is null") @(t : T?) {
        t |> equal(states[0].action != null, true)
        t |> equal(states[1].action == null, true)
    }
    t |> run("a function value's zero is default<function<...>>, compared with null; `= null` is not a function value") @(t : T?) {
        var f : function<() : int> = default<function<() : int>>
        t |> equal(f == null, true)
        f = @@forty_two
        t |> equal(f != null, true)
        t |> equal(invoke(f), 42)
        f = default<function<() : int>>
        t |> equal(f == null, true)
    }
    t |> run("var private and def private compile and resolve inside the module") @(t : T?) {
        t |> equal(helper(), 3)
    }
}
