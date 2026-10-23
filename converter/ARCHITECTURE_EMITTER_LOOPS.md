# converter Architecture - the emitter's loops, compound stores and volatile access

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### Loops

`while` is `while`, with a side-effecting condition spelled `while (true)` plus the test and
`break`; `do` is the `_first` flag. A `for` is one of four shapes, the first that applies:

- **The range loop** (`for_range`), O1 of `docs/very-detailed-plan.md` section 6 in the shape the
  "General for" of `docs/lowering-examples.md` prescribes: `for (T i = a; i < n; ++i)` (or `i++`,
  `i += 1`) with `T` a 32- or 64-bit integer the initializer declares, the test comparing `i`
  with a bound of `i`'s own type, the body never writing `i` or taking its address and the bound
  invariant - literals, enumerators, `sizeof`, and the function's own locals and parameters that
  the body never writes and nothing in the function takes the address of, under casts, `+`, `-`
  and `*`, never `i` itself (the increment writes it), a call, a global, a load through a pointer
  or a volatile object - is
  `for (i in range(a, n))`: `range`, `range64`, `urange` or `urange64` by `T`, `range(n)` when
  `a` is the literal 0. das evaluates `a` and then `n` once, which is C's order and, with the
  bound invariant, C's every-pass test; `i` dies with the loop as C99's does, `continue` reaches
  the next value as C's increment does, and a start past the bound runs no pass
  (`probes/test_loops.das`). The start's hoisted statements, when it has any, go in a block of
  their own before the loop. Under the `loops` option `while` (the CLI's `--loops while`, the
  sidecar's `"loops": "while"`) no loop takes this shape.
- **The trailing increment**: a body that holds no `continue` of the loop (one outside every
  nested loop, a switch's included) is `while (cond) { body; inc }`. A `break`, a `return` or a
  `goto` out of the body skips the increment, as C's does, and a body ending in one takes no
  increment, which no pass would reach.
- **The `finally` block**: a body with a `continue` that never leaves the loop (no `break` at its
  level, no `return`, no `goto`) is `while (cond) { { body } finally { inc } }`, since `finally`
  runs on `continue` and on every pass but also on `break`.
- **The increment-first flag** `_f` otherwise.

The split is measured: `benchmarks/bench_for_shapes.das` times one body under the four
spellings; the interpreter runs the range loop fastest, then the trailing increment, the
`finally` form and the flag, while the JIT compiles all four to the same code. On the perf
kernels the range loop and the next two rewrites take `fib_loop`'s interpreter cell from 0.357
to 0.060 s and `primes`'s from 0.363 to 0.135 s on the FX-6300 (`perf/ARCHITECTURE.md` section 3).

### Compound stores and the wrapping sum

`x = x op y` with `op` one of `+ - * & | ^`, `x` the same object on both sides (one variable, or
the same field or element chain over equal bases and literal or variable indexes, compared on
the C-IR, `same_lvalue`), no call or effect in `x` or `y` and no volatile read in `x` (C reads a
volatile index or pointer of `x` on both sides), and the operation in `x`'s own type -
a number of 32 or 64 bits or a float, never a pointer, a small integer, an enum, `_Bool`, a
bitfield, a member of a `[c_union]` record (a property, F52) or a volatile object - is
`x op= y` (`self_operation`): the interpreter runs the compound node 1.3 to 1.7 times faster than
the assignment of the sum, and the text is the one a person writes. `y` is the integer the plain
form adds, a truth value its 0 or 1 (`x += (a < b ? 1 : 0)`), parenthesized at `op`'s precedence.

C's wrapping signed sum, `(T) ((U) a + (U) b)` or `-`, with `T` a signed integer of 32 or 64
bits, `U` its unsigned twin and both operands of type `T` (`wrap_pair`), is `a + b` in `T`: das
`int` and `int64` `+` and `-` wrap on every tier (daScript builds with `-fwrapv`, the JIT emits
`add` without `nsw`, and the AOT host compiles with `-fwrapv`; `probes/test_scalars.das` under the
interpreter and the JIT, `tests/test_tier_facts.das` under all four tiers). The fold takes the
cast pair whether the program or clang wrote it, since the bits are the same; `x = (T) ((U) x +
(U) y)` then is `x += y`. A truth value as an operand is its 0 or 1, as the cast made it.

### Volatile access

A volatile object keeps every access C makes of it, since das has no volatile: the dumper marks
an lvalue of volatile-qualified type (`ref`, `member`, `index`, `un deref`, section 3), and the
emitter spells a read of it `c_volatile_load(x)` and a store `c_volatile_store(x, v)`, the
`c_runtime/c_volatile.das` piece over the `crt` forwarders that access the object through a
`volatile` pointer (`volatile_kept`). The object goes by reference, so the text carries no `addr`.
A compound store is one load and one store (`c_volatile_store(x, c_volatile_load(x) + 5)`, a
small integer's sum widened as the plain form's is), a step the same with one; the value of an
assignment or a prefix step read back is a load, a postfix step's old value the step's one load,
which the store adds to; a discarded read (`(void) v;`) is a load into a fresh temporary. A
volatile read inside a store's or a step's target, an index or a pointer the target goes through,
is made once into a temporary every spelling of the target reads (`pin_lvalue`), as C makes it
once. Neither the JIT nor the AOT host folds such a read or drops such a store, at any width,
where the plain access in the same loop is folded out of it (`tests/test_tier_facts.das`).

A number, `_Bool`, a data or function pointer, a field of a plain record and an element go
through the piece. A bitfield, a member of a `[c_union]` or marshal-only record and an enum are
properties or tagged values with no address, and a whole volatile record read or written at once
(csmith's programs copy volatile records) is a copy of every field, no single access: their
access stays the plain one, the volatile access no tier keeps. A volatile pointer steps and moves
as the plain one does, a step back as the sum of the negated count, since das's pointer `-`
takes only a variable (`probes/test_pointers.das`); a volatile `_Bool`'s compound store stores the
truth of the promoted result; its step fails closed as the plain one's does.
