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
        t |> equal(layout_dir("w", "lua", "source-cut"), "w/source-cut/lua")
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
    t |> run("the AOT lane takes program arguments: the host hands them on, so a missing module fails in the build, not in a refusal") @(t : T?) {
        var error : string
        t |> equal(build_aot("m.das", "perf/work/lanes_aot_args", ["-e", "x"], error), "")
        t |> success(error |> starts_with("the build exited "), error)
        t |> success(error |> contains("error[20605]: missing prerequisite 'm.das'"), error)
        rmdir_rec("perf/work/lanes_aot_args")
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
def test_aot_build_line(t : T?) {
    t |> run("an aot build's reason: the heap line, else the first error line, else the last reported line") @(t : T?) {
        t |> equal(aot_build_line("failed to simulate m.das\nerror[50500]: exception during init script\n at aot_cpp.das:1:2\nout of heap memory, requested 8 bytes\ntotal 3 tracked pointers\n"), "out of heap memory, requested 8 bytes")
        t |> equal(aot_build_line("[I] error in info\nx.cpp:1:2: warning: -Werror=a\nx.cpp:3:4: error: cannot jump\n3 errors generated.\n"), "x.cpp:3:4: error: cannot jump")
        t |> equal(aot_build_line("compile m.das\nerror[30304]: no such function\ntotal 3 tracked pointers\n"), "error[30304]: no such function")
        t |> equal(aot_build_line("/usr/lib/strerror.o\nfake link failure\n[I] done\n"), "fake link failure")
        t |> equal(aot_build_line(""), "")
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
    t |> run("a lane whose sample passes its limit: the error line under the kernel's name, no cell") @(t : T?) {
        var inscope cells : table<string; Cell>
        var errors : array<string>
        measure_lane(cells, errors, "k", "interp", ["sleep", "5"], 1, 0, 1.0)
        t |> equal(join(errors, "|"), "k/interp: a sample took longer than 1 s")
        t |> success(!key_exists(cells, "interp"))
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

[test]
def test_guarded_samples(t : T?) {
    t |> run("a guarded run: sh waiting on prlimit with a one-byte core limit, no core file written, the address space capped only when asked") @(t : T?) {
        t |> equal(join(guarded(["k", "a b"], 0l), "|"), "sh|-c|\"$@\"; exit $?|sh|prlimit|--core=1|--|k|a b")
        t |> equal(join(guarded(["k"], 1073741824l), "|"), "sh|-c|\"$@\"; exit $?|sh|prlimit|--core=1|--as=1073741824|--|k")
        var out : string
        t |> equal(run_and_capture(guarded(["sh", "-c", "ulimit -c; ulimit -v"], 1073741824l), out, 30.0), 0, out)
        t |> equal(out, "0\n1048576\n")
        t |> equal(run_and_capture(guarded(["sh", "-c", "kill -SEGV $$"], 0l), out, 30.0), 139, out)
        t |> success(!(out |> contains("core dumped")), out)
    }
    t |> run("an exit code in words: a signal from 129 to 192, named up to 15, else the code") @(t : T?) {
        t |> equal(exit_text(139), "signal 11 (SEGV)")
        t |> equal(exit_text(133), "signal 5 (TRAP)")
        t |> equal(exit_text(158), "signal 30")
        t |> equal(exit_text(129), "signal 1 (HUP)")
        t |> equal(exit_text(192), "signal 64")
        t |> equal(exit_text(3), "exited 3")
        t |> equal(exit_text(128), "exited 128")
        t |> equal(exit_text(193), "exited 193")
        t |> equal(run_error(134, "\n[I] jit\n"), "signal 6 (ABRT), no output")
        t |> equal(run_error(139, "Segmentation fault (core dumped)\n"), "signal 11 (SEGV), no output")
        t |> equal(run_error(135, "Bus error\nwhy\n"), "signal 7 (BUS): why")
        t |> success(!shell_signal_line("Segmentation fault in f") && shell_signal_line("Aborted"))
    }
    t |> run("a sample dying of a signal: the signal named with its first reported line, never a bare exit code") @(t : T?) {
        var error : string
        let segv <- measure(["sh", "-c", "echo; echo boom >&2; kill -SEGV $$"], 1, error, 30.0)
        t |> equal(error, "signal 11 (SEGV): boom")
        t |> equal(length(segv.samples), 0)
        var abrt_error, exit_error, no_error : string
        let abrt <- measure(["sh", "-c", "kill -ABRT $$"], 1, abrt_error, 30.0)
        t |> success(abrt_error |> starts_with("signal 6 (ABRT)"), abrt_error)
        let exited <- measure(["sh", "-c", "echo why; exit 5"], 1, exit_error, 30.0)
        t |> equal(exit_error, "exited 5: why")
        let timed <- measure(["sh", "-c", "echo 0.25 4 7"], 2, no_error, 30.0)
        t |> equal(no_error, "")
        t |> equal(length(timed.samples), 2, no_error)
        t |> equal(timed.result, 7)
    }
}

[test]
def test_guarded_build_run(t : T?) {
    t |> run("the run an exe or aot build ends with is guarded: a one-byte core limit and the address-space cap asked for") @(t : T?) {
        let work = "perf/work/lanes_guarded_run"
        mkdir_rec(work)
        let limits_path = get_full_file_name(work) + "/limits.txt"
        let das_path = path_join(work, "limits.das")
        fwrite(das_path, "options gen2\nrequire daslib/fio\n[export]\ndef main() : int \{\n    fwrite(\"{limits_path}\", fread(\"/proc/self/limits\"))\n    return 0\n\}\n")
        let no_modules, no_args : array<string>
        for (tier in ["exe", "aot"]) {
            remove(limits_path)
            var error : string
            t |> success(!empty(lane_binary(das_path, tier, path_join(work, tier), no_modules, no_args, error, 600.0, 8589934592l)), "{tier}: {error}")
            let limits = fexist(limits_path) ? fread(limits_path) : ""
            var inscope core <- [for (ln in split(limits, "\n")); ln; where ln |> starts_with("Max core file size")]
            var inscope space <- [for (ln in split(limits, "\n")); ln; where ln |> starts_with("Max address space")]
            t |> success(length(core) == 1 && core[0] |> contains(" 1 "), "{tier}: {limits}")
            t |> success(length(space) == 1 && space[0] |> contains(" 8589934592 "), "{tier}: {limits}")
        }
        rmdir_rec(work)
    }
}

[test]
def test_cpu_override(t : T?) {
    t |> run("$C2DAS_CPU_NAME stands in for the machine's CPU, whatever the box") @(t : T?) {
        let saved = get_env_variable("C2DAS_CPU_NAME")
        set_env_variable("C2DAS_CPU_NAME", "stand-in cpu A")
        let first = cpu_name()
        set_env_variable("C2DAS_CPU_NAME", "stand-in cpu B")
        let second = cpu_name()
        set_env_variable("C2DAS_CPU_NAME", saved)
        t |> equal("{first}|{second}", "stand-in cpu A|stand-in cpu B")
    }
}

[test]
def test_env_gate_prlimit(t : T?) {
    t |> run("the env gate names a missing prlimit") @(t : T?) {
        var dir_error : string
        let shim = create_temp_directory("c2das_no_prlimit", dir_error)
        t |> equal(dir_error, "")
        var out : string
        for (tool in ["bash", "dirname", "cmake", "sed", "head", "git", "ls"]) {
            run_and_capture(["sh", "-c", "ln -s \"$(command -v \"$1\")\" \"$0/$1\"", shim, tool], out, 30.0)
        }
        t |> equal(run_and_capture(["/usr/bin/env", "PATH={shim}", "bash", "scripts/verify_daslang.sh"], out, 60.0), 1, out)
        t |> success(out |> contains("verify: prlimit is not on PATH"), out)
        t |> success(!(out |> contains("cmake is not on PATH")), out)
        rmdir_rec(shim)
    }
}
