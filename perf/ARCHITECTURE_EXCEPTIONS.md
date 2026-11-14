# perf Architecture - the exception ledger

Companion to `ARCHITECTURE.md` in this folder: the cells of the perf table whose values a reader
would take for a defect, each with its reason (`ARCHITECTURE_COMMON.md`, the exception ledger).

## 1. The ledger

- `sieve` and `matmul` / `aot`: 8.0 and 1.6 times native. The generated C++ finds a module global
  through the context's mangled-name lookup at every access (`das_global<T, mnh>`), and a C
  file-scope array is a module global. In `sieve` every iteration stores into the array, and the
  host compiles with `-fno-strict-aliasing`, so any store may alias the lookup table and clang keeps
  the probe inside the loop. `matmul`'s inner loop stores nothing, yet the probes stay in it too:
  hoisting the three lookups by hand in the generated C++ with the bounds checks kept takes the cell
  from 0.864 to 0.599 ms (native 0.600), while keeping the lookups and indexing raw without the
  bounds check leaves it at 0.84 ms; the lookup is the cost, the bounds check is not
  (`docs/probe-findings.md` F49, lookibed/daScript#5). daslang documents the lookup as the
  contract: every converted module carries `options solid_context`, which "prohibits AOT and
  patches" (`doc/source/reference/language/options.rst` in `DASLANG_ROOT`), so the AOT context
  keeps the mangled-name lookup (lookibed/daScript#48, closed as outside the contract).
