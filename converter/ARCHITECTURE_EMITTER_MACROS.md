# converter Architecture - function-like macros folded into defs

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`.

### Which expansions fold {#fold-verdict}

A node Dumper A marks as a whole expansion of a function-like macro (`ARCHITECTURE_DUMPER_MACROS.md`,
`docs/c-ir-spec.md` section 6.3) may print as a call of a `[c_macro] def` of the macro when
`macro_fold.das` finds, from the node alone, that the call means what the expansion means
(`fold_expr_site`, `fold_stmt_site`); every other expansion prints expanded. The walk takes the
copies of each argument in evaluation order, the copies below a `?:` arm or the right side of
`&&`/`||`, or in a statement body below an `if`, a loop or a `switch`, as read on some paths only. The verdict, in this order:

- `never`: the sidecar's `no_fold` names the macro, or folding reads worse: a body that is
  `((void)0)`, an argument under casts alone (an identity, a single cast), one operator over its
  arguments when one argument is never read (`luai_numadd(L, a, b)`); a statement macro that is
  neither a block nor a `do { ... } while (0)`, or an empty one.
- `shape`: a compound literal, an initializer list, `va_arg`, `offsetof`, or a call of `alloca`,
  `setjmp`, `longjmp` or a `va_*` builtin in the body.
- `flow`: a `return`, `goto`, label, or a `case`, `default`, `break` or `continue` that leaves the
  body (one inside a loop or switch of the body stays inside).
- `incomplete`: some argument has fewer or more copies than the macro's `uses`, or `uses` is
  unknown (-1): a type argument, `sizeof`, a split argument, a called parameter.
- `capture`: the body outside the copies names a parameter or local of the caller that the body
  does not declare in a block still open there, or names something a parameter of the macro is
  named (a global reached through an object-like macro, `#define OFF off` in `ADDOFF(off)`), which
  the def's parameter would hide.
- `lvalue`: a copy is addressed, or stored into, stepped or reached as an object rather than
  loaded (a field of a record argument, an array argument) when it is not a caller's local, which
  the def would do to its parameter; a caller's local the body writes is a reference parameter
  instead (`refs`, the def's `var x : auto&`).
- class B (a parameter read twice, never, or on some paths only): `effects` when any argument has
  a call, a store, a step or a volatile read; `faulting` when such an argument is not a constant, a
  local or parameter, a field of one through `.`, the address of either, or arithmetic over those
  without `/` or `%` (an argument the body never reads is only its text: a decimal literal or a
  local's name). A copy of a volatile local counts as effectful: its load is an access. `faulting`
  also when a copy C reads after a call of the body (which may exit) is not such a value: das
  evaluates the argument before the call. The report counts the faulting sites apart
  (`fold_counts`).
- `order`: a copy whose value a store of the body could change by the time C reads it (after a
  store, a call or on a loop's next turn), unless it is a constant or a local whose address is
  never taken; an argument reading the local another argument passes by reference or an effectful
  argument stores into; an effectful argument C evaluates after the body read or wrote state
  outside its locals or called (a declaration's initializer included); two arguments with effects,
  or one beside an argument that is not such a value, since das fixes no order among a call's
  arguments.

### The defs and the calls {#fold-emission}

`fold_macro` tries a node's chain outermost first (`#define GETA(i) GETBITS(i, 3, 4)` marks one node
with both) and folds at the first level that passes: an expression read for its value
(`emit_expr`; an lvalue expansion only through its load, so a store into `FLD(p)` stays expanded),
an expression statement (`emit_effect`), or a statement macro (`emit_stmt_kind`). The arguments
are spelled in the caller first, each from its first copy (an argument with no copy is its text);
then the body is spelled as the expanded C reads it, in a fresh statement state (temporaries from
`_t0`, no C comments, no caller's pending statements), with every copy read as its parameter
through `hoisted` and every node inside a copy read as a marker that refuses the def; the chain's
next level may fold inside the body, and so may any other expansion the body holds. A def's text
is refused (the site stays expanded, counted `spelling`) when it holds that marker, names a
caller's local an argument held (unless the parameter of that name takes exactly that local),
leaves a parameter with copies unnamed (a literal shift count spelled into the body), needs a
compound literal's declaration ahead of the statement, or fails. An arm of a pointer `?:` whose
other arm is `null` keeps every expansion inside it expanded (`ternary`), a guard the `[inline]`
carrier the defs had before needed (das inlines no `[inline]` call there). A def whose text returns
a value after statements (Lua's `tonumberns`, a `?:` whose arms assign) has no `[c_macro]` shape: its
sites stay expanded (`statements`).

A macro a header `#define`s has one public def in that header's module (`plan_shared_macros`)
when the header is a node of the layout (it owns a record or an enum), no expansion of the macro
names a function, a global or a string literal outside its arguments (a unit owns those), the
module sees every record and enum the expansions spell (its own or one it requires), and every
module spelling a site sees the module (it or one it requires), one of them another module (a
macro only its header's own module uses, a cluster or the single layout's one module, keeps the
private def): the module is assembled after every
other one has spelled its sites, its defs after its own, the `#define` constants they name as its
own private `let`s and the `c_runtime` modules they need required there. `[c_macro]` substitutes
the body at the call, where its names resolve in the calling module, so each module spelling a
site keeps those constants and requires as well, as a private def's module does. A def that
module holds folds only the macros whose def it sees itself and leaves every other expansion
expanded, and its `var` parameters are decided for the whole program before any module is spelled
(`hosted_var_parameters`: every expansion's need, a nested header def's `var` parameters closed
over), so a def in any module passing its parameter on sees the final def. Every other
macro's defs are private to the module that spells its sites, in first-use order after the
module's `#define` constants. Each def stands under a comment naming the `#define`'s file, line and text: one
def with untyped parameters when every site spells one text, else one typed overload per signature
of each text (a parameter's type is its argument's das type, `bool` for a truth value), a site
whose text differs from the overload of its signature staying expanded (`overload`). A parameter
the body writes a caller's local through is `var x : auto&`. A parameter whose argument is a data
pointer, or a record holding one, is `var` only when some fold's body needs it writable
(`var_parameters`, classification row 9): a value of it - the parameter, a cast or an offset of it,
an address into what it points at, a pointer loaded through it - is written through, passed to a
call (every C function's pointer parameter is `var`, F3) or to a `var` parameter of a nested folded
def (the inner def is decided first, its fold spelled inside the outer body), stored into a
variable, a field or an initializer, or is the def's result; one only read through, compared or
tested is not, so a read-only reinterpret prints no const strip. A later fold needing it makes it
`var` for every site. A pointer result names its type (das types a bare `null` as `void?`). A
body that needs `unsafe` takes `[c_function]`. Every def is `[c_macro]`
(`c_runtime/ARCHITECTURE_MACROS.md`): a call is replaced by the body with the arguments
substituted as written, C's own expansion, so the interpreter runs the expanded text, where an
`[inline]` splice bound a copy per `var` parameter per level, a result local per `unsafe` body
and a flag per `&&` operand (`docs/probe-findings.md` F107).
The name is the macro's, `<name>_m` where a function, global or type of the program, das or the
runtime has it, `<name>_2` for a second macro of one name (an `#undef` and a new `#define`); a
private def takes no name a header's public def has.
Every outermost site counts once per module (`fold_counts`): `folded` or its reason.

The `fn_macros` option `expand` (`--fn-macros expand` or the sidecar's `"fn_macros": "expand"`)
folds no site: every expansion prints expanded and the module holds no def, the text the readable
`fold` default replaces, kept for its own perf lane and readability keys; the sidecar's `no_fold`
names are still checked against the program's macros. Its sites count under the reason `expand`,
so the fold counts of either value total the program's sites.
