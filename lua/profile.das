options gen2

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/dumper_a.das
require sources

//! The profile the source layout's cycle cut weighs its edges by (`ARCHITECTURE.md` section 5):
//! the native interpreter built by the pinned clang with `-finstrument-functions` and a counting
//! runtime, run over the release's test suite and the benchmark scripts, every call from one file
//! to a function another file defines counted by the callee and the caller's file, written to
//! `lua/lua.profile.json`. Run from the repository root.

let WORK = "lua/work/profile"
let PROFILE = "lua/lua.profile.json"
let TESTS = "lua/fetch/lua-5.4.8-tests"
let BENCH <- ["fib", "binary_trees", "nbody", "spectral_norm"]

// the counting runtime: each (callee, call site) pair counted in an open-addressed table, the table
// written at exit, one `<callee> <site> <count>` line each, appended to the file
// `C2DAS_PROFILE_OUT` names
let COUNTER = "#include <stdio.h>\n#include <stdlib.h>\n#define SLOTS (1 << 20)\nstatic void *fns[SLOTS];\nstatic void *sites[SLOTS];\nstatic unsigned long long counts[SLOTS];\nstatic int registered;\n__attribute__((no_instrument_function)) static void dump(void) \{\n    const char *path = getenv(\"C2DAS_PROFILE_OUT\");\n    FILE *f = fopen(path ? path : \"profile.raw\", \"a\");\n    if (!f) return;\n    for (int i = 0; i < SLOTS; i++) if (counts[i]) fprintf(f, \"%p %p %llu\\n\", fns[i], sites[i], counts[i]);\n    fclose(f);\n\}\n__attribute__((no_instrument_function)) void __cyg_profile_func_enter(void *fn, void *site) \{\n    if (!registered) \{ registered = 1; atexit(dump); \}\n    unsigned long long h = ((unsigned long long)(size_t)fn * 0x9E3779B97F4A7C15ull) ^ (unsigned long long)(size_t)site;\n    h ^= h >> 29;\n    size_t i = h & (SLOTS - 1);\n    while (counts[i] && (fns[i] != fn || sites[i] != site)) i = (i + 1) & (SLOTS - 1);\n    fns[i] = fn;\n    sites[i] = site;\n    counts[i]++;\n\}\n__attribute__((no_instrument_function)) void __cyg_profile_func_exit(void *fn, void *site) \{\n    (void)fn;\n    (void)site;\n\}\n"

[CommandLineArgs]
struct Args {
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
    @clarg_doc = "the binutils nm that reads the symbol tables, at the version VERSIONS.md pins"
    nm : string = "nm"
}

// `nm --version`'s first line against the version the `nm:` line of VERSIONS.md pins: "" when they
// agree, else the refusal; a missing or failing `nm` prints no version and is refused
def private nm_pin_mismatch(nm : string) : string {
    var pin = ""
    for (line in split(fread("VERSIONS.md"), "\n")) {
        if (line |> starts_with("nm: ")) {
            pin = split(slice(line, 4), " ")[0]
        }
    }
    var out : string
    let rc = run_and_capture([nm, "--version"], out, 30.0)
    let first = split(out, "\n")[0]
    let words <- split(strip(first), " ")
    let version = rc == 0 ? words[length(words) - 1] : ""
    return version == pin ? "" : "`{nm} --version` printed `{strip(first)}` (exit {rc}), VERSIONS.md pins nm `{pin}`"
}

// `argv` run, its output logged when it fails; whether it exited 0
def private ran(argv : array<string>; timeout : float) : bool {
    var out : string
    let rc = run_and_capture(argv, out, timeout)
    if (rc != 0) {
        to_log(LOG_ERROR, "lua: profile: {join(argv, " ")} exited {rc}:\n{out}\n")
    }
    return rc == 0
}

// the text symbols of an object or a binary, `nm -n`: each address with its name; a failed `nm`
// or one that lists no text symbol is logged and gives none
def private text_symbols(nm, path : string) : array<tuple<at : uint64; name : string>> {
    var out : string
    let rc = run_and_capture([nm, "-n", path], out, 60.0)
    var syms : array<tuple<at : uint64; name : string>>
    if (rc != 0) {
        to_log(LOG_ERROR, "lua: profile: {nm} -n {path} exited {rc}:\n{out}\n")
        return <- syms
    }
    for (ln in split(out, "\n")) {
        var inscope parts <- split(strip(ln), " ")
        if (length(parts) == 3 && (parts[1] == "T" || parts[1] == "t")) {
            syms |> push((at = to_uint64(parts[0], true), name = parts[2]))
        }
    }
    if (empty(syms)) {
        to_log(LOG_ERROR, "lua: profile: {nm} -n {path} lists no text symbol\n")
    }
    return <- syms
}

// the function holding address `at`: the last symbol at or below it
def private holder(syms : array<tuple<at : uint64; name : string>>; at : uint64) : string {
    var lo = 0
    var hi = length(syms) - 1
    var found = ""
    while (lo <= hi) {
        let mid = (lo + hi) / 2
        if (syms[mid].at <= at) {
            found = syms[mid].name
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return found
}

// the calls `raw` counts that cross files, by callee and the caller's file, written to `PROFILE`;
// `syms` resolves each address to its function, `unit_of` each function to its file
def private write_profile(syms : array<tuple<at : uint64; name : string>>; raw : string; unit_of : table<string; string>) {
    var counts : table<string; table<string; int64>>
    for (ln in split(fread(raw), "\n")) {
        var inscope parts <- split(strip(ln), " ")
        if (length(parts) == 3) {
            let callee = holder(syms, to_uint64(slice(parts[0], 2), true))
            let caller = holder(syms, to_uint64(slice(parts[1], 2), true))
            let to = unit_of?[callee] ?? ""
            let from = unit_of?[caller] ?? ""
            if (!empty(to) && !empty(from) && to != from) {
                let before = counts?[callee]?[from] ?? 0l
                counts[callee][from] = before + to_int64(parts[2])
            }
        }
    }
    var callees <- [for (k in keys(counts)); k]
    sort(callees)
    var lines : array<string>
    lines |> reserve(length(callees))
    for (callee in callees) {
        var inscope froms : array<string>
        counts |> get(callee) $(by_unit) {
            froms |> push_from([for (from, n in keys(by_unit), values(by_unit)); "{write_json(JV(from))}: {n}"])
        }
        sort(froms)
        let row = join(froms, ", ")
        lines |> push("  {write_json(JV(callee))}: \{{row}\}")
    }
    fwrite(PROFILE, "\{\n{join(lines, ",\n")}\n\}\n")
    to_log(LOG_INFO, "lua: profile: {length(callees)} functions called across files, written to {PROFILE}\n")
}

[export, arch(at="ARCHITECTURE.md#profile")]
def main : int {
    var args = Args()
    let early = cli_prologue(args, "lua/profile.das")
    if (early >= 0) {
        return early
    }
    let pin_error = nm_pin_mismatch(args.nm)
    if (!empty(pin_error)) {
        to_log(LOG_ERROR, "lua: profile: {pin_error}\n")
        return 1
    }
    mkdir_rec(WORK)
    let counter = path_join(WORK, "counter.c")
    fwrite(counter, COUNTER)
    let clang = default_clang()
    if (!ran([clang, "-O0", "-w", "-c", "-o", path_join(WORK, "counter.o"), counter], 120.0)) {
        return 1
    }
    // each file compiled apart, so its functions name its file
    var unit_of : table<string; string>
    var objects : array<string>
    objects |> reserve(length(program_sources("lua")))
    for (c_path in program_sources("lua")) {
        let stem = file_stem(c_path)
        let obj = path_join(WORK, "{stem}.o")
        if (!ran([clang, "-O0", "-w", "-funsigned-char", "-fno-pie", "-finstrument-functions", "-c", "-o", obj, c_path], 300.0)) {
            return 1
        }
        objects |> push(obj)
        var inscope file_syms <- text_symbols(args.nm, obj)
        if (empty(file_syms)) {
            return 1
        }
        for (s in file_syms) {
            unit_of[s.name] = stem
        }
    }
    let bin = path_join(get_full_file_name(WORK), "lua_profiled")
    var link <- [clang, "-no-pie", "-o", bin]
    link |> push_from(objects, [path_join(WORK, "counter.o"), "-lm"])
    if (!ran(link, 300.0)) {
        return 1
    }
    let raw = path_join(get_full_file_name(WORK), "profile.raw")
    remove(raw)
    set_env_variable("C2DAS_PROFILE_OUT", raw)
    var ok = ran(["sh", "-c", "cd \"$0\" && exec \"$@\"", TESTS, bin, "-e", "_port=true", "all.lua"], 3600.0)
    for (name in BENCH) {
        ok = ran([bin, get_full_file_name("ports/lua/bench/{name}.lua")], 600.0) && ok
    }
    if (!ok) {
        return 1
    }
    let syms <- text_symbols(args.nm, bin)
    if (empty(syms)) {
        return 1
    }
    write_profile(syms, raw, unit_of)
    return 0
}
