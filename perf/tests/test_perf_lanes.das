options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../perf_lanes.das
require ../perf_measure.das
require ../../converter/dumper_a.das

//! The shared lane module: the sample arithmetic, the output lines a lane's error quotes, the
//! native and das lane commands, the AOT tier's refusal of program arguments and its binary's name,
//! and the line an exe build's failure quotes.

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
    t |> run("lines without a prefix keep every other line, blanks included; a program's output drops the info lines") @(t : T?) {
        t |> equal(join(lines_without("a\n# x\n\nb", "# "), "|"), "a||b")
        t |> equal(program_output("[I] jit\nout\n[I] more\nend"), "out\nend")
    }
    t |> run("a command in a folder runs through sh there; in no folder it is the command itself") @(t : T?) {
        t |> equal(join(in_folder("/tmp/w", ["prog", "a b"]), "|"), "sh|-c|cd \"$0\" && exec \"$@\"|/tmp/w|prog|a b")
        t |> equal(join(in_folder("", ["prog"]), "|"), "prog")
        var out : string
        t |> equal(run_and_capture(in_folder("/", ["pwd"]), out, 30.0), 0, out)
        t |> equal(strip(out), "/")
    }
    t |> run("the source layout's conversion lands in its stem's folder, the others in the layout's") @(t : T?) {
        t |> equal(layout_dir("w", "lua", "source"), "w/lua")
        t |> equal(layout_dir("w", "lua", "scc"), "w/scc/lua")
        t |> equal(layout_dir("w", "lua", "single"), "w/single/lua")
    }
}

[test]
def test_commands(t : T?) {
    t |> run("the native lane: the pinned clang at -O3 with unsigned char, the program's files in order, the libraries last") @(t : T?) {
        let cmd <- native_build_command(["k.c"], "k_native", ["-lm"])
        t |> equal(join(cmd, " "), "{default_clang()} -O3 -w -funsigned-char -o k_native k.c -lm")
        let program <- native_build_command(["a.c", "b.c"], "p_native", ["-lm"])
        t |> equal(join(program, " "), "{default_clang()} -O3 -w -funsigned-char -o p_native a.c b.c -lm")
    }
    t |> run("the interpreter and JIT lanes: daslang, the module folders, the flag, the module") @(t : T?) {
        t |> equal(join(das_lane_command("m.das", "", ["a"]), " "), "{get_das_root()}/bin/daslang -load_module a m.das")
        t |> equal(join(das_lane_command("m.das", "-jit", ["a", "b"]), " "), "{get_das_root()}/bin/daslang -load_module a -load_module b -jit m.das")
    }
    t |> run("the AOT lane refuses program arguments: no binary, the tier's reason alone, since no build ran") @(t : T?) {
        var error : string
        t |> equal(build_aot("m.das", "perf/work/none", ["-e", "x"], error), "")
        t |> equal(error, "the aot tier's host passes the program no arguments")
    }
    t |> run("the AOT lane removes an earlier binary by the tier's name for it, the stem spelled as a C++ identifier") @(t : T?) {
        let stale = "perf/work/lanes_aot_name/ctx/no_such_module_aot"
        mkdir_rec("perf/work/lanes_aot_name/ctx")
        fwrite(stale, "stale\n")
        let no_args : array<string>
        var error : string
        t |> equal(build_aot("perf/work/lanes_aot_name/no-such-module.das", "perf/work/lanes_aot_name", no_args, error), "")
        t |> success(!fexist(stale), "an earlier binary survived: {error}")
        t |> success(error |> starts_with("the build exited "), error)
        rmdir_rec("perf/work/lanes_aot_name")
    }
}

[test]
def test_exe_build_line(t : T?) {
    t |> run("an exe build's reason is the linker's line after daslang's Output: line, else the first reported line") @(t : T?) {
        t |> equal(exe_build_line("[I] LLVM EXE: x\nFailed to link Library a.exe, command 'c++ ...'\nOutput:\n\nld: cannot find -lfoo\nwrite_artifact: link failed\n"), "ld: cannot find -lfoo")
        t |> equal(exe_build_line("[I] LLVM EXE: x\nerror[30304]: no such function\n"), "error[30304]: no such function")
        t |> equal(exe_build_line("Failed to link Library a.exe\nOutput:\n"), "Failed to link Library a.exe")
    }
}

[test]
def test_time_limits(t : T?) {
    t |> run("a sample past its limit is the lane's error, no cell") @(t : T?) {
        var error : string
        let cell <- measure(["sleep", "5"], 1, error, 1.0)
        t |> equal(error, "a sample took longer than 1 s")
        t |> equal(length(cell.samples), 0)
    }
    t |> run("an exe build whose run never ends leaves no lane, the limit named") @(t : T?) {
        let work = "perf/work/lanes_exe_limit"
        mkdir_rec(work)
        let das_path = path_join(work, "forever.das")
        fwrite(das_path, "options gen2\n[export]\ndef main() : int \{\n    var i = 0\n    while (i >= 0) \{\n        i = (i + 1) % 7\n    \}\n    return i\n\}\n")
        let no_args : array<string>
        var error : string
        t |> equal(build_exe(das_path, work, no_args, error, 20.0), "")
        t |> equal(error, "the build or its run took longer than 20 s")
        rmdir_rec(work)
    }
}
