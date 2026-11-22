# converter Architecture - the link

Companion to `ARCHITECTURE.md` in this folder, its section 6.

## The link {#link}

A program of several C files converts as one program: each file is dumped as its own translation
unit, as one file is, its `<stem>.cir.json` written and round-tripped, and `link_tus` merges the
dumper's trees in their link order into one tree the emitter takes as it takes one unit, in one
module or, in the source layouts, in a module per file (`ARCHITECTURE_LAYOUT.md`); each declaration
keeps the unit it came from (`owners`). The link
consumes the trees in memory and never rereads the C-IR files, whose writer keeps no record
spelling (the `va_list` record's included). `program.cir.json` beside them is the manifest of
`docs/c-ir-spec.md` section 7: `cir`, `target`, `tus` (the units' C-IR files) and `entry`, `main`,
the one entry point the emitter wraps. A manifest the converter takes has the same shape, with
`tus` naming the C files, each relative to the manifest (an absolute path taken as is), since the
link runs on the dumper's trees: a C-IR file there, an entry that is no file name, an empty `tus`,
or a `target` triple other than the conversion's is refused, and so is a file stemmed `program`,
whose C-IR file would be the manifest's. The program's sidecar is the one given, else the
`<stem>.c2das` of the file holding `main` (beside one file only, and that file must be the entry
file: one beside another file, or beside two, is refused), else the `.c2das` of the first file's
folder; its `defines` reach every unit.

- Types: every unit's table merges into one by a structural key, a record and an enum by their
  spelling (location-based for an anonymous one, so a header's record is one record in every unit
  that includes it), every other type by its kind and its merged parts; every type index of every
  declaration, statement and expression is remapped. A record incomplete in one unit takes the
  definition another gives; two definitions of one spelling with different layouts, or one enum
  spelling with different enumerators, are refused naming both locations.
- Externals: each name binds to one declaration, its definition with a body or an initializer,
  else its first tentative definition, else its first declaration (a function defined nowhere
  stays a prototype, the emitter's libc mapping or error); the rest drop, each that drops for a
  definition in another unit a `bound` line. Two definitions of one name, or one name as a
  function in one unit and an object in another, are refused; two definitions at one header
  location (a header function without `static`, C99 `inline` among them) name both units. An
  array declaration of another length than its definition's (`extern int a[3];` against `int
  a[4];`) is refused naming both; one of unknown length takes the definition's. Units of
  two dialects, or of one stem, are refused. Internal linkage belongs to the name: the dumper makes
  a declaration without `static` after a `static` one of its name static too.
- Scopes: once the externals are bound, the caller's block sees the units, the merged types and
  the link's facts (the unit defining each external name, the names each unit references) and gives
  each unit its scope, the output module that holds it; the single layout puts every unit in one.
- Statics: every static keeps its unit and wants its C name (a hoisted local static the dumper's
  `<function>_<name>`, numbered past every file-scope name the unit declares, a libc function's
  included, and every parameter and local of the function; two statics of one unit wanting one
  name are refused). A static is
  renamed `<stem>_<name>` (`docs/lowering-examples.md`, "Functions") when another owner takes its
  name: an external name of the program, a name a converted module can resolve besides the
  program's own (`reserved_das_names` of `emit.das`: the names mapped to libc, crt or c_runtime and
  their unqualified das names such as `c_exit`, every name the emitter spells bare such as
  `end_index` or `c2das_dialect`, every public c_runtime definition and every crt binding; a das builtin a call with no argument reaches, such as `count`, is not among them: the emitter renames the program's function of no parameter, static or not, `converter/ARCHITECTURE_EMITTER.md`)
  (whether or not a unit calls it), or, in a unit of its own scope, a name that unit's code
  references without a static of its own by that name (a libc function it calls) or that unit's
  static: a `def private` of one name in two modules is no collision, one beside a public name of a
  module it requires is (`probes/test_modules.das`). The new
  name passes every file-scope name of the program and every parameter, local and label of the
  units that reach it, numbered past them; a parameter or local of the old name is left alone. A
  static object a header defines stays one copy per unit. A function a header defines is kept once
  where its copies in several units of one scope are byte-identical and every name they reference resolves alike
  in every one of those units: an external in all of them, or a static function in all of them
  that is itself kept once across them (a static object, or a name static in one unit and external
  in another, keeps a copy per unit); the other units' references reach the kept copy, so its
  address is one where C gives each unit its own.
- Type anchors (`record`, `enumdef`, `typedefdecl`) are kept once per merged type. One typedef
  name with two targets in two units stays two transparent typedefs.

The merged declarations follow the units' order; the program's `tu` is the file of the unit
defining `main`, so the module and the wrapper's `argv[0]` carry that unit's stem. A program of one
file does not pass through the link: its statics keep the dumper's `<stem>__<name>`.

### Function-like macros {#link-macros}

The units' `macros` tables (`docs/c-ir-spec.md` section 6.3) merge first, before anything else,
into the program's one table, a `#define` of one name, file, line and text once; every `fn_macro`
takes its index there, and each unit's expansion ids (the `site` of `fn_macro` and of
`macro_args`) move past the ids of the units before it, so an id names one expansion of the
program. A header function's copies compare with each copy's ids numbered by first appearance, so
two units' identical copies stay identical; the kept copy keeps its own ids.
