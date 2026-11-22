options gen2
require dastest/testing_boost public
require math
require strings
require daslib/fio
require daslib/strings_boost
require ../ab_band.das
require ../../converter/tiers.das

//! The A/B decision (`ab_band.das`, `ab.das`) over `ab_fixture.txt`, a batch shaped like the box's
//! add38 batch 5: per tier the geomean ratio, the robust band and the verdict, one 1.175 s sample
//! among 0.51 s ones that the whole range would turn into a 129% band, and the knob rule.

def private near(a, b : double) : bool => abs(a - b) < 1e-6lf

def private fixture : Batch => <- read_batch(fread("perf/tests/ab_fixture.txt"), "work_s")

[test]
def test_read_batch(t : T?) {
    t |> run("run lines by bench, tier and arm; a failed or differing run skipped and counted; other lines ignored") @(t : T?) {
        var inscope batch <- fixture()
        t |> equal(batch.skipped, 2)
        t |> equal(join(benches_of(batch), ","), "fib,spectral_norm")
        t |> equal(join(tiers_of(batch), ","), "jit,exe")
        t |> equal(length(samples_of(batch, "fib", "jit", "d")), 5)
        t |> equal(length(samples_of(batch, "fib", "native", "-")), 1)
        t |> equal(length(samples_of(batch, "fib", "aot", "d")), 0)
    }
}

[test]
def test_verdicts(t : T?) {
    t |> run("the JIT: faster beyond the robust band, which the whole range of one outlier would swallow") @(t : T?) {
        var inscope batch <- fixture()
        let v <- tier_verdict(batch, "jit", "t", "d")
        t |> success(near(v.ratio, sqrt(0.8lf * 0.42lf / 0.515lf)), "{v.ratio}")
        t |> success(near(v.band, 0.02lf), "{v.band}")
        t |> success(near(v.range_band, (1.175lf - 0.51lf) / 0.515lf), "{v.range_band}")
        t |> equal(v.verdict, FASTER)
    }
    t |> run("exe: slower beyond the band") @(t : T?) {
        var inscope batch <- fixture()
        let v <- tier_verdict(batch, "exe", "t", "d")
        t |> success(near(v.ratio, 1.1lf), "{v.ratio}")
        t |> success(near(v.band, 0.01lf / 0.30lf), "{v.band}")
        t |> equal(v.verdict, SLOWER)
    }
    t |> run("a tier without one arm's samples has no verdict") @(t : T?) {
        var inscope batch <- fixture()
        let v <- tier_verdict(batch, "jit", "t", "nope")
        t |> equal(v.missing, "fib")
    }
    t |> run("the knob stays only when faster on a tier and on more tiers faster than slower") @(t : T?) {
        t |> success(!knob_stays([TierVerdict(verdict = FASTER), TierVerdict(verdict = SLOWER)]))
        t |> success(knob_stays([TierVerdict(verdict = FASTER), TierVerdict(verdict = WITHIN)]))
        t |> success(knob_stays([TierVerdict(verdict = FASTER), TierVerdict(verdict = FASTER), TierVerdict(verdict = SLOWER)]))
        t |> success(!knob_stays([TierVerdict(verdict = WITHIN), TierVerdict(verdict = WITHIN)]))
    }
    t |> run("the report: a line per tier, the knob's, the skipped count; the cells with both spreads and the outlier") @(t : T?) {
        var inscope batch <- fixture()
        let text = render_ab(batch, "t", "d")
        t |> success(text |> contains("jit: t/d 0.808 [fib 0.800, spectral_norm 0.816] band 2.0% (whole ranges 129.1%) F\n"), text)
        t |> success(text |> contains("exe: t/d 1.100 "), text)
        t |> success(text |> contains("knob t over d: faster on [jit], slower on [exe]: goes\n"), text)
        t |> success(text |> contains("skipped 2 run lines"), text)
        let cells = render_cells(batch)
        t |> success(cells |> contains("| spectral_norm | jit | d | 5 | 0.5150 | ±64.6% | ±1.0% | +128.2% |"), cells)
    }
}

[test(timeout = 1200)]
def test_ab_command(t : T?) {
    t |> run("ab.das decides the fixture; a missing flag is a usage error") @(t : T?) {
        var out : string
        let base <- daslang_cmd(CONVERTED_MODULES)
        var argv := base
        argv |> push_from(["perf/ab.das", "--", "--file", "perf/tests/ab_fixture.txt", "--arm", "t", "--base", "d", "--cells"])
        t |> equal(run_and_capture(argv, out, 600.0), 0, out)
        t |> success(out |> contains("knob t over d: faster on [jit], slower on [exe]: goes"), out)
        t |> success(out |> contains("| bench | tier | arm |"), out)
        var bad := base
        bad |> push_from(["perf/ab.das", "--", "--file", "perf/tests/ab_fixture.txt"])
        t |> equal(run_and_capture(bad, out, 600.0), 2, out)
    }
}
