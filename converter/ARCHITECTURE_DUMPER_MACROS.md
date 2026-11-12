# converter Architecture - Dumper A's function-like macros

Companion to `ARCHITECTURE.md` in this folder, continuing section 3 of `ARCHITECTURE_DUMPER.md`.

### Function-like macro expansions {#fn-macros}

The dumper marks every expansion of a function-like macro of the program whose node it can name, in
the C-IR fields of `docs/c-ir-spec.md` section 6.3, and decides nothing about folding: the emitter
derives a macro's class from the marks (`macro_sites.das`). Two sources feed it, both from passes
the dump already makes:

- libclang's preprocessing record (`CXTranslationUnit_DetailedPreprocessingRecord` on the layout
  pass): every `#define` of a program file (`register_macro_definition`) and every expansion a
  program file spells, keyed by the canonical file and offset of its name to the definition it
  used (`register_macro_expansion`), the macros an argument of another call spells included. The
  definition is exact under `#if` variants; a name a body calls resolves to the one definition of
  that name the unit processed, and to none when there are two. A system header's function-like
  macro (`offsetof`, `va_start`, `MAX`) is none of the program's: it is never marked, only its name
  is kept, and a call of it in a body is followed no further (the macro's `uses` are -1, an end
  spelled through it unknown). A system header's object-like macro an expansion spells (`NULL`) is
  kept only to find where its tokens are spelled.
- the JSON dump's spellings. Every token of an expansion is spelled either in a `#define` body or
  in the call's text, and a node's range names the spelling of its first and last token. A
  macro's body, its arguments' text and the bodies of the macros it calls give where an
  expansion's first and last token must be spelled (`spelled_end`, through parameters, object-like
  and function-like macros at either end); the node spelled exactly there is the whole expansion,
  and each topmost expression below it spelled exactly as an argument is that argument's copy.

The walk (`find_macro_sites`) takes, for each outermost expansion (a node whose range begins and
ends at one expansion offset libclang recorded), the call's text at that offset, the first node
below it spelled over the body, then the copies and every call the body writes, each a nested
expansion found the same way below its parent's node; the calls the outermost call's arguments write
are nested expansions too. One node is the whole expansion of each macro of a body that is one call
(`#define GET(i) CAST(int, i)`), outermost first. Two expansions side by side can spell one body's
first and last token (`ADD1(x) + ADD1(0)` spells `ADD1`'s `(` to `)`), one body can call a macro
twice (`tonumberns(v1, n1) && tonumberns(v2, n2)`), and two bodies can differ only in a constant
(`checktag((o), LUA_VNUMINT)` and `checktag((o), LUA_VNUMFLT)`), so a candidate, the outermost one
included, is taken only when it holds the expansion's tokens (`fits_call`): its leaves (names and
literals) are the leaves of the full expansion, each spelled where the expansion's token is and as
often (`expansion_leaves`, through parameters, object-like and function-like macros; unknown where
a parameter or a system header's macro is called), and every number of the expansion is among
them; and its topmost argument copies in preorder follow the order the expansion holds the
parameters (`param_seq`), or, where that order is unknown, each copied argument as often as the
macro uses it. An argument with no copy at all (a type, an operator, one the body's precedence
splits) is left out of that comparison, and the backend counts the copies against `uses`. The
outermost expansion is the topmost such node; a nested one claims every such node no expansion of
its macro took, unless every argument its expansion holds has no known spelling (`APPLY3(f, x)` of
`ADD1(f(x)) + ADD1(f(0))`), which tells no candidate apart. A call written once in an argument the
body uses twice (`SQ(SQ(x))`) marks each node it expanded to, and an expansion whose argument is
another expansion of the same body is never its own copy. A macro the walk does not
follow is left unmarked: variadic, `#` or `##` in its body, a site where two arguments are spelled
alike (no copy then tells them apart), and an expansion no node spells whole (`MUL2(i + 1)` of `x * 2`). A parameter the body calls (`op_arith_aux`'s `fop(L, n1, n2)`) expands to what
its argument names: the pass resolves no end through it and counts its own uses and those of an
argument passed to it as unknown, and follows the rest of the body. Each site records the text of
its arguments as the call writes them, since an argument the expansion never uses has no node.

A node the dump collapses through its parentheses carries its own marks before its inner node's,
so `fn_macro` stays outermost first (`#define OUTP(x) (ADD1(x))`).

The writer puts `macros` after `types`, `fn_macro` after `macro` on an expression and before `loc`
on a statement, `macro_args` after `fn_macro`, each absent when empty; the reader takes them back,
and `"cir": "0.2"` names the version that has them.
