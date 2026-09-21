# Pinned versions

Every external the pipeline depends on, at an exact version. `scripts/verify_daslang.sh`
checks the daScript pin; the rest are checked by the tool that needs them.

daScript commit: 1969ad4d4e38ae8fb9b6854a0c8f98922784558a (lookibed/daScript, branch lookibed/mcp-served-tree-paths: upstream master ad002a9e6 plus the MCP served-tree path fix this repository relies on), built at DASLANG_ROOT with `-DDAS_CLANG_BIND_DISABLED=OFF -DDAS_STDDLG_DISABLED=OFF -DDAS_HV_DISABLED=OFF -DDAS_LLVM_DISABLED=OFF -DPATH_TO_LIBCLANG=/root/libclang`
libclang: LLVM 22.1.8 Linux x86_64 release archive, extracted at PATH_TO_LIBCLANG (`lib/cmake/clang/ClangConfig.cmake` present); `DAS_CLANG_INCLUDE` names its `include/`
ast-grep: 0.44.1 (`sg` on PATH; sgconfig.yml maps `.das` to daScript's tree-sitter grammar and `.c/.h/.hpp` to C++)
clang-format: 22.1.8 (the libclang archive's `bin/clang-format`)
vendored skills: `skills/DASLANG_SKILLS_PIN` (the daScript commit `scripts/sync_daslang_skills.sh` last copied from)
