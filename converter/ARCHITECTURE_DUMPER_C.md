# converter Architecture - Dumper C behind --dumper c

Companion to `ARCHITECTURE.md` in this folder. It describes `dumper_c.das`, the converter's way to
Dumper C, the clang-free C-IR builder of `frontend/` (`frontend/ARCHITECTURE_TYPES.md`,
`ARCHITECTURE_EXPRS.md`, `ARCHITECTURE_NAMES.md`), and the `--dumper` option that selects it.

## 1. The driver {#dumper-c}

`dumper_c_tu` builds a unit's C-IR with Dumper C: the frontend's preprocessor reads the unit
(`c_parser_open_source`: the dialect's predefined-macro table, its feature table for the `#if`
queries, the own headers' folder searched, the file system through `PpFioProvider`), the parser
reads its tokens, and `c_ir_unit` builds the C-IR, the own headers' folder as the library. Every
place in the C-IR is the builder's own token's (`frontend/ARCHITECTURE_NAMES.md` section 48). No
clang runs for Dumper C. The builder leaves out the declarations of
a file outside the program root (the sidecar's `program_root`, else the main file's folder) as it
leaves out the own headers', and a C file outside it is an error, as Dumper A's file policy has it;
a main file outside the root is refused before it is read.

Dumper C writes no macro spelling yet: its C-IR has no `macro`, `fn_macro` or `macros` (A.6 of the
plan brings them), so a `--dumper c` module carries no named constant and folds no function-like
macro expansion into a call of its `[c_macro] def`; the das differs from `--dumper a`'s in those
places alone, and a sidecar's `no_fold` naming a macro fails under `--dumper c`, as it names no
macro the program expands. A sidecar's `defines`, `include_dirs` and
`include_files` are refused, since the builder takes none yet; the C-IR's producer is
`c2das-dumper-c 0.1`.

`pipeline.das`'s `convert` and `convert_program` take `dumper` (`"a"` by default): `"c"` builds each
unit with Dumper C in place of `dump_tu`, and every step after the dump (the C-IR written, read back
and rewritten, emitted, compile-checked) is the same. The frontend's modules require dasFlex,
which the converter does not load, so the pipeline runs Dumper C in a child daslang that loads it
(`dumper_c_child`): `dumper_c_main.das` writes the unit's C-IR text to
`<out_dir>/<stem>.dumper_c.cir.json`, which the pipeline reads back, or prints why it failed. No
module the converter requires requires `frontend/`. `main.das`'s `--dumper a|c` sets it, any other
value a usage error (exit 2), and the suites' runner passes its own `--dumper` on
(`suites/ARCHITECTURE.md`).
