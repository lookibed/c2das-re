# frontend Architecture - macro expansion

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family
(`ARCHITECTURE_PP.md` holds sections 5 to 13, 53 and 54).

## 29. The expansion over the directive layer {#pp-expansion}

`pp_expand.das` expands the macros of C11 6.10.3 between the directive layer and its caller.
`pp_expand_start` starts a unit as `pp_start` does and sets `pp.expansion` to a `PpExpander`, a
class of `PpExpansion`, the directive layer's interface for it; from then on `pp_next_token`
hands out expanded tokens, and `#include`, `#line`, `#if` and `#elif` lines are expanded before
the directive reads them (section 33). A preprocessor started by `pp_start` alone expands nothing.
The directive layer's raw read is `pp_next_directive_token`; the expander calls it whenever its
own contexts are empty, so a directive between the lines of a call's arguments is done when the
arguments are read, as in clang.

A handed-out token is a `PpOutToken`: the token in its spelling place (a macro body's token in its
`#define`, an argument's token where it was written), its `call`, and where its spelling lies
(`spelled`): its file's buffer, which the unit keeps (`ARCHITECTURE_PP.md` section 5), the macro
body pool, its identifier's symbol, or the expansion's `text` pool for a pasted, stringified or
directive-line token. A source token kept in a context, an argument or a lookahead needs no copy.
`pp_span_of` and `pp_spelling_of` read any of them. A spelling in the `text` pool is valid until
the next `pp_next_token`: that read first leaves the contexts already read to their end, and
clears the pool when no context and no call is open, so back-to-back expansions keep it flat and a
reader that keeps tokens copies those spellings.

## 30. Rescanning: the context model {#pp-context}

The expander keeps a stack of contexts, token lists it reads from before the source: a macro's
replacement, a token read past and given back, an argument being expanded, a directive's line.
A context of a macro's replacement disables that macro while it is on the stack, counted per
definition (`disabled`, by index of `pp.macros`). A name read while its macro is disabled is
painted (`painted`) and never expands again, wherever the token goes - into an argument, a
replacement, the output. This is clang's and gcc's model, not Prosser's per-token hide sets:
a context is left only when a read goes past its end, so a macro stays disabled until its last
token is read and enabled again as soon as the read passes it. So `EXPAND(REPEAT(1))` of the
deferred-recursion idiom gives `1 1 REPEAT_INDIRECT ()(1)` as clang and gcc give it, and
map-macro, Cloak, metalang99 and Boost.PP expand as there; a per-token hide set gives `1
REPEAT(1)` and grows without bound on Boost.PP.

`read_raw` reads the next token unexpanded: from the top context, popping each exhausted one, or
from the source. A barrier context (an argument, a line) ends the input when read past instead of
reading below it. `next_expanded` reads with expansion: a painted name or a non-name is handed
out; a name of a disabled macro is painted and handed out; a function-like macro's name expands
only when `(` comes next (`next_is_lparen` reads past exhausted contexts and gives back any other
token, and a `(` of the source read past a directive line, counted by `pp.directives_read`: clang's
`-E` gives `g` then `(2)` for a directive between them); an object-like macro always does. The memory the expander holds is the open contexts and
calls, each a token list from a pool of reused buffers, so a deep expansion keeps it flat; the
call record (section 34) grows with the calls.

The expander recurses once per argument expanded inside another (section 32), so a program that
runs it on deep macro libraries declares `options stack` of 1 MB in its main module, as the tests
and the oracle do; daslang's default stack of 16 KB holds a few dozen nested arguments.

## 31. Calls and their arguments {#pp-calls}

The arguments of a call are read unexpanded up to the `)` that closes its `(`, split at commas
outside parentheses, every comma after the named parameters belonging to the variadic one; a
token of the source keeps its place, and a newline in the call is a space (`at_bol` becomes
`has_space`), as clang prints it. A name read there whose macro is disabled at that moment is
painted (6.10.3.4p2, clang's `ReadMacroCallArgumentList`): reading on can leave the macro's
context, so `#define kk k(kk` gives `kk 1` for `kk 1)`, not a new expansion of `kk`. A call reads
at most to the end of its input: the end of the unit, or of the directive line it is in, is the
error "unterminated function-like macro invocation", and the name and the call's tokens are
dropped, as clang's `-E` prints it. The count follows clang under gnu17: `f()` of a macro with no
parameter is a call with none, of a macro with one an empty argument; a missing variadic argument
is an empty one, marked elided; fewer arguments than named parameters, or more than the
parameters, is clang's error, and the name is handed out as itself and the call's tokens are
dropped. A call's arguments live in an invocation slot (`PpInvocation`), one per
nesting depth, reused.

## 32. Substitution {#pp-substitute}

The replacement is built from the body in one pass (C11 6.10.3.1): a parameter that is an
operand of neither `#` nor `##` is replaced by its argument fully expanded, alone, as a barrier
context, with the called macro still enabled (it is disabled only when its replacement is
pushed); an argument is expanded once, when first needed. An operand of `##` is the argument as
written, and `#` stringifies it as written (section 35). `__VA_OPT__ ( ... )` in a variadic
macro is its content, replaced the same way, when the variadic argument expands to at least one
token, as clang 22 decides under gnu17 (`F(EMPTY)` gives none), and it can be an operand of `#`
and `##`. In a function-like macro that is not variadic (clang's warning at the `#define`)
`__VA_OPT__ ( ... )` is empty and `# __VA_OPT__ ( ... )` is `""`; in an object-like macro it is
no operator and stays as written. The GNU `, ## __VA_ARGS__` removes the comma when the call wrote no variadic argument
(`G(1)`, and `F()` of a macro whose only parameter is variadic); a written one, empty or not,
keeps the comma and is not pasted onto it - clang's reading under gnu17.

A token's space follows clang: a body token keeps its own, an argument's first token takes the
parameter's, an empty argument passes its space to the next token, and the replacement's first
token takes the macro name's `at_bol` and `has_space`. An empty replacement gives both to the
next token read (`carry_bol`, `carry_space`), so `EMPTY x` at a line start leaves `x` starting
it. Every token of the replacement gets the call's index and the presumed place of the outermost
name (`pline`, `pname`), where clang's `-E` prints it.

## 33. Directive lines {#pp-expand-line}

`expand_line` expands the tokens of `pp.line` in place, as a barrier context, so a call in the
line cannot read past its end. `#include` then takes one `"..."` string literal, or the spellings
from `<` to `>` joined with a blank where a token has space (6.10.2p4, clang's choice: `LT a.h >`
names ` a.h `), a `<` with no `>` being clang's "expected '>'"; `#line` takes a number and an
optional name, anything but a number asking for "a positive integer argument" as clang does. In
an `#if` or `#elif` line the operand of `defined` - `defined X` and `defined ( X )`, written or
produced by a macro - is left as written, and so is the `< ... >` of `__has_include ( < ... > )`
and `__has_include_next`, which clang lexes as a header name (`#define linux 1` leaves
`<linux/version.h>`), and `__has_embed`'s. The parenthesized operand of the queries clang reads
unexpanded - `__has_feature`, `__has_extension`, `__has_builtin`, `__has_constexpr_builtin`,
`__has_warning`, `__is_identifier`, `__is_target_*`, `__building_module` - is left as written too
(`PP_UNEXPANDED_QUERIES`); any other operand, `__has_include`'s macro name and the attribute queries'
among them, is expanded, as clang expands it. An argument of a call in the line is pre-expanded
as anywhere else, with no operand left: `F(defined X)` of a defined `X` gives clang's `defined 1`.
The expanded line goes to the evaluator hook (`ARCHITECTURE_PP.md` section 11). A `_Pragma` in
the line is done there, as clang does it, and the rest of the line read on: `#if _Pragma("x") 1`
takes its group; in an `#include` line it is done too and leaves nothing behind, which no header
name can hold.

## 34. The call record {#pp-record}

Every expansion is a `PpCall` in `pp.expansion.calls`, in the order the calls are read: the
macro, the name token's place, the call the name came from (`parent`, -1 for the source), the
presumed place of the outermost name, its end - the presumed line, and the physical line and
column, of the `)` that closes it, or of an object-like macro's name; of the call it came from
when that token came from a replacement, as a `)` a macro hands out ends the outer call there -
and its arguments as
`PpCallArg` spans of `call_args` - the file and byte range from an argument's first token to the
end of its last, -1 when it is empty or not one stretch of a file. Both arrays grow geometrically,
so a unit of a million calls makes a few dozen heap blocks for its record. A token carries the index of
the call whose replacement it is in; with its spelling place this tells a body token from an
argument's (its place lies in the call's argument spans). This is what PP.5's expansion record
builds on: it adds the expansion location of each token and the argument text.

## 35. `#` and `##` {#pp-stringify}

`#` makes a string literal of its argument as written (6.10.3.2): the tokens' spellings with one
blank where a token has space (a newline in a call is one, section 31), none at either end, and
`\` and `"` escaped inside string and character literals; a final `\` left unescaped is dropped
with clang's warning "invalid string literal, ignoring final '\'" (`q(\)` is `""`). The result is
spelled in the `text` pool at the place of the `#`.

### Pasting {#pp-paste}

`##` joins the spelling of the token before it and of the first token of its operand (6.10.3.3);
the result is one token, kept in the place of the left one with its space. A run of letters,
digits and `_` is a name, or a pp-number when it starts with a digit, and needs no lexer; any
other text is lexed by the pp lexer from its own reused buffer, and must be exactly one token that
is not OTHER. Otherwise
the paste is clang's error "pasting formed 'X', an invalid preprocessing token", and both tokens
stay. An empty operand is a placemarker: pasted with a token it is that token, two make one, and
the placemarkers left are dropped when the replacement is done. A pasted name is a new name: it
expands on rescan unless its macro is disabled then, and a poisoned one is clang's error
(`ARCHITECTURE_PP.md` section 54). A name pasted for the first time is interned
from the pool's bytes, read in place; a paste allocates no string.

## 36. The builtin names {#pp-builtins}

A name with no macro definition that the preprocessor answers itself becomes one token, not
rescanned: `__LINE__` the presumed line of the end of its outermost call (the `)`, clang's rule
for a call over several lines) or, read from the source, its own; `__FILE__` the presumed file
name of the outermost call's name, `\` and `"` escaped; `__FILE_NAME__` its last component;
`__BASE_FILE__` the main file; `__INCLUDE_LEVEL__` the files open below the current one;
`__COUNTER__` 0, 1, ... in the order read. Each value is spelled into the `text` pool directly, no
string made. `__DATE__`, `__TIME__` and `__TIMESTAMP__` show the
time `pp_expand_start` is given, in UTC (`"Sep  9 2001"`, `"01:46:40"`, `"Sun Sep  9 01:46:40
2001"`), the current time by default: clang shows `SOURCE_DATE_EPOCH` the same way, which makes a
unit's output reproducible and the oracle's comparison exact; `__TIMESTAMP__` shows that time,
not the file's, since the file provider has no file times. clang's other builtin names, the
`__has_*` family but `__has_cpp_attribute`, which clang under C does not have, `__is_identifier`,
`__is_target_*` and `__building_module`, are the `#if` evaluator's (`ARCHITECTURE_EVAL.md` section
50): PP.3 hands them out as names, and `PpExpansion.is_builtin` tells `defined` they are there. A `#define` of a builtin name no macro defines is
clang's warning "redefining builtin macro" and the definition takes over; an `#undef` of one is
"undefining builtin macro" and removes the builtin for the rest of the unit, so `__LINE__` after
`#undef __LINE__` is a name, as it is after a `#define` and `#undef` of it (the directive layer
calls `PpExpansion.macro_changed`).

`_Pragma ( string-literal )` reads its `(`, its operand and its `)` with expansion, as clang's
`Handle_Pragma` lexes them (6.10.9): `_Pragma(S)` of `#define S "pack(1)"` and
`_Pragma(STRINGIFY(...))` are pragmas. The literal's prefix and quotes are taken off, `\"` and
`\\` read as one character each, into the scratch lexer's buffer, and the text is lexed and done
as a `#pragma` line (`pp_pragma_line`) - into the pragma or pack ledger at the tokens handed out
before it, or `once`, `push_macro`, `pop_macro`. The token after it starts a line, as after the
directive. While an argument is pre-expanded (section 32) a `_Pragma` is not done: its operand is
checked, given back unexpanded and handed out after the name, so the pragma is done at the
rescan, once for each use of the argument and at its place among the tokens, as clang delays it
(6.10.3.4p3): `TWICE(_Pragma("pack(8)"))` is two pragmas, and the pack of
`WRAP(struct A ...; _Pragma("pack(1)") struct B ...;)` stands after `A`. An argument `#` or `##`
takes as written does no pragma. Malformed, it is clang's error "_Pragma takes a parenthesized
string literal", and the token read where the `(`, the string or the `)` was expected is handed out
in its place - for a missing string after the tokens up to the `)` or a line start, the token
after them - as clang recovers: `_Pragma("x" y) z` leaves `y ) z`.

## 37. Known differences from clang

The expander recurses once per argument expanded inside another, which the 1 MB stack of section
30 holds for the macro libraries the tests and the research corpus run; a deeper nesting
overflows it where clang's own stack still holds. A directive met while looking for a call's `(`
is done before the name is handed out, so a `#pragma` there is placed one token earlier than
clang's `-E` prints it. `defined` produced by a macro in an `#if` line is taken without clang's
warning "macro expansion producing 'defined' has undefined behavior". A poisoned name formed by `##` is
reported at the left operand, where clang reports it at the macro call.
