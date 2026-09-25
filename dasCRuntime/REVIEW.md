# dasCRuntime Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `dasCRuntime/ARCHITECTURE.md`.

**A forwarder in `src/dasCRuntime.h` is one CRT call and the casts its spelling needs; a
forwarder with a branch, a loop, a local that outlives the call, or a second call is a
defect.** Logic belongs in `c_runtime/` (das), never here.

**Every `addExtern` whose das signature takes or returns a pointer sets
`unsafeOperation = true`; every bind that writes memory or CRT state is `modifyExternal` or
stronger, never `none`.**

**A forwarder spells the CRT type at its platform width - `size_t` as `uint64_t`, `long`
and `time_t` as `int64_t`, `char *` as `uint8_t *` - and never narrows or widens a value
itself.** The converter's dialect is applied at the call site by the emitter.

**A diff that adds or renames a bind or a constant adds or renames its arm in
`tests/test_crt.das`, asserting a value the C standard fixes; weakening `REVIEW.das`, which
checks the name appears there, is a defect.**

**A diff that changes a compile flag or define in `CMakeLists.txt` that the daScript headers
read - RTTI, `DAS_FUSION`, `DAS_ENABLE_DYN_INCLUDES`, `SIZE_OF_VOID_P` - updates
`VERSIONS.md` in the same change.**
