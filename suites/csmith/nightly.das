options gen2

module nightly public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/random
require ../suite_runner.das
require verdict

//! The nightly csmith run (`run.das --nightly`, suites/ARCHITECTURE.md, the nightly run): N fresh
//! seeds drawn from a recorded start seed, so a night replays from its start alone, judged once
//! with no ratchet, into one dated result file of counts and seed lists per verdict.

//! the seeds a night judges unless `--seeds` names a count (the P4 exit criterion)
let NIGHTLY_SEEDS = 1000

//! the folder under the csmith work folder the result files land in
let NIGHTLY_DIR = "nightly"

//! the draws a night may make, as a share of the seeds it asks for: the seeds it cannot judge
//! are replaced from the same sequence up to this many draws in all
let DRAW_CAP_PERCENT = 150

//! the stages whose timeout is the reference side's (`timed_out` in `run.das`): csmith writing
//! the program, the native build running it
let CSMITH_STAGE = "csmith"
let NATIVE_STAGE = "the native run"

//! the verdicts of a night, in the result file's order; the first five are judged seeds
let NIGHTLY_VERDICTS <- ["pass", "differs", "refused", "timeout", "crash", "native", "native-timeout"]
let JUDGED_VERDICTS <- ["pass", "differs", "refused", "timeout", "crash"]

//! The start seed `text` names: a decimal of one to nine digits, so every start fits an `int`;
//! -1 for anything else.
def parse_start(text : string) : int {
    if (empty(text) || length(text) > 9) {
        return -1
    }
    for (ch in text) {
        if (!is_number(ch)) {
            return -1
        }
    }
    return to_int(text)
}

//! The start seed of a night dated `date` (`YYYY-MM-DD`): its digits, `20261122`; -1 when the
//! date is not of that shape.
def date_start(date : string) : int {
    let parts <- split(date, "-")
    if (length(parts) != 3 || length(parts[0]) != 4 || length(parts[1]) != 2 || length(parts[2]) != 2) {
        return -1
    }
    return parse_start(join(parts, ""))
}

// the murmur3 finalizer: every bit of `x` reaches every bit of the result
def private mix32(x : uint) : uint {
    var h = x
    h ^= h >> 16u
    h *= 0x85ebca6bu
    h ^= h >> 13u
    h *= 0xc2b2ae35u
    h ^= h >> 16u
    return h
}

//! The generator state of the night `start`: each lane a hash of the start and the lane, so
//! the nights of consecutive starts are unrelated (`random_seed(start)` makes lane `y` of a
//! start lane `x` of the next one, and a seed's high bits the next night's low bits).
def night_generator(start : int) : int4 {
    let base = uint(start) * 4u + 0x9e3779b9u
    return int4(int(mix32(base)), int(mix32(base + 1u)), int(mix32(base + 2u)), int(mix32(base + 3u)))
}

//! `count` distinct csmith seeds drawn from `start`: the same list for the same start on every
//! run, each seed a decimal from 1 to 2^30.
def nightly_seeds(start, count : int) : array<string> {
    var rng = night_generator(start)
    var chosen : table<string>
    var out : array<string>
    while (length(out) < count) {
        let s = "{random_big_int(rng) + 1}"
        if (!key_exists(chosen, s)) {
            chosen |> insert(s)
            out |> push(s)
        }
    }
    return <- out
}

//! The status of a seed's verdict as the night counts it: a timeout of csmith or of the native
//! run is `native-timeout`, the reference side's, never the converter's.
def night_status(v : Verdict) : string {
    let native = v.signature == "timeout {CSMITH_STAGE}" || v.signature == "timeout {NATIVE_STAGE}"
    return v.status == "timeout" && native ? "native-timeout" : v.status
}

//! The night's verdict of a seed's status: `differs` for a diverging run (`output`, `exit`),
//! `refused` for a conversion the converter refused, the others as they are.
def nightly_verdict(status : string) : string {
    if (status == "output" || status == "exit") {
        return "differs"
    }
    return status == "convert" ? "refused" : status
}

//! Whether a seed counts toward the night's N: the reference side judged it, `native` and
//! `native-timeout` aside.
def is_judged(status : string) : bool => JUDGED_VERDICTS |> has_value(nightly_verdict(status))

//! Whether a seed fails the night: a divergence, or a conversion or converted run past its limit
//! after the native side passed.
def fails_night(status : string) : bool {
    let verdict = nightly_verdict(status)
    return verdict == "differs" || verdict == "timeout"
}

//! Whether a seed's work folder outlives the night: a failure and a crash keep their program,
//! conversion and outputs for a person; every other seed regenerates from its number.
def keeps_files(status : string) : bool => fails_night(status) || status == "crash"

//! The most seeds a night asking for `count` draws.
def draw_cap(count : int) : int => count * DRAW_CAP_PERCENT / 100

//! Why a night may not start: one with its date and start is running (`running_pid`, empty when
//! none), or its result file exists and `force` is off; empty when it may.
def night_refusal(result : string; result_exists : bool; running_pid : string; force : bool) : string {
    if (!empty(running_pid)) {
        return "a night with this date and start is running (pid {running_pid}) and writes {result}"
    }
    if (result_exists && !force) {
        return "{result} exists: this night ran; --force runs it again over that file"
    }
    return ""
}

//! What a night ran: its date, start seed, the seeds it asks to judge, tier, reference compiler,
//! the commits and csmith options its seeds' verdicts depend on, and the command that replays it.
struct NightlyRun {
    date : string
    start : int
    count : int
    tier : string
    compiler : string
    csmith_commit : string
    csmith_options : string
    repo_commit : string
    das_commit : string
    replay : string
}

def nightly_result_path(work_dir : string; night : NightlyRun) : string {
    let tier = night.tier == "interp" ? "" : "-{night.tier}"
    return path_join(work_dir, "{NIGHTLY_DIR}/{night.date}-{night.start}{tier}.txt")
}

//! The result file of `night` after the seeds `drawn` so far, in draw order, of which `finished`
//! holds the ones that ended (`seconds` of wall time): the header, the judged line, a count per
//! verdict, the seeds of each verdict in draw order, and per failure or crash its folder; a
//! divergence also gets its two outputs and its reducer line. Two runs of one night differ in
//! the wall line alone.
def nightly_report(night : NightlyRun; work_dir : string; drawn : array<string>; finished : table<string; Outcome>; seconds : float) : string {
    let ended <- [for (s in drawn); finished?[s] ?? Outcome(); where key_exists(finished, s)]
    var seeds_of : table<string; string>
    var count_of : table<string; int>
    for (v in NIGHTLY_VERDICTS) {
        var inscope seeds <- [for (o in ended); o.id; where nightly_verdict(o.status) == v]
        seeds_of[v] = join(seeds, " ")
        count_of[v] = length(seeds)
    }
    let judged = length([for (o in ended); o.id; where is_judged(o.status)])
    let cap = draw_cap(night.count)
    let cap_hit = judged < night.count && length(drawn) >= cap && length(ended) == length(drawn)
    var lines <- [
        "# csmith nightly {night.date}: start seed {night.start}, {night.count} seeds asked, tier {night.tier}, reference {night.compiler}",
        "# csmith {night.csmith_commit}, options {night.csmith_options}; c2das-re {night.repo_commit}; daScript {night.das_commit}",
        "# replay: {night.replay}",
        "judged {judged} of {night.count} asked, drew {length(drawn)}, native-timeout {count_of?["native-timeout"] ?? 0}",
        cap_hit ? "draw cap {cap} hit: the night judged {judged} seeds, not {night.count}" : "draw cap {cap}",
        "wall {int(seconds)} s"
    ]
    lines |> push_from([for (v in NIGHTLY_VERDICTS); "{v} {count_of?[v] ?? 0}"], [for (v in NIGHTLY_VERDICTS); "seeds {v}: {seeds_of?[v] ?? ""}"; where v != "pass"])
    for (o in ended) {
        if (keeps_files(o.status)) {
            lines |> push_from(["{nightly_verdict(o.status)} {o.id}: {o.status}: {replace(first_line(o.reason), "\t", " ")}", "  files: {work_dir}/{o.id}/"])
        }
        if (nightly_verdict(o.status) == "differs") {
            lines |> push_from(["  outputs: {work_dir}/{o.id}/{o.id}.native.out {work_dir}/{o.id}/{o.id}.das.out", "  reduce: CC={night.compiler} suites/csmith/reduce.sh {o.id}"])
        }
    }
    lines |> push("seeds pass: {seeds_of?["pass"] ?? ""}")
    return join(lines, "\n") + "\n"
}

//! `text` written to `path` through a temporary file and a rename, so a reader never sees half a
//! file; false when either step fails.
def write_atomically(path, text : string) : bool {
    let tmp = "{path}.tmp"
    return fwrite(tmp, text) && rename(tmp, path)
}

//! The night's exit code: 1 when any seed failed it (`fails_night`), else 0.
def nightly_exit_code(outcomes : array<Outcome>) : int {
    for (o in outcomes) {
        if (fails_night(o.status)) {
            return 1
        }
    }
    return 0
}
