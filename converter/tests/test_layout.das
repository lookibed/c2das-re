options gen2
// the pipeline parses clang's JSON dump below the test's own frames: a deep expression tree
// overflows the default 16 KB context stack
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/sha_256
require math
require ../pipeline.das
require ../layout.das
require ../tiers.das
require ../dumper_a.das

//! The source module layout (`converter/layout.das`, `ARCHITECTURE_LAYOUT.md`): a program of four
//! files in two folders converted into a module per file, a cluster of two fragments, a header's
//! types module and the module of the types no file defines, run against the native build of the
//! same files under the interpreter and the JIT; the same program in the single layout, byte for
//! byte the module the link gave before the layout; a type cycle across two headers; the refusals.

let TREE = "converter/tests/fixtures/p5_layout_tree"
let TYPES = "converter/tests/fixtures/p5_layout_types"
let CUT = "converter/tests/fixtures/p5_layout_cut"

// the single layout's module of each fixture as the multi-TU link wrote it before the source
// layout (P5.1b1), which the single layout keeps byte for byte
let TREE_SINGLE_SHA = "a8229aef9c94381aaad779978bcf37308c110a9489a6e28cd19703b0a7ddc501"
let TYPES_SINGLE_SHA = "cfbd3ed05076a2f81ddec33c0bb79f78347369ffece083b4f1ca307352fc4725"

var work_root : string

// the tree fixture's paths and its conversion in the source layout, which the runs of
// `test_source_tree` read
var tree_files : array<string>
var tree : ConvertResult

// the C files of the tree fixture, in its manifest's link order
def private tree_paths : array<string> {
    var error : string
    let input <- read_program_input("{TREE}/program.json", "linux", error)
    return <- clone_to_move(input.c_paths)
}

// the program of `paths` converted in `layout` under the work root's `dir`
def private converted(paths : array<string>; dir, layout : string) : ConvertResult => <- convert_program(paths, path_join(work_root, dir), "linux", "", "", "", "", "main", layout)

// the program of `paths` converted in the source layout under the work root's `dir`, with a sidecar
// of text `sidecar` written beside it ("" for none)
def private converted_with(paths : array<string>; dir, sidecar : string) : ConvertResult {
    let at = path_join(work_root, dir)
    mkdir_rec(at)
    let side = empty(sidecar) ? "" : path_join(at, "cut.c2das")
    if (!empty(side)) {
        fwrite(side, sidecar)
    }
    return <- convert_program(paths, path_join(at, "out"), "linux", "", side, "", "", "main", "source")
}

// the text of the file at `rel` under the work root's `dir`
def private text_of(dir, rel : string) : string => fread(path_join(path_join(work_root, dir), rel))

// the text occurs `n` times in `text`
def private occurs(t : T?; text, needle : string; n : int) {
    t |> equal(length(split(text, needle)) - 1, n, "`{needle}` {n} times in:\n{text}")
}

// the native build of `paths` and the converted program at `das_path` under `tier`, both with no
// argument: the same exit code and output
def private agrees(t : T?; paths : array<string>; das_path, tier, name : string) {
    let native = native_run(default_clang(), ["-w", "-funsigned-char"], paths, path_join(work_root, "{name}_native"), 60.0, array<string>())
    t |> equal(native.built, true, native.output)
    var out : string
    let rc = run_tier(das_path, tier, path_join(work_root, "{name}_{tier}"), out, CONVERTED_MODULES)
    // the JIT reports its compilation on `info` lines among the program's output
    out = join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")
    t |> equal(rc, native.rc, out)
    t |> equal(out, native.output)
}

[test]
def test_scc_tree(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_layout", dir_error)
    t |> equal(dir_error, "")
    delete tree_files
    tree_files <- tree_paths()
    delete tree
    tree <- converted(tree_files, "tree", "scc")
    if (!tree.ok) {
        t |> failure(tree.error)
        return
    }
    t |> run("in the scc layout four files in two folders are a module per file, a cluster of the two that call each other, a header's types and the types no file defines, mirroring the folders") @(t : T?) {
        t |> equal(join(tree.files, " "), "sub/shapes_h.das c_types.das ring_a.das.inc sub/ring_b.das.inc ring_a_cluster.das sub/solo.das main.das")
        t |> equal(tree.das_path, path_join(path_join(work_root, "tree"), "main.das"))
        t |> equal(join(tree.partition, "\n"), "c_types\nmain\nring_a_cluster: cluster of 2: ring_a ring_b\nshapes_h\nsolo\nring_a_cluster: ring_a -> ring_b: ring_b\nring_a_cluster: ring_b -> ring_a: a_value, ring_a")
    }
    for (tier in ["interp", "jit"]) {
        t |> run("the modules print what the native build of the files prints under {tier}") @(t : T?) {
            agrees(t, tree_files, tree.das_path, tier, "tree")
        }
    }
    t |> run("a module requires another by name in its folder and by its relative path elsewhere; a cluster includes its fragments, the one holding a global another's initializer takes the address of first, and carries their digest") @(t : T?) {
        let main = text_of("tree", "main.das")
        t |> success(main |> contains("require ./sub/shapes_h.das\nrequire ./sub/solo.das\nrequire c_runtime/c_args\nrequire c_runtime/c_function\nrequire c_runtime/printf\nrequire c_runtime/variadic\nrequire c_types\nrequire ring_a_cluster\n"), main)
        let solo = text_of("tree", "sub/solo.das")
        t |> success(solo |> contains("require c_runtime/c_function\nrequire c_runtime/variadic\n\nvar solo_count : int = 5\n"), solo)
        let cluster = text_of("tree", "ring_a_cluster.das")
        // ring_b.c comes first in the link order, but its `b_ptr` takes ring_a.c's `a_value`
        t |> success(cluster |> contains("require ./sub/shapes_h.das\nrequire c_runtime/c_function\nrequire c_types\nrequire crt\n\nvar private c2das_empty : uint8[1] = fixed_array(uint8(0))\n\ninclude ring_a.das.inc\ninclude sub/ring_b.das.inc\n// the fragments' digest: "), cluster)
        t |> success(text_of("tree", "sub/ring_b.das.inc") |> starts_with("// generated by c2das - regenerate, never edit\nvar b_ptr : int? = unsafe(addr(a_value))\n"))
    }
    t |> run("a global another module's initializer takes the address of is taken inline: the required module's globals are set first") @(t : T?) {
        let main = text_of("tree", "main.das")
        t |> success(main |> contains("var main_count : int? = unsafe(addr(solo_count))\n"), main)
        t |> success(!(main |> contains("c2das_init_globals")), main)
    }
    t |> run("a static is renamed where its module holds another of its name, kept where it is alone in its module") @(t : T?) {
        t |> equal(join(tree.renamed, "\n"), "ring_b.c: helper -> ring_b_helper\nring_a.c: helper -> ring_a_helper")
        occurs(t, text_of("tree", "ring_a.das.inc"), "def private ring_a_helper(v : int) : int", 1)
        occurs(t, text_of("tree", "sub/ring_b.das.inc"), "def private ring_b_helper(v : int) : int", 1)
        occurs(t, text_of("tree", "main.das"), "def private helper(v : int) : int", 1)
        occurs(t, text_of("tree", "sub/solo.das"), "def private helper(v : int) : int", 1)
    }
    t |> run("a header's function is kept once in a cluster and once in each other module that calls it") @(t : T?) {
        t |> equal(join(tree.deduplicated, "\n"), "twice: ring_b.c, ring_a.c")
        occurs(t, text_of("tree", "sub/ring_b.das.inc") + text_of("tree", "ring_a.das.inc"), "def private twice(v : int) : int", 1)
        occurs(t, text_of("tree", "main.das"), "def private twice(v : int) : int", 1)
        occurs(t, text_of("tree", "sub/solo.das"), "def private twice(v : int) : int", 1)
    }
    t |> run("two fragments' compound literal objects take two names, and the empty literal is the cluster's one byte") @(t : T?) {
        let a = text_of("tree", "ring_a.das.inc")
        let b = text_of("tree", "sub/ring_b.das.inc")
        t |> success(a |> contains("var private _cl0 : point = point(x = 3, y = 4)\nvar a_corner : point? = unsafe(addr(_cl0))\n"), a)
        t |> success(b |> contains("var private _cl1 : int[3] = fixed_array(4, 5, 6)\nvar b_list : int? = unsafe(addr(_cl1[0]))\n"), b)
        occurs(t, a + b, "addr(c2das_empty[0])", 2)
        occurs(t, a + b, "var private c2das_empty", 0)
    }
    t |> run("the header's records, enum and union are its module's, the opaque FILE the shared types module's") @(t : T?) {
        let shapes = text_of("tree", "sub/shapes_h.das")
        t |> success(shapes |> contains("require c_runtime/c_union\n\nenum mode \{\n    MODE_ADD = 1\n    MODE_MUL\n\}\n\nstruct point \{\n    x, y : int\n\}\n\n[c_union]\nstruct number \{\n"), shapes)
        t |> success(shapes |> contains("[init]\ndef private c2das_layout_check"), shapes)
        t |> success(text_of("tree", "c_types.das") |> ends_with("options stack = 8388608\n\nstruct _IO_FILE \{\}\n\n"))
    }
    t |> run("a function value, a variadic call and a [c_union] value cross modules as they are spelled in one") @(t : T?) {
        let main = text_of("tree", "main.das")
        for (needle in ["solo_apply(@@add, p.x, p.y)", "solo_apply(@@ring_mul, p.x, p.y)", "solo_sum`va(3, (1, 2, 3))", "    var u : number\n"]) {
            t |> success(main |> contains(needle), "`{needle}` in:\n{main}")
        }
    }
    rmdir_rec(work_root)
}

[test]
def test_single_layout(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_layout_single", dir_error)
    t |> equal(dir_error, "")
    t |> run("the single layout is one module, the multi-TU link's text byte for byte, which prints what the native build prints") @(t : T?) {
        let paths <- tree_paths()
        let res <- converted(paths, "single", "single")
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        t |> equal(length(res.files), 0)
        t |> equal(res.das_path, path_join(path_join(work_root, "single"), "main.das"))
        t |> equal(sha256_hex(res.das_text), TREE_SINGLE_SHA, res.das_text)
        agrees(t, paths, res.das_path, "interp", "single")
        let types <- converted(["{TYPES}/main.c", "{TYPES}/weigh.c"], "types_single", "single")
        t |> equal(sha256_hex(types.das_text), TYPES_SINGLE_SHA, types.das_text)
    }
    t |> run("one file is one module in either layout") @(t : T?) {
        let source <- converted(["converter/tests/fixtures/ret42.c"], "one_source", "source")
        let single <- converted(["converter/tests/fixtures/ret42.c"], "one_single", "single")
        t |> equal(source.ok && single.ok, true, "{source.error} {single.error}")
        t |> equal(length(source.files), 0)
        t |> equal(source.das_text, single.das_text)
    }
    rmdir_rec(work_root)
}

[test]
def test_type_cluster(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_layout_types", dir_error)
    t |> equal(dir_error, "")
    t |> run("two headers whose records point at each other are one module of two fragments, the one whose record the other holds by value included first") @(t : T?) {
        let paths <- ["{TYPES}/main.c", "{TYPES}/weigh.c"]
        let res <- converted(paths, "types", "source")
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        t |> equal(join(res.partition, "\n"), "a_h_cluster: cluster of 2: a_h b_h\nmain\nweigh\na_h_cluster: a_h -> b_h: union B\na_h_cluster: b_h -> a_h: struct A")
        let cluster = text_of("types", "a_h_cluster.das")
        t |> success(cluster |> contains("include a_h.das.inc\ninclude b_h.das.inc\n"), cluster)
        t |> success(text_of("types", "b_h.das.inc") |> contains("[c_union]\nstruct B \{\n    a : A\n"))
        agrees(t, paths, res.das_path, "interp", "types")
    }
    rmdir_rec(work_root)
}

[test]
def test_layout_refusals(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_layout_refusals", dir_error)
    t |> equal(dir_error, "")
    t |> run("two modules of one name are refused, naming both files") @(t : T?) {
        let dir = path_join(work_root, "clash")
        mkdir_rec(dir)
        fwrite(path_join(dir, "shape.h"), "struct shape \{ int w; \};\n")
        fwrite(path_join(dir, "shape_h.c"), "#include \"shape.h\"\nint area(struct shape *s) \{ return s->w; \}\n")
        fwrite(path_join(dir, "main.c"), "#include \"shape.h\"\nint area(struct shape *s);\nint main(void) \{ struct shape s = \{ 3 \}; return area(&s); \}\n")
        let res <- converted([path_join(dir, "main.c"), path_join(dir, "shape_h.c")], "clash/out", "source")
        t |> success(res.error |> contains("link: the modules of ") && res.error |> contains("would both be `shape_h.das`; rename a file"), res.error)
        t |> success(res.error |> contains("shape.h") && res.error |> contains("shape_h.c"), res.error)
    }
    t |> run("a layout other than source or single is refused before any conversion") @(t : T?) {
        let res <- converted(["{TYPES}/main.c", "{TYPES}/weigh.c"], "flat", "flat")
        t |> equal(res.error, "--layout is source, scc or single, not `flat`")
        let one <- converted(["converter/tests/fixtures/ret42.c"], "flat_one", "flat")
        t |> equal(one.error, "--layout is source, scc or single, not `flat`")
    }
    rmdir_rec(work_root)
}

// the cut fixture's files, in link order
def private cut_paths : array<string> => <- ["{CUT}/main.c", "{CUT}/a.c", "{CUT}/b.c"]

// the cut lines of a conversion's partition report
def private cut_lines(res : ConvertResult) : string => join([for (ln in res.partition); ln; where ln |> starts_with("cut ") || ln |> starts_with("kept together")], "\n")

[test]
def test_cut_tree(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_layout_cut_tree", dir_error)
    t |> equal(dir_error, "")
    t |> run("the source layout cuts the cycle of two files: the lighter edge late-binds through the link module, each file its own module, which print what the native build prints") @(t : T?) {
        let paths <- tree_paths()
        let res <- converted(paths, "tree", "source")
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        // ring_b.c's edge carries the object `a_value`, which no cut late-binds
        t |> equal(cut_lines(res), "cut ring_b: ring_a -> ring_b, 1 call sites of the edge's 1")
        t |> equal(join(res.files, " "), "sub/shapes_h.das c_types.das ring_a.das sub/ring_b.das sub/solo.das main.das main_link.das")
        let link = text_of("tree", "main_link.das")
        t |> success(link |> contains("var ring_b_slot : function<(a0 : int) : int>\n\ndef ring_b(a0 : int) : int \{\n    if (ring_b_slot == null) \{\n        panic(\"ring_b is late-bound and no module has bound it\")\n    \}\n    return invoke(ring_b_slot, a0)\n\}\n"), link)
        let ring_a = text_of("tree", "ring_a.das")
        t |> success(ring_a |> contains("require main_link\n") && !(ring_a |> contains("require ./sub/ring_b.das")), ring_a)
        // the defining module binds the slot and names its own function, which the wrapper shadows
        let ring_b = text_of("tree", "sub/ring_b.das")
        t |> success(ring_b |> contains("require ../main_link.das\nrequire ../ring_a.das\n"), ring_b)
        t |> success(ring_b |> contains("[init]\ndef private c2das_late_bind \{\n    ring_b_slot = @@__::ring_b\n\}\n"), ring_b)
        // the entry module requires the defining module, so it loads and binds before main runs
        t |> success(text_of("tree", "main.das") |> contains("require ./sub/ring_b.das\n"))
        agrees(t, paths, res.das_path, "interp", "cut_tree")
        agrees(t, paths, res.das_path, "jit", "cut_tree")
        t |> equal(fread(path_join(path_join(work_root, "tree"), "program.layout.txt")), join(res.partition, "\n") + "\n")
    }
    rmdir_rec(work_root)
}

[test]
def test_cut_choices(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_layout_cut", dir_error)
    t |> equal(dir_error, "")
    t |> run("by the static count the edge of two call sites is cut, the edge of three kept; a variadic function late-binds with its list; the header owns the record a unit defines") @(t : T?) {
        let paths <- cut_paths()
        let res <- converted_with(paths, "count", "")
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        t |> equal(cut_lines(res), "cut b_note: a -> b, 1 call sites of the edge's 2\ncut b_step: a -> b, 1 call sites of the edge's 2")
        let link = text_of("count/out", "main_link.das")
        t |> success(link |> contains("var b_note_slot : function<(a0 : int; a1 : CVaList) : int>\n\n[variadic]\ndef b_note(a0 : int; va : va_args) : int \{"), link)
        let b = text_of("count/out", "b.das")
        t |> success(b |> contains("def private b_note_slot_bind(a0 : int; a1 : CVaList) : int \{\n    return __::b_note`va(a0, a1)\n\}\n"), b)
        t |> success(text_of("count/out", "cut_h.das") |> contains("struct hidden \{\n    secret : int\n\}\n"))
        t |> success(!(b |> contains("struct hidden \{")), b)
        agrees(t, paths, res.das_path, "interp", "count")
    }
    t |> run("a profile weighs the edges by calls: the edge it makes hot is kept and the other cut") @(t : T?) {
        let paths <- cut_paths()
        fwrite(path_join(work_root, "cut.profile.json"), "\{\"b_step\": \{\"a\": 1000\}, \"a_back\": \{\"b\": 10\}\}\n")
        let res <- converted_with(paths, "profile", "\{\"layout\": \{\"profile\": \"../cut.profile.json\"\}\}\n")
        t |> equal(res.error, "")
        t |> equal(cut_lines(res), "cut a_back: b -> a, 10 calls profiled of the edge's 10")
        agrees(t, paths, res.das_path, "interp", "profile")
    }
    t |> run("layout.keep_together keeps two files in one module, by their stems or by a symbol of the cycle, layout.cut cuts a symbol, layout.threshold keeps every heavier edge") @(t : T?) {
        let paths <- cut_paths()
        for (sidecar in ["\{\"layout\": \{\"keep_together\": [[\"a\", \"b\"]]\}\}\n", "\{\"layout\": \{\"keep_together\": [\"b_step\", \"a_back\"]\}\}\n", "\{\"layout\": \{\"threshold\": 1\}\}\n"]) {
            let res <- converted_with(paths, "kept", sidecar)
            t |> equal(cut_lines(res), "kept together: a b", sidecar)
            t |> success(fexist(path_join(work_root, "kept/out/a_cluster.das")), sidecar)
            agrees(t, paths, res.das_path, "interp", "kept")
        }
        let forced <- converted_with(paths, "forced", "\{\"layout\": \{\"cut\": [\"a_back\"]\}\}\n")
        t |> equal(cut_lines(forced), "cut a_back: b -> a, 3 call sites of the edge's 0, layout.cut")
        agrees(t, paths, forced.das_path, "interp", "forced")
        let light <- converted_with(paths, "threshold", "\{\"layout\": \{\"threshold\": 2\}\}\n")
        t |> equal(cut_lines(light), "cut b_note: a -> b, 1 call sites of the edge's 2\ncut b_step: a -> b, 1 call sites of the edge's 2")
    }
    t |> run("a file the program reaches only through cut edges is required by the entry module, so it loads and binds its slots before main runs") @(t : T?) {
        let dir = path_join(work_root, "unreached")
        mkdir_rec(dir)
        for (name in ["cut.h", "a.c", "b.c"]) {
            fwrite(path_join(dir, name), fread("{CUT}/{name}"))
        }
        fwrite(path_join(dir, "main.c"), "#include <stdio.h>\n#include \"cut.h\"\n\nint main(int argc, char **argv) \{\n    printf(\"%d %d\\n\", a_run(argc + 2), argv[argc] == 0);\n    return 0;\n\}\n")
        var inscope files <- [for (name in ["main.c", "a.c", "b.c"]); path_join(dir, name)]
        let res <- convert_program(files, path_join(dir, "out"), "linux", "", "", "", "", "main", "source")
        t |> equal(res.error, "")
        t |> success(fread(path_join(dir, "out/main.das")) |> contains("require b\n"), res.das_text)
        agrees(t, files, res.das_path, "interp", "unreached")
    }
    t |> run("layout.cut naming an object is refused; the scc layout keeps the cycle a cluster; single is one module; each prints what the native build prints") @(t : T?) {
        let paths <- cut_paths()
        let refused <- converted_with(paths, "object", "\{\"layout\": \{\"cut\": [\"b_count\"]\}\}\n")
        t |> equal(refused.error, "link: layout.cut names `b_count`, which no cut can late-bind: an object")
        let scc <- convert_program(paths, path_join(work_root, "scc"), "linux", "", "", "", "", "main", "scc")
        t |> success(fexist(path_join(work_root, "scc/a_cluster.das")) && !fexist(path_join(work_root, "scc/main_link.das")), scc.error)
        agrees(t, paths, scc.das_path, "interp", "scc")
        let single <- convert_program(paths, path_join(work_root, "single"), "linux", "", "", "", "", "main", "single")
        t |> equal(length(single.files), 0)
        agrees(t, paths, single.das_path, "interp", "single")
    }
    rmdir_rec(work_root)
}

// the weight of the edges going up `order` (lowest first), `w` as `cut_order` takes it
def private order_cost(n : int; w : array<int64>; order : array<int>) : int64 {
    var place : array<int>
    place |> resize(n)
    for (at, v in count(), order) {
        place[v] = at
    }
    var cost = 0l
    for (a in range(n)) {
        for (b in range(n)) {
            if (place[a] < place[b]) {
                cost += w[a * n + b]
            }
        }
    }
    return cost
}

// the least `order_cost` of any order of `n` nodes, over every permutation
def private brute_cost(n : int; w : array<int64>; var prefix : array<int>; var used : array<bool>) : int64 {
    if (length(prefix) == n) {
        return order_cost(n, w, prefix)
    }
    var best = NO_CUT
    for (v in range(n)) {
        if (!used[v]) {
            used[v] = true
            prefix |> push(v)
            best = min(best, brute_cost(n, w, prefix, used))
            prefix |> pop()
            used[v] = false
        }
    }
    return best
}

[test]
def test_cut_order(t : T?) {
    t |> run("up to 16 nodes the order is a minimum weight feedback arc set, the least weight any order gives") @(t : T?) {
        var seed = 12345
        for (_ in range(20)) {
            let n = 6
            var inscope w : array<int64>
            w |> resize(n * n)
            for (a in range(n)) {
                for (b in range(n)) {
                    seed = (seed * 1103515245 + 12345) & 0x7fffffff
                    w[a * n + b] = a == b || (seed & 3) == 0 ? 0l : int64(seed % 97)
                }
            }
            var inscope prefix : array<int>
            var inscope used : array<bool>
            used |> resize(n)
            t |> equal(order_cost(n, w, cut_order(n, w)), brute_cost(n, w, prefix, used))
        }
    }
    t |> run("past 16 nodes the greedy order places every node once and cuts nothing of an acyclic graph") @(t : T?) {
        let n = 18
        var w : array<int64>
        w |> resize(n * n)
        for (a in range(1, n)) {
            w[a * n + (a - 1)] = 5l
            w[a * n + 0] = 1l
        }
        let order <- cut_order(n, w)
        var seen : table<int>
        for (v in order) {
            seen |> insert(v)
        }
        t |> equal(length(seen), n)
        t |> equal(order_cost(n, w, order), 0l)
    }
}
