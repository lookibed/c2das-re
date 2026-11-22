options gen2
require dastest/testing_boost public
require math
require strings
require daslib/strings_boost
require daslib/fio
require ../samples.das
require ../perf_lanes.das

//! The sample rule (`samples.das`) on the outlier shapes the box's batches gave, the sample count,
//! the header notes, and the pin of a timed sample (`perf_lanes.das`).

def near(a, b : double) : bool => abs(a - b) < 1e-9lf

[test]
def test_spread(t : T?) {
    t |> run("one sample 1.5x slow among five: the spread leaves it out and the record keeps its distance") @(t : T?) {
        let s <- [0.59lf, 0.59lf, 0.60lf, 0.58lf, 0.89lf]
        let m = median_of(s)
        t |> success(near(m, 0.59lf))
        t |> success(near(range_spread_of(s, m), 0.31lf * 0.5lf / 0.59lf), "the whole range is suspect: {range_spread_of(s, m)}")
        t |> equal(outlier_index(s, m), 4)
        t |> success(near(spread_of(s, m), 0.02lf * 0.5lf / 0.59lf), "{spread_of(s, m)}")
        t |> success(near(outlier_of(s, m), 0.30lf / 0.59lf), "{outlier_of(s, m)}")
    }
    t |> run("one sample 2.3x slow among seven, and a 27 s cell with one 41 s sample") @(t : T?) {
        let s <- [0.51lf, 0.52lf, 0.50lf, 1.175lf, 0.51lf, 0.515lf, 0.505lf]
        let m = median_of(s)
        t |> equal(outlier_index(s, m), 3)
        t |> success(near(spread_of(s, m), 0.02lf * 0.5lf / 0.51lf), "{spread_of(s, m)}")
        let long <- [27.0lf, 27.5lf, 26.8lf, 41.0lf, 27.2lf]
        let ml = median_of(long)
        t |> success(near(spread_of(long, ml), 0.7lf * 0.5lf / 27.2lf), "{spread_of(long, ml)}")
        t |> success(near(outlier_of(long, ml), 13.8lf / 27.2lf), "{outlier_of(long, ml)}")
    }
    t |> run("a fast outlier is left out too, its distance negative; two slow samples still widen the spread") @(t : T?) {
        let fast <- [1.0lf, 1.0lf, 1.0lf, 1.0lf, 0.5lf]
        t |> success(near(outlier_of(fast, 1.0lf), -0.5lf))
        t |> success(near(spread_of(fast, 1.0lf), 0.0lf))
        let two <- [1.0lf, 1.0lf, 1.0lf, 1.5lf, 1.6lf]
        t |> success(near(spread_of(two, 1.0lf), 0.25lf), "{spread_of(two, 1.0lf)}")
    }
    t |> run("under five samples nothing is left out: the spread is the whole range's, the outlier 0") @(t : T?) {
        let four <- [1.0lf, 1.0lf, 1.0lf, 2.0lf]
        t |> equal(outlier_index(four, 1.0lf), -1)
        t |> success(near(outlier_of(four, 1.0lf), 0.0lf))
        t |> success(near(spread_of(four, 1.0lf), 0.5lf))
        t |> success(near(outlier_of([1.0lf, 1.0lf, 1.0lf, 1.0lf, 2.0lf], 0.0lf), 0.0lf), "a zero median has no outlier share")
    }
}

[test]
def test_counts_and_notes(t : T?) {
    t |> run("the count: the command line's, else 9 for a short or allocating workload, else 5") @(t : T?) {
        t |> equal(samples_for(7, 0.3lf, true), 7)
        t |> equal(samples_for(0, 0.3lf, false), NOISY_SAMPLES)
        t |> equal(samples_for(0, 2.0lf, true), NOISY_SAMPLES)
        t |> equal(samples_for(0, 2.0lf, false), DEFAULT_SAMPLES)
    }
    t |> run("the header names the count asked, else both of the rule's; the trimmed rule adds its note") @(t : T?) {
        t |> equal(samples_text(5), "5 samples")
        t |> equal(samples_text(0), "5 samples (9 for a workload whose native run takes under 1 s or that allocates heavily)")
        t |> equal(spread_note(""), "")
        t |> success(spread_note(TRIMMED_SPREAD) |> starts_with(", the sample farthest from the median left out from 5 samples on"))
        t |> equal(spread_note(RANGE_SPREAD), "")
        t |> equal(spread_rule_of(5), TRIMMED_SPREAD)
        t |> equal(spread_rule_of(3), RANGE_SPREAD)
    }
}

[test]
def test_pin(t : T?) {
    t |> run("a Cpus_allowed_list: ranges and single cores; garbage reads as none") @(t : T?) {
        t |> equal(length(cpu_list("0-15")), 16)
        t |> equal(join([for (c in cpu_list(" 0,2,4-6\n")); "{c}"], ","), "0,2,4,5,6")
        t |> equal(length(cpu_list("x")), 0)
        t |> equal(length(cpu_list("3-1")), 0)
    }
    t |> run("the pin is opt-in: the core the variable names, none when it is unset, empty or off") @(t : T?) {
        let all <- cpu_list("0-15")
        t |> equal(join(timing_pin("7", "/usr/bin/taskset", all).prefix, " "), "/usr/bin/taskset -c 7")
        t |> equal(timing_pin("7", "/usr/bin/taskset", all).core, 7)
        let none : array<int>
        t |> equal(join(timing_pin("9", "/usr/bin/taskset", none).prefix, " "), "/usr/bin/taskset -c 9")
        for (setting in ["", "off"]) {
            let unset = timing_pin(setting, "/usr/bin/taskset", all)
            t |> success(empty(unset.prefix) && unset.core == -1 && !unset.warn && unset.note == "C2DAS_TIMING_CORE is unset: timed samples run unpinned", "{setting}: {unset.note}")
        }
    }
    t |> run("a pin asked for and not taken warns: no taskset, or a core the process may not run on") @(t : T?) {
        let all <- cpu_list("0-15")
        let missing = timing_pin("3", "", all)
        t |> success(empty(missing.prefix) && missing.warn && missing.note == "C2DAS_TIMING_CORE=3 but no taskset on PATH: timed samples run unpinned", missing.note)
        for (setting in ["99", "abc", "-1"]) {
            let bad = timing_pin(setting, "/usr/bin/taskset", all)
            t |> success(empty(bad.prefix) && bad.warn && bad.core == -1 && bad.note |> contains("names no core"), "{setting}: {bad.note}")
        }
    }
    t |> run("a timed sample is the pin before the guard, and runs on the pinned core") @(t : T?) {
        t |> equal(join(timed(["k"], 0l, ["taskset", "-c", "2"]), "|"), "taskset|-c|2|sh|-c|\"$@\"; exit $?|sh|prlimit|--core=1|--|k")
        let unpinned : array<string>
        t |> equal(join(timed(["k"], 0l, unpinned), "|"), join(guarded(["k"], 0l), "|"))
        let taskset = on_path("taskset")
        if (empty(taskset)) {
            t |> skip("no taskset on PATH")
            return
        }
        var out : string
        t |> equal(run_and_capture(timed(["grep", "Cpus_allowed_list", "/proc/self/status"], 0l, [taskset, "-c", "0"]), out, 30.0), 0, out)
        t |> success(out |> contains("Cpus_allowed_list:\t0\n"), out)
        t |> equal(on_path("no-such-program-c2das"), "")
    }
}
