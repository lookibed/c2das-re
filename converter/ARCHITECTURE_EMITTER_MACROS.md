# converter Architecture - function-like macros folded into defs

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### Which expansions fold {#fold-verdict}

A node Dumper A marks as a whole expansion of a function-like macro (`ARCHITECTURE_DUMPER_MACROS.md`,
`docs/c-ir-spec.md` section 6.3) may print as a call of an `[inline] def` of the macro when
`macro_fold.das` finds, from the node alone, that the call means what the expansion means
(`fold_expr_site`, `fold_stmt_site`). The emitter reads no verdict: every expansion prints
expanded. The walk takes the copies of each argument in evaluation order, the copies below a `?:` arm or the
right side of `&&`/`||`, or in a statement body below an `if`, a loop or a `switch`, as read on
some paths only. The verdict, in this order:

- `never`: the sidecar's `no_fold` names the macro, or folding reads worse: a body that is
  `((void)0)`, an argument under casts alone (an identity, a single cast), one operator over its
  arguments when one argument is never read (`luai_numadd(L, a, b)`); a statement macro that is
  neither a block nor a `do { ... } while (0)`, or an empty one.
- `shape`: a compound literal, an initializer list, `va_arg`, `offsetof`, or a call of `alloca`,
  `setjmp`, `longjmp` or a `va_*` builtin in the body.
- `flow`: a `return`, `goto`, label, or a `case`, `default`, `break` or `continue` that leaves the
  body (one inside a loop or switch of the body stays inside).
- `incomplete`: some argument has fewer or more copies than the macro's `uses`, or `uses` is
  unknown (-1): a type argument, `sizeof`, a split argument, a called parameter.
- `capture`: the body outside the copies names a parameter or local of the caller that the body
  does not declare itself.
- `lvalue`: a copy is addressed, or stored into, stepped or reached as an object rather than
  loaded (a field of a record argument, an array argument) when it is not a caller's local, which
  the def would do to its parameter; a caller's local the body writes is a reference parameter
  instead (`refs`, the def's `var x : auto&`).
- class B (a parameter read twice, never, or on some paths only): `effects` when any argument has
  a call, a store, a step or a volatile read; `faulting` when such an argument is not a constant, a
  local or parameter, a field of one through `.`, the address of either, or arithmetic over those
  without `/` or `%` (an argument the body never reads is only its text: a decimal literal or a
  local's name).
- `order`: a copy whose value a store of the body could change by the time C reads it (after a
  store, a call or on a loop's next turn), unless it is a constant or a local whose address is
  never taken; an argument reading the local another argument passes by reference; two arguments
  with effects, or one beside an argument that is not such a value, since das fixes no order
  among a call's arguments.
