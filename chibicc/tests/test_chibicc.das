options gen2
require dastest/testing_boost public
require daslib/fio
require daslib/strings_boost
require ../sources.das
require ../../converter/tiers.das
require ../../perf/perf_lanes.das

//! The converted chibicc against the native one over the fetched sources: `-S` and `-E` of one C
//! file give the same bytes. The test skips without the fetch (`chibicc/fetch.sh`) and with a
//! checkout at another commit than `VERSIONS.md` pins.

let SAMPLE = "#include <stdarg.h>\n#define TWICE(x) ((x) + (x))\nstruct P \{ int x; char tag[3]; double d; \};\nstatic int total(int n, ...) \{\n    va_list ap;\n    va_start(ap, n);\n    int sum = 0;\n    for (int i = 0; i < n; i++) sum += va_arg(ap, int);\n    va_end(ap);\n    return sum;\n\}\nint main(void) \{\n    struct P p = \{TWICE(2), \"ab\", 1.5\};\n    switch (p.x) \{\n    case 4: return total(2, p.tag[0], (int)p.d) - 'a' - 1;\n    default: return 1;\n    \}\n\}\n"

// the commit the `chibicc:` line of VERSIONS.md pins, "" without the line
def private pinned_commit : string {
    for (line in split(fread("VERSIONS.md"), "\n")) {
        if (line |> starts_with("chibicc: ")) {
            return split(slice(line, 9), " ")[0]
        }
    }
    return ""
}

// why the fetched checkout cannot be the oracle, "" when it can
def private fetch_refusal : string {
    if (!fexist(NATIVE)) {
        return "no {NATIVE}: run chibicc/fetch.sh"
    }
    var head : string
    let rc = run_and_capture(["git", "-C", SOURCES, "rev-parse", "HEAD"], head, 30.0)
    let pin = pinned_commit()
    if (rc != 0 || empty(pin) || strip(head) != pin) {
        return "{SOURCES} is at `{strip(head)}`, VERSIONS.md pins `{pin}`: run chibicc/fetch.sh"
    }
    return ""
}

// the conversion in `root` and both compilers over the sample, mode by mode
def private compare_in(t : T?; root : string) {
    let manifest = path_join(root, "chibicc.program.json")
    fwrite(manifest, program_manifest())
    fwrite(path_join(root, "sample.c"), SAMPLE)
    let module_dirs <- [get_full_file_name("dasCRuntime"), get_full_file_name("c_runtime")]
    var out : string
    var convert <- daslang_cmd(module_dirs)
    convert |> push_from([get_full_file_name("converter/main.das"), "--", "--program", manifest, "--out", path_join(root, "chibicc"), "--target", "linux", "--sidecar", get_full_file_name(SIDECAR)])
    let converted = run_and_capture(convert, out, 600.0)
    t |> equal(converted, 0, out)
    if (converted != 0) {
        return
    }
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

[test]
def test_converted_equals_native(t : T?) {
    let refusal = fetch_refusal()
    if (!empty(refusal)) {
        t |> skip(refusal)
        return
    }
    var error : string
    let root = create_temp_directory("chibicc_convert", error)
    if (!empty(error)) {
        t |> failure(error)
        return
    }
    compare_in(t, root)
    rmdir_rec(root)
}
