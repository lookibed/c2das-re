# frontend Architecture - the C-IR byte diff

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes `diff.das`, the byte diff of two dumpers' C-IR (the plan's C.6), which the comparison of
`compare/types/` and the converter's tests run over Dumper A's and Dumper C's texts.

## 49. Normalization and diff {#cir-diff}

Two dumpers' C-IR for one unit must be byte-identical (`docs/c-ir-spec.md`, the differential
test). `cir_normalized` reads a text with the C-IR reader (`read_cir` of `converter/cir.das`) and
writes it again with `write_cir`, the one writer, after clearing what the comparison sets aside:
the unit's `macros` table and every node's `macro`, `fn_macro` and `macro_args` (spec sections
6.2 and 6.3, the recovery hooks a dumper may leave out, which Dumper C does until its preprocessor
expands macros), and the `producer`, which names the dumper that wrote the text. `cir_diff`
compares the two normalized texts byte for byte; a difference is reported at its first line with
both lines, and a text the reader refuses by which side it is. The module reads two texts and
nothing else: it opens no file and starts no process, so a driver outside this folder runs the
dumpers (`compare/types/`).

The `producer` names the dumper and its version (`c2das-dumper-a 0.1 / clang <version>` against
`c2das-dumper-c 0.1`), so two conforming dumpers never agree on it; the plan's byte diff sets it
aside beside the macro fields (C-To-DAS part 2, C.6 and acceptance row F3).
