options gen2
require dastest/testing_boost public
require daslib/fio
require strings

// The wasm64 archive of `crt` (dasCRuntime/ARCHITECTURE.md section 8), built the way the package's
// release_wasm_build hook builds it, into a scratch folder. Where emscripten is not on PATH the test
// is skipped: no gate installs the toolchain (docs/implementation_order.md, P9.35).

def private on_path(tool : string) : bool {
    var out : string
    return run_and_capture(["sh", "-c", "command -v {tool}"], out, 30.0) == 0
}

[test(description = "the emscripten build of dasCRuntime gives liblibDasModuleCRuntime.a, which defines the registration a cross-compiled program calls", timeout = 1200)]
def test_crt_wasm_archive(t : T?) {
    t |> run("emcmake builds the archive, and it defines jit_register_Module_CRT") @(t : T?) {
        if (!on_path("emcmake") || !on_path("emnm")) {
            t |> skip("emscripten (emcmake, emnm) is not on PATH: the wasm toolchain is opt-in, P9.35")
            return
        }
        var dir_error : string
        let work = create_temp_directory("c2das_crt_wasm", dir_error)
        t |> equal(dir_error, "")
        let source = get_full_file_name("dasCRuntime")
        let out_dir = path_join(work, "out")
        var out : string
        let configured = run_and_capture(["emcmake", "cmake", "-S", source, "-B", path_join(work, "build"),
            "-DDASLANG_ROOT={get_das_root()}", "-DCMAKE_BUILD_TYPE=Release", "-DDAS_CRT_WASM_DIR={out_dir}", "-G", "Ninja"], out, 600.0)
        t |> equal(configured, 0, out)
        if (configured == 0) {
            let built = run_and_capture(["cmake", "--build", path_join(work, "build")], out, 1200.0)
            t |> equal(built, 0, out)
            let archive = path_join(out_dir, "liblibDasModuleCRuntime.a")
            t |> equal(run_and_capture(["emnm", "--defined-only", archive], out, 120.0), 0, out)
            t |> success(find(out, " T jit_register_Module_CRT") >= 0, "the archive's defined symbols name jit_register_Module_CRT")
        }
        rmdir_rec(work)
    }
}
