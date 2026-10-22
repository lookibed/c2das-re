options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require math
require ../ports_render.das

//! The renderer over fixed captures: the times, ratio and not-yet text, the geometric means of
//! the projects table, the top-level README's marker, the license block and the VERSIONS.md pin.

def private cell(workload, lane : string; time : double) : LaneCell => <- LaneCell(workload = workload, lane = lane, time = time, spread = 0.02lf, samples <- [time])

def private failed(workload, lane, error : string) : LaneCell => <- LaneCell(workload = workload, lane = lane, error = error)

// two workloads and the startup row; interp everywhere, jit on one workload, aot a lane error,
// exe a failed cell
def private fixture : Capture => <- Capture(
    program = "lua", timestamp = "2026-10-22 10:00 UTC", samples = 3,
    machine = Machine(arch = "x86_64", cpu = "CPU", clang = "clang version 22", daslang = "0.6.4"),
    lanes <- [for (lane in ["native", "interp", "jit", "exe", "aot"]); Lane(name = lane, command = "run {lane}", error = lane == "aot" ? "no arguments" : "")],
    workloads <- [
        Workload(name = "startup", args = "-e \"print(1)\"", startup = true),
        Workload(name = "fib", args = "bench/fib.lua"),
        Workload(name = "nbody", args = "bench/nbody.lua")
    ],
    cells <- [
        cell("startup", "native", 0.001lf),
        cell("startup", "interp", 10.0lf),
        cell("fib", "native", 1.0lf),
        cell("fib", "interp", 200.0lf),
        cell("fib", "jit", 8.0lf),
        failed("fib", "exe", "exited 3"),
        failed("fib", "aot", "no arguments"),
        cell("nbody", "native", 2.0lf),
        cell("nbody", "interp", 100.0lf),
        failed("nbody", "jit", "prints `x`")
    ])

[test]
def test_tables(t : T?) {
    t |> run("the times table: a cell per workload and lane, `not yet` for a failed cell, n/a for a missing one") @(t : T?) {
        let c <- fixture()
        t |> equal(render_times(c), "| Workload | Arguments         |    clang -O3 |    interpreter |          JIT |     exe |     AOT |\n| :------- | :---------------- | -----------: | -------------: | -----------: | ------: | ------: |\n| startup  | `-e \"print(1)\"`   | 0.001 s ±2% |  10.000 s ±2% |          n/a |     n/a |     n/a |\n| fib      | `bench/fib.lua`   | 1.000 s ±2% | 200.000 s ±2% | 8.000 s ±2% | not yet | not yet |\n| nbody    | `bench/nbody.lua` | 2.000 s ±2% | 100.000 s ±2% |      not yet |     n/a |     n/a |\n")
    }
    t |> run("the ratio table: each das lane over native, then the lane pairs") @(t : T?) {
        let c <- fixture()
        let text = render_ratios(c)
        t |> success(text |> starts_with("| Workload | Arguments         | interpreter / native | JIT / native | exe / native | AOT / native | interpreter / JIT | interpreter / exe | interpreter / AOT | JIT / AOT |"), text)
        t |> success(text |> contains("| fib      | `bench/fib.lua`   |               200.00 |         8.00 |          n/a |          n/a |             25.00 |               n/a |               n/a |       n/a |"), text)
    }
    t |> run("not yet: a lane error once for every workload, a failed cell of a working lane on its own line") @(t : T?) {
        let c <- fixture()
        let lines <- render_not_yet(c)
        t |> equal(join(lines, "\n"), "- nbody, JIT: not yet: prints `x`\n- fib, exe: not yet: exited 3\n- AOT, every workload: not yet: no arguments")
    }
    t |> run("the perf section names the machine, the samples and every lane's command") @(t : T?) {
        let c <- fixture()
        let text = render_perf(c)
        t |> success(text |> starts_with("Captured 2026-10-22 10:00 UTC on x86_64, CPU; clang version 22; daslang 0.6.4. A cell is the median wall time of 3 runs"), text)
        t |> success(text |> contains("- JIT: `run jit`\n"), text)
        t |> success(text |> ends_with("Not yet:\n\n- nbody, JIT: not yet: prints `x`\n- fib, exe: not yet: exited 3\n- AOT, every workload: not yet: no arguments\n"), text)
    }
}

[test]
def test_projects(t : T?) {
    t |> run("the geometric mean skips the startup row and the cells that do not stand") @(t : T?) {
        let c <- fixture()
        var count = 0
        t |> equal(round(geomean_ratio(c, "interp", count) * 1000.0lf), round(sqrt(200.0lf * 50.0lf) * 1000.0lf))
        t |> equal(count, 2)
        t |> equal(round(geomean_ratio(c, "jit", count) * 1000.0lf), 8000.0lf)
        t |> equal(count, 1)
        t |> equal(geomean_ratio(c, "aot", count), 0.0lf)
        t |> equal(count, 0)
    }
    t |> run("a projects row: all workloads bare, some named, none `not yet`") @(t : T?) {
        var captures : array<Capture>
        captures |> emplace(fixture())
        t |> equal(render_projects(captures), "| Program              | Captured             | Workloads | interpreter |           JIT |     exe |     AOT |\n| :------------------- | :------------------- | --------: | ----------: | ------------: | ------: | ------: |\n| [lua](lua/README.md) | 2026-10-22 10:00 UTC |         2 |      100.00 | 8.00 (1 of 2) | not yet | not yet |\n")
    }
    t |> run("the top-level README keeps the charter above the marker and replaces what is under it") @(t : T?) {
        var captures : array<Capture>
        captures |> emplace(fixture())
        let first = render_top_readme("# ports\n\ncharter\n", captures, true)
        t |> success(first |> starts_with("# ports\n\ncharter\n\n{README_MARKER}\n\n## Programs\n\n"), first)
        t |> success(first |> contains("[lua](lua/README.md)"), first)
        let again = render_top_readme(first + "stale\n", captures, true)
        t |> equal(again, first)
        var none : array<Capture>
        t |> success(render_top_readme(first, none, true) |> ends_with("No program has a capture yet.\n"))
        // without --perf the projects section is the one line the perf method audit leaves
        t |> equal(render_top_readme(first, captures, false), "# ports\n\ncharter\n\n{README_MARKER}\n\n## Programs\n\n{PERF_NOT_YET}\n")
    }
}

[test]
def test_sources(t : T?) {
    t |> run("the license block runs from Copyright (C) to DEALINGS IN THE SOFTWARE., the `* ` stripped") @(t : T?) {
        let header = "/*\n* lua.h\n*/\n/***\n* Copyright (C) 1994 Someone.\n*\n* Permission is granted.\n* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n****/\n"
        t |> equal(license_block(header), "Copyright (C) 1994 Someone.\n\nPermission is granted.\nSOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n")
        t |> equal(license_block("* Copyright (C) 1994\n* never closed\n"), "")
        t |> equal(license_block("int x;\n"), "")
    }
    t |> run("the VERSIONS.md pin: the version and every tarball with its sha256") @(t : T?) {
        let a = repeat("a", 64)
        let b = repeat("b", 64)
        var release : Release
        t |> success(release_of("# pins\nlua: 9.9 (the release https://x.invalid/lua-9.9.tar.gz (sha256 {a}) and https://x.invalid/t.tar.gz (sha256 {b}))\n", "lua", release))
        t |> equal(release.version, "9.9")
        t |> equal(length(release.tarballs), 2)
        t |> equal(release.tarballs[0].url, "https://x.invalid/lua-9.9.tar.gz")
        t |> equal(release.tarballs[0].sha256, a)
        t |> equal(release.tarballs[1].sha256, b)
        var missing : Release
        t |> success(!release_of("doom: 1\n", "lua", missing))
    }
}
