# dasCRuntime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md`. Planned work: `docs/implementation_order.md`.

**A forwarder in `src/dasCRuntime.h` is one CRT call and the casts its spelling needs; a
forwarder with a branch, a loop, a `static` or `thread_local` local, or a second call is a
defect.** Logic belongs in `c_runtime/` (das), never here.

**A diff that adds or changes an `addExtern` whose das signature takes or returns a pointer
sets `unsafeOperation = true` on it.**

**A diff that adds or changes an `addExtern` registers it `SideEffects::none` only when the
call reads nothing but its arguments and changes nothing but its return value,
`SideEffects::modifyArgumentAndExternal` when it may write through a pointer argument (a
destination buffer, an out-parameter, an end pointer, memory it frees or moves), and
`SideEffects::modifyExternal` otherwise - `errno`, the `rand` seed, the environment, the clock,
streams and memory all count; no other `SideEffects` value.**

**A forwarder spells each CRT integer type as the fixed-width type of the same width and
signedness on the building platform (`size_t` as `uint64_t`, `long` as `int64_t`), each `char`
pointer as a `uint8_t` pointer with the same `const`, and never narrows or widens a value
itself.** The converter's 32-bit `long` is applied at the call site by the emitter.

**A diff that adds or renames a bind or a constant asserts in `tests/test_crt.das` a result the
C standard fixes for it; a constant is checked by name (`crt::ERANGE`) or by a relation the
standard fixes (`crt::CLOCKS_PER_SEC > 0`), never against its glibc number.**

**Never weaken `REVIEW.das` - fix what it flags instead.**

**A diff that changes in `CMakeLists.txt` the RTTI flag, or a define on the
`target_compile_definitions` line its comment names as the checkout's own ABI, updates
`VERSIONS.md` (repo root) in the same change.**
