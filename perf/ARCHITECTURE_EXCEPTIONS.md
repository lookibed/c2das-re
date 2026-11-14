# perf Architecture - the exception ledger

Companion to `ARCHITECTURE.md` in this folder: the cells of the perf table whose values a reader
would take for a defect, each with its reason (`ARCHITECTURE_COMMON.md`, the exception ledger).

## 1. The ledger

- `sieve`, `str_copy`, `switch_local` and `matmul` / `aot`: 8.1, 3.6, 1.7 and 1.6 times native. The
  generated C++ finds a module global through the context's mangled-name lookup at every access
  (`das_global<T, mnh>`, a perfect-hash probe), and a C file-scope array is a module global. In
  `sieve` every iteration stores a byte into the array; a `uint8_t` store may alias anything, so clang
  keeps the probe inside the loop (an `int` array built with strict aliasing is as slow, so
  `-fno-strict-aliasing` is not the cause). `matmul`'s inner loop stores nothing, yet the probes stay
  in it too: hoisting the three lookups by hand in the generated C++ with the bounds checks kept takes
  the cell from 0.864 to 0.599 ms (native 0.600), while keeping the lookups and indexing raw without
  the bounds check leaves it at 0.84 ms; the lookup is the cost, the bounds check is not
  (`docs/probe-findings.md` F49, lookibed/daScript#5). The lookup is a daslang emitter gap, not its
  contract: `daslib/aot_cpp.das` `visitExprVar` spells every global access in a function body as the
  probe whether or not the module carries `options solid_context` (the bodies are identical either
  way, `probes/test_globals.das` `test_aot_globals`), while the standalone `-ctx` context the AOT tier
  builds fixes every global's offset at generation time (its constructor asserts each one, and under
  `solid_context` its initializers already address them as `das_global_solid<T, offset>`). The same
  generated C++ with the reads rewritten to `das_global_solid` runs `sieve` 1.63, `str_copy` 1.40,
  `switch_local` 1.00 and `matmul` 1.01 times native, and PureDOOM demo1 1.14 against 5.56 (exclusive;
  the A/B, the das-only repro and the generated C++ are in lookibed/daScript#48). No option, flag or
  annotation reaches that emitter path, so the cells wait on that issue (reopened).
