# metrics Architecture - the readability criteria

Companion to `ARCHITECTURE.md` in this folder. The criteria measure what a reader of the
converted output misses against a port a human would write: one criterion per finding and blind
spot of the owner's readability review of the Lua output (owner ruling 21). Each criterion is a
compliance percentage, 100 meaning the output has what a human port would have; the densities
(section 6) count the same sites, and the ones the criteria had no measure of, per thousand lines
of output, beside a port a human wrote. The counts are read off the text of the C sources and
the emitted modules, never off a compiled AST, so a run needs no compile beyond the conversion's
own.

daslang's lint never runs on converted output: the repository's `.lint_config` and the preflight
lint gate cover house code only, and the generated modules carry no lint options. A lint rule
(the `STYLE047` comparators, `LINT003` on pointers, the line-length gate) reaches generated code
only as a criterion here, decided per rule by what a human port would write.

## 1. File charters

- `criteria.das` - the driver (`scripts/run_criteria.sh`): every Lua key and every ratchet suite
  key `expected_input_keys` names (the readability inputs without the `perf` group), every
  compare project row of `ROWS` (`project/<name>`) and every hand-written port (`hand/<name>`,
  `HAND_PORTS`: the `.das` files of a folder an environment variable names, read where they lie,
  no C side), one worker process per input (`--one <key>`),
  the Lua and project inputs one at a time and the rest `--jobs` at a time, a project's worker
  with its soft address-space limit raised to the hard one (`worker_argv`)
  (4 by default), each writing `work/<key>/criteria.txt`; it sums the rows (section 2), prints the
  criteria, density and length tables, with `--delta <capture>` the delta tables, and a complete
  run (no `--filter`, no failed input) writes `criteria_linux.json`. `--report` is the preflight
  gate (section 5).
- `readability_inputs.das` - one input key converted as both metrics convert it: the C file or
  the Lua program's files, the sidecar, the emitted modules and fragments (a module's layout file,
  `is_layout_file` of `converter/pipeline.das`, neither); a `project/<name>` key
  through `convert_project` of `compare/projects.das`, the conversion the ports publisher
  publishes, over the Rust checkout (`$C2DAS_RUST`, else `/root/c2das`).
- `criteria_scan.das` - the lexer of C and das text and the facts of one C source and one emitted
  module.
- `criteria_defines.das` - a unit preprocessed by the pinned clang (`-E -C -dD`): its macros and
  the lines it keeps; the program's numeric-constant macros and its function-like macros
  (section 3).
- `criteria_count.das` - the raw counts of one input from its sources and modules (section 4),
  the functions' lengths among them (section 6).
- `criteria_file.das` - the criteria, their formulas, the densities and their pooled column, the
  capture's text, reader and shape check, the capture read from its file, the tables, the worker
  file and the sample check. It requires nothing beyond daslib, so `ports/publish.das` renders the
  criteria table with it.
- `criteria_linux.json` - the committed capture: `compliance` (per column, each criterion's
  percentage, `null` where it does not apply), `density` (per row and the `programs` column, each
  density and the two totals), `raw` (per row, the raw counts), `sample` (the raw counts of the
  four c-testsuite inputs the gate re-measures) and `totals` (per column).
- `tests/test_criteria.das` - every counter on small C and das texts, a positive and a negative
  case each, the formulas, the densities, the capture's text and shape check, the tables, the
  worker file, the hand-port worker and the gate's three outcomes.

## 2. Rows, columns and the total {#rows}

A row is one Lua program in one layout (`lua/lua`, `lua/lua@source-cut`, `lua/lua@single`, the same for
`luac`), one Lua program under an opt-in (`lua/lua@inline`, `--inline-helpers`; `lua/lua@goto`, `--switch-dispatch goto`; `lua/lua@checks-off`, `--checks off`;
`lua/lua@past-end-inline`, `--past-end inline`; `lua/lua@fn-macros-expand`, `--fn-macros expand`; the opt-in's readability
price, which the `all` column leaves out), one ratchet suite (`c_testsuite`, `csmith`, `gcc_torture`),
whose raw counts are the sum over its inputs, or one compare project (`project/wasm3`, `project/binjgb`,
`project/h264bsd-mp4`, `project/plmpeg-stream`, `project/doomgeneric`, `project/quakegeneric`, the
order of `project_table`). A project that converts whole is measured over every C file it compiles
and its modules; one that refuses whole over the files that convert alone and their modules, the
others in no count. `c_files` and `c_files_converted` record the program's C files and the ones
measured, the coverage the ports README states; they enter no criterion. A hand-written port
(`hand/plmpeg-stream`, the plmpeg port a human wrote) is a row with no C side: only the counts read
off das text apply to it. The `all` column leaves the project and hand rows out as it leaves the
opt-in rows out (`in_all`): a partly converted project's criteria describe only its converted
files and a hand port is no output, so `all` stays the default output of the Lua programs and
suites; the densities' `programs` column (section 6) is where the projects count. A per-function
ratio's median, 90th percentile and worst, and a row's function lengths, are taken over the row's
pooled functions. Each criterion's compliance is computed per row from the row's raw counts; a criterion
whose denominator is zero in a row does not apply there (`n/a`). The `all` column is each
criterion's unweighted mean over the rows where it applies, every row weighing the same: a Lua
layout weighs as much as a whole suite, since each is one way a reader meets the output. A
column's total is the unweighted mean of its applicable criteria: the review argues no weight
between its findings, so none is applied.

## 3. The numeric-constant and function-like macros {#constants}

Clang expands every `#define` before the converter sees the program, so the output spells a
macro's value where the C source spells its name. The program's numeric-constant macros are the
object-like `#define`s its own files make (its `.c` files and the headers they include by a quoted
name, found beside the including file, transitively) whose body, expanded under the macros each
unit's preprocessing reports (`clang -E -C -dD`, the sidecar's `defines` and `-D__NO_CTYPE` as
the dumper passes them), is numbers and character literals under arithmetic, comparison and
logic operators, once each cast (identifiers and `*` in parentheses before an operand that is not
a sign) and each `sizeof(...)` is dropped. A function-like macro is expanded with its arguments; a
macro already being expanded stays a name, which leaves the expression non-constant.

The program's function-like macros are the `#define`s of its own files that take parameters in
some unit, whatever their body: every C use of one (its name before a `(`, outside directives) is
an expansion the output spells in place, since the converter sees clang's expanded program.

A unit is preprocessed with the sidecar's include folders (`-I`) and forced includes (`-include`)
too, and a quoted include not beside the including file is found in the first include folder that
holds it, so a project's own headers are found where its build finds them.

The same preprocessing gives the lines a unit keeps: a conditional branch (`#if`, `#ifdef`,
`#ifndef`, `#elif`, `#else`) none of whose lines the preprocessor emitted is inactive, and every C
count but the `#include` and `#define` lines skips it, as the conversion never sees it. An own
header from which some unit emits a function definition (a single-header library whose
implementation a `.c` file enables, pl_mpeg's or minimp4's) is C source of the program beside its
`.c` files, its lines kept as the units emit them; the line markers name a header as its include
resolved it, so the names compare as full paths.

## 4. The criteria {#criteria}

A C code line is a non-blank line outside comments and directives; a das code line a non-blank
line outside comments. A das function is the span from its `def` line ending in `{` to the next
line that is `}` alone at the margin; a C function the span from its name to the brace closing a
file-level `{` that follows a head ending in `)` with no `=` and no `struct`, `union`, `enum` or
`typedef` before it. A das function is matched to the first unmatched C function of its name, with
a `_c_` prefix dropped and `c_main` read as `main`; the per-function criteria count over matched
functions only, so a converter-made function (a link wrapper, the layout check) is in none of
them. The `<name>_sites` counts behind them, and the densities' own, are taken over every line
of every module, since a density reads the whole text a reader meets. "Clean share" is the share
of the denominator free of the defect.

| Criterion | Counted | Human port | Compliance |
|---|---|---|---|
| `comments` | das comment lines equal to a C comment line, or of two words or more inside one (the banner excepted) | every C comment line carried | carried / C comment lines |
| `constant_names` | per macro, das uses of the name, capped at the C uses | every C use of a numeric-constant macro by name | named / C uses |
| `char_literals` | per spelling, das character literals, capped at the C ones | every C character literal as one | kept / C character literals |
| `macro_blowup` | das code lines per C code line of each matched function; median and worst recorded | within 1.5x | functions within / matched |
| `repeated_blocks` | code lines covered by a window of four consecutive non-trivial lines seen twice | the C source's own repetition | das unique share / C unique share, capped |
| `switch_flags` | `var _flag = false` switches (with `_flag ||=` and `_goto` lines recorded) | a `switch` as `if`/`elif` | clean share of the C `switch` statements |
| `temporaries` | `var`/`let _tN`, `var _first`, `x = x` (discarded `let _tN` recorded) | none | clean share of matched functions |
| `addr_deref` | `addr(x).f`, `addr(deref(`, `deref(addr(`, and with a unary `*` for `deref(` (`addr(*p)`, `*addr(`) | none | clean share of matched functions |
| `reinterpret_casts` | `reinterpret<T>(...)` of anything but a string literal | none | clean share of matched functions |
| `late_binding` | a module named `*_link` or spelling a `*_slot` | none | clean share of modules |
| `qualified_calls` | `__::` and `<module>::` of a program module; `crt::` and other outside modules are not counted, since `crt` is a real outside module holding the C library and a human port qualifies a call to it too | none | clean share of matched functions |
| `require_lines` | das `require` lines | one per C `#include` | C includes / das requires, capped |
| `setjmp` | `try` lines inside a `while (_sj_run)` trampoline | a flat `try`/`recover` | clean share of the `try` lines |
| `layout_checks` | `static_assert(typeinfo ...)` lines of the module and its fragments; a source layout module's layout file (`<module>.layout.das.inc`, `converter/ARCHITECTURE_LAYOUT.md`) is no fragment and is not read | in a test, not the module | clean share of modules |
| `stray_braces` | a line holding `{` alone | none | clean share of matched functions |
| `label_stubs` | `label N:` and `goto label N` lines | none | clean share of matched functions |
| `string_literals` | `reinterpret<T>("...")` and `cstr("...")`, which expands to it | a C string as a string | clean share of the C string literals |
| `lost_parens` | a shift beside `+`, `-`, `&`, `\|` or `^` at one parenthesis level | the author's parentheses | clean share of matched functions |
| `literal_arithmetic` | an arithmetic operator between two number literals (`0 + 7`) | a named value | clean share of matched functions |
| `bool_roundtrip` | `? 1 : 0`, and `int_of(`, the c_runtime macro that expands to it | a plain condition | clean share of matched functions |
| `c_renames` | identifiers starting `_c_` | the C name | clean share of matched functions |
| `long_lines` | lines over 160 bytes | none | clean share of modules |

Where the C source has no counterpart (most noise criteria), the denominator is the unit a reader
judges, the function or the module, since a site count per C line would read near 100 percent
however noisy the worst functions are. `switch_flags` and `string_literals` take the larger of
the C count and the das count as the denominator, so a das count past the C one reads 0. The
per-module criteria (`layout_checks`, `long_lines`, `late_binding`) are binary in a one-module
row: the `single` layout and every suite input hold one module, so a single layout check or long
line takes a Lua `single` row to 0 where the source layout's many modules read a share
(`lua/lua@single` `layout_checks` 0.0 against 72.9 in `lua/lua`).

What the criteria leave out: the unreachable `return` the emitter adds after a function whose end
is formally reachable (no text shape tells it from a reachable one), `[c_function]` (the
annotation is the C context's mechanism, not noise) and `typeinfo sizeof` (daslang's spelling of
`sizeof`). The casts, `addr`, `deref`, expanded macros and `_tN` names the review found the
criteria blind to are densities (section 6).

## 5. The gate

`criteria.das --report --delta-ref <base>` reads the committed capture: missing, not JSON or
failing the shape check, it exits 1 naming why; otherwise it prints the table, the delta against
the capture `git show <base>:metrics/criteria_linux.json` gives (`base_capture_of_text`: a base recorded
before a raw key of `LATER_RAW_KEYS` existed reads it as 0) (a line saying there is none when
the base has no capture) and re-measures the `sample` inputs, printing one `stale:` line per
input whose raw counts differ from the capture's, and exits 0. The full measurement converts
every Lua layout and about 1,500 suite inputs, over half an hour, which is past the fast tier's
budget; the four c-testsuite inputs (a switch with character literals and comments, defines, a
plain switch) convert in seconds and show whether the converter's output moved since the capture
was recorded.

## 6. The densities {#density}

A criterion's clean share reads a function with one `_t` and `luaV_execute` with forty as equally
dirty, and the `all` column weighs a Lua layout as a whole suite, six Lua rows against three. The
densities read the same text the other way: each is a count of sites per thousand das code lines
of the row, so a row's total is the sites a reader meets per thousand lines, and the `programs`
column pools the raw counts of `lua/lua` (the published program in the default layout; `luac`
shares its files, the other layouts and opt-ins its functions) and every compare project, each
row weighing its lines of output. The suites stay rows and out of the column: a csmith program is
nobody's reading, and its 350 thousand lines would weigh eight real programs. The hand-written
port is the base shown beside: the densities a human's das has.

| Density | Sites | Needs C |
|---|---|---|
| `casts` | a numeric type, `intptr`, `uintptr` or `enum_from_int` called on anything but a bare number literal (`int(x)`), not after `.` | |
| `literal_casts` | statements with a cast of a bare number literal (`uint8(7)`, `uint64(0)`), a statement the line layout broke inside its parentheses counted once: a table of a thousand entries is one statement a reader skips, and a suffix is what would replace the cast | |
| `addr`, `deref` | every `addr(` and `deref(`, and every unary `*`: the emitter spells `deref(p)` as `*p`, the same node | |
| `reinterpret` | `reinterpret<T>(...)` of anything but a string literal | |
| `string_casts` | `reinterpret<T>("...")` | |
| `temp_names` | every `_tN` identifier, declared or used | |
| `stray_braces`, `labels`, `qualified_calls`, `c_renames`, `bool_roundtrip`, `lost_parens`, `literal_arithmetic`, `long_lines` | the criterion's sites | |
| `switch_machinery` | `var _flag = false` switches, `_flag ||=` and `_goto` lines | |
| `setjmp_loops` | `while (_sj_run)` trampolines | |
| `layout_checks` | `static_assert(typeinfo ...)` lines | |
| `lost_comments` | C comment lines less the das lines that carried one | yes |
| `unnamed_constants` | C uses of a numeric-constant macro less the das uses of its name | yes |
| `macro_expansions` | C uses of a function-like macro less the das uses of its name | yes |
| `lost_chars` | C character literals less the das ones kept | yes |
| `blowup_lines` | per matched function, its das lines past 1.5 times its C lines | yes |
| `excess_repeats` | the code lines a repeated block covers, beyond the C source's own repeated share of the output's lines (a table repeats in C too) | yes |

A density needing C is `n/a` where a row has no C code lines, the hand port among them, so a
column has two totals: `total`, every applicable density summed, and `das_side`, the ones read off
das text alone, the number the hand port's compares with. The pairs `addr(x).f` and
`addr(deref(...))` stay a criterion only: they are inside `addr` and `deref`. The lengths beside
the densities (the length table) are the das functions' body code lines, the converter's own
`c2das_*` functions left out: how many, the median, the 90th percentile, the longest and the ones
past 100 lines, with the matched functions' das-to-C ratio at the median, the 90th percentile and
the worst, then the `macro_blowup` companions read off the conversion itself (`fold_counts`): the
outermost function-like macro expansions, the ones printed as a call of their `[c_macro] def`, and
on a line of their own the ones left expanded because an argument the body evaluates zero times or
in one branch only may fault (a dereference, an index or a division, ruling 38 addendum 14); a
compare project's are 0, its conversion keeping no verdicts; `programs` has no length column, since a pooled percentile needs the functions, which
the capture does not keep. A delta's base recorded before a density's raw key existed gives no
density delta and says which keys it lacks.
