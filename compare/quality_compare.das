options gen2

module quality_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/pipeline.das
require ../suites/suite_runner.das
require ../perf/perf_compose.das
require ../suites/csmith/generate.das
require ../metrics/readability_file.das
require ../metrics/readability_count.das
require rust_translator
require suite_compare
require perf_compare

//! The cleanliness and size of both translators' output over the inputs both translated: each
//! side's module counted by the readability metric's counters, its files and non-blank lines, the
//! totals per suite and over all, and a fixed sample of functions side by side
//! (`compare/ARCHITECTURE.md`).

let QUALITY_WORK = "compare/work/quality"

//! the Rust statuses of a suite case whose translation compiled under daslang
let COMPILED_STATUSES <- ["pass", "exit", "output"]

//! the group of a kernel's key: a kernel `k` of the perf section is the key `perf/k`
let PERF_GROUP = "perf"

//! The functions shown side by side: a key, then the C names of its functions.
let SAMPLES <- [("perf/fib_loop", ["fibI", "kernel_run"]), ("perf/sieve", ["kernel_run"]), ("perf/str_copy", ["copy_text", "work"]), ("perf/switch_local", ["step", "kernel_run"]), ("c_testsuite/00156", ["main"]), ("c_testsuite/00205", ["main"])]

//! One side of a key: `status` `ok` when it was measured, else why not (`convert` or `refused`,
//! `compile` when the counters' compile failed, `crash` or `timeout` for a worker); `error` the
//! reason; the count of `.das` and `.das.inc` files, their non-blank lines; on the Rust side the
//! lines of its emitted runtime (`runtime_lines`) and of its `c2da_` declarations derived from the
//! program (`program_c2da_lines`), both 0 on ours; and the counters.
struct SideQuality {
    status : string
    error : string
    files : int
    lines : int
    runtime_lines : int
    program_c2da_lines : int
    counts : table<string; int>
}

//! One sampled function: its key, its C name and each side's text, "" when a side has none.
struct FunctionPair {
    key : string
    name : string
    ours : string
    rust : string
}

//! What a worker measures of one key; `rust_c2da` the non-blank lines of each `c2da_` declaration
//! of the Rust side, which the driver splits into runtime and program code.
struct KeyQuality {
    ours : SideQuality
    rust : SideQuality
    functions : array<FunctionPair>
    rust_c2da : table<string; int>
}

//! The keys of the corpus, sorted, the ones holding `filter`: per suite of the capture's `suites`
//! section the ids whose Rust status is in `COMPILED_STATUSES` and which `listed[suite]` holds, and
//! per kernel of its `perf` section that the Rust side ran, `perf/<kernel>`.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def quality_corpus(results : JsonValue?; listed : table<string; table<string>>; filter : string) : array<string> {
    var corpus : array<string>
    let suites = results?["suites"]
    if (suites != null && suites.value is _object) {
        for (suite, entry in keys(suites.value as _object), values(suites.value as _object)) {
            let outcomes = entry?["outcomes"]
            let n = outcomes != null && outcomes.value is _array ? length(outcomes.value as _array) : 0
            listed |> get(suite) $(ids) {
                for (i in range(n)) {
                    let id = outcomes?[i]?["id"] ?? ""
                    if (has_value(COMPILED_STATUSES, outcomes?[i]?["status"] ?? "") && key_exists(ids, id)) {
                        corpus |> push("{suite}/{id}")
                    }
                }
            }
        }
    }
    let kernels = results?["perf"]?["kernels"]
    if (kernels != null && kernels.value is _object) {
        for (k, entry in keys(kernels.value as _object), values(kernels.value as _object)) {
            if ((entry?["rust"]?["status"] ?? "") == "ran") {
                corpus |> push("{PERF_GROUP}/{k}")
            }
        }
    }
    var picked <- [for (k in corpus); k; where empty(filter) || k |> contains(filter)]
    picked |> sort()
    return <- picked
}

//! The corpus of the capture at `path` and the suites' ratchets, the keys holding `filter`; none,
//! with `error` set, when the file present there is not JSON.
def quality_corpus_of(path, filter : string; var error : string&) : array<string> {
    if (!fexist(path)) {
        error = "no capture at {path}: the corpus comes from its suites and perf sections"
        return <- array<string>()
    }
    let results = read_json(fread(path), error)
    if (results == null) {
        error = "cannot read {path}: {error}"
        return <- array<string>()
    }
    var listed : table<string; table<string>>
    for (spec in compare_suites()) {
        var inscope r <- read_ratchet(spec.expected_pass, spec.skip_ledger)
        listed[spec.name] <- r.expected_set
    }
    return <- quality_corpus(results, listed, filter)
}

//! The C file of `key` and the clang arguments of its Rust translation: a suite case's file, a
//! csmith seed's program found under `csmith_dir` or generated into `work`, or a kernel composed by
//! the method into `work`; "" with `error` set when there is none.
def quality_source(key, work : string; var clang_args : array<string>; var error : string&; csmith_dir : string) : string {
    let group = text_before(key, "/")
    let id = slice(key, length(group) + 1)
    if (group == "c_testsuite") {
        return "{C_TESTSUITE_TESTS}/{id}.c"
    } elif (group == "gcc_torture") {
        return "{GCC_TORTURE_TESTS}/{id}.c"
    } elif (group == CSMITH) {
        let prog = csmith_source(id, csmith_dir, work)
        error = csmith_error(prog)
        return prog.c_path
    }
    for (k in perf_kernels("")) {
        if (group == PERF_GROUP && k.key == id) {
            clang_args |> push(METHOD_NATIVE_DEFINE)
            return write_method_composed(k.dir, k.name, work)
        }
    }
    error = "no input is keyed {key}"
    return ""
}

//! Why a csmith program could not be had, "" when it was.
def csmith_error(prog : CsmithProgram) : string => prog.timed_out ? "csmith took longer than {int(CSMITH_TIMEOUT)} s" : prog.error

//! The seconds the Rust translator may take over `key`: a kernel's limit, else a suite case's.
def quality_translate_timeout(key : string) : float => group_of(key) == PERF_GROUP ? PERF_TRANSLATE_TIMEOUT : TRANSLATE_TIMEOUT

//! The folder where the csmith suite's own run leaves its programs, which a key reuses.
let CSMITH_PROGRAMS = "suites/csmith/work"

//! Why `--quality` over `corpus` cannot start, "" when it can: the input of a suite of `specs` the
//! corpus holds a key of is missing.
def quality_missing(corpus : array<string>; specs : array<SuiteSpec>) : string {
    for (spec in specs) {
        let used = find_index_if(corpus, $(k) => group_of(k) == spec.name) >= 0
        if (used && !fexist(input_of(spec))) {
            return "{input_of(spec)} is missing: run suites/{spec.name}/fetch.sh"
        }
    }
    return ""
}

//! The non-blank lines of `text`.
def nonblank_lines(text : string) : int => length([for (ln in split(text, "\n")); ln; where !empty(strip(ln))])

//! A side measured: the files and non-blank lines of `files`, the counters over `entry`; `compile`
//! with the first line of the compiler's output when `entry` does not compile as written.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def measure_side(files : array<string>; entry : string) : SideQuality {
    var side = SideQuality(status = "ok", files = length(files))
    for (f in files) {
        side.lines += nonblank_lines(fread(f))
    }
    var mc <- count_module(entry)
    if (!empty(mc.error)) {
        side.status = "compile"
        side.error = first_line(strip(mc.error))
    }
    side.counts <- mc.counts
    return <- side
}

//! the words that open a top-level declaration
let DECLARATION_WORDS <- ["def ", "var ", "let ", "struct ", "enum ", "typedef "]

//! The name a top-level declaration line `line` declares: the word after `def`, `var`, `let`,
//! `struct` or `enum` and an optional `private ` or `public `; "" for any other line.
def declared_name(line : string) : string {
    let word = find_index_if(DECLARATION_WORDS, $(w) => line |> starts_with(w))
    if (word < 0) {
        return ""
    }
    let after = slice(line, length(DECLARATION_WORDS[word]))
    let rest = after |> starts_with("private ") ? slice(after, 8) : after |> starts_with("public ") ? slice(after, 7) : after
    var n = 0
    peek_data(rest) $(bytes) {
        while (n < length(bytes) && (is_alnum(int(bytes[n])) || int(bytes[n]) == '_')) {
            n++
        }
    }
    return slice(rest, 0, n)
}

//! the prefix of every name the Rust translator declares of its own
let C2DA_PREFIX = "c2da_"

//! the prefixes of the Rust translator's emitted runtime: its heap and its libc helpers
let RUNTIME_PREFIXES <- ["c2da_rt_", "c2da_std_"]

//! The non-blank lines of each top-level declaration of the module `text` whose name starts with
//! `C2DA_PREFIX`, by name: each from its first annotation line to the line before the next
//! declaration's first line (a `typedef` is one), the last to the end of the text.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def c2da_blocks(text : string) : table<string; int> {
    var blocks : table<string; int>
    let lines <- split(text, "\n")
    let n = length(lines)
    var current = ""
    for (i in range(n)) {
        let annotated = i > 0 && lines[i - 1] |> starts_with("[")
        if (!annotated) {
            var decl = i
            while (decl < n && lines[decl] |> starts_with("[")) {
                decl++
            }
            let name = decl < n ? declared_name(lines[decl]) : ""
            if (!empty(name)) {
                current = name |> starts_with(C2DA_PREFIX) ? name : ""
            }
        }
        if (!empty(current) && !empty(strip(lines[i]))) {
            blocks[current] = (blocks?[current] ?? 0) + 1
        }
    }
    return <- blocks
}

//! Whether the `c2da_` declaration `name` is the Rust translator's emitted runtime: a name with a
//! prefix of `RUNTIME_PREFIXES`, or one `every_module` holds, the names every Rust module declares.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def is_runtime(name : string; every_module : table<string>) : bool => find_index_if(RUNTIME_PREFIXES, $(p) => name |> starts_with(p)) >= 0 || key_exists(every_module, name)

//! Each Rust side of `entries` split: `runtime_lines` the lines of its `c2da_` declarations
//! `is_runtime` holds, `program_c2da_lines` the rest; the names every module declares are those the
//! `rust_c2da` of every entry measured `ok` on the Rust side holds.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def split_runtime(var entries : table<string; KeyQuality>) {
    var modules = 0
    var declared : table<string; int>
    for (q in values(entries)) {
        if (q.rust.status == "ok") {
            modules++
            for (name in keys(q.rust_c2da)) {
                declared[name] = (declared?[name] ?? 0) + 1
            }
        }
    }
    let every_module <- {for (name, count in keys(declared), values(declared)); name; where count == modules}
    for (q in values(entries)) {
        q.rust.runtime_lines = 0
        q.rust.program_c2da_lines = 0
        for (name, lines in keys(q.rust_c2da), values(q.rust_c2da)) {
            if (is_runtime(name, every_module)) {
                q.rust.runtime_lines += lines
            } else {
                q.rust.program_c2da_lines += lines
            }
        }
    }
}

//! Whether the daslang function `das_name` of `side` (`ours` or `rust`) is the C function `c_name`:
//! the same name, our TU-qualified `<stem>__<name>` of a static, or C's `main` as each side renames
//! it, `c_main` and `main_0`.
[arch(at="ARCHITECTURE_QUALITY.md#side-by-side")]
def is_c_function(das_name, c_name, side : string) : bool {
    if (c_name == "main") {
        return das_name == (side == "ours" ? "c_main" : "main_0")
    }
    return das_name == c_name || (side == "ours" && das_name |> ends_with("__{c_name}"))
}

//! The text of the C function `c_name` in the daslang module `text` of `side`: the annotation lines
//! right above its `def` line, the `def` line, and every line after it up to the first `}` at
//! column 0, or the `def` line alone when it does not end in `{`; "" when no function matches.
[arch(at="ARCHITECTURE_QUALITY.md#side-by-side")]
def function_text(text, c_name, side : string) : string {
    let lines <- split(text, "\n")
    let n = length(lines)
    for (at in range(n)) {
        let name = lines[at] |> starts_with("def ") ? declared_name(lines[at]) : ""
        if (empty(name) || !is_c_function(name, c_name, side)) {
            continue
        }
        var first = at
        while (first > 0 && lines[first - 1] |> starts_with("[")) {
            first--
        }
        var last = at
        if (lines[at] |> ends_with("\{")) {
            while (last + 1 < n && !(lines[last] |> starts_with("\}"))) {
                last++
            }
        }
        return join([for (i in range(first, last + 1)); lines[i]], "\n")
    }
    return ""
}

//! Our side of `c_path`: converted under `linux` into `out_dir` and measured; `convert` with the
//! error's first line when the conversion fails. `das_path` is the module, "" without one.
def ours_quality(c_path, out_dir : string; var das_path : string&) : SideQuality {
    let res <- convert(c_path, out_dir, "linux")
    if (!res.ok) {
        return SideQuality(status = "convert", error = first_line(res.error))
    }
    das_path = res.das_path
    return <- measure_side([res.das_path], res.das_path)
}

//! The Rust side of `c_path`: translated by `bin` into `out_dir` with `clang_args` within `timeout`
//! seconds and measured; `refused` with the translator's error when it fails or no module defines
//! `main`. `entry` is the module daslang runs, "" without one; `c2da` gets the lines of each
//! `c2da_` declaration of its modules.
def rust_quality(bin, c_path, out_dir : string; clang_args : array<string>; timeout : float; var entry : string&; var c2da : table<string; int>) : SideQuality {
    let no_flags : array<string>
    let t <- translate_file(bin, c_path, out_dir, no_flags, clang_args, timeout)
    if (!t.ok || empty(t.entry)) {
        return SideQuality(status = "refused", error = t.ok ? "no module of {t.out_dir} defines main" : t.error)
    }
    entry = t.entry
    var side <- measure_side(t.files, t.entry)
    for (f in t.files) {
        var inscope blocks <- c2da_blocks(fread(f))
        for (name, lines in keys(blocks), values(blocks)) {
            c2da[name] = (c2da?[name] ?? 0) + lines
        }
    }
    return <- side
}

//! The folder of a key's work: the C file, `ours/` and `rust/`.
def quality_work(key : string) : string => path_join(QUALITY_WORK, key)

//! The file a key's worker writes its `KeyQuality` to.
def quality_result_path(key : string) : string => path_join(quality_work(key), "quality.json")

// the sampled functions of `key` from each side's module, "" for a side with no module
def private sampled_functions(key, ours_path, rust_path : string) : array<FunctionPair> {
    var pairs : array<FunctionPair>
    for (sample in SAMPLES) {
        if (sample._0 == key) {
            let ours_text = empty(ours_path) ? "" : fread(ours_path)
            let rust_text = empty(rust_path) ? "" : fread(rust_path)
            pairs |> push_from([for (name in sample._1); FunctionPair(key = key, name = name, ours = function_text(ours_text, name, "ours"), rust = function_text(rust_text, name, "rust"))])
        }
    }
    return <- pairs
}

//! One key measured by the Rust translator `bin` in `<root>/<key>` (`quality_work(key)` for the
//! driver's `QUALITY_WORK`), emptied first: our conversion under `linux` into `ours/`, the Rust
//! translation into `rust/`, each side counted and sized, the sampled functions taken from both;
//! written to its `quality.json`.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def measure_key(key, bin, root : string) : KeyQuality {
    let work = path_join(root, key)
    rmdir_rec(work)
    mkdir_rec(work)
    var q : KeyQuality
    var clang_args : array<string>
    var error, ours_path, rust_path : string
    let c_path = quality_source(key, work, clang_args, error, CSMITH_PROGRAMS)
    if (!empty(error) || empty(c_path)) {
        q.ours = SideQuality(status = "convert", error = error)
        q.rust = SideQuality(status = "refused", error = error)
    } else {
        q.ours <- ours_quality(c_path, path_join(work, "ours"), ours_path)
        q.rust <- rust_quality(bin, c_path, path_join(work, "rust"), clang_args, quality_translate_timeout(key), rust_path, q.rust_c2da)
    }
    q.functions <- sampled_functions(key, ours_path, rust_path)
    fwrite(path_join(work, "quality.json"), sprint_json(q, false))
    return <- q
}

//! The `KeyQuality` a worker for `key` wrote; both sides `timeout` when the driver `killed` it, and
//! `crash` with the worker's exit code `rc` when it wrote none.
def read_key_quality(key : string; killed : bool; rc : int) : KeyQuality {
    var q : KeyQuality
    let path = quality_result_path(key)
    if (killed || !fexist(path) || !sscan_json(fread(path), q)) {
        let status = killed ? "timeout" : "crash"
        let error = killed ? "the worker was killed" : "the worker exited {rc} with no result"
        q.ours = SideQuality(status = status, error = error)
        q.rust = SideQuality(status = status, error = error)
    }
    return <- q
}

//! seconds a worker may live: a csmith seed converts in up to a minute, and the Rust translator may
//! take 600 s over a kernel
let QUALITY_WORKER_LIMIT = 900.0

//! Every key of `corpus` measured by a `--one quality/<key>` worker of `compare/run.das`, `jobs` at
//! a time.
def drive_quality(corpus : array<string>; jobs : int) : table<string; KeyQuality> {
    var entries : table<string; KeyQuality>
    run_workers(length(corpus), jobs, QUALITY_WORKER_LIMIT, $(index) => spawn_one(WORKER_SCRIPT, "quality/{corpus[index]}", quality_result_path(corpus[index]))) $(index, killed, rc, _output) {
        entries[corpus[index]] <- read_key_quality(corpus[index], killed, rc)
    }
    return <- entries
}

// every metric of `METRICS` plus `files` and `lines`, all 0
def private zero_sums : table<string; int> {
    var sums <- {for (m in METRICS); m => 0}
    sums["files"] = 0
    sums["lines"] = 0
    sums["runtime_lines"] = 0
    sums["program_c2da_lines"] = 0
    return <- sums
}

// `side`'s counts, files and lines added into `sums`
def private add_side(var sums : table<string; int>; side : SideQuality) {
    for (m in METRICS) {
        sums[m] += side.counts?[m] ?? 0
    }
    sums["files"] += side.files
    sums["lines"] += side.lines
    sums["runtime_lines"] += side.runtime_lines
    sums["program_c2da_lines"] += side.program_c2da_lines
}

//! The totals of `entries` per group (the key's text before its first `/`) and over `ALL_GROUPS`:
//! `keys` the corpus keys, `counted` those both sides measured `ok`, `excluded` the rest by side
//! and status (`rust_compile`), `ours` and `rust` the counters, files, lines and runtime lines
//! summed over the counted keys, `line_ratio` the Rust lines over ours and `program_line_ratio` the
//! Rust lines less its runtime's over ours.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def quality_totals(entries : table<string; KeyQuality>) : JsonValue? {
    var by_group : table<string; JsonValue?>
    var groups <- [ALL_GROUPS]
    for (k in keys(entries)) {
        if (!has_value(groups, group_of(k))) {
            groups |> push(group_of(k))
        }
    }
    for (g in groups) {
        var inscope ours <- zero_sums()
        var inscope rust <- zero_sums()
        var inscope excluded : table<string; int>
        var total, counted = 0
        for (k, q in keys(entries), values(entries)) {
            if (g != ALL_GROUPS && group_of(k) != g) {
                continue
            }
            total++
            if (q.ours.status == "ok" && q.rust.status == "ok") {
                counted++
                add_side(ours, q.ours)
                add_side(rust, q.rust)
            }
            for (side in [("ours", q.ours.status), ("rust", q.rust.status)]) {
                if (side._1 != "ok") {
                    excluded["{side._0}_{side._1}"] = (excluded?["{side._0}_{side._1}"] ?? 0) + 1
                }
            }
        }
        let ratio = ours["lines"] == 0 ? 0.0lf : double(rust["lines"]) / double(ours["lines"])
        let program_ratio = ours["lines"] == 0 ? 0.0lf : double(rust["lines"] - rust["runtime_lines"]) / double(ours["lines"])
        by_group[g] = JV((keys = total, counted = counted, excluded = JV(excluded), ours = JV(ours), rust = JV(rust), line_ratio = ratio, program_line_ratio = program_ratio))
    }
    return JV(by_group)
}

//! The `quality` section: the run's stamps, every key's two sides, the totals and the sampled
//! functions in the order `SAMPLES` lists them.
[arch(at="ARCHITECTURE_QUALITY.md#quality")]
def quality_section(stamps : Stamps; var entries : table<string; KeyQuality>) : JsonValue? {
    split_runtime(entries)
    var functions : array<FunctionPair>
    for (sample in SAMPLES) {
        entries |> get(sample._0) $(q) {
            functions |> push_from(q.functions)
        }
    }
    var keyed <- {for (k, q in keys(entries), values(entries)); k => JV((ours = JV(q.ours), rust = JV(q.rust)))}
    var root <- {
        "rust_commit" => JV(stamps.rust_commit),
        "rust_commit_error" => JV(stamps.rust_commit_error),
        "daslang" => JV(stamps.daslang),
        "date" => JV(stamps.date),
        "keys" => JV(keyed),
        "totals" => quality_totals(entries),
        "functions" => JV(functions)
    }
    return JV(root)
}
