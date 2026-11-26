# metrics Architecture - the conversions census

Companion to `ARCHITECTURE.md` in this folder. The census counts the cast nodes of the C-IR
(`docs/c-ir-spec.md` section 6, the `cast` node with its `kind` and `explicit`) of the programs the
project converts and of the suites' passing tests, the conversions a frontend that writes the C-IR
itself must insert where clang inserts them. It reads the C-IR, never clang's AST and never the
emitted das. It records no capture and has no ratchet: a run prints its tables, and `--json`
writes the raw counts.

## 1. File charters

- `conversion_census.das` - the driver: `das metrics/conversion_census.das -- [--filter <row>]
  [--jobs N] [--limit N] [--json <file>]` from the repository root. The rows are the c-testsuite,
  gcc-torture and csmith suites, Lua (its two programs pooled), PureDOOM and each compare project,
  then the total and, past one row, the total without csmith, whose generated programs hold most
  of the casts. A program row converts through `convert_input` of `readability_inputs.das` in a
  worker of its own, one at a time, and the worker counts every unit's `.cir.json` the conversion
  wrote, so a program whose emission fails is still counted from its dump; each file is removed once
  read. A suite row dumps every id its `expected_pass.txt` lists alone, with the sidecar the
  converter finds beside the file (a csmith seed generated first, as the csmith driver generates
  it), in eight workers that each take every eighth id (csmith in 48, since a seed's dump is a
  hundred times a test's and a worker's heap grows with each dump). A worker leaves only `counts.tsv` (a `unit`
  line per unit, then its counts) and `failures.tsv` under `work/conversion_census/<key>/`; the
  driver adds a row's units through `add_counts_file`, a unit two inputs share counted once. `--reuse` prints the tables from
  the files already written; `--c <file>` prints the tables of one C file.
- `conversion_census_count.das` - the counting (section 2) and the tables: `census_tu` counts one
  unit, `census_c_file` dumps a C file under the `linux` dialect and counts it, `census_cir_file`
  counts a C-IR file; `census_lines` and `read_census_line` are a counts file's lines,
  `unit_lines` a unit's block of them and `add_counts_file` the sum of a file's units, each unit
  once; `render_set` is a row's report and `render_json` the raw counts.
- `tests/test_conversion_census.das` over `tests/fixtures/conversion_census.c`, a C file with one
  function per counted context; its counts are clang's own casts of the file (`-Xclang -ast-dump`)
  less the case label's, which the C-IR folds.

## 2. What a cast is counted under

Every cast node of a global's initializer and of a function body is counted once under each
dimension. A unit counts in every program that links it, so a header's function counts per unit
that holds it.

- `kind` - the castKind and `implicit` or `explicit` (a C cast is `explicit`).
- `pair` - the castKind, the form, the operand's class and the result's: `bool`, the integer
  classes `char` (plain), `schar`, `uchar`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`,
  `llong`, `ullong`, `float`, `double`, `ldouble`, `enum`, `objptr`, `fnptr`, `void*`, `array`,
  `function`, `record`, `void`, read through typedefs. The C-IR keeps no qualifier, so a cast that
  only adds `const` has one class on both sides.
- `context` - the castKind, the form and the slot the chain's top cast fills: an operator's operand
  by operator group (`binary arithmetic`, `comparison`, `bitwise`, `shift`, `logical`, the unary
  groups, `unary not` apart), `assign rhs`, `compound rhs`, a call's argument (`prototyped` within
  the callee type's parameters, `variadic` past a variadic one's, `K&R definition` past the
  parameters of a type with none when the unit defines the function with that many parameters,
  which clang converts to the parameter type, `unprototyped` past any other's, since the C-IR spells
  `T ()` as `T (void)`), `callee`, `return`, `init scalar`, `init element`, the conditions
  of `if`, `while`, `do`, `for` and `?:`, a `?:` arm, `switch`, a subscript's base and index, a
  member's base, `comma lhs` and `rhs`, `expr stmt`, `for inc`, `va_arg list`. An implicit cast
  takes the context of the cast over it; the operand of an explicit cast is `cast operand`.
- `rule` - an explicit cast is `6.5.4 cast operator: <kind>`; an lvalue conversion (a record's
  apart), an array decay (a string literal's apart), a function decay (a callee's apart) and a null
  pointer constant are their C11 6.3.2 rule in any context; any other implicit cast is its
  context's rule (6.3.1.1p2 for a binary operand whose cast is a promotion, 6.3.1.8 for any other
  conversion to the common type, 6.5.7p3, 6.5.3.3, 6.5.3.3p5, 6.5.13-6.5.14, 6.5.16.1, 6.5.16.2,
  6.5.2.2p6-7, clang's K&R definition argument, 6.8.6.4p3, 6.7.9, 6.5.15, 6.8.4-6.8.5, 6.8.4.2p5,
  6.5.2.1) and its castKind. clang writes one cast for a promotion and the conversion to the common
  type after it, so an operand cast is labelled by its result: a promotion when it reaches `int`
  (or an unsigned enum's `unsigned int`), the usual arithmetic conversions otherwise.
- `crule` - the C rule alone: the rule's name before its castKind, so the context and kind keys of
  one rule (`6.5.4 cast operator` over ten castKinds) count as one.
- `clause` - the C11 6.3 paragraph the conversion applies, by castKind and classes: an integer
  conversion is a promotion (6.3.1.1p2) in a promoting context (an operator's operand, `&&` and
  `||` included, a `?:` condition or arm, a switch condition, a variadic or unprototyped argument)
  from below `int`'s rank, an enum, or a bit-field narrower than `int` (read from the record's
  field, since the C-IR types a bit-field as its declared type) to `int`, or from an enum to
  `unsigned int`; else 6.3.1.3 p1, p2 or p3 by width and signedness, by the classes and not the
  value; a pointer bit cast
  is 6.3.2.3 p1, p4, p7 or p8 by its classes; a `NoOp` between pointers is 6.3.2.3p2, an explicit
  one to the same class 6.5.4. A conversion no paragraph names is `no clause: <kind> <from> -> <to>`.
- `chain` - per top cast, the castKinds down its chain of casts, outermost first, an explicit one
  marked `!`.
- `anomaly` - the shapes worth knowing beside the rules: a `NoOp` whose operand and result are one
  C-IR type, a `NoOp` over a decayed string literal, an implicit `BitCast` to or from `void*`, a
  function decay of a callee, a `__builtin_` callee or a value, a string literal's decay, `ToVoid`,
  the conversions to `_Bool` by context, a cast inside a `__builtin_` call's arguments, a cast of a
  literal or enumerator, an implicit `IntegralCast` directly over a call (the shape of the dumper's
  own cast of a redeclared library function's result), an implicit cast under an explicit one, a
  chain of three or more casts, an argument past a non-variadic callee's parameters, and a compound
  assignment whose operands' classes differ, whose computation type the C-IR does not hold.
- `total` - the units, the expression nodes and the casts.

## 3. What the census cannot see

The C-IR holds the result of conversions clang made in places that are no expression of it, so
these conversions exist in clang's dump and are not counted:

- a `sizeof` or `_Alignof` operand, a `typeof` operand: the C-IR keeps the value and the type only;
- a case label: the C-IR keeps the folded value, and the `IntegralCast` clang gives the label's
  constant to the promoted controlling type (6.8.4.2p5) is lost;
- an enumerator's initializer, an array bound, a bit-field width, a `_Static_assert`: folded to
  their values;
- the `ToVoid` of an expression statement `(void)({ ... })`, which the dumper unwraps to the block;
- a compound assignment's left operand converted to the computation type and the result converted
  back, which clang writes as attributes of the operator, not as cast nodes;
- qualifiers: a qualifying `NoOp` is counted, but its operand and result have one class.
