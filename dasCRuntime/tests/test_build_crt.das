options gen2
require dastest/testing_boost public
require daslib/fio
require strings

// scripts/build_crt.sh's refusals and the CMake branch that builds `crt` for a libc++ wasm host
// (dasCRuntime/ARCHITECTURE.md section 8), checked without emscripten and without building: each
// refusal fires before cmake runs, and the libc++ branch is only configured.

// runs the shell command `cmd` from the repository root, its stdout and stderr in `out`
def private run_in_repo(cmd : string; var out : string&) : int => run_and_capture(["sh", "-c", "{cmd} 2>&1"], out, 120.0)

[test(description = "build_crt.sh refuses an unknown argument and a --libcxx-host DASLANG_ROOT that is no libc++ host, before any build")]
def test_build_crt_refusals(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_build_crt", dir_error)
    t |> equal(dir_error, "")
    t |> run("an unknown argument exits 2 and names it") @(t : T?) {
        var out : string
        let rc = run_in_repo("bash scripts/build_crt.sh --bogus", out)
        t |> equal(rc, 2, out)
        t |> success(find(out, "unknown argument --bogus") >= 0, out)
    }
    t |> run("--libcxx-host refuses a DASLANG_ROOT with no runtime library") @(t : T?) {
        var out : string
        let rc = run_in_repo("DASLANG_ROOT={work} bash scripts/build_crt.sh --libcxx-host", out)
        t |> equal(rc, 2, out)
        t |> success(find(out, "is no built daslang") >= 0, out)
    }
    t |> run("--libcxx-host refuses the pin, whose runtime library links libstdc++") @(t : T?) {
        var out : string
        let rc = run_in_repo("DASLANG_ROOT={get_das_root()} bash scripts/build_crt.sh --libcxx-host", out)
        t |> equal(rc, 2, out)
        t |> success(find(out, "is not a libc++ host") >= 0, out)
    }
    t |> run("--libcxx-host refuses where ldd is not on PATH") @(t : T?) {
        // a PATH holding only what the script runs before its check: bash and dirname
        let bin = path_join(work, "bin")
        mkdir_rec(bin)
        var out : string
        for (tool in ["bash", "dirname"]) {
            let rc = run_in_repo("ln -s \"$(command -v {tool})\" {bin}/{tool}", out)
            t |> equal(rc, 0, out)
        }
        let rc = run_in_repo("PATH={bin} DASLANG_ROOT={get_das_root()} {bin}/bash scripts/build_crt.sh --libcxx-host", out)
        t |> equal(rc, 2, out)
        t |> success(find(out, "which is not on PATH") >= 0, out)
    }
    rmdir_rec(work)
}

// a copy of dasCRuntime's sources (CMakeLists.txt, .das_module, .das_package, src/) in `into`,
// the package's text replaced by `das_package` when it is not empty
def private copy_crt_sources(t : T?; into, das_package : string) {
    var out : string
    let rc = run_in_repo("mkdir -p {into} && cp -r dasCRuntime/CMakeLists.txt dasCRuntime/.das_module dasCRuntime/.das_package dasCRuntime/src {into}/", out)
    t |> equal(rc, 0, out)
    if (!empty(das_package)) {
        fwrite(path_join(into, ".das_package"), das_package)
    }
}

[test(description = "the DAS_CRT_LIBCXX_HOST configure writes _wasmhost/ with the package pointed at the folder above, and refuses a package it cannot point")]
def test_libcxx_host_configure(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_crt_libcxx", dir_error)
    t |> equal(dir_error, "")
    t |> run("the _wasmhost/ copies: .das_module as is, .das_package with CRT_SOURCE = \"..\"") @(t : T?) {
        let src = path_join(work, "ok")
        copy_crt_sources(t, src, "")
        var out : string
        let rc = run_in_repo("cmake -S {src} -B {work}/ok_build -DDASLANG_ROOT={get_das_root()} -DCMAKE_BUILD_TYPE=Release -DDAS_CRT_LIBCXX_HOST=ON", out)
        t |> equal(rc, 0, out)
        let copied = fread(path_join(src, "_wasmhost/.das_package"))
        t |> success(find(copied, "CRT_SOURCE = \"..\"") >= 0, "the copy points at the folder above")
        t |> success(find(copied, "CRT_SOURCE = \".\"\n") < 0, "the copy keeps no CRT_SOURCE = \".\"")
        t |> equal(fread(path_join(src, "_wasmhost/.das_module")), fread(path_join(src, ".das_module")))
    }
    t |> run("a .das_package without the CRT_SOURCE line stops the configure") @(t : T?) {
        let src = path_join(work, "bad")
        copy_crt_sources(t, src, "options gen2\n")
        var out : string
        let rc = run_in_repo("cmake -S {src} -B {work}/bad_build -DDASLANG_ROOT={get_das_root()} -DCMAKE_BUILD_TYPE=Release -DDAS_CRT_LIBCXX_HOST=ON", out)
        t |> success(rc != 0, out)
        t |> success(find(out, "holds no `CRT_SOURCE") >= 0, out)
    }
    rmdir_rec(work)
}
