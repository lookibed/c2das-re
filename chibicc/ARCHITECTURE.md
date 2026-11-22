# chibicc Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
converts chibicc (MIT), a small C11 compiler written in C, as a whole program. It is the probe of
ledger item P10.0: a C compiler converted by this repository is a candidate C frontend that runs
inside daslang, with no clang.

## 1. File charters

- `fetch.sh` - clones chibicc at the commit the `chibicc:` line of `VERSIONS.md` pins into
  `fetch/chibicc/`, applies `patches/*.patch`, and builds the native compiler
  `fetch/chibicc/chibicc` from the patched sources at `-O2`. The checkout is never committed.
- `patches/0001-c2das-host.patch` - the port's changes to chibicc's sources (section 3).
- `sources.das` - the units in link order, the sidecar's and the native compiler's paths, and the
  program manifest's text.
- `chibicc.c2das` - the sidecar: `jit_whole_program`, nothing else. The program has no packed,
  over-indexed or padded record.
- `tests/test_chibicc.das` - converts the fetched program and compares the converted compiler's
  `-S` and `-E` output of one C file with the native compiler's, byte for byte. It passes with a
  warning when the fetch is absent.

## 2. The program

The program is chibicc's nine C files and the port's `host.c`, each a translation unit, linked by
the converter with `main` as the entry. In the source layout eight of them call each other and
form one module, `main.das`, of `.das.inc` fragments; `host.das`, `strarray.das` and the header's
`chibicc_h.das` stand alone.

The converted compiler runs in the checkout's folder: chibicc finds its own headers in
`include/` beside `argv[0]`, and the converted program's `argv[0]` has no folder.

## 3. The port's patch

The oracle is the native compiler built from the same patched sources, so each change holds on
both sides.

- The compiler proper runs in the driver's process. Upstream runs it as a child of itself through
  `fork` and `execvp`, and runs `as` and `ld` the same way; c_runtime maps no process call. The
  port keeps `-E` and `-S`; a run that needs the assembler or the linker stops with a message.
- `host.c` holds, as portable C, the libc calls c_runtime does not map: `strndup`, `dirname`,
  `basename`, `strtok`. `chibicc.h` renames the calls to them.
- `open_memstream` is gone: `format` measures with `vsnprintf` and prints into a buffer of that
  size, `read_file` grows a buffer, and the assembly goes straight to its file.
- `glob` (the search for gcc's library folder) and `stat` are gone: `file_exists` opens the file,
  and `__TIMESTAMP__` is always the text upstream gives for a file it cannot stat.
- A numeric literal's value is a `double`, not a `long double`: the converter's `long double` is
  the 8-byte `double`, and a record holding a 16-byte one is not laid out naturally. `host.c`'s
  `host_f80_bits` gives the x87 bytes of a `long double` constant from the `double`, so such a
  constant is exact when a `double` holds it and rounded to a `double` otherwise.
- `strings.c` is `strarray.c`: a das module named `strings` is taken.
