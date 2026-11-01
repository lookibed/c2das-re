# converter Architecture - the source layout

Companion to `ARCHITECTURE.md` in this folder, its section 8.

## The partition {#layout}

A program of several C files converts, by default, into a das module per C file, every cycle among
the files one module of fragments (`--layout source`, the sidecar's `layout`); `--layout source-cut`
cuts the cycles by late binding instead, and `--layout single` is the one module of section 6. A
program of one file is one module in each layout: it never reaches the link, and its headers' types
stay in it. The layout is the owner's rulings (`docs/very-detailed-plan.md` section 1, "Module
layout": the cycle-cut ruling and ruling 12): the output reads like the C program's own files, its
calls spelled as C spells them, and a cut by late binding is the opt-in, since its slots, wrappers
and qualified calls are text the C program does not have.

The names say what each layout keeps: `source` the C files, `source-cut` the C files with the cut,
`single` one module. Any other value, `scc` included, is refused naming the three.

daslang refuses a cyclic `require` and has no forward declaration of another module's function
(`probes/test_modules.das`, `test_mutual_require`), and C files call each other in
cycles without including each other's headers (Lua's `ldo.c` and `lvm.c`), so a file cannot always
be a module of its own. `plan_layout` (`layout.das`) partitions the linked program before its
statics are named:

- Nodes: each unit (a `.c` file), each other file that defines a record or an enum the program
  uses (a header; `lobject.h` is the node `lobject_h`), and `c_types`, the one node of the types no
  single file defines: an external record the dumper anchors where each unit first uses it
  (`struct tm`), one the program reaches only through pointers (`FILE`, no anchor at all), and one
  two files define alike. A record or enum belongs to the one file every unit anchors it in, its
  definition's; never to the `.c` file of the same stem, since `lua.c` owning `lua.h`'s types would
  make every core file require the entry module. A record a header spells belongs to the header
  even where a unit's `.c` defines it: a header typedef naming it, or a field of a record the
  header owns (through pointers, an incomplete type's included), claims it, and the claim repeats
  through the claimed record's fields, so `struct lua_longjmp`, which `ldo.c` defines and `lstate.h`
  points at, is `lstate_h`'s, its body emitted there, and no header ever requires a unit.
- Edges: a unit to the unit defining each function or object its code references (the link's
  binding), and any node to the node owning each record and enum its declarations spell, through
  pointers, arrays, functions and typedefs (a record's fields are its own node's). A unit's
  prototypes and `extern` declarations spell nothing of their own: the definition does.
- Modules: each strongly connected component (Tarjan's algorithm) is one module. A single node is
  `<stem>.das`; a component of several is `<lexically first stem>_cluster.das`, the one holding
  `main` named by the entry unit's stem, with a `<stem>.das.inc` fragment per member. Two modules
  of one name (a unit `shape_h.c` beside a header `shape.h`) are refused, as is a module named like
  one daslang or c2das-re loads by that name (a daslib module file, `crt`, a `c_runtime` module):
  `math.c` would be `math.das`, which a bare `require math` resolves to daslib's.
- Placement: the output folder mirrors the C files' folders under their common folder, the root; a
  module lies in its naming node's folder, `c_types` at the root, a fragment beside its file. A
  module requires another by its name in the same folder and by its relative path elsewhere
  (`./sub/x.das`, `../x.das`), a cluster includes its fragments by their relative paths.
- Include order: a cluster's type nodes first, each after the members whose records its own hold
  by value, since `[c_union]` reads a member's record where it is declared (Lua's `GCUnion` in
  `lstate.h` holds `lobject.h`'s records); then its units in link order, each after a member whose
  global its global initializers take the address of; a cycle keeps the earlier order.

The link names the statics per module (`ARCHITECTURE_LINK.md`): each unit's scope is its module,
so a static is renamed `<stem>_<name>` only when it meets an external name of the program, a
reserved name, or a static or a reference of another unit of its own module; a `def private` of
one name in two modules is no collision (`probes/test_modules.das`). A function a header defines
is kept once per module, never across modules.

## The cycle cut {#cut}

In the `source-cut` layout each strongly connected component of more than one node is made acyclic
by late binding instead of merged (`cut_cycles`). A candidate is an edge between two units every
symbol of which is a function the program defines, calls directly everywhere (no reference takes its
address, so its identity stays one) and whose type spells no unit's record; an object, a type edge,
an edge from a unit spelling a record another unit defines (its calls or not: the record needs the
`require`), a symbol `layout.keep_together` names, two units of one `layout.keep_together` group,
and an edge whose weight is above `layout.threshold` are never cut, and an edge carrying a symbol
`layout.cut` names always is. The options are checked before the cut and refused naming the option
and the value: a `layout.keep_together` stem no file has or symbol no file calls from another, a
symbol both options name, a `layout.cut` symbol no edge of a cycle carries, a forced edge out of the
entry module, carrying a type or a symbol no cut can late-bind, kept by `layout.keep_together`, or
inside a group no cut parts (the entry's joined group among them), and a profile count that is not
an integer of 0 or more; the `source` layout cuts nothing and applies none of them, the profile's
counts still read and refused alike (Lua's sidecar names its profile for `source-cut`). The edges
never cut collapse into groups, which stay one module of fragments as in `source`; the entry module
is highest in its component's order, since it requires and nothing requires it, so a group with a
never-cut path to it joins its group, one module with it (the report's `kept with the entry` edge),
and every edge into it is cut. Among the groups the cut is a minimum weight feedback arc set: the
order of the groups, lowest first, that minimizes the weight of the edges going up it, exact over
the subsets for up to 16 groups, among equal weights the order leaving the fewest groups whose
callers are all below them, else a greedy order (a group requiring nothing unplaced goes lowest, one
nothing unplaced requires highest, else the one most required over what it requires). An edge's
weight is the dynamic call count of its symbols from the calling file, read from the profile
`layout.profile` names (a JSON object of callee names, each an object of calling file stems and
counts, `lua/profile.das` writes Lua's), else the count of its call sites. `program.layout.txt`
beside the program's C-IR lists every cut symbol with its edge and weight and every group no cut
parts.

A cut edge is the C linker's work done at `[init]`: the generated link module
`<entry stem>_link.das` at the root, the lowest layer, holds per late-bound function a slot `<name>_slot` of
its das function type and a wrapper of the function's own name, so a call site reads as C writes it;
the wrapper panics naming the function while the slot is empty, and a variadic one forwards its list
(`c_runtime/variadic`'s `to_cvalist` of a `CVaList` takes it as it is). The defining module requires
the link module and binds the slot in its `[init]` (`c2das_late_bind`), a variadic function through
a private function taking its list; it spells its own calls of the function `__::name` (the module's
own, however the module is compiled), and a module requiring both it and the link module spells them
`<module>::name`, since the wrapper of that name is in sight (`probes/test_modules.das`). A module
whose cut edge carries a symbol requires the link module, not the defining module; the entry module
requires every module it would not reach otherwise, so each loads and binds before `main` runs; with
the entry highest in its cycles' order a module reaching the entry is outside them, never called
from `main`, and stays unrequired. A module defining a late-bound function `main` can call (over the
edges before the cut) that the entry module still does not reach is refused as a defect of the
layout, never shipped to panic at run time (`unbound_module`). The link module requires the modules
of the types the signatures spell, all header type modules.

## Emitting the modules {#emission}

`emit_program` (`emit.das`) spells the modules over one program state, `EmitProgram`: the
functions the program defines, the wrapper's renames, its global names, the sidecar's records
and options, the layout memo and the scoping facts `unshadow_locals` finds, computed once. Each
module gets a fresh `Emitter`, whose own state is the module's: its lines, requires, literal
objects, the empty literal, the label statement, the module-init stores and the dialect's
`[init]`. A part of the program (`select_node`) is a node's globals and functions, by the unit
the link took each from, and the records and enums the node owns. A module of one node is spelled
as `emit_tu` spells a whole unit; `emit_tu` is the same sequence with every part selected, so the
single layout's text is the link's one module, unchanged.

A cluster shares one module scope: one `Emitter` spells every member in include order, each
member's types, globals and functions into its fragment, so the compound literal objects
(`_cl<N>`), the empty literal and the label statement are declared once and named apart. The
cluster's own file holds the requires, the empty literal, the dialect's `[init]`, one `include`
per fragment, the fragments' digest, the layout check of every member's records, the module-init
stores and the `main` wrapper. daslang initializes every module's globals in `require` order, a
required module's before the requiring one's, and runs the `[init]` functions after all of them
in the same order (`probes/test_modules.das`): an initializer takes the address of another
module's global inline, and inside a module the order of the `include` lines is the order of its
globals. The digest is a comment line of the fragments' hashes: daslang's module cache keys a
module by its own file's text and serves a stale module when only an included fragment changed
(`docs/probe-findings.md` F72), so a changed fragment changes the cluster's file.

A module requires the program modules its nodes' edges reach (a superset of the names its text
spells, acyclic by construction) and the c_runtime pieces its text reaches; a caller of a variadic
function requires `c_runtime/variadic` for the trailing arguments' spelling. Every external name of
the program is one name and the link renames a static meeting one, so two modules a module requires
export one name only for a late-bound function, its definer and the link module; any other
cross-module name is spelled bare. The pipeline lists every module and fragment it writes in
`program.modules.txt` beside them (the files the ports publisher copies) and, before converting,
deletes the files an earlier conversion listed there, none other, so no stale module stays beside
the new ones; it writes every file, formats each, and compile-checks each module no other module
requires (the entry's, and any the program never reaches), which compiles every module they require.
