# frontend Architecture - names and places

Companion to `ARCHITECTURE.md` in this folder; section numbers are unique across the family. It
describes the names `c_ir.das` gives declarations and references and the places it gives
declarations and statements, which are Dumper A's
(`converter/dumper_a.das`: `dump_decl`, `local_name`, `free_fn_name`, `hoist_static`,
`dump_block_extern`), so the C-IR's names match its byte for byte.

## 46. File statics and linkage {#c-names-statics}

A declaration at file scope is named by its C name, except one with internal linkage: a `static`
declaration takes `<stem>__<name>` (`linkage_name`), the stem the unit's file name before its first
`.` as an identifier (`ident_of` of `converter/cir.das`: every other character `_`, a leading `_`
before a digit), and every later declaration of the name keeps it, `static` or not (C11 6.2.2p4).
The declaration's `static` is set for such a name. A block-scope `extern` declaration or prototype
spells the name of the file-scope entity (`<stem>__<name>` for a static one, else the C name). An
own header's declaration keeps its C name.

## 47. Locals, parameters and hoisted statics {#c-names-locals}

Before a definition's body the walk collects the names its parameters and the variables under it
declare (a block prototype's parameters among them, `fn_all_locals`) and the names its block-scope
`extern` declarations and prototypes declare (`fn_extern_names`); before the unit, every name the
unit declares at file scope, the own headers' included, and every name a block-scope `extern` or
prototype declares anywhere (`file_scope_names`). A parameter or local keeps its C name unless a
block-scope `extern` or prototype of the function declares that name, whose references must spell
the program-wide name: it then takes the first free name of `<name>`, `<name>1`, `<name>2`, ... not
taken by a hoisted static, a file-scope name or a name of the function, and that name joins the
function's (`local_name`, `free_fn_name`). A `static` local is hoisted to a global of the first free
name of `<function>_<name>` by the same rule, and joins the hoisted names. Each reference spells the
name its declaration took (`CId.name`), bound through the identifier scopes, so a local hiding a
global, a block `extern` hiding a local and a block prototype hiding a local each reach their own
declaration's name, never one found by spelling.

## 48. Places {#c-ir-places}

A declaration's place (`loc`) is its name's token, a typedef's, a variable's and a function's
alike; a statement's is its first token's (a declaration statement's its variable's name, a `case`,
`default` or label marker its keyword's or name's, a block `{`, a GNU statement block used as a
statement the expression statement's). The builder places a token where its own token stream puts
it (`loc_of`): over C source the preprocessor reads, its expansion location in the file as read -
a source token's own place, a token an expansion made the outermost macro name's line and column -
with `#line` aside, as Dumper A places it (`frontend/ARCHITECTURE_PARSER.md` section 14). A
preprocessed unit's tokens have only the place its line markers present. A macro expansion's
parentheses are marked only around a shift or a bitwise operator, which Dumper A keeps there; the
source's own are all marked.
