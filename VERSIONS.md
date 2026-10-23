# Pinned versions

Every external the pipeline depends on, at an exact version. `scripts/verify_daslang.sh`
checks the daScript pin; the rest are checked by the tool that needs them.

daScript commit: 0fd34f17fcb8b96e228276a81066a93e314b06d8 (GaijinEntertainment/daScript master, the merge of PR #4107 `mcp-served-tree-paths-rebased`: the MCP served-tree path fix this repository relies on; any later master commit satisfies the pin), built at DASLANG_ROOT with `-DDAS_CLANG_BIND_DISABLED=OFF -DDAS_STDDLG_DISABLED=OFF -DDAS_HV_DISABLED=OFF -DDAS_LLVM_DISABLED=OFF -DPATH_TO_LIBCLANG=/root/libclang`
libclang: LLVM 22.1.8 Linux x86_64 release archive, extracted at PATH_TO_LIBCLANG (`lib/cmake/clang/ClangConfig.cmake` present); `DAS_CLANG_INCLUDE` names its `include/`
ast-grep: 0.44.1 (`sg` on PATH; sgconfig.yml maps `.das` to daScript's tree-sitter grammar and `.c/.h/.hpp` to C++)
clang-format: 22.1.8 (the libclang archive's `bin/clang-format`)
vendored skills: `skills/DASLANG_SKILLS_PIN` (the daScript commit `scripts/sync_daslang_skills.sh` last copied from)
dasCRuntime: built by `scripts/build_crt.sh` (cmake 3.16+, a C++17 compiler) against `DASLANG_ROOT/include` and `lib/liblibDaScriptDyn*`, with the checkout's ABI: no RTTI, `DAS_ENABLE_DYN_INCLUDES=1`, `DAS_FUSION=2`, `SIZE_OF_VOID_P` = the pointer width
gcc-torture: 04696df09633baf97cdbbdd6e9929b9d472161d3 (gcc-mirror/gcc releases/gcc-14.2.0, the subtree `gcc/testsuite/gcc.c-torture/execute`; `suites/gcc_torture/fetch.sh` sparse-clones it)
c-testsuite: 5c7275656d751de0e68b2d340a95b5681858ed07 (c-testsuite/c-testsuite master of 2020-03-09, the single-exec suite; `suites/c_testsuite/fetch.sh` checks it out)
csmith: 0cdc710315cfee9035e22ef4363ca479270d1934 (csmith-project/csmith master; `suites/csmith/fetch.sh` clones it and builds it with cmake)
cvise: 134d6f6a2c0344903b44629b27e211d9b15dee1c (marxin/cvise master, cvise 2.12.0; `suites/csmith/fetch.sh --cvise` builds it against PATH_TO_LIBCLANG, its Python packages pinned in the script and installed in a venv beside it)
gcc: 14.2.0 (Debian 14.2.0-19, the reference compiler of the csmith differential; `suites/csmith/run.das` checks `gcc -dumpfullversion` against it)
lua: 5.4.8 (the lua.org release https://www.lua.org/ftp/lua-5.4.8.tar.gz (sha256 4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae) and its test suite https://www.lua.org/tests/lua-5.4.8-tests.tar.gz (sha256 9581d5a7c39ffbf29b8ccde2709083c380f7bbddbd968dcb15712d2f2e33f4e5); `lua/fetch.sh` downloads both, checks each hash and extracts them)
dasProfile commit: 436d58d2840ff839550d44d32f98e10a15b57bf2 (borisbat/dasProfile master; `perf/dasprofile.sh` clones it into `perf/work/dasprofile/src`, builds it against the daScript SDK with PATH_TO_LIBCLANG's clang and clang++, runs its `--json --das-only` capture and copies it to `perf/dasprofile_linux.json`)
daScript SDK: /root/daScript-sdk (`cmake --install` of DASLANG_ROOT's `build/` tree, the layout dasProfile's `find_package(DAS)` reads; `perf/dasprofile.sh` installs it, then copies in the headers the install omits, `daScript/misc/das_asan.h` among them)
