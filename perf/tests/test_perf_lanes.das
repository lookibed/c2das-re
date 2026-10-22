options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../perf_lanes.das
require ../../converter/dumper_a.das

//! The shared lane module: the sample arithmetic, the output lines a lane's error quotes, the
//! native and das lane commands, and the AOT tier's refusal of program arguments.

[test]
def test_samples(t : T?) {
    t |> run("the median of an odd and an even count, 0 for none") @(t : T?) {
        t |> equal(median_of([3.0lf, 1.0lf, 2.0lf]), 2.0lf)
        t |> equal(median_of([4.0lf, 1.0lf, 3.0lf, 2.0lf]), 2.5lf)
        let none : array<double>
        t |> equal(median_of(none), 0.0lf)
    }
    t |> run("the spread is half the range over the median, 0 without samples or a median") @(t : T?) {
        t |> equal(spread_of([1.0lf, 3.0lf, 2.0lf], 2.0lf), 0.5lf)
        let none : array<double>
        t |> equal(spread_of(none, 2.0lf), 0.0lf)
        t |> equal(spread_of([1.0lf], 0.0lf), 0.0lf)
    }
    t |> run("the first reported line skips info lines and blanks; the last line skips blanks") @(t : T?) {
        t |> equal(first_reported_line("\n[I] jit\n  ld: failed  \nmore\n"), "ld: failed")
        t |> equal(first_reported_line("[I] only\n"), "")
        t |> equal(last_line("a\nb  \n\n"), "b")
        t |> equal(last_line(""), "")
    }
}

[test]
def test_commands(t : T?) {
    t |> run("the native lane: the pinned clang at -O3 with unsigned char, the libraries last") @(t : T?) {
        let cmd <- native_build_command("k.c", "k_native", ["-lm"])
        t |> equal(join(cmd, " "), "{default_clang()} -O3 -w -funsigned-char -o k_native k.c -lm")
    }
    t |> run("the interpreter and JIT lanes: daslang, the module folders, the flag, the module") @(t : T?) {
        t |> equal(join(das_lane_command("m.das", "", ["a"]), " "), "{get_das_root()}/bin/daslang -load_module a m.das")
        t |> equal(join(das_lane_command("m.das", "-jit", ["a", "b"]), " "), "{get_das_root()}/bin/daslang -load_module a -load_module b -jit m.das")
    }
    t |> run("the AOT lane refuses program arguments: no binary, the tier's reason") @(t : T?) {
        var error : string
        t |> equal(build_aot("m.das", "perf/work/none", ["-e", "x"], error), "")
        t |> equal(error, "the build exited -1 and left no binary: the aot tier's host passes the program no arguments")
    }
}
