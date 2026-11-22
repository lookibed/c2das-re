options gen2

module samples public

require math

//! The sample rule every timing harness shares (perf/ARCHITECTURE_SAMPLES.md section 5): how many
//! samples a cell takes, its value (the median) and its spread, which leaves out the one sample
//! farthest from the median, so a single slow run cannot inflate it, and records that sample's
//! distance as the cell's `outlier`. It measures nothing and reads no file.

//! the fewest samples a spread leaves its outlier out of
let OUTLIER_MIN_SAMPLES = 5
//! the `spread_rule` a capture records once its spreads follow `spread_of`; a capture without one
//! holds half the whole range
let TRIMMED_SPREAD = "trimmed"
//! the samples a cell takes when the command line names no count
let DEFAULT_SAMPLES = 5
//! the samples a noisy cell takes when the command line names no count: a workload whose native run
//! is under `SHORT_RUN` seconds or that allocates heavily
let NOISY_SAMPLES = 9
//! the native seconds under which a workload's cell is noisy
let SHORT_RUN = 1.0lf

//! The median of `values`, 0 for none.
def median_of(values : array<double>) : double {
    var sorted := values
    sorted |> sort()
    let n = length(sorted)
    return n == 0 ? 0.0lf : (n & 1) == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5lf
}

//! The index of the sample of `samples` farthest from `median`, the first of a tie, which the spread
//! leaves out; -1 under `OUTLIER_MIN_SAMPLES` samples.
def outlier_index(samples : array<double>; median : double) : int {
    if (length(samples) < OUTLIER_MIN_SAMPLES) {
        return -1
    }
    var at = 0
    for (s, i in samples, count()) {
        if (abs(s - median) > abs(samples[at] - median)) {
            at = i
        }
    }
    return at
}

//! The left-out sample's distance from `median` as a signed share of it (0.5 for a sample half as
//! slow again); 0 when none is left out or the median is 0.
def outlier_of(samples : array<double>; median : double) : double {
    let at = outlier_index(samples, median)
    return at < 0 || median <= 0.0lf ? 0.0lf : (samples[at] - median) / median
}

// half the range of `samples` but the one at `skip` (-1 for none) over `median`
def private half_range(samples : array<double>; median : double; skip : int) : double {
    if (median <= 0.0lf) {
        return 0.0lf
    }
    var lo = 0.0lf
    var hi = 0.0lf
    var seen = false
    for (s, i in samples, count()) {
        if (i != skip) {
            lo = seen ? min(lo, s) : s
            hi = seen ? max(hi, s) : s
            seen = true
        }
    }
    return (hi - lo) * 0.5lf / median
}

//! Half the range of every sample of `samples` as a share of `median`, the spread of a capture
//! without a `spread_rule`; 0 when there are none or the median is 0.
def range_spread_of(samples : array<double>; median : double) : double => half_range(samples, median, -1)

//! A cell's spread: half the range of `samples` as a share of `median`, the sample `outlier_index`
//! names left out; 0 when there are none or the median is 0.
def spread_of(samples : array<double>; median : double) : double => half_range(samples, median, outlier_index(samples, median))

//! What a table's header adds after its `±` for a capture of `rule`: "" for one without a rule.
def spread_note(rule : string) : string => rule == TRIMMED_SPREAD ? ", the sample farthest from the median left out from {OUTLIER_MIN_SAMPLES} samples on (the record keeps its distance as `outlier`)" : ""

//! The samples a cell takes: `asked` when the command line names a count (above 0), else
//! `NOISY_SAMPLES` for a workload whose native run takes under `SHORT_RUN` seconds or that
//! `allocates` heavily, else `DEFAULT_SAMPLES`.
def samples_for(asked : int; native_seconds : double; allocates : bool) : int {
    if (asked > 0) {
        return asked
    }
    return allocates || native_seconds < SHORT_RUN ? NOISY_SAMPLES : DEFAULT_SAMPLES
}

//! The samples a header names for a capture that asked `asked` (0: by `samples_for`).
def samples_text(asked : int) : string => asked > 0 ? "{asked} samples" : "{DEFAULT_SAMPLES} samples ({NOISY_SAMPLES} for a workload whose native run takes under {int(SHORT_RUN)} s or that allocates heavily)"
