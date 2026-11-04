options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../converter/dumper_a.das

//! perf/sampler/: the library built from `sampler.c` with the pinned clang, a stand-in program
//! run under `LD_PRELOAD` with `SAMPLER_GATE=clock`, the sample file's format, `symbolize.sh`'s
//! self samples and `--callers` on a frameless leaf, and no file when the gate never opens.

let SAMPLER_C = "perf/sampler/sampler.c"
let SYMBOLIZE = "perf/sampler/symbolize.sh"
let STAND_IN = "perf/tests/sampler_stand_in.c"

// `argv` run, its exit code checked; the merged output
def private checked_run(t : T?; argv : array<string>) : string {
    var out : string
    let rc = run_and_capture(argv, out, 120.0)
    t |> equal(rc, 0, "{join(argv, " ")}: {out}")
    return out
}

// the library and the two stand-ins built into `dir`
def private build_all(t : T?; dir : string) {
    checked_run(t, [default_clang(), "-O2", "-fPIC", "-shared", "-o", path_join(dir, "libsampler.so"), SAMPLER_C, "-ldl", "-lrt"])
    checked_run(t, [default_clang(), "-O2", "-o", path_join(dir, "stand_in"), STAND_IN])
    checked_run(t, [default_clang(), "-O2", "-DNO_CLOCK", "-o", path_join(dir, "stand_in_no_clock"), STAND_IN])
}

// `bin` run under the sampler at 100 us with the clock gate, its sample files prefixed `out`
def private sampled_run(t : T?; dir, bin, out : string) {
    checked_run(t, ["env", "SAMPLER_OUT={path_join(dir, out)}", "SAMPLER_US=100", "SAMPLER_GATE=clock", "LD_PRELOAD={path_join(dir, "libsampler.so")}", path_join(dir, bin)])
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

// the first count line of a symbolize.sh table (`count percent file name`): its count and name
def private top_row(text : string; var name : string&) : int {
    for (ln in split(text, "\n")) {
        var inscope cols <- [for (c in split(strip(ln), " ")); c; where !empty(c)]
        if (length(cols) >= 4 && !(cols[0] |> starts_with("#"))) {
            name = cols[3]
            return to_int(cols[0])
        }
    }
    return 0
}

// the header of a sample file, `# samples N dropped D clock_calls C`; "" for no file
def private header_line(path : string) : string {
    let text = empty(path) ? "" : fread(path)
    let at = find(text, "\n")
    return at >= 0 ? slice(text, 0, at) : text
}

// the sample count a header line names, 0 for a line of another shape
def private header_samples(header : string) : int {
    let words <- split(header, " ")
    return length(words) == 7 ? to_int(words[2]) : 0
}

[test]
def test_sampler(tt : T?) {
    let dir = test_temp_dir()
    build_all(tt, dir)
    sampled_run(tt, dir, "stand_in", "gated")
    let files <- sample_files(dir, "gated")
    let file = length(files) == 1 ? files[0] : ""
    let header = header_line(file)
    let samples = header_samples(header)
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
    return if (samples == 0)
    tt |> run("symbolize.sh puts most self samples in the hot function") @(t : T?) {
        let text = checked_run(t, ["bash", SYMBOLIZE, file, "--top", "5"])
        var name : string
        let count = top_row(text, name)
        t |> equal(name, "hot_leaf", text)
        t |> success(count * 10 >= samples * 8, "{count} of {samples} in hot_leaf: {text}")
    }
    tt |> run("--callers names the caller of a frameless leaf through the stack-top word") @(t : T?) {
        let text = checked_run(t, ["bash", SYMBOLIZE, file, "--callers", "hot_leaf", "--top", "5"])
        var name : string
        let count = top_row(text, name)
        t |> equal(name, "hot_caller", text)
        t |> success(count * 10 >= samples * 8, "{count} of {samples} name hot_caller: {text}")
    }
    tt |> run("a gated run that never calls clock() writes no file") @(t : T?) {
        sampled_run(t, dir, "stand_in_no_clock", "never")
        t |> equal(length(sample_files(dir, "never")), 0)
    }
}
