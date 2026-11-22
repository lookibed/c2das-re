options gen2

module ab_band public

require math
require strings
require daslib/strings_boost
require daslib/strings_convert
require samples

//! The A/B decision over one batch of timed runs (perf/ARCHITECTURE_SAMPLES.md section 6): an arm
//! over a base arm, per tier the geometric mean over the benches of the ratio of their medians, the
//! band the samples' robust spread allows, the verdict beyond it, and whether the knob the arm
//! switches on stays. Values are times: a ratio under 1 is the arm faster. It reads no file.

//! the verdict of a tier whose arm is faster beyond the band, slower beyond it, or neither
let FASTER = "F"
let SLOWER = "S"
let WITHIN = "-"

//! The samples of one arm of one bench under one tier.
struct ArmSamples {
    bench : string
    tier : string
    arm : string
    samples : array<double>
}

//! One batch: the samples of every bench, tier and arm in the order the lines name them first,
//! the count of run lines whose value is not a number or whose output differs, and a line for each
//! run line whose value is a number but no time (0, negative, NaN or infinite), which it refuses.
struct Batch {
    cells : array<ArmSamples>
    skipped : int
    refused : array<string>
}

//! One tier's verdict on the arm over the base: the geometric mean of the per-bench ratios, the
//! band (the widest robust full spread, twice `spread_of`, of either arm over the benches), the
//! band the whole ranges would give, and `FASTER`, `SLOWER` or `WITHIN`; `missing` says which
//! bench lacks the samples of which arm under the tier, which leaves the tier without a verdict.
struct TierVerdict {
    tier : string
    ratio : double
    ratios : array<double>
    band : double
    range_band : double
    verdict : string
    missing : string
}

// the `key=value` fields of a line
def private fields_of(line : string) : table<string; string> {
    var fields : table<string; string>
    for (word in split(strip(line), " ")) {
        let eq = find(word, "=")
        if (eq > 0) {
            fields.insert(slice(word, 0, eq), slice(word, eq + 1))
        }
    }
    return <- fields
}

//! The batch `text` holds: a run line has `bench=`, `lane=` (the tier), `arm=` and `<value_key>=`
//! fields among its `key=value` words; a line without the first three is no run line; a run line
//! whose value is no number or that carries `OUTPUT_DIFFERS` is skipped and counted; one whose value
//! is a number but no time (not above 0, or not finite) is refused with its line number.
def read_batch(text, value_key : string) : Batch {
    var batch : Batch
    for (line, number in split(text, "\n"), count(1)) {
        var inscope f <- fields_of(line)
        if (!key_exists(f, "bench") || !key_exists(f, "lane") || !key_exists(f, "arm")) {
            continue
        }
        let parsed = try_to_double(f?[value_key] ?? "")
        if (is_err(parsed) || find(line, "OUTPUT_DIFFERS") >= 0) {
            batch.skipped++
            continue
        }
        let value = unwrap(parsed)
        if (!is_finite(value) || value <= 0.0lf) {
            batch.refused |> push("line {number}: `{value_key}={f?[value_key] ?? ""}` is no time above 0")
            continue
        }
        let bench = f?["bench"] ?? ""
        let tier = f?["lane"] ?? ""
        let arm = f?["arm"] ?? ""
        var at = -1
        for (c, i in batch.cells, count()) {
            if (c.bench == bench && c.tier == tier && c.arm == arm) {
                at = i
            }
        }
        if (at < 0) {
            at = length(batch.cells)
            batch.cells |> emplace(ArmSamples(bench = bench, tier = tier, arm = arm))
        }
        batch.cells[at].samples |> push(value)
    }
    return <- batch
}

//! The samples of `bench` under `tier` in `arm`, none when the batch has none.
def samples_of(batch : Batch; bench, tier, arm : string) : array<double> {
    for (c in batch.cells) {
        if (c.bench == bench && c.tier == tier && c.arm == arm) {
            return <- clone_to_move(c.samples)
        }
    }
    return <- array<double>()
}

// whether a cell before the `at`th names `bench` (`tier` false) or tier `name`
def private seen_before(batch : Batch; at : int; name : string; tier : bool) : bool {
    for (i in range(at)) {
        if ((tier ? batch.cells[i].tier : batch.cells[i].bench) == name) {
            return true
        }
    }
    return false
}

// whether a cell of `bench` lies under a tier other than `native`
def private timed_by_a_tier(batch : Batch; bench : string) : bool {
    for (c in batch.cells) {
        if (c.bench == bench && c.tier != "native") {
            return true
        }
    }
    return false
}

//! The benches of the batch with samples under a tier other than `native`, in first-seen order.
def benches_of(batch : Batch) : array<string> => <- [for (c, i in batch.cells, count()); c.bench; where !seen_before(batch, i, c.bench, false) && timed_by_a_tier(batch, c.bench)]

//! The benches of the batch with samples under `native` alone, which no tier's verdict weighs.
def native_only(batch : Batch) : array<string> => <- [for (c, i in batch.cells, count()); c.bench; where !seen_before(batch, i, c.bench, false) && !timed_by_a_tier(batch, c.bench)]

//! The tiers of the batch but `native`, in first-seen order.
def tiers_of(batch : Batch) : array<string> => <- [for (c, i in batch.cells, count()); c.tier; where c.tier != "native" && !seen_before(batch, i, c.tier, true)]

//! The verdict of `tier` on `arm` over `base` over every bench of the batch.
def tier_verdict(batch : Batch; tier, arm, base : string) : TierVerdict {
    var v = TierVerdict(tier = tier, verdict = WITHIN)
    var log_sum = 0.0lf
    let benches <- benches_of(batch)
    v.ratios |> reserve(length(benches))
    for (bench in benches) {
        var inscope a <- samples_of(batch, bench, tier, arm)
        var inscope b <- samples_of(batch, bench, tier, base)
        if (empty(a) || empty(b)) {
            v.missing = "{bench} has no `{empty(a) ? arm : base}` samples under {tier}"
            return <- v
        }
        let ma = median_of(a)
        let mb = median_of(b)
        v.ratios |> push(ma / mb)
        log_sum += log(ma / mb)
        v.band = max(v.band, 2.0lf * max(spread_of(a, ma), spread_of(b, mb)))
        v.range_band = max(v.range_band, 2.0lf * max(range_spread_of(a, ma), range_spread_of(b, mb)))
    }
    v.ratio = exp(log_sum / double(length(benches)))
    v.verdict = v.ratio < 1.0lf - v.band ? FASTER : v.ratio > 1.0lf + v.band ? SLOWER : WITHIN
    return <- v
}

//! Whether the knob an arm switches on stays (the lead's rule, 2026-11-22): faster beyond the band
//! on at least one tier, and on more tiers faster than slower.
def knob_stays(verdicts : array<TierVerdict>) : bool {
    var faster = 0
    var slower = 0
    for (v in verdicts) {
        faster += v.verdict == FASTER ? 1 : 0
        slower += v.verdict == SLOWER ? 1 : 0
    }
    return faster >= 1 && faster > slower
}

// a share as a percent to a tenth
def private percent(share : double) : string => "{share * 100.0lf:.1f}%"

//! The decision of `arm` over `base`: a line per tier, then the knob's.
def render_ab(batch : Batch; arm, base : string) : string {
    var verdicts : array<TierVerdict>
    let benches <- benches_of(batch)
    var lines : array<string>
    for (tier in tiers_of(batch)) {
        var v <- tier_verdict(batch, tier, arm, base)
        if (!empty(v.missing)) {
            lines |> push("{tier}: {arm}/{base} no verdict: {v.missing}")
            continue
        }
        let per = join([for (bench, r in benches, v.ratios); "{bench} {r:.3f}"], ", ")
        lines |> push("{tier}: {arm}/{base} {v.ratio:.3f} [{per}] band {percent(v.band)} (whole ranges {percent(v.range_band)}) {v.verdict}")
        verdicts |> emplace(v)
    }
    let faster = join([for (v in verdicts); v.tier; where v.verdict == FASTER], ",")
    let slower = join([for (v in verdicts); v.tier; where v.verdict == SLOWER], ",")
    lines |> push("knob {arm} over {base}: faster on [{faster}], slower on [{slower}]: {knob_stays(verdicts) ? "stays" : "goes"}")
    let left_out = join(native_only(batch), ", ")
    if (!empty(left_out)) {
        lines |> push("left out, timed under native alone: {left_out}")
    }
    lines |> push_from([for (r in batch.refused); "refused {r}"])
    if (batch.skipped > 0) {
        lines |> push("skipped {batch.skipped} run lines (no value or OUTPUT_DIFFERS)")
    }
    return join(lines, "\n") + "\n"
}

//! A markdown row per cell: its samples, median, whole-range and robust spread (half the range,
//! as a share of the median) and the left-out sample's distance from the median.
def render_cells(batch : Batch) : string {
    var lines <- ["| bench | tier | arm | n | median | spread, whole range | spread | outlier |", "|---|---|---|---:|---:|---:|---:|---:|"]
    lines |> reserve(2 + length(batch.cells))
    for (c in batch.cells) {
        let m = median_of(c.samples)
        let d = outlier_of(c.samples, m) * 100.0lf
        let outlier = outlier_index(c.samples, m) < 0 ? "none" : "{d > 0.0lf ? "+" : ""}{d:.1f}%"
        lines |> push("| {c.bench} | {c.tier} | {c.arm} | {length(c.samples)} | {m:.4f} | ±{percent(range_spread_of(c.samples, m))} | ±{percent(spread_of(c.samples, m))} | {outlier} |")
    }
    return join(lines, "\n") + "\n"
}
