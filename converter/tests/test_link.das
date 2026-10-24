options gen2
// the pipeline parses clang's JSON dump below the test's own frames: a deep expression tree
// overflows the default 16 KB context stack
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../cir.das
require ../link.das
require ../pipeline.das
require ../tiers.das
require ../dumper_a.das
require ../emit.das

//! The link of several translation units (`converter/link.das`): a three-file program converted
//! into one module and run against the native build of the same files, a manifest and a file list
//! giving the same module, the refusals over small C programs, and the binding rules over trees
//! built by hand.

let PROGRAM = "converter/tests/fixtures/p5_multi_link"
let UNITS <- ["geo", "parity", "prog"]

var work_root : string

def private unit_paths : array<string> => <- [for (stem in UNITS); "{PROGRAM}/{stem}.c"]

// the program of `paths` linked in the single layout, the one module this file's checks read
def private single_program(paths : array<string>; out_dir : string) : ConvertResult => <- convert_program(paths, out_dir, "linux", "", "", "", "", "main", "single")

// the text occurs `n` times in `text`
def private occurs(t : T?; text, needle : string; n : int) {
    t |> equal(length(split(text, needle)) - 1, n, "`{needle}` {n} times in:\n{text}")
}

// `sources` written under the work root's `dir`, each `<name>` a C file: their paths in order
def private written(dir : string; sources : array<tuple<name : string; text : string>>) : array<string> {
    let at = path_join(work_root, dir)
    mkdir_rec(at)
    var paths : array<string>
    paths |> reserve(length(sources))
    for (s in sources) {
        let path = path_join(at, s.name)
        fwrite(path, s.text)
        paths |> push(path)
    }
    return <- paths
}

// the program of `sources` refused by the link, the error carrying every needle
def private refused(t : T?; dir : string; sources : array<tuple<name : string; text : string>>; needles : array<string>) {
    let paths <- written(dir, sources)
    let res <- single_program(paths, path_join(path_join(work_root, dir), "out"))
    t |> equal(res.ok, false, "{dir} converted:\n{res.das_text}")
    for (needle in needles) {
        t |> success(res.error |> find(needle) >= 0, "{dir}: `{needle}` not in `{res.error}`")
    }
}

[test]
def test_three_files(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_link", dir_error)
    t |> equal(dir_error, "")
    t |> run("three files link into the module of the unit holding main, which prints what the native build prints") @(t : T?) {
        let paths <- unit_paths()
        let native = native_run(default_clang(), ["-w", "-funsigned-char"], paths, path_join(work_root, "multi_native"), 60.0, array<string>())
        t |> equal(native.built, true, native.output)
        let out_dir = path_join(work_root, "multi")
        let res <- single_program(paths, out_dir)
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        t |> equal(res.das_path, path_join(out_dir, "prog.das"))
        var out : string
        t |> equal(run_tier(res.das_path, "interp", out_dir, out, CONVERTED_MODULES), native.rc)
        t |> equal(out, native.output)
        let text = res.das_text
        // argv[0] is the entry unit's stem, not the first file's
        t |> success(text |> contains("c_runtime_init(\"prog\")"), text)
        // the extern global the header declares, defined tentatively in prog.c, is one object
        occurs(t, text, "var calls : int\n", 1)
        // the colliding statics take their unit's stem; `geo_bump` is the external, so geo.c's
        // `bump` takes the next free name
        for (needle in ["var private geo_counter : int = 100\n", "var private prog_counter : int = 1\n", "def private geo_bump1 : int", "def private prog_bump : int"]) {
            occurs(t, text, needle, 1)
        }
        // a header object stays one copy per unit, and so does a header function reading it
        for (stem in UNITS) {
            occurs(t, text, "var private {stem}_header_bias : int = 3\n", 1)
            occurs(t, text, "def private {stem}_biased(v : int) : int", 1)
        }
        // identical header functions are kept once, a call among them included
        occurs(t, text, "def private twice(v : int) : int", 1)
        occurs(t, text, "def private quad(v : int) : int", 1)
        // geo.c's `flavor` differs, so parity.c's copy serves prog.c too, and a function calling
        // `flavor` stays one copy per unit
        occurs(t, text, "def private geo_flavor1 : int", 1)
        // the kept copy's new name passes prog.c's local `parity_flavor`, which reaches it
        occurs(t, text, "def private parity_flavor1 : int", 1)
        occurs(t, text, "def private prog_flavor_twice : int \{\n    return parity_flavor1() * 2\n", 1)
        // a parameter or local named like a renamed static is no reference to it
        t |> success(text |> contains("        var counter : int = n * 100\n        sum += counter\n"), text)
        t |> success(text |> contains("    for (counter in range(3)) \{\n        sum += counter\n"), text)
        t |> success(text |> contains("    return sum + prog_counter\n"), text)
        t |> equal(join(res.renamed, "\n"), "geo.c: biased -> geo_biased\ngeo.c: bump -> geo_bump1\ngeo.c: counter -> geo_counter\ngeo.c: flavor -> geo_flavor1\ngeo.c: flavor_twice -> geo_flavor_twice\ngeo.c: header_bias -> geo_header_bias\nparity.c: biased -> parity_biased\nparity.c: flavor -> parity_flavor1\nparity.c: flavor_twice -> parity_flavor_twice\nparity.c: header_bias -> parity_header_bias\nprog.c: biased -> prog_biased\nprog.c: bump -> prog_bump\nprog.c: counter -> prog_counter\nprog.c: flavor_twice -> prog_flavor_twice\nprog.c: header_bias -> prog_header_bias")
        t |> equal(join(res.deduplicated, "\n"), "flavor: parity.c, prog.c\nquad: geo.c, parity.c, prog.c\ntwice: geo.c, parity.c, prog.c")
        for (line in ["geo.c: calls -> prog.c", "parity.c: is_even -> geo.c", "prog.c: area -> geo.c", "prog.c: total -> parity.c"]) {
            t |> success(has_value(res.bound, line), "{line} not in {res.bound}")
        }
        // each unit's C-IR beside the program manifest naming them
        for (stem in UNITS) {
            t |> success(fexist(path_join(out_dir, "{stem}.cir.json")), stem)
        }
        t |> equal(fread(path_join(out_dir, "program.cir.json")), res.cir_text)
        t |> equal(res.cir_text, "\{\n \"cir\": \"0.1\",\n \"target\": \{\n  \"triple\": \"x86_64-unknown-linux-gnu\",\n  \"int\": 32,\n  \"long\": 64,\n  \"llong\": 64,\n  \"ptr\": 64,\n  \"char_signed\": false\n \},\n \"tus\": [\"geo.cir.json\", \"parity.cir.json\", \"prog.cir.json\"],\n \"entry\": \"main\"\n\}\n")
    }
    t |> run("one file is the one-unit conversion: its own module, no program manifest") @(t : T?) {
        let out_dir = path_join(work_root, "single")
        let res <- convert_program(["converter/tests/fixtures/ret42.c"], out_dir, "linux")
        t |> equal(res.ok, true, res.error)
        t |> equal(res.das_path, path_join(out_dir, "ret42.das"))
        t |> equal(res.cir_path, path_join(out_dir, "ret42.cir.json"))
        t |> success(!fexist(path_join(out_dir, "program.cir.json")))
    }
    t |> run("a program needs a file, and its entry is main") @(t : T?) {
        let none <- convert_program(array<string>(), path_join(work_root, "none"), "linux")
        t |> equal(none.error, "a program needs at least one C file")
        let start <- convert_program(["converter/tests/fixtures/ret42.c"], path_join(work_root, "start"), "linux", "", "", "", "", "start")
        t |> equal(start.error, "link: the program's entry `start` is not `main`: C `main` is the one entry point the emitter wraps")
    }
    rmdir_rec(work_root)
}

// `converter/main.das -- <args>` as a child process: its exit code and output
def private run_main(args : array<string>; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--"], args)
    return run_and_capture(argv, out, 600.0)
}

[test]
def test_manifest(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_manifest", dir_error)
    t |> equal(dir_error, "")
    t |> run("the files on the command line and a manifest naming them give one module in the single layout") @(t : T?) {
        var listed <- unit_paths()
        listed |> push_from(["--out", path_join(work_root, "listed"), "--target", "linux", "--layout", "single"])
        var out : string
        t |> equal(run_main(listed, out), 0, out)
        t |> equal(run_main(["--program", "{PROGRAM}/program.json", "--out", path_join(work_root, "manifest"), "--target", "linux", "--layout", "single"], out), 0, out)
        let text = fread(path_join(work_root, "listed/prog.das"))
        t |> success(text |> contains("def c_main"), text)
        t |> equal(fread(path_join(work_root, "manifest/prog.das")), text)
    }
    t |> run("a manifest beside files is a usage error, a refused manifest exits 1") @(t : T?) {
        var out : string
        t |> equal(run_main(["{PROGRAM}/geo.c", "--program", "{PROGRAM}/program.json"], out), 2, out)
        t |> success(out |> contains("--program names the files; give no file beside it"), out)
        t |> equal(run_main(["--program", path_join(work_root, "missing.json")], out), 1, out)
        t |> success(out |> contains("cannot read {path_join(work_root, "missing.json")}"), out)
    }
    t |> run("a manifest's `tus` are C files relative to it, and its target, when named, is the conversion's") @(t : T?) {
        var error : string
        let input <- read_program_input("{PROGRAM}/program.json", "linux", error)
        t |> equal(error, "")
        t |> equal(join(input.c_paths, " "), join(unit_paths(), " "))
        t |> equal(input.entry, "main")
        let cases <- [
            ("not_json.json", "tus", "is not JSON"),
            ("no_tus.json", "\{\"entry\": \"main\"\}", "`tus` is no list of C files"),
            ("empty_tus.json", "\{\"tus\": []\}", "`tus` is no list of C files"),
            ("cir_tus.json", "\{\"tus\": [\"a.cir.json\"]\}", "`a.cir.json` in `tus` is no C file; the link runs on the dumper's trees"),
            ("msvc.json", "\{\"target\": \{\"triple\": \"x86_64-pc-windows-msvc\"\}, \"tus\": [\"a.c\"]\}", "the manifest's target is x86_64-pc-windows-msvc, the conversion's x86_64-unknown-linux-gnu"),
            ("number_tus.json", "\{\"tus\": [\"a.c\", 5]\}", "an entry of `tus` is no file name")
        ]
        for (c in cases) {
            let path = path_join(work_root, c._0)
            fwrite(path, c._1)
            var refusal : string
            read_program_input(path, "linux", refusal)
            t |> success(refusal |> contains(c._2), "{c._0}: `{c._2}` not in `{refusal}`")
        }
        // no `entry` is `main`, and an absolute path is taken as is
        let linux_path = path_join(work_root, "linux.json")
        fwrite(linux_path, "\{\"target\": \{\"triple\": \"x86_64-unknown-linux-gnu\"\}, \"tus\": [\"a.c\", \"/abs/b.c\"], \"entry\": \"start\"\}")
        var refusal : string
        let linux <- read_program_input(linux_path, "linux", refusal)
        t |> equal(refusal, "")
        t |> equal(join(linux.c_paths, " "), "{work_root}/a.c /abs/b.c")
        t |> equal(linux.entry, "start")
        let bare_path = path_join(work_root, "bare.json")
        fwrite(bare_path, "\{\"tus\": [\"a.c\"]\}")
        let bare <- read_program_input(bare_path, "linux", refusal)
        t |> equal(refusal, "")
        t |> equal(bare.entry, "main")
    }
    rmdir_rec(work_root)
}

[test]
def test_refusals(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_link_refusals", dir_error)
    t |> equal(dir_error, "")
    t |> run("two initialized definitions of one object, or two bodies of one function, are refused") @(t : T?) {
        refused(t, "strong_object", [(name = "a.c", text = "int value = 1;\nint main(void) \{ return value; \}\n"), (name = "b.c", text = "int value = 2;\n")], ["link: `value` is defined twice: ", "a.c:1 and ", "b.c:1"])
        refused(t, "strong_function", [(name = "a.c", text = "int f(void) \{ return 1; \}\nint main(void) \{ return f(); \}\n"), (name = "b.c", text = "\nint f(void) \{ return 2; \}\n")], ["link: `f` is defined twice: ", "a.c:1 and ", "b.c:2"])
    }
    t |> run("one name as a function and an object is refused") @(t : T?) {
        refused(t, "kinds", [(name = "a.c", text = "int x(void) \{ return 0; \}\nint main(void) \{ return x(); \}\n"), (name = "b.c", text = "int x = 3;\n")], ["link: `x` is a function in one unit and an object in another: ", "a.c:1 and ", "b.c:1"])
    }
    t |> run("one record or enum spelling with two definitions is refused") @(t : T?) {
        refused(t, "layout", [(name = "a.c", text = "struct s \{ int a; \};\nint get_a(struct s *p) \{ return p->a; \}\nint main(void) \{ return 0; \}\n"), (name = "b.c", text = "\nstruct s \{ long a; long b; \};\nlong get_b(struct s *p) \{ return p->b; \}\n")], ["link: `struct s` is defined with two different layouts: ", "a.c:1 and ", "b.c:2"])
        refused(t, "enumerators", [(name = "a.c", text = "enum e \{ A = 1 \};\nint main(void) \{ return A; \}\n"), (name = "b.c", text = "enum e \{ A = 2 \};\nint b(void) \{ return A; \}\n")], ["link: `enum e` is defined with two different enumerator lists: ", "a.c:1 and ", "b.c:1"])
    }
    t |> run("two same-size layouts differing in field order or in a dimension's enumerator are refused") @(t : T?) {
        refused(t, "field_order", [(name = "a.c", text = "struct s \{ int x; int y; \};\nint ga(struct s *p) \{ return p->x; \}\nint main(void) \{ return 0; \}\n"), (name = "b.c", text = "struct s \{ int y; int x; \};\nint gb(struct s *p) \{ return p->y; \}\n")], ["link: `struct s` is defined with two different layouts: ", "a.c:1 and ", "b.c:1"])
        refused(t, "dims", [(name = "a.c", text = "enum \{ N = 2 \};\nstruct s \{ int v[N]; \};\nint ga(struct s *p) \{ return p->v[0]; \}\nint main(void) \{ return 0; \}\n"), (name = "b.c", text = "enum \{ M = 2 \};\nstruct s \{ int v[M]; \};\nint gb(struct s *p) \{ return p->v[1]; \}\n")], ["link: `struct s` is defined with two different layouts: ", "a.c:2 and ", "b.c:2"])
    }
    t |> run("a function a header defines without `static` in two units names `inline` and both units") @(t : T?) {
        let paths <- written("inline", [(name = "inl.h", text = "inline int sq(int x) \{ return x * x; \}\n"), (name = "i1.c", text = "#include \"inl.h\"\nint u1(void) \{ return sq(3); \}\n"), (name = "i2.c", text = "#include \"inl.h\"\nextern int sq(int);\nint u1(void);\nint main(void) \{ return u1() + sq(4); \}\n")])
        let res <- single_program([paths[1], paths[2]], path_join(work_root, "inline/out"))
        for (needle in ["link: `sq` is defined in i1.c and i2.c by ", "inl.h:1: a function or object a header defines without `static` (C99 `inline` among them) is one definition per unit, which the link does not merge yet"]) {
            t |> success(res.error |> contains(needle), "`{needle}` not in `{res.error}`")
        }
    }
    t |> run("a unit stemmed `program` is refused, its C-IR being the manifest's file") @(t : T?) {
        let paths <- written("program", [(name = "program.c", text = "int main(void) \{ return 0; \}\n"), (name = "b.c", text = "int b(void) \{ return 0; \}\n")])
        let res <- single_program(paths, path_join(work_root, "program/out"))
        t |> success(res.error |> ends_with("program.c: its C-IR would be {work_root}/program/out/program.cir.json, the program manifest's file; rename the file"), res.error)
    }
    t |> run("two units of one stem are refused") @(t : T?) {
        let first <- written("stem/one", [(name = "u.c", text = "int main(void) \{ return 0; \}\n")])
        let second <- written("stem/two", [(name = "u.c", text = "int u(void) \{ return 0; \}\n")])
        let res <- single_program([first[0], second[0]], path_join(work_root, "stem/out"))
        t |> equal(res.error, "link: u.c and u.c share the stem `u`")
    }
    rmdir_rec(work_root)
}

let NAMES = "converter/tests/fixtures/p5_multi_names"

[test]
def test_names(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_link_names", dir_error)
    t |> equal(dir_error, "")
    t |> run("statics named like libc functions, like another unit's names, like a local, and a static prototype print what the native build prints") @(t : T?) {
        let paths <- ["{NAMES}/a.c", "{NAMES}/b.c"]
        let native = native_run(default_clang(), ["-w", "-funsigned-char", "-lm"], paths, path_join(work_root, "names_native"), 60.0, array<string>())
        t |> equal(native.built, true, native.output)
        let out_dir = path_join(work_root, "names")
        let res <- single_program(paths, out_dir)
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        var out : string
        t |> equal(run_tier(res.das_path, "interp", out_dir, out, CONVERTED_MODULES), native.rc)
        t |> equal(out, native.output)
        let text = res.das_text
        // a header function reading a name that is external in one unit and static in the other
        // stays one copy per unit
        for (needle in ["def private a_get1 : int", "def private b_get : int", "def private a_wrap : int", "def private b_wrap : int"]) {
            occurs(t, text, needle, 1)
        }
        // the renamed static passes the local that already spells `a_count`
        occurs(t, text, "var private a_count1 : int = 7\n", 1)
        t |> success(text |> contains("    var a_count : int = 1\n    return a_count1 + a_count + helper(2)"), text)
        // a static named like a mapped libc function is renamed, and the other unit's calls reach libc
        for (needle in ["def private a_abs(", "def private a_strlen(", "def private a_rand :"]) {
            occurs(t, text, needle, 1)
        }
        // the definition after a static prototype is the same internal function
        occurs(t, text, "def private helper(v : int) : int", 1)
        // a hoisted local static and a file-scope static of its name stay two objects
        occurs(t, text, "var private f_x : int = 5\n", 1)
        occurs(t, text, "var private f_x1 : int = 7\n", 1)
        // a parameter named like a renamed static, and a local static named like an external
        t |> success(text |> contains("def private bump(counter : int) : int \{\n    return counter + 1\n"), text)
        // ... whose hoisted name passes the external `tick_total` the same unit references
        occurs(t, text, "var private tick_total1 : int = 0\n", 1)
        t |> equal(join(res.renamed, "\n"), "a.c: abs -> a_abs\na.c: c_exit -> a_c_exit\na.c: count -> a_count1\na.c: get -> a_get1\na.c: rand -> a_rand\na.c: scale -> a_scale\na.c: strlen -> a_strlen\na.c: toupper -> a_toupper\na.c: wrap -> a_wrap\nb.c: count -> b_count\nb.c: counter -> b_counter\nb.c: foo -> b_foo\nb.c: get -> b_get\nb.c: wrap -> b_wrap")
        t |> equal(length(res.deduplicated), 0)
    }
    rmdir_rec(work_root)
}

let HOISTED = "converter/tests/fixtures/p5_multi_hoisted"

[test]
def test_hoisted(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_link_hoisted", dir_error)
    t |> equal(dir_error, "")
    t |> run("a hoisted local static passes the externals, file-scope statics and locals that spell its name") @(t : T?) {
        let paths <- ["{HOISTED}/a.c", "{HOISTED}/b.c"]
        let native = native_run(default_clang(), ["-w", "-funsigned-char"], paths, path_join(work_root, "hoisted_native"), 60.0, array<string>())
        t |> equal(native.built, true, native.output)
        let out_dir = path_join(work_root, "hoisted")
        let res <- single_program(paths, out_dir)
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        var out : string
        t |> equal(run_tier(res.das_path, "interp", out_dir, out, CONVERTED_MODULES), native.rc)
        t |> equal(out, native.output)
        for (needle in ["var private e_x2 : int = 1\n", "var private f_x2 : int = 1\n", "var private f_x3 : int = 50\n", "var private k_x1 : int = 1\n"]) {
            occurs(t, res.das_text, needle, 1)
        }
        t |> equal(length(res.renamed), 0)
    }
    t |> run("one file: a hoisted local static passes a local of its function") @(t : T?) {
        let paths <- written("one_hoisted", [(name = "k.c", text = "#include <stdio.h>\nint f(void) \{ static int x = 1; int f_x = 3; return x + f_x; \}\nint main(void) \{ printf(\"%d\\n\", f()); return 0; \}\n")])
        let res <- single_program(paths, path_join(work_root, "one_hoisted/out"))
        t |> equal(res.ok, true, res.error)
        var out : string
        t |> equal(run_tier(res.das_path, "interp", path_join(work_root, "one_hoisted/out"), out, CONVERTED_MODULES), 0, out)
        t |> equal(out, "4\n")
    }
    t |> run("a tree no Dumper A input gives, two statics of one unit wanting one name, is refused") @(t : T?) {
        var tus <- [unit("a.c", target_lp64_linux()), unit("b.c", target_lp64_linux())]
        tus[0].decls <- [new CirDecl(k = "global", name = "a__f_x", c_name = "f_x", t = 0, is_static = true), new CirDecl(k = "global", name = "f_x", c_name = "x", t = 0, is_static = true, from_func = "f")]
        var res <- link_tus(tus, "main")
        t |> equal(res.error, "a.c: the statics `a__f_x` and `f_x` both want the name `f_x`")
        delete_tu(res.program)
    }
    rmdir_rec(work_root)
}

let RESERVED = "converter/tests/fixtures/p5_multi_reserved"

[test]
def test_reserved(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_link_reserved", dir_error)
    t |> equal(dir_error, "")
    t |> run("a renamed static passes the names the module spells bare: c_runtime helpers, the label and dialect functions") @(t : T?) {
        let paths <- ["{RESERVED}/end.c", "{RESERVED}/c.c", "{RESERVED}/c2das.c", "{RESERVED}/b.c"]
        let native = native_run(default_clang(), ["-w", "-funsigned-char"], paths, path_join(work_root, "reserved_native"), 60.0, array<string>())
        t |> equal(native.built, true, native.output)
        let out_dir = path_join(work_root, "reserved")
        let res <- single_program(paths, out_dir)
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        var out : string
        t |> equal(run_tier(res.das_path, "interp", out_dir, out, CONVERTED_MODULES), native.rc)
        t |> equal(out, native.output)
        t |> equal(join(res.renamed, "\n"), "end.c: index -> end_index1\nc.c: label_end -> c_label_end1\nc.c: volatile_load -> c_volatile_load1\nc2das.c: dialect -> c2das_dialect1\nb.c: dialect -> b_dialect\nb.c: index -> b_index\nb.c: label_end -> b_label_end\nb.c: volatile_load -> b_volatile_load")
    }
    t |> run("the reserved names hold every name the emitter spells bare, every crt binding and every public c_runtime definition") @(t : T?) {
        let reserved <- reserved_das_names()
        for (name in EMITTED_NAMES) {
            t |> success(has_value(reserved, name), name)
        }
        for (name in C_RUNTIME_EXPORTS) {
            t |> success(has_value(reserved, name), name)
        }
        for (name in ["c_stdin", "strlen", "c_errno_location"]) {
            t |> success(has_value(reserved, name), name)
        }
        let defined <- c_runtime_definitions()
        t |> success(has_value(defined, "end_index") && has_value(defined, "cstr_array") && has_value(defined, "c_long_bits"), "the scan finds the helpers")
        for (name in defined) {
            t |> success(has_value(C_RUNTIME_EXPORTS, name), "c_runtime defines `{name}`, which C_RUNTIME_EXPORTS (converter/emit.das) lacks")
        }
    }
    rmdir_rec(work_root)
}

def private leading_identifier(text : string) : string {
    return build_string() $(var w) {
        for (ch in text) {
            if (!is_alnum(ch) && ch != '_') {
                break
            }
            w |> write_char(ch)
        }
    }
}

// the public top-level names of `c_runtime/c_runtime/*.das`: each function, global, type and call
// macro, as a module requiring one of them sees it
def private c_runtime_definitions : array<string> {
    var names : array<string>
    let heads <- ["def ", "var ", "let ", "struct ", "enum ", "typedef ", "variant ", "bitfield ", "class "]
    dir("c_runtime/c_runtime") $(file) {
        if (!(file |> ends_with(".das"))) {
            return
        }
        for (raw in split(fread(path_join("c_runtime/c_runtime", file)), "\n")) {
            var text = raw
            let macro = find(text, "[call_macro(name = \"")
            if (macro == 0) {
                let start = length("[call_macro(name = \"")
                names |> push(slice(text, start, find(text, "\"", start)))
            }
            if (text |> starts_with("[") && find(text, "] ") > 0) {
                text = slice(text, find(text, "] ") + 2)
            }
            var head_length = 0
            for (head in heads) {
                if (text |> starts_with(head)) {
                    head_length = length(head)
                }
            }
            if (head_length > 0) {
                var rest = slice(text, head_length)
                if (rest |> starts_with("inscope ")) {
                    rest = slice(rest, length("inscope "))
                }
                if (!(rest |> starts_with("private "))) {
                    names |> push(leading_identifier(rest))
                }
            }
        }
    }
    return <- names
}

let SIDECAR_PROGRAM = "converter/tests/fixtures/p5_multi_sidecar"

[test]
def test_program_sidecar(t : T?) {
    var dir_error : string
    work_root = create_temp_directory("c2das_link_sidecar", dir_error)
    t |> equal(dir_error, "")
    t |> run("the entry file's sidecar, found whatever the order, defines for every unit") @(t : T?) {
        let paths <- ["{SIDECAR_PROGRAM}/lib.c", "{SIDECAR_PROGRAM}/main.c"]
        let native = native_run(default_clang(), ["-w", "-funsigned-char", "-DVALUE=7"], paths, path_join(work_root, "sidecar_native"), 60.0, array<string>())
        t |> equal(native.built, true, native.output)
        let out_dir = path_join(work_root, "sidecar")
        let res <- single_program(paths, out_dir)
        if (!res.ok) {
            t |> failure(res.error)
            return
        }
        var out : string
        t |> equal(run_tier(res.das_path, "interp", out_dir, out, CONVERTED_MODULES), native.rc)
        t |> equal(out, native.output)
    }
    t |> run("a sidecar beside a file other than the entry, or beside two files, is refused; the folder's applies") @(t : T?) {
        let other <- written("other", [(name = "a.c", text = "int a(void) \{ return VALUE; \}\n"), (name = "a.c2das", text = "\{\"defines\": [\"VALUE=1\"]\}\n"), (name = "b.c", text = "int a(void);\nint main(void) \{ return a(); \}\n")])
        let res <- single_program([other[0], other[2]], path_join(work_root, "other/out"))
        t |> equal(res.error, "{other[1]} is the sidecar of a, but the program's entry file is b.c: a program's sidecar is its entry file's")
        let both <- written("both", [(name = "a.c", text = "int a(void) \{ return 0; \}\n"), (name = "a.c2das", text = "\{\}\n"), (name = "b.c", text = "int main(void) \{ return 0; \}\n"), (name = "b.c2das", text = "\{\}\n")])
        let refused_both <- single_program([both[0], both[2]], path_join(work_root, "both/out"))
        t |> equal(refused_both.error, "{both[1]} and {both[3]} are each a file's sidecar; a program's is its entry file's: pass --sidecar")
        let folder <- written("folder", [(name = "a.c", text = "int a(void) \{ return VALUE; \}\n"), (name = ".c2das", text = "\{\"defines\": [\"VALUE=3\"]\}\n"), (name = "b.c", text = "int a(void);\nint main(void) \{ return a(); \}\n")])
        let folder_res <- single_program([folder[0], folder[2]], path_join(work_root, "folder/out"))
        t |> equal(folder_res.ok, true, folder_res.error)
        var out : string
        t |> equal(run_tier(folder_res.das_path, "interp", path_join(work_root, "folder/out"), out, CONVERTED_MODULES), 3, out)
    }
    rmdir_rec(work_root)
}

// the renames of a.c's static `abs` when b.c's initializer references `abs` (`referenced`) and
// with `reserved` reserved
def private renames_of_abs(referenced : bool; reserved : array<string>) : string {
    var tus <- [unit("a.c", target_lp64_linux()), unit("b.c", target_lp64_linux())]
    tus[0].decls <- [new CirDecl(k = "global", name = "a__abs", c_name = "abs", t = 0, is_static = true)]
    if (referenced) {
        tus[1].decls <- [new CirDecl(k = "global", name = "user", c_name = "user", t = 0, init = new CirExpr(e = "ref", t = 0, name = "abs"))]
    }
    var res <- link_tus(tus, "main", reserved)
    let renamed = empty(res.error) ? join(res.renamed, "\n") : res.error
    delete_tu(res.program)
    return renamed
}

def private int_type : CirType => CirType(k = "int", w = 32, is_signed = true, spell = "int")

// a unit of the trees below, `int` its type 0 unless `types` are given
def private unit(name : string; target : CirTarget; var types : array<CirType>) : CirTu {
    var tu = CirTu(cir = CIR_VERSION, tu = name, target = target)
    tu.types <- types
    return <- tu
}

def private unit(name : string; target : CirTarget) : CirTu => unit(name, target, [int_type()])

def private object(name : string; init : string; is_extern : bool = false) : CirDecl? {
    var d = new CirDecl(k = "global", name = name, c_name = name, t = 0, is_extern = is_extern, loc = CirLoc(file = "f.c", line = 1))
    if (!empty(init)) {
        d.init = new CirExpr(e = "int_lit", t = 0, v = init)
    }
    return d
}

// the program's declarations as `name=init` in order
def private objects(program : CirTu) : string => join([for (d in program.decls); "{d.name}={d.init != null ? d.init.v : ""}"], " ")

[test]
def test_binding(t : T?) {
    t |> run("an object binds to its initialized definition, whichever unit holds it, else to its first definition") @(t : T?) {
        var tus <- [unit("a.c", target_lp64_linux()), unit("b.c", target_lp64_linux()), unit("c.c", target_lp64_linux())]
        tus[0].decls <- [object("x", ""), object("y", "")]
        tus[1].decls <- [object("x", "", true), object("y", ""), object("z", "", true)]
        tus[2].decls <- [object("x", "5"), object("z", "", true)]
        var res <- link_tus(tus, "main")
        t |> equal(res.error, "")
        // an object declared and defined nowhere keeps its first declaration, and binds no line
        t |> equal(objects(res.program), "y= z= x=5")
        t |> equal(join(res.bound, "\n"), "a.c: x -> c.c\nb.c: x -> c.c\nb.c: y -> a.c")
        delete_tu(res.program)
    }
    t |> run("a record incomplete in one unit is the record another defines") @(t : T?) {
        var opaque <- [int_type(), CirType(k = "struct", name = "s", spell = "struct s", size = -1, align = -1), CirType(k = "ptr", to = 1)]
        var defined <- [int_type(), CirType(k = "ptr", to = 2), CirType(k = "struct", name = "s", spell = "struct s", size = 4, align = 4, fields <- [CirField(name = "v", t = 0)])]
        var tus <- [unit("a.c", target_lp64_linux(), opaque), unit("b.c", target_lp64_linux(), defined)]
        tus[0].decls <- [new CirDecl(k = "global", name = "p", c_name = "p", t = 2)]
        tus[1].decls <- [new CirDecl(k = "global", name = "q", c_name = "q", t = 1)]
        var res <- link_tus(tus, "main")
        t |> equal(res.error, "")
        t |> equal(length(res.program.types), 3)
        t |> equal(res.program.types[1].size, 4)
        t |> equal(length(res.program.types[1].fields), 1)
        t |> equal(res.program.decls[0].t, res.program.decls[1].t)
        delete_tu(res.program)
    }
    t |> run("a record defined first and incomplete later stays the definition") @(t : T?) {
        var defined <- [int_type(), CirType(k = "struct", name = "s", spell = "struct s", size = 4, align = 4, fields <- [CirField(name = "v", t = 0)])]
        var opaque <- [int_type(), CirType(k = "struct", name = "s", spell = "struct s", size = -1, align = -1)]
        var tus <- [unit("a.c", target_lp64_linux(), defined), unit("b.c", target_lp64_linux(), opaque)]
        var res <- link_tus(tus, "main")
        t |> equal(res.error, "")
        t |> equal(res.program.types[1].size, 4)
        delete_tu(res.program)
    }
    t |> run("one enum spelling with other enumerator names or another signedness is refused") @(t : T?) {
        for (other in [CirType(k = "enum", spell = "enum e", is_signed = true, items <- [CirEnumItem(name = "B", v = 1l)]), CirType(k = "enum", spell = "enum e", is_signed = false, items <- [CirEnumItem(name = "A", v = 1l)])]) {
            var inscope first <- [int_type(), CirType(k = "enum", spell = "enum e", is_signed = true, items <- [CirEnumItem(name = "A", v = 1l)])]
            var inscope second <- [int_type(), other]
            var tus <- [unit("a.c", target_lp64_linux(), first), unit("b.c", target_lp64_linux(), second)]
            let res <- link_tus(tus, "main")
            t |> equal(res.error, "`enum e` is defined with two different enumerator lists: a.c:0 and b.c:0")
        }
    }
    t |> run("a static is renamed when another unit references its name without one of its own, or when the name is reserved") @(t : T?) {
        t |> equal(renames_of_abs(true, array<string>()), "a.c: abs -> a_abs")
        t |> equal(renames_of_abs(false, ["abs"]), "a.c: abs -> a_abs")
        t |> equal(renames_of_abs(false, array<string>()), "")
    }
    t |> run("units of two dialects, a type kind with no rule and no unit at all are refused") @(t : T?) {
        var dialects <- [unit("a.c", target_lp64_linux()), unit("b.c", target_llp64_msvc())]
        let mixed <- link_tus(dialects, "main")
        t |> equal(mixed.error, "b.c is dumped for x86_64-pc-windows-msvc, a.c for x86_64-unknown-linux-gnu")
        var odd <- [unit("a.c", target_lp64_linux(), [int_type(), CirType(k = "vector")])]
        let unknown <- link_tus(odd, "main")
        t |> equal(unknown.error, "a.c: type kind `vector` has no link rule")
        var none : array<CirTu>
        let empty_program <- link_tus(none, "main")
        t |> equal(empty_program.error, "a program needs at least one translation unit")
    }
}
