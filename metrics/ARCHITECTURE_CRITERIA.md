# metrics Architecture - the readability criteria

Companion to `ARCHITECTURE.md` in this folder. The criteria measure what a reader of the
converted output misses against a port a human would write: one criterion per finding and blind
spot of the owner's readability review of the Lua output (owner ruling 21). Each criterion is a
compliance percentage, 100 meaning the output has what a human port would have. The counts are
read off the text of the C sources and the emitted modules, never off a compiled AST, so a run
needs no compile beyond the conversion's own.

## 1. File charters

- `criteria.das` - the driver (`scripts/run_criteria.sh`): every Lua key and every ratchet suite
  key `expected_input_keys` names (the readability inputs without the `perf` group), one worker
  process per input (`--one <key>`), the Lua inputs one at a time and the rest `--jobs` at a time
  (4 by default), each writing `work/<key>/criteria.txt`; it sums the rows (section 2), prints the
  table, with `--delta <capture>` the delta table, and a complete run (no `--filter`, no failed
  input) writes `criteria_linux.json`. `--report` is the preflight gate (section 5).
- `readability_inputs.das` - one input key converted as both metrics convert it: the C file or
  the Lua program's files, the sidecar, the emitted modules and fragments.
- `criteria_scan.das` - the lexer of C and das text and the facts of one C source and one emitted
  module.
- `criteria_defines.das` - a unit preprocessed by the pinned clang (`-E -C -dD`): its macros and
  the lines it keeps; the program's numeric-constant macros (section 3).
- `criteria_count.das` - the raw counts of one input from its sources and modules (section 4).
- `criteria_file.das` - the criteria, their formulas, the capture's text, reader and shape check,
  the tables, the worker file and the sample check. It requires nothing beyond daslib.
- `criteria_linux.json` - the committed capture: `compliance` (per column, each criterion's
  percentage, `null` where it does not apply), `raw` (per row, the raw counts), `sample` (the raw
  counts of the four c-testsuite inputs the gate re-measures) and `totals` (per column).
- `tests/test_criteria.das` - every counter on small C and das texts, a positive and a negative
  case each, the formulas, the capture's text and shape check, the tables, the worker file and
  the gate's three outcomes.

## 2. Rows, columns and the total {#rows}

A row is one Lua program in one layout (`lua/lua`, `lua/lua@scc`, `lua/lua@single`, the same for
`luac`) or one ratchet suite (`c_testsuite`, `csmith`, `gcc_torture`), whose raw counts are the
sum over its inputs. A per-function ratio's median and worst are taken over the row's pooled
functions. Each criterion's compliance is computed per row from the row's raw counts; a criterion
whose denominator is zero in a row does not apply there (`n/a`). The `all` column is each
criterion's unweighted mean over the rows where it applies, every row weighing the same: a Lua
layout weighs as much as a whole suite, since each is one way a reader meets the output. A
column's total is the unweighted mean of its applicable criteria: the review argues no weight
between its findings, so none is applied.

## 3. The numeric-constant macros {#constants}

Clang expands every `#define` before the converter sees the program, so the output spells a
macro's value where the C source spells its name. The program's numeric-constant macros are the
object-like `#define`s its own files make (its `.c` files and the headers they include by a quoted
name, found beside the including file, transitively) whose body, expanded under the macros each
unit's preprocessing reports (`clang -E -C -dD`, the sidecar's `defines` and `-D__NO_CTYPE` as
the dumper passes them), is numbers and character literals under arithmetic, comparison and
logic operators, once each cast (identifiers and `*` in parentheses before an operand that is not
a sign) and each `sizeof(...)` is dropped. A function-like macro is expanded with its arguments; a
macro already being expanded stays a name, which leaves the expression non-constant.

The same preprocessing gives the lines a unit keeps: a conditional branch (`#if`, `#ifdef`,
`#ifndef`, `#elif`, `#else`) none of whose lines the preprocessor emitted is inactive, and every C
count but the `#include` and `#define` lines skips it, as the conversion never sees it.

## 4. The criteria {#criteria}

A C code line is a non-blank line outside comments and directives; a das code line a non-blank
line outside comments. A das function is the span from its `def` line ending in `{` to the next
line that is `}` alone at the margin; a C function the span from its name to the brace closing a
file-level `{` that follows a head ending in `)` with no `=` and no `struct`, `union`, `enum` or
`typedef` before it. A das function is matched to the first unmatched C function of its name, with
a `_c_` prefix dropped and `c_main` read as `main`; the per-function criteria count over matched
functions only, so a converter-made function (a link wrapper, the layout check) is in none of
them. "Clean share" is the share of the denominator free of the defect.

| Criterion | Counted | Human port | Compliance |
|---|---|---|---|
| `comments` | das comment lines equal to a C comment line, or of two words or more inside one (the banner excepted) | every C comment line carried | carried / C comment lines |
| `constant_names` | per macro, das uses of the name, capped at the C uses | every C use of a numeric-constant macro by name | named / C uses |
| `char_literals` | per spelling, das character literals, capped at the C ones | every C character literal as one | kept / C character literals |
| `macro_blowup` | das code lines per C code line of each matched function; median and worst recorded | within 1.5x | functions within / matched |
| `repeated_blocks` | code lines covered by a window of four consecutive non-trivial lines seen twice | the C source's own repetition | das unique share / C unique share, capped |
| `switch_flags` | `var _flag = false` switches (with `_flag ||=` and `_goto` lines recorded) | a `switch` as `if`/`elif` | clean share of the C `switch` statements |
| `temporaries` | `var`/`let _tN`, `var _first`, `x = x` (discarded `let _tN` recorded) | none | clean share of matched functions |
| `addr_deref` | `addr(x).f`, `addr(deref(`, `deref(addr(` | none | clean share of matched functions |
| `reinterpret_casts` | `reinterpret<T>(...)` of anything but a string literal | none | clean share of matched functions |
| `late_binding` | a module named `*_link` or spelling a `*_slot` | none | clean share of modules |
| `qualified_calls` | `__::` and `<module>::` of a program module; `crt::` and other outside modules are not counted, since `crt` is a real outside module holding the C library and a human port qualifies a call to it too | none | clean share of matched functions |
| `require_lines` | das `require` lines | one per C `#include` | C includes / das requires, capped |
| `setjmp` | `try` lines inside a `while (_sj_run)` trampoline | a flat `try`/`recover` | clean share of the `try` lines |
| `layout_checks` | `static_assert(typeinfo ...)` lines | in a test, not the module | clean share of modules |
| `stray_braces` | a line holding `{` alone | none | clean share of matched functions |
| `label_stubs` | `c_label_end` | none | clean share of matched functions |
| `string_literals` | `reinterpret<T>("...")` | a C string as a string | clean share of the C string literals |
| `lost_parens` | a shift beside `+`, `-`, `&`, `\|` or `^` at one parenthesis level | the author's parentheses | clean share of matched functions |
| `literal_arithmetic` | an arithmetic operator between two number literals (`0 + 7`) | a named value | clean share of matched functions |
| `bool_roundtrip` | `? 1 : 0` | a plain condition | clean share of matched functions |
| `c_renames` | identifiers starting `_c_` | the C name | clean share of matched functions |
| `long_lines` | lines over 160 bytes | none | clean share of modules |

Where the C source has no counterpart (most noise criteria), the denominator is the unit a reader
judges, the function or the module, since a site count per C line would read near 100 percent
however noisy the worst functions are. `switch_flags` and `string_literals` take the larger of
the C count and the das count as the denominator, so a das count past the C one reads 0. The
per-module criteria (`layout_checks`, `long_lines`, `late_binding`) are binary in a one-module
row: the `single` layout and every suite input hold one module, so a single layout check or long
line takes a Lua `single` row to 0 where the source layout's many modules read a share
(`lua/lua@single` `layout_checks` 0.0 against 64.6 in `lua/lua`).

What the criteria leave out: the unreachable `return` the emitter adds after a function whose end
is formally reachable (no text shape tells it from a reachable one), `[c_function]` (the
annotation is the C context's mechanism, not noise) and `typeinfo sizeof` (daslang's spelling of
`sizeof`).

## 5. The gate

`criteria.das --report --delta-ref <base>` reads the committed capture: missing, not JSON or
failing the shape check, it exits 1 naming why; otherwise it prints the table, the delta against
the capture `git show <base>:metrics/criteria_linux.json` gives (a line saying there is none when
the base has no capture) and re-measures the `sample` inputs, printing one `stale:` line per
input whose raw counts differ from the capture's, and exits 0. The full measurement converts
every Lua layout and about 1,500 suite inputs, over half an hour, which is past the fast tier's
budget; the four c-testsuite inputs (a switch with character literals and comments, defines, a
plain switch) convert in seconds and show whether the converter's output moved since the capture
was recorded.
