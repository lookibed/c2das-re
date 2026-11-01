options gen2

module suite_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/cir.das
require ../converter/tiers.das
require ../suites/suite_runner.das
require ../suites/csmith/generate.das
require ../suites/csmith/verdict.das
require ../perf/perf_lanes.das
require rust_translator
require compare_render public

//! The three suites through the Rust translator: every id a suite's own run judges, translated,
//! checked under `-compile-only`, run under the interpreter and judged by the suite's oracle, one
//! worker process per id; the counts land in the `suites` section of the capture
//! (`compare/ARCHITECTURE.md`).

let WORK = "compare/work"
let CAPTURE = "compare/results_linux.json"
let WORKER_SCRIPT = "compare/run.das"
let CSMITH = "csmith"

//! the Rust side's csmith reference: the suite's gcc flags without `-funsigned-char`, since the
//! Rust translator's `char` is signed
let RUST_NATIVE_FLAGS <- ["-O0", "-fwrapv", "-w"]

//! seconds the native csmith program may run, the suite's own limit
let NATIVE_TIMEOUT = 2.0

//! seconds the translator and the compile check may take
let TRANSLATE_TIMEOUT = 300.0
let COMPILE_TIMEOUT = 120.0

//! The seconds each timed child of a case may take.
struct Limits {
    translate : float
    compile : float
    run : float
    native : float
}

//! A case's limits in `spec`: the suite's own run timeout, the fixed ones for the rest.
def suite_limits(spec : SuiteSpec) : Limits => Limits(translate = TRANSLATE_TIMEOUT, compile = COMPILE_TIMEOUT, run = spec.run_timeout, native = NATIVE_TIMEOUT)

//! seconds a worker gets past the sum of its timed children's limits before the driver kills it
let WORKER_MARGIN = 60.0

def private suite_spec(name, tests_dir : string; run_timeout : float) : SuiteSpec =>
    SuiteSpec(name = name, tests_dir = tests_dir, work_dir = "{WORK}/{name}", expected_pass = "suites/{name}/expected_pass.txt", skip_ledger = "suites/{name}/skip.txt", run_timeout = run_timeout)

//! The suites as this comparison runs them, each with its own run's timeout; csmith's `tests_dir`
//! is where the suite's own run leaves its programs, which a comparison reuses.
def compare_suites : array<SuiteSpec> => <- [suite_spec("c_testsuite", C_TESTSUITE_TESTS, 60.0), suite_spec("gcc_torture", GCC_TORTURE_TESTS, 20.0), suite_spec(CSMITH, "suites/csmith/work", 300.0)]

//! What a run over `spec` needs on disk: the tests folder, for csmith the built csmith.
def input_of(spec : SuiteSpec) : string => spec.name == CSMITH ? "{CSMITH_DIR}/build/src/csmith" : spec.tests_dir

//! The ids of `spec` whose name holds `filter`, sorted: every `.c` file of a file-based suite,
//! every seed csmith's ratchet or ledger lists.
def suite_ids(spec : SuiteSpec; ratchet : Ratchet; filter : string) : array<string> {
    if (spec.name != CSMITH) {
        return <- c_file_ids(spec.tests_dir, filter)
    }
    var seeds : table<string>
    for (s in ratchet.expected) {
        seeds |> insert(s)
    }
    for (s in keys(ratchet.skips)) {
        seeds |> insert(s)
    }
    var ids <- [for (s in keys(seeds)); s; where empty(filter) || find(s, filter) >= 0]
    ids |> sort()
    return <- ids
}

//! `ours` for an id the ratchet lists, `skipped` for one the ledger lists, `unlisted` otherwise.
def id_tag(ratchet : Ratchet; id : string) : string => key_exists(ratchet.expected_set, id) ? "ours" : key_exists(ratchet.skips, id) ? "skipped" : "unlisted"

//! A worker's verdict on one case: the status, the reason and the worker's seconds; an empty
//! status when no worker wrote one.
struct CaseVerdict {
    status : string
    reason : string
    seconds : float
}

def case_verdict_path(spec : SuiteSpec; id : string) : string => "{spec.work_dir}/{id}/verdict"

def write_case_verdict(path : string; v : CaseVerdict) {
    fwrite(path, "{v.status}\t{replace(replace(v.reason, "\t", " "), "\n", " ")}\t{v.seconds}\n")
}

def read_case_verdict(path : string) : CaseVerdict {
    let fields <- split(strip(fread(path)), "\t")
    if (length(fields) != 3) {
        return CaseVerdict()
    }
    return CaseVerdict(status = fields[0], reason = fields[1], seconds = to_float(fields[2]))
}

//! What a translated program must do: exit 0 and, under `judge_output`, print `expected`.
struct Oracle {
    judge_output : bool
    expected : string
}

def private timed_out(stage : string; seconds : float) : CaseVerdict => CaseVerdict(status = "timeout", reason = "{stage} took longer than {int(seconds)} s")

// `entry` under `daslang -compile-only` with no module folders: the exit code and the text
def private compile_entry(entry : string; timeout : float; var text : string&) : int {
    let no_modules : array<string>
    return compile_entry(entry, no_modules, timeout, text)
}

//! `entry` under `daslang -compile-only` with `module_dirs` loaded: the exit code and the text.
def compile_entry(entry : string; module_dirs : array<string>; timeout : float; var text : string&) : int {
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from(["-compile-only", entry])
    return run_and_capture(cmd, text, timeout)
}

//! The first `error[` line of a failed compile check, else its first line.
def compile_error(text : string) : string {
    for (ln in split(text, "\n")) {
        if (ln |> starts_with("error[")) {
            return strip(ln)
        }
    }
    return first_line(text)
}

//! `c_path` translated by `bin` into `<work>/das`, checked under `-compile-only`, run under the
//! interpreter in `<work>/run`, each step within `limits`, and judged against `oracle`.
[arch(at="ARCHITECTURE.md#statuses")]
def judge_translation(bin, c_path, work : string; limits : Limits; oracle : Oracle) : CaseVerdict {
    let no_args : array<string>
    let t = translate_file(bin, c_path, path_join(work, "das"), no_args, no_args, limits.translate)
    if (t.exit_code == popen_timed_out) {
        return timed_out("the translator", limits.translate)
    }
    if (!t.ok || empty(t.entry)) {
        return CaseVerdict(status = "refused", reason = t.ok ? "no module of {t.out_dir} defines main" : t.error)
    }
    var compiled : string
    let compile_rc = compile_entry(t.entry, limits.compile, compiled)
    if (compile_rc == popen_timed_out) {
        return timed_out("the compile check", limits.compile)
    }
    if (compile_rc != 0) {
        return CaseVerdict(status = "compile", reason = compile_error(compiled))
    }
    var output : string
    let rc = run_translation(t, "interp", path_join(work, "run"), output, limits.run, ["-no-module-cache"], no_args)
    if (rc == popen_timed_out) {
        return timed_out("the run", limits.run)
    }
    let outcome = compare_output("", rc, output, oracle.judge_output ? oracle.expected : output)
    return CaseVerdict(status = outcome.status, reason = outcome.reason)
}

//! The program of csmith seed `seed`: the one the suite's own run left under `reuse_dir`, else
//! one generated into `work`.
def csmith_source(seed, reuse_dir, work : string) : CsmithProgram {
    let reused = "{reuse_dir}/{seed}/{seed}.c"
    if (fexist(reused)) {
        return CsmithProgram(c_path = reused)
    }
    return csmith_program(seed, work, CSMITH_TIMEOUT)
}

//! A csmith program judged against its native build by gcc at `RUST_NATIVE_FLAGS`: `native`
//! when that build or its run fails, else the translation's verdict against its output.
[arch(at="ARCHITECTURE.md#csmith-char")]
def judge_csmith_program(bin, c_path, work : string; limits : Limits) : CaseVerdict {
    mkdir_rec(work)
    let native = native_run("gcc", RUST_NATIVE_FLAGS, c_path, path_join(work, "{file_stem(c_path)}_native"), limits.native)
    if (!native.built) {
        return CaseVerdict(status = "native", reason = "gcc refused it: {first_line(native.output)}")
    }
    if (native.rc == popen_timed_out) {
        return CaseVerdict(status = "native", reason = "the native run took longer than {int(limits.native)} s")
    }
    if (native.rc != 0) {
        return CaseVerdict(status = "native", reason = "the native run exited {native.rc}")
    }
    return judge_translation(bin, c_path, work, limits, Oracle(judge_output = true, expected = native.output))
}

// a csmith seed: its program found or generated, then judged
def private judge_seed(seed, bin, reuse_dir, work : string; limits : Limits) : CaseVerdict {
    let prog = csmith_source(seed, reuse_dir, work)
    if (prog.timed_out) {
        return CaseVerdict(status = "native", reason = "csmith took longer than {int(CSMITH_TIMEOUT)} s")
    }
    if (!empty(prog.error)) {
        return CaseVerdict(status = "native", reason = prog.error)
    }
    return judge_csmith_program(bin, prog.c_path, work, limits)
}

//! One case of `spec` judged by the Rust translator `bin` in `<work_dir>/<id>`, emptied first, its
//! verdict written there; a csmith seed's program is `<tests_dir>/<seed>/<seed>.c` when present.
def judge_case(spec : SuiteSpec; id, bin : string) : CaseVerdict {
    let started = ref_time_ticks()
    let work = "{spec.work_dir}/{id}"
    rmdir_rec(work)
    mkdir_rec(work)
    let limits = suite_limits(spec)
    let c_path = "{spec.tests_dir}/{id}.c"
    var v : CaseVerdict
    if (spec.name == CSMITH) {
        v = judge_seed(id, bin, spec.tests_dir, work, limits)
    } elif (spec.name == "c_testsuite") {
        v = judge_translation(bin, c_path, work, limits, Oracle(judge_output = true, expected = fread("{c_path}.expected")))
    } else {
        v = judge_translation(bin, c_path, work, limits, Oracle())
    }
    v.seconds = seconds_since(started)
    write_case_verdict(case_verdict_path(spec, id), v)
    return v
}

//! The worker's argument naming one case, `<suite>/<id>`.
def worker_id(suite, id : string) : string => "{suite}/{id}"

//! `text` as `<suite>/<id>`; false when either part is empty or the id names a path.
def split_worker_id(text : string; var suite, id : string&) : bool {
    let at = find(text, "/")
    if (at <= 0) {
        return false
    }
    suite = slice(text, 0, at)
    id = slice(text, at + 1)
    return !empty(id) && find(id, "/") < 0 && !(id |> starts_with("."))
}

//! seconds a worker of `spec` may live: its timed children's limits summed (csmith's and the
//! native run's for csmith alone), and the margin
def worker_limit(spec : SuiteSpec) : float {
    let limits = suite_limits(spec)
    let reference = spec.name == CSMITH ? CSMITH_TIMEOUT + limits.native : 0.0
    return reference + limits.translate + limits.compile + limits.run + WORKER_MARGIN
}

//! One case's line in a capture.
struct CaseOutcome {
    id : string
    tag : string
    status : string
    reason : string
    seconds : float
}

//! The outcome of case `id`'s worker: `timeout` when the driver `killed` it past `limit`
//! seconds, `crash` when it exited with `rc` and no verdict, else its verdict.
def case_outcome(id, tag : string; killed : bool; rc : int; limit : float; v : CaseVerdict) : CaseOutcome {
    let o = worker_outcome(id, killed, rc, limit, Verdict(status = v.status, reason = v.reason))
    return CaseOutcome(id = id, tag = tag, status = o.status, reason = o.reason, seconds = v.seconds)
}

//! Every id of `ids` through a `--one` worker of `compare/run.das`, `jobs` at a time; the
//! outcomes sorted by id.
def drive_suite(spec : SuiteSpec; ids : array<string>; ratchet : Ratchet; jobs : int) : array<CaseOutcome> {
    var outcomes : array<CaseOutcome>
    let limit = worker_limit(spec)
    run_workers(length(ids), jobs, limit, $(index) => spawn_one(WORKER_SCRIPT, worker_id(spec.name, ids[index]), case_verdict_path(spec, ids[index]))) $(index, killed, rc, _output) {
        let id = ids[index]
        outcomes |> push(case_outcome(id, id_tag(ratchet, id), killed, rc, limit, read_case_verdict(case_verdict_path(spec, id))))
    }
    outcomes |> sort() $(a, b) => a.id < b.id
    return <- outcomes
}

//! What a suite's entry records of the run that wrote it: the Rust translator's commit, or why
//! there is none, the first line of `daslang -version`, and the date.
struct Stamps {
    rust_commit : string
    rust_commit_error : string
    daslang : string
    date : string
}

//! The stamps of a run now, the Rust translator `bin`'s commit logged as a warning when it has none.
def run_stamps(bin : string) : Stamps {
    var s : Stamps
    s.rust_commit = rust_version(bin, s.rust_commit_error)
    if (empty(s.rust_commit)) {
        to_log(LOG_WARNING, "no commit to stamp: {s.rust_commit_error}\n")
    }
    var clang_version : string
    tool_versions(clang_version, s.daslang)
    s.date = strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))
    return s
}

//! A suite's entry in the capture's `suites` section.
struct SuiteCapture {
    rust_commit : string
    rust_commit_error : string
    daslang : string
    date : string
    ids : int
    ours_pass : int
    ours_skipped : int
    rust : table<string; int>
    rust_pass_of_ours : int
    rust_pass_of_skipped : int
    rust_pass_of_unlisted : int
    seconds : float
    outcomes : array<CaseOutcome>
}

//! The entry of a run over a whole suite: our side's counts from `ratchet`, the Rust side's from
//! `outcomes`, every status of `STATUSES` counted, stamped with `stamps`.
[arch(at="ARCHITECTURE.md#capture")]
def suite_capture(ratchet : Ratchet; var outcomes : array<CaseOutcome>; seconds : float; stamps : Stamps) : SuiteCapture {
    var c = SuiteCapture(rust_commit = stamps.rust_commit, rust_commit_error = stamps.rust_commit_error, daslang = stamps.daslang, date = stamps.date, ids = length(outcomes), ours_pass = length(ratchet.expected), ours_skipped = length(ratchet.skips), seconds = seconds)
    for (s in STATUSES) {
        c.rust[s] = 0
    }
    for (o in outcomes) {
        c.rust[o.status] = (c.rust?[o.status] ?? 0) + 1
        if (o.status == "pass") {
            c.rust_pass_of_ours += o.tag == "ours" ? 1 : 0
            c.rust_pass_of_skipped += o.tag == "skipped" ? 1 : 0
            c.rust_pass_of_unlisted += o.tag == "unlisted" ? 1 : 0
        }
    }
    c.outcomes <- outcomes
    return <- c
}

//! The capture at `path` as a JSON object, a fresh one when there is no file; null with `error`
//! set when the file present there is not a JSON object.
[arch(at="ARCHITECTURE.md#capture")]
def capture_root(path : string; var error : string&) : JsonValue? {
    if (!fexist(path)) {
        var empty_root : table<string; JsonValue?>
        return JV(empty_root)
    }
    var read_error : string
    var root = read_json(fread(path), read_error)
    if (!empty(read_error) || root == null || !(root.value is _object)) {
        error = "cannot read {path}: {read_error}"
        return null
    }
    return root
}

//! `path` rewritten with each entry of `suites` replacing the suite of its name in the `suites`
//! section, every other suite and section kept; "" or why the file present at `path` cannot be
//! read.
[arch(at="ARCHITECTURE.md#capture")]
def write_capture(path : string; var suites : table<string; JsonValue?>) : string {
    var error : string
    var root = capture_root(path, error)
    if (root == null) {
        return error
    }
    var section = root?["suites"]
    if (section == null || !(section.value is _object)) {
        var empty_section : table<string; JsonValue?>
        section = JV(empty_section)
        (root.value as _object)["suites"] = section
    }
    for (name, entry in keys(suites), values(suites)) {
        (section.value as _object)[name] = entry
    }
    fwrite(path, write_json(root) + "\n")
    return ""
}

//! `path` rewritten with its section `name` replaced by `section` as a whole, every other section
//! kept; "" or why the file present at `path` cannot be read.
[arch(at="ARCHITECTURE.md#capture")]
def write_capture_section(path, name : string; var section : JsonValue?) : string {
    var error : string
    var root = capture_root(path, error)
    if (root == null) {
        return error
    }
    (root.value as _object)[name] = section
    fwrite(path, write_json(root) + "\n")
    return ""
}

//! Why a run over `specs` cannot start, "" when it can: the Rust translator is missing, or a
//! suite's `input_of`.
def missing_inputs(specs : array<SuiteSpec>) : string {
    var reason : string
    if (!rust_available(reason)) {
        return reason
    }
    for (spec in specs) {
        if (!fexist(input_of(spec))) {
            return "{input_of(spec)} is missing: run suites/{spec.name}/fetch.sh"
        }
    }
    return ""
}

//! The end of a run: the entries written into the capture `out` unless the run was `filtered`;
//! 0, or 1 when the capture cannot be read.
def record_run(out, filter : string; var entries : table<string; JsonValue?>) : int => record_run(out, filter) $(path) => write_capture(path, entries)

//! The end of a run whose capture `write` writes into `out`, called unless the run was
//! `filtered`, returning "" or why the capture cannot be read; 0, or 1 when it cannot.
def record_run(out, filter : string; write : block<(path : string) : string>) : int {
    if (!empty(filter)) {
        to_log(LOG_INFO, "a --filter run writes no capture\n")
        return 0
    }
    let error = invoke(write, out)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    to_log(LOG_INFO, "written to {out}\n")
    return 0
}
