# research/c1_parser architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. This folder
is the C.1 parser probe of Part 2: two candidate C parsers in daslang, recursive descent (RD)
and a dasBison grammar (LR), built over one token source into one AST, with the oracles that
compare them with each other and with clang. It is a probe, not the frontend: it lives outside
`frontend/` because its oracles run clang, and outside the preflight's gated folders because
its LR candidate loads dasBison and dasFlex from the gitignored `fetch/` that
`scripts/fetch_dasbison.sh` fills.

## 1. File charters

- `c1_ast.das` - the shared data: token kinds (`TK`), the keyword table with its GNU
  alternates, `Tok` and `Source` (the token array of one unit), the byte interner, the AST
  (`Node` in one array, children and list links by index, `ROLES` per kind), the typedef
  scope table both parsers consult, and the dump two trees are compared through. No parsing.
- `c1_lexer.das` - preprocessed C text into `Source.toks`: line markers set file and line,
  words are interned and keywords classified, nothing allocated per token. No typedef decision.
- `c1_rd.das` - candidate RD: recursive descent, precedence climbing for binary operators,
  exact scopes. Refuses `_Generic`, `__label__`, `__int128`, `__auto_type`, `_Atomic(type)`,
  `asm goto`, a file-scope asm and the old `field:` designator by name and location.
- `c1_lr.das` - candidate LR: the `[bison]` grammar and its actions building the same AST, and
  `lr_scan`, the parser's lexer over the token array, which classifies typedef names from the
  scope table and the specifier state it tracks.
- `c1_clang.das` - the clang oracle: clang's JSON dump and a tree reduced to one line form
  (section 2), and the wildcard match of the two.
- `c1_compare.das`, `c1_errors.das`, `c1_speed.das`, `c1_memory.das`, `c1_tables.das` - the
  runs: correctness (RD against LR against clang), the broken inputs, tokens per millisecond,
  heap use, and the LR tables' size and build time.
- `prep.das` - the inputs: each unit preprocessed by clang under Dumper A's frontend flags and
  the program's sidecar defines.
- `cases/` - C inputs of the probe: the typedef scope cases, the attribute-in-parentheses
  cases, the broken inputs (`cases/errors/`).

## 2. The clang line form {#clang-lines}

A declaration of the main file is one line: its kind (`func`, `var`, `typedef`, `param`,
`field`, `enumerator`), its name, its type as clang spells it, and its name's line and column.
A statement or expression is one line per node, indented by depth: its kind, its operator or
member or referenced name, the line and column of its first token. Clang's implicit casts and
`ConstantExpr` are transparent, as is the access of an anonymous member clang inserts. The
inside of an initializer list, asm operands, `__builtin_offsetof` paths and goto targets are one
opaque line. A type the tree alone cannot spell as clang does (an array sized by an expression
or by its initializer, an anonymous record, `typeof`, an old-style parameter) is `?` and matches
any type; a location the tree does not have (an unnamed parameter's) is `@?`. On preprocessed
input clang's JSON names the line marker's file and line as `presumedFile` and `presumedLine`,
each written only where it differs from the last one written, whatever the location's file.
