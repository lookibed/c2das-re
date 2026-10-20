options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost

[test]
def test_run_help(t : T?) {
    t |> run("-? prints the help and exits before any kernel runs") @(t : T?) {
        var out : string
        let rc = run_and_capture(["bash", "scripts/run_perf.sh", "-?"], out, 60.0)
        t |> equal(rc, 0, out)
        t |> success(out |> contains("show this help and exit"), out)
        t |> success(!(out |> contains("Captured on")), out)
    }
}
