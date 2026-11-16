options gen2
require dastest/testing_boost public
require daslib/fio
require strings
require daslib/strings_boost

// The wasm64 archive of `crt` (dasCRuntime/ARCHITECTURE.md section 8), built the way the package's
// release_wasm_build hook builds it, into a scratch folder. Where emscripten, cmake or ninja is not on
// PATH the test is skipped: no gate installs the toolchain (docs/implementation_order.md, P9.35). An
// emscripten other than the one VERSIONS.md pins is refused.

def private on_path(tool : string) : bool {
    var out : string
    return run_and_capture(["sh", "-c", "command -v {tool}"], out, 30.0) == 0
}

// the version of the `emscripten:` line of VERSIONS.md, empty when there is none
def private pinned_emscripten : string {
    let prefix = "emscripten: "
    for (line in split(fread("VERSIONS.md"), "\n")) {
        if (starts_with(line, prefix)) {
            let rest = slice(line, length(prefix))
            let space = find(rest, " ")
            return space < 0 ? rest : slice(rest, 0, space)
        }
    }
    return ""
}

[test(description = "the emscripten build of dasCRuntime gives liblibDasModuleCRuntime.a, which defines the registration a cross-compiled program calls", timeout = 1200)]
def test_crt_wasm_archive(t : T?) {
    t |> run("emcmake builds the archive, and it defines jit_register_Module_CRT") @(t : T?) {
        for (tool in ["emcmake", "emcc", "emnm", "cmake", "ninja"]) {
            if (!on_path(tool)) {
                t |> skip("{tool} is not on PATH: the wasm toolchain is opt-in, P9.35")
                return
            }
        }
        let pinned = pinned_emscripten()
        t |> success(!empty(pinned), "VERSIONS.md has an `emscripten:` line")
        var out : string
        t |> equal(run_and_capture(["emcc", "--version"], out, 30.0), 0, out)
        let first_line = split(out, "\n")[0]
        if (find(first_line, ") {pinned} (") < 0) {
            t |> failure("emcc on PATH is not the emscripten {pinned} VERSIONS.md pins: {first_line}")
            return
        }
        var dir_error : string
        let work = create_temp_directory("c2das_crt_wasm", dir_error)
        t |> equal(dir_error, "")
        let out_dir = path_join(work, "out")
        let configured = run_and_capture(["emcmake", "cmake", "-S", get_full_file_name("dasCRuntime"),
            "-B", path_join(work, "build"), "-DDASLANG_ROOT={get_das_root()}", "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_C_FLAGS=-sMEMORY64=1", "-DCMAKE_CXX_FLAGS=-sMEMORY64=1", "-DDAS_CRT_WASM_DIR={out_dir}",
            "-G", "Ninja"], out, 300.0)
        t |> equal(configured, 0, out)
        if (configured == 0) {
            let built = run_and_capture(["cmake", "--build", path_join(work, "build")], out, 600.0)
            t |> equal(built, 0, out)
            let archive = path_join(out_dir, "liblibDasModuleCRuntime.a")
            t |> equal(run_and_capture(["emnm", "--defined-only", archive], out, 60.0), 0, out)
            t |> success(find(out, " T jit_register_Module_CRT") >= 0, "the archive's defined symbols name jit_register_Module_CRT")
        }
        rmdir_rec(work)
    }
}
