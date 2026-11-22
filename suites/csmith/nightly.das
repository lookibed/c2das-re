options gen2

module nightly public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/random
require ../suite_runner.das

//! The nightly csmith run (`run.das --nightly`, suites/ARCHITECTURE.md, the nightly run): N fresh
//! seeds drawn from a recorded start seed, so a night replays from its start alone, judged once
//! with no ratchet, into one dated result file of counts and seed lists per verdict.

//! the seeds a night judges unless `--seeds` names a count (the P4 exit criterion)
let NIGHTLY_SEEDS = 1000

//! the folder under the csmith work folder the result files land in
let NIGHTLY_DIR = "nightly"

//! the verdicts of a night, in the result file's order
let NIGHTLY_VERDICTS <- ["pass", "differs", "refused", "native", "timeout", "crash"]

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

//! `count` distinct csmith seeds drawn from `start`: the same list for the same start on every
//! run, each seed a decimal from 1 to 2^30.
def nightly_seeds(start, count : int) : array<string> {
    var rng = random_seed(start)
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

//! The night's verdict of a seed's status: `differs` for a diverging run (`output`, `exit`),
//! `refused` for a conversion the converter refused, the others as they are.
def nightly_verdict(status : string) : string {
    if (status == "output" || status == "exit") {
        return "differs"
    }
    return status == "convert" ? "refused" : status
}

//! Whether a seed's work folder outlives the night: a divergence, a timeout and a crash keep their
//! program, conversion and outputs for a person; every other seed regenerates from its number.
def keeps_files(status : string) : bool {
    let verdict = nightly_verdict(status)
    return verdict == "differs" || verdict == "timeout" || verdict == "crash"
}

//! What a night ran: its date, start seed, seed count, tier, reference compiler and the command
//! that replays it.
struct NightlyRun {
    date : string
    start : int
    count : int
    tier : string
    compiler : string
    replay : string
}

def nightly_result_path(work_dir : string; night : NightlyRun) : string {
    let tier = night.tier == "interp" ? "" : "-{night.tier}"
    return path_join(work_dir, "{NIGHTLY_DIR}/{night.date}-{night.start}{tier}.txt")
}

//! The result file of `night` after `outcomes` (`seconds` of wall time): a header, a count per
//! verdict, the seeds of each verdict, and per divergence its folder and reducer line.
def nightly_report(night : NightlyRun; work_dir : string; outcomes : array<Outcome>; seconds : float) : string {
    var seeds_of : table<string; string>
    var count_of : table<string; int>
    for (v in NIGHTLY_VERDICTS) {
        var inscope seeds <- [for (o in outcomes); o.id; where nightly_verdict(o.status) == v]
        seeds_of[v] = join(seeds, " ")
        count_of[v] = length(seeds)
    }
    var lines <- [
        "# csmith nightly {night.date}: start seed {night.start}, {night.count} seeds, tier {night.tier}, reference {night.compiler}",
        "# replay: {night.replay}",
        "judged {length(outcomes)} of {night.count}",
        "wall {int(seconds)} s"
    ]
    lines |> push_from([for (v in NIGHTLY_VERDICTS); "{v} {count_of?[v] ?? 0}"], [for (v in NIGHTLY_VERDICTS); "seeds {v}: {seeds_of?[v] ?? ""}"; where v != "pass"])
    for (o in outcomes) {
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

//! The night's exit code: 1 when any seed diverged, else 0.
def nightly_exit_code(outcomes : array<Outcome>) : int {
    for (o in outcomes) {
        if (nightly_verdict(o.status) == "differs") {
            return 1
        }
    }
    return 0
}
