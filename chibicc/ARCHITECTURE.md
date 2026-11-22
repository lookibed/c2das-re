# chibicc Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
converts chibicc (MIT), a small C11 compiler written in C, as a whole program. It is the probe of
ledger item P10.0: a C compiler converted by this repository is a candidate C frontend that runs
inside daslang, with no clang.

## 1. File charters

- `fetch.sh` - clones chibicc at the commit the `chibicc:` line of `VERSIONS.md` pins into
  `fetch/chibicc/`, applies `patches/*.patch`, and builds the native compiler
  `fetch/chibicc/chibicc`, the oracle (section 4). The checkout is never committed.
- `patches/0001-c2das-host.patch` - the port's changes to chibicc's sources (section 3).
- `sources.das` - the units in link order, the sidecar's and the native compiler's paths, and the
  program manifest's text.
- `chibicc.c2das` - the sidecar: `jit_whole_program`, nothing else. The program has no packed,
  over-indexed or padded record.
- `tests/test_chibicc.das` - converts the fetched program and compares the converted compiler's
  `-S` and `-E` output of one C file with the native compiler's, byte for byte. It skips, with
  the reason, when the fetch is absent or the checkout is at another commit than the pin, and it
  removes the temp folder it converts in.

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
- `-c2das-time` prints the CPU time of the compiler proper on stderr (`cc1 <n> us`, `clock()`
  around it). A converted run spends 0.6 s under the interpreter, and 9 s under the wasm one,
  compiling the das program before `main`; a clock around the process cannot take that out of a
  unit that compiles in a tenth of a second.

Against upstream the patched compiler differs in four more ways:

- A `double` or `float` literal is rounded once, by `strtod`. Upstream reads it with `strtold`
  and rounds the `long double` again, so a literal between two doubles can differ in its last
  bit.
- The compiler proper keeps its state from one input to the next: with several inputs on one
  command line the macros, the include folders and the label counter of an earlier file reach a
  later one. The tests and the oracle runs give one input a run.
- An error the code generator raises leaves the assembly written so far in the output file;
  upstream writes the file only after the generator ends.
- `__TIMESTAMP__` and the x87 constants, as above.

## 4. The oracle

`fetch.sh` compiles the patched sources with `cc -std=c11 -O2 -fno-common -funsigned-char -w`,
each file by its full path. Both flags are the converter's dialect: its plain `char` is unsigned
(chibicc prints an initializer's bytes through a `char`, `.byte 215` where a signed `char` gives
`.byte -41`), and the dumper reads each unit by its full path, which `__FILE__` in chibicc's
`unreachable()` message carries. The oracle of a comparison is this build, not upstream's
default one.
