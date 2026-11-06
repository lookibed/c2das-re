options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../converter/dumper_a.das

//! perf/sampler/: the library built from `sampler.c` with the pinned clang, stand-in programs run
//! under `LD_PRELOAD` (`perf/sampler/ARCHITECTURE.md` section 3), the sample file's format and
//! every way it is written or not, and `symbolize.sh`'s modes over the files.

let SAMPLER_C = "perf/sampler/sampler.c"
let SYMBOLIZE = "perf/sampler/symbolize.sh"
let STAND_IN = "perf/tests/sampler_stand_in.c"
let STAND_IN_LIB = "perf/tests/sampler_stand_in_lib.c"
let GATE_SHIM = "perf/sampler/gate_shim.c"

// `argv` run: its exit code, the merged output in `out`
def private run_argv(argv : array<string>; var out : string&) : int => run_and_capture(argv, out, 120.0)

// `argv` run, its exit code checked; the merged output
def private checked_run(t : T?; argv : array<string>) : string {
    var out : string
    let rc = run_argv(argv, out)
    t |> equal(rc, 0, "{join(argv, " ")}: {out}")
    return out
}

// `source` built by the pinned clang into `<dir>/<name>` under `flags`
def private build(t : T?; dir, name, source : string; flags : array<string>) {
    var argv <- [default_clang(), "-O2"]
    argv |> push_from(flags, ["-o", path_join(dir, name), source])
    checked_run(t, argv)
}

// the libraries and stand-ins built into `dir`
def private build_all(t : T?; dir : string) {
    let lib_flags <- ["-fPIC", "-shared"]
    build(t, dir, "libsampler.so", SAMPLER_C, lib_flags)
    build(t, dir, "libsampler_cap.so", SAMPLER_C, ["-fPIC", "-shared", "-DMAX_SAMPLES=16"])
    build(t, dir, "libsampler_small_maps.so", SAMPLER_C, ["-fPIC", "-shared", "-DMAPS_BYTES=2048", "-DMAPS_FINAL_RESERVE=512"])
    build(t, dir, "libspin.so", STAND_IN_LIB, ["-fPIC", "-shared", "-s"])
    build(t, dir, "libgate_shim.so", GATE_SHIM, ["-fPIC", "-shared", "-ldl"])
    build(t, dir, "stand_in_gettime", STAND_IN, ["-DGETTIME"])
    build(t, dir, "stand_in", STAND_IN, ["-gdwarf-4"])
    for (name, define in ["no_clock", "exit", "sleep", "fork", "dlopen"], ["NO_CLOCK", "EXIT_AFTER", "SLEEP_AFTER", "FORK", "DLOPEN"]) {
        build(t, dir, "stand_in_{name}", STAND_IN, ["-D{define}", "-ldl"])
    }
}

// `bin` (with `args`) run under `lib` at 100 us from `dir`, its sample files prefixed
// `out` in `dir` ("" leaves SAMPLER_OUT empty), with `gated` the clock gate and `env` more
// `NAME=value` words for the environment; the merged output
def private sampled_run(t : T?; dir, lib, bin, out : string; gated : bool; args : array<string>; env : string = "") : string {
    // from `dir`: an empty SAMPLER_OUT would name `.<pid>` there
    var argv <- ["env", "-C", dir, "SAMPLER_OUT={empty(out) ? "" : path_join(dir, out)}", "SAMPLER_US=100", "SAMPLER_GATE={gated ? "clock" : ""}", "LD_PRELOAD={path_join(dir, lib)}"]
    argv |> push_from([for (w in split(env, " ")); w; where !empty(w)], [path_join(dir, bin)], args)
    return checked_run(t, argv)
}

// the files in `dir` named `<prefix>.<pid>`
def private sample_files(dir, prefix : string) : array<string> {
    var found : array<string>
    dir(dir) $(name) {
        if (name |> starts_with("{prefix}.")) {
            found |> push(path_join(dir, name))
        }
    }
    return <- found
}

// the one sample file `prefix` names in `dir`, "" unless there is exactly one
def private only_file(dir, prefix : string) : string {
    let files <- sample_files(dir, prefix)
    return length(files) == 1 ? files[0] : ""
}

// the header of a sample file, `# samples N dropped D clock_calls C`; "" for no file
def private header_line(path : string) : string {
    let text = empty(path) ? "" : fread(path)
    let at = find(text, "\n")
    return at >= 0 ? slice(text, 0, at) : text
}

// the header's word at `index` as a number (2 samples, 4 dropped, 6 clock calls), -1 off-shape
def private header_number(header : string; index : int) : int {
    let words <- split(header, " ")
    return length(words) == 7 ? to_int(words[index]) : -1
}

// the count rows of a symbolize.sh table (`count percent file name`), each split into words
def private table_rows(text : string) : array<array<string>> {
    var rows : array<array<string>>
    for (ln in split(text, "\n")) {
        var inscope cols <- [for (c in split(strip(ln), " ")); c; where !empty(c)]
        if (length(cols) >= 4 && !(cols[0] |> starts_with("#"))) {
            rows |> push_clone(cols)
        }
    }
    return <- rows
}

// the first count row's count, its file and name into `file` and `name`; 0 without a row
def private top_row(text : string; var file : string&; var name : string&) : int {
    let rows <- table_rows(text)
    if (empty(rows)) {
        return 0
    }
    file = rows[0][2]
    name = rows[0][3]
    return to_int(rows[0][0])
}

var private built = false

// the scratch folder with everything built in it, once per run
def private built_dir(t : T?) : string {
    let dir = test_temp_dir()
    if (!built) {
        build_all(t, dir)
        built = true
    }
    return dir
}

[test]
def test_sampler(tt : T?) {
    let dir = built_dir(tt)
    sampled_run(tt, dir, "libsampler.so", "stand_in", "gated", true, array<string>())
    let file = only_file(dir, "gated")
    let header = header_line(file)
    let samples = header_number(header, 2)
    tt |> run("the gated run writes one file: a header, one `pc stack-top` line per sample, then the maps") @(t : T?) {
        let head <- split(header, " ")
        t |> equal(length(head), 7, "one file {file} with its header: {header}")
        return if (length(head) != 7)
        t |> equal("{head[0]} {head[1]} {head[3]} {head[5]}", "# samples dropped clock_calls")
        t |> equal(head[6], "2", "both clock() calls counted")
        t |> success(samples > 50, "{samples} samples in the window")
        let lines <- split(fread(file), "\n")
        var pairs = 0
        for (i in range(1, samples + 1)) {
            var inscope words <- [for (w in split(lines[i], " ")); w; where !empty(w)]
            pairs += length(words) == 2 ? 1 : 0
        }
        t |> equal(pairs, samples, "every sample line is two words")
        t |> equal(lines[samples + 1], "# maps")
        t |> success(lines[samples + 2] |> contains("stand_in"), "the maps name the program: {lines[samples + 2]}")
    }
    return if (samples <= 0)
    tt |> run("symbolize.sh puts most self samples in the hot function") @(t : T?) {
        let text = checked_run(t, ["bash", SYMBOLIZE, file, "--top", "5"])
        var at, name : string
        let count = top_row(text, at, name)
        t |> equal(name, "hot_leaf", text)
        t |> success(count * 10 >= samples * 8, "{count} of {samples} in hot_leaf: {text}")
    }
    tt |> run("--callers names the caller of a frameless leaf through the stack-top word") @(t : T?) {
        let text = checked_run(t, ["bash", SYMBOLIZE, file, "--callers", "hot_leaf", "--top", "5"])
        var at, name : string
        let count = top_row(text, at, name)
        t |> equal(name, "hot_caller", text)
        t |> success(count * 10 >= samples * 8, "{count} of {samples} name hot_caller: {text}")
    }
    tt |> run("--addr counts one function's samples per instruction and its share of all") @(t : T?) {
        let text = checked_run(t, ["bash", SYMBOLIZE, file, "--addr", "hot_leaf"])
        let lines <- [for (l in split(text, "\n")); strip(l); where !empty(strip(l)) && !(l |> starts_with("#"))]
        t |> success(length(lines) >= 2, text)
        t |> success(length([for (l in lines); l; where l |> ends_with("of all")]) == 1, text)
    }
    tt |> run("--dso keeps the samples of the mapped files it names") @(t : T?) {
        let kept <- table_rows(checked_run(t, ["bash", SYMBOLIZE, file, "--dso", "stand_in"]))
        var others = 0
        for (r in kept) {
            others += r[2] != "stand_in" ? 1 : 0
        }
        t |> success(!empty(kept) && others == 0, "{kept}")
        t |> equal(length(table_rows(checked_run(t, ["bash", SYMBOLIZE, file, "--dso", "no_such_file"]))), 0)
    }
    tt |> run("--lines maps one function's samples to source lines of a -g build") @(t : T?) {
        let text = checked_run(t, ["bash", SYMBOLIZE, file, "--lines", "hot_leaf"])
        t |> success(text |> contains("sampler_stand_in.c:"), text)
    }
    tt |> run("an unknown flag exits 2") @(t : T?) {
        var out : string
        t |> equal(run_argv(["bash", SYMBOLIZE, file, "--nope"], out), 2, out)
    }
}

[test]
def test_sampler_writes(tt : T?) {
    let dir = built_dir(tt)
    sampled_run(tt, dir, "libsampler.so", "stand_in", "full_maps", true, array<string>())
    let file = only_file(dir, "full_maps")
    tt |> run("a gated run that never calls clock() writes no file") @(t : T?) {
        sampled_run(t, dir, "libsampler.so", "stand_in_no_clock", "never", true, array<string>())
        t |> equal(length(sample_files(dir, "never")), 0)
    }
    tt |> run("an empty or unset SAMPLER_OUT samples nothing and writes nothing") @(t : T?) {
        let before <- sample_files(dir, "")
        sampled_run(t, dir, "libsampler.so", "stand_in", "", false, array<string>())
        checked_run(t, ["env", "-C", dir, "-u", "SAMPLER_OUT", "LD_PRELOAD={path_join(dir, "libsampler.so")}", path_join(dir, "stand_in")])
        t |> equal(length(sample_files(dir, "")), length(before))
    }
    tt |> run("ungated, the file is written at exit, the default period and one of 0 sampling too") @(t : T?) {
        sampled_run(t, dir, "libsampler.so", "stand_in", "ungated", false, array<string>())
        t |> success(header_number(header_line(only_file(dir, "ungated")), 2) > 0, "ungated at 100 us")
        let lib = path_join(dir, "libsampler.so")
        for (period in ["", "SAMPLER_US=0"]) {
            let prefix = empty(period) ? "default_us" : "zero_us"
            checked_run(t, ["env", "-u", "SAMPLER_US", "SAMPLER_OUT={path_join(dir, prefix)}", period == "" ? "C2DAS=1" : period, "LD_PRELOAD={lib}", path_join(dir, "stand_in")])
            t |> success(header_number(header_line(only_file(dir, prefix)), 2) > 0, "{prefix}: samples at 250 us")
        }
    }
    tt |> run("past MAX_SAMPLES the samples are counted as dropped") @(t : T?) {
        sampled_run(t, dir, "libsampler_cap.so", "stand_in", "capped", true, array<string>())
        let head = header_line(only_file(dir, "capped"))
        t |> equal(header_number(head, 2), 16, head)
        t |> success(header_number(head, 4) > 0, head)
    }
    tt |> run("a run that leaves through _exit writes its file, gated at the second clock() and ungated in _exit") @(t : T?) {
        sampled_run(t, dir, "libsampler.so", "stand_in_exit", "exit_gated", true, array<string>())
        t |> success(header_number(header_line(only_file(dir, "exit_gated")), 2) > 0, "gated")
        sampled_run(t, dir, "libsampler.so", "stand_in_exit", "exit_ungated", false, array<string>())
        t |> success(header_number(header_line(only_file(dir, "exit_ungated")), 2) > 0, "ungated")
    }
    tt |> run("the timer stops with the file: a sleep after the window is not interrupted") @(t : T?) {
        let out = sampled_run(t, dir, "libsampler.so", "stand_in_sleep", "sleep", true, array<string>())
        t |> success(out |> contains("sleep rc 0"), out)
    }
    tt |> run("a forked child writes no file of its own") @(t : T?) {
        sampled_run(t, dir, "libsampler.so", "stand_in_fork", "fork", false, array<string>())
        t |> equal(length(sample_files(dir, "fork")), 1)
    }
    tt |> run("a library dlclosed in the window keeps its PCs; past its last sized symbol they are `?`") @(t : T?) {
        sampled_run(t, dir, "libsampler.so", "stand_in_dlopen", "dlopen", true, [path_join(dir, "libspin.so")])
        let dl_file = only_file(dir, "dlopen")
        let dl_samples = header_number(header_line(dl_file), 2)
        let text = checked_run(t, ["bash", SYMBOLIZE, dl_file, "--top", "5"])
        var at, name : string
        let count = top_row(text, at, name)
        t |> equal(at, "libspin.so", text)
        t |> equal(name, "?", text)
        t |> success(dl_samples > 0 && count * 10 >= dl_samples * 8, "{count} of {dl_samples}: {text}")
    }
    tt |> run("maps snapshots past the buffer are marked truncated") @(t : T?) {
        sampled_run(t, dir, "libsampler_small_maps.so", "stand_in_dlopen", "small_maps", true, [path_join(dir, "libspin.so")])
        t |> success(fread(only_file(dir, "small_maps")) |> contains("\n# maps truncated: "), "the marker")
        t |> success(!(fread(file) |> contains("# maps truncated")), "no marker in the full buffer")
    }
}

// the shim's window over `stand_in_gettime` under `env` (the SHIM_* words): the sample file's
// header and the function holding most of its samples
def private shim_window(t : T?; dir, out, env : string; var name : string&) : string {
    let libs = "libsampler.so:{path_join(dir, "libgate_shim.so")}"
    sampled_run(t, dir, libs, "stand_in_gettime", out, true, array<string>(), env)
    let file = only_file(dir, out)
    let header = header_line(file)
    var at : string
    let count = top_row(checked_run(t, ["bash", SYMBOLIZE, file, "--top", "5"]), at, name)
    t |> success(count * 10 >= header_number(header, 2) * 8, "{count} of {header}: {name}")
    return header
}

[test]
def test_gate_shim(tt : T?) {
    let dir = built_dir(tt)
    tt |> run("gate_shim.c makes the named caller's SHIM_OPEN-th and SHIM_CLOSE-th clock_gettime the gate's clock() pair") @(t : T?) {
        var name : string
        let header = shim_window(t, dir, "shim_hot", "SHIM_CALLER=stand_in_gettime SHIM_OPEN=2 SHIM_CLOSE=3", name)
        t |> equal(header_number(header, 6), 2, "two clock() calls seen: {header}")
        t |> equal(name, "hot_leaf", "the window between the second and the third call")
        shim_window(t, dir, "shim_cold", "SHIM_CALLER=stand_in_gettime SHIM_OPEN=1 SHIM_CLOSE=2", name)
        t |> equal(name, "cold_leaf", "the window between the first and the second call")
    }
    tt |> run("SHIM_CALLER is a comma-separated list, any entry matching; the window defaults to calls 1 and 2") @(t : T?) {
        var name : string
        let header = shim_window(t, dir, "shim_list", "SHIM_CALLER=no_such_caller,stand_in_gettime", name)
        t |> equal(header_number(header, 6), 2, "two clock() calls seen: {header}")
        t |> equal(name, "cold_leaf", "the default window, the first two calls")
    }
    tt |> run("a caller SHIM_CALLER does not name, or no SHIM_CALLER at all, never opens the gate: no file, a clean exit") @(t : T?) {
        let libs = "libsampler.so:{path_join(dir, "libgate_shim.so")}"
        sampled_run(t, dir, libs, "stand_in_gettime", "shim_none", true, array<string>(), "SHIM_CALLER=no_such_caller")
        t |> equal(length(sample_files(dir, "shim_none")), 0)
        sampled_run(t, dir, libs, "stand_in_gettime", "shim_unset", true, array<string>())
        t |> equal(length(sample_files(dir, "shim_unset")), 0)
    }
}
