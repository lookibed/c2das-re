options gen2
require dastest/testing_boost public
require daslib/fio
require ../sources.das
require ../../converter/tiers.das
require ../../perf/perf_lanes.das

//! The converted chibicc against the native one over the fetched sources: `-S` and `-E` of one C
//! file give the same bytes. Without the fetch (`chibicc/fetch.sh`) the test logs that and passes.

let SAMPLE = "#include <stdarg.h>\n#define TWICE(x) ((x) + (x))\nstruct P \{ int x; char tag[3]; double d; \};\nstatic int total(int n, ...) \{\n    va_list ap;\n    va_start(ap, n);\n    int sum = 0;\n    for (int i = 0; i < n; i++) sum += va_arg(ap, int);\n    va_end(ap);\n    return sum;\n\}\nint main(void) \{\n    struct P p = \{TWICE(2), \"ab\", 1.5\};\n    switch (p.x) \{\n    case 4: return total(2, p.tag[0], (int)p.d) - 'a' - 1;\n    default: return 1;\n    \}\n\}\n"

def private scratch(name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    return empty(error) ? dir : ""
}

[test]
def test_converted_equals_native(t : T?) {
    if (!fexist(NATIVE)) {
        to_log(LOG_WARNING, "test_chibicc: no {NATIVE}; run chibicc/fetch.sh\n")
        return
    }
    let root = scratch("chibicc_convert")
    t |> success(!empty(root))
    let manifest = path_join(root, "chibicc.program.json")
    fwrite(manifest, program_manifest())
    fwrite(path_join(root, "sample.c"), SAMPLE)
    let module_dirs <- [get_full_file_name("dasCRuntime"), get_full_file_name("c_runtime")]
    var out : string
    var convert <- daslang_cmd(module_dirs)
    convert |> push_from([get_full_file_name("converter/main.das"), "--", "--program", manifest, "--out", path_join(root, "chibicc"), "--target", "linux", "--sidecar", get_full_file_name(SIDECAR)])
    let converted = run_and_capture(convert, out, 600.0)
    t |> equal(converted, 0, out)
    // both run in the checkout, where `./include` holds chibicc's own headers
    let cwd = get_full_file_name(SOURCES)
    for (mode in ["-S", "-E"]) {
        let native_out = path_join(root, "native{mode}.txt")
        let das_out = path_join(root, "das{mode}.txt")
        var native_log : string
        // by its name in the folder: chibicc's first include folder is `include/` beside `argv[0]`
        let native_rc = run_and_capture(in_folder(cwd, ["./chibicc", mode, "-o", native_out, path_join(root, "sample.c")]), native_log, 60.0)
        t |> equal(native_rc, 0, native_log)
        var das_log : string
        let rc = run_tier(path_join(root, "chibicc/main.das"), "interp", root, das_log, module_dirs, 300.0, array<string>(), [mode, "-o", das_out, path_join(root, "sample.c")], array<string>(), cwd)
        t |> equal(rc, 0, das_log)
        t |> success(!empty(fread(native_out)), "native {mode} wrote nothing")
        t |> equal(fread(das_out), fread(native_out), "{mode}")
    }
}
