options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost
require ../converter/pipeline.das

//! The translator page (web/ARCHITECTURE.md section 8): its program `web/translator/main_web.das` as a
//! desktop run answering requests, `web/translator/precompute.das` over a small manifest, and
//! `scripts/build_translator_site.sh`'s refusals, which come before its first write.

// precompute.das run by the daslang running the test, its output in `out`
def private precompute(args : array<string>; var out : string&) : int {
    var argv <- ["{get_das_root()}/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime", "web/translator/precompute.das", "--"]
    argv |> push_from(args)
    return run_and_capture(argv, out, 300.0)
}

[test(description = "precompute converts each example, records its C, C-IR, module and output, passes the Lua snippets through, and refuses a bad call and a program that exits nonzero")]
def test_precompute(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_translator_pre", dir_error)
    t |> equal(dir_error, "")
    let manifest = path_join(work, "examples.json")
    fwrite(path_join(work, "hi.c"), "#include <stdio.h>\nint main(void) \{ printf(\"hi %d\\n\", 6 * 7); return 0; \}\n")
    fwrite(manifest, "\{\"examples\": [\{\"id\": \"hi\", \"title\": \"hi\", \"file\": \"hi.c\", \"about\": \"a test\"\}], \"lua\": [\{\"id\": \"l\", \"title\": \"l\", \"code\": \"print(1)\"\}]\}")
    let out_json = path_join(work, "out.json")
    var out : string
    let rc = precompute([manifest, out_json, path_join(work, "w")], out)
    t |> equal(rc, 0, out)
    var error : string
    var bundle = read_json(fread(out_json), error)
    t |> success(bundle != null, error)
    if (bundle != null) {
        let ex = bundle?["examples"]?[0]
        t |> equal(ex?["id"] ?? "", "hi")
        t |> success(starts_with(ex?["c"] ?? "", "#include <stdio.h>"), "the C source")
        t |> success(find(ex?["cir"] ?? "", "\"main\"") >= 0, "the C-IR names main")
        t |> success(find(ex?["das"] ?? "", "def c_main") >= 0 || find(ex?["das"] ?? "", "def main") >= 0, "the module")
        t |> equal(ex?["output"] ?? "", "hi 42\n")
        t |> equal(bundle?["lua"]?[0]?["code"] ?? "", "print(1)")
    }
    let usage = precompute([manifest], out)
    t |> equal(usage, 2, out)
    fwrite(path_join(work, "bad.c"), "int main(void) \{ return 3; \}\n")
    let bad_manifest = path_join(work, "bad.json")
    fwrite(bad_manifest, "\{\"examples\": [\{\"id\": \"bad\", \"file\": \"bad.c\"\}], \"lua\": []\}")
    let rc_bad = precompute([bad_manifest, path_join(work, "bad_out.json"), path_join(work, "w")], out)
    t |> equal(rc_bad, 1, out)
    t |> success(find(out, "exits 3") >= 0, out)
    rmdir_rec(work)
}

// main_web.das staged beside the converter's modules in `stage`, as the build stages it, answering
// the request in `io`: what it answered, "out.das:<module>" or "out.err:<error>"
def private answer(t : T?; stage, io, cir, sidecar : string) : string {
    for (f in ["go", "done", "out.das", "out.err"]) {
        remove(path_join(io, f))
    }
    fwrite(path_join(io, "in.cir.json"), cir)
    fwrite(path_join(io, "sidecar.c2das"), sidecar)
    fwrite(path_join(io, "go"), "")
    var out : string
    let rc = run_and_capture(["{get_das_root()}/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime", path_join(stage, "main_web.das"), "--", io], out, 300.0)
    t |> equal(rc, 0, out)
    t |> success(fexist(path_join(io, "done")), "the request is answered: {out}")
    t |> success(!fexist(path_join(io, "go")), "the request is taken")
    if (fexist(path_join(io, "out.err"))) {
        return "out.err:{fread(path_join(io, "out.err"))}"
    }
    return "out.das:{fread(path_join(io, "out.das"))}"
}

[test(description = "main_web.das answers a request with the pipeline's module under the knobs, a bad sidecar and a bad C-IR with their errors")]
def test_main_web(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_translator_host", dir_error)
    t |> equal(dir_error, "")
    let stage = path_join(work, "stage")
    let io = path_join(work, "io")
    mkdir_rec(stage)
    mkdir_rec(io)
    var out : string
    let rc_stage = run_and_capture(["sh", "-c", "cp converter/*.das web/translator/main_web.das '{stage}/' && mkdir '{work}/frontend' && cp frontend/c_defines.das '{work}/frontend/'"], out, 30.0)
    t |> equal(rc_stage, 0, out)
    let c_path = path_join(work, "hi.c")
    fwrite(c_path, "int pick(int k) \{ switch (k) \{ case 0: return 5; case 1: return 7; case 2: return 9; default: return 0; \} \}
int main(void) \{ return pick(1); \}
")
    let res <- convert(c_path, path_join(work, "native"), "linux", "", "", "", "", "", "goto")
    t |> success(res.ok, res.error)
    let good = answer(t, stage, io, res.cir_text, "\{\"switch_dispatch\": \"goto\"\}")
    t |> equal(good, "out.das:{res.das_text}")
    let bad_side = answer(t, stage, io, res.cir_text, "\{\"switch_dispatch\": \"sideways\"\}")
    t |> success(starts_with(bad_side, "out.err:sidecar: "), bad_side)
    let bad_cir = answer(t, stage, io, "\{ not c-ir", "\{\}")
    t |> success(starts_with(bad_cir, "out.err:reader: "), bad_cir)
    rmdir_rec(work)
}

// VERSIONS.md's daScript pin, the 40 digits after "daScript commit: "
def private find_pin(versions : string) : string {
    let at = find(versions, "daScript commit: ")
    return at < 0 ? "" : slice(versions, at + 17, at + 57)
}

// build_translator_site.sh with `args`, its output in `out`
def private build_site(args : string; var out : string&) : int => run_and_capture(["sh", "-c", "bash scripts/build_translator_site.sh {args} 2>&1"], out, 120.0)

[test(description = "build_translator_site.sh refuses --commit without --pages, a missing --ports, a ports checkout without Lua, a --pages that is no checkout, c2das-ports' gh-pages, a missing --interp, one without the interpreter, one of another daScript, one whose crt is no commit here and one whose crt is older than this tree's")]
def test_build_translator_refusals(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_translator_ref", dir_error)
    t |> equal(dir_error, "")
    let out_dir = path_join(work, "out")
    var out : string
    let rc_commit = build_site("--commit --out '{out_dir}'", out)
    t |> equal(rc_commit, 1, out)
    t |> success(find(out, "there is none") >= 0, out)
    let rc_ports = build_site("--out '{out_dir}'", out)
    t |> equal(rc_ports, 1, out)
    t |> success(find(out, "--ports <c2das-ports checkout> is required") >= 0, out)
    let rc_lua = build_site("--ports '{work}' --out '{out_dir}'", out)
    t |> equal(rc_lua, 1, out)
    t |> success(find(out, "holds no converted Lua") >= 0, out)
    let rc_pages = build_site("--ports '{work}' --pages '{work}' --out '{out_dir}'", out)
    t |> equal(rc_pages, 1, out)
    t |> success(find(out, "is not a git checkout") >= 0, out)
    let ports_pages = path_join(work, "ports_pages")
    let rc_init = run_and_capture(["sh", "-c", "git init -q -b gh-pages '{ports_pages}' && git -C '{ports_pages}' remote add origin https://github.com/lookibed/c2das-ports.git && git -C '{ports_pages}' -c user.name=t -c user.email=t@t commit -q --allow-empty -m old"], out, 30.0)
    t |> equal(rc_init, 0, out)
    let rc_other = build_site("--ports '{work}' --pages '{ports_pages}' --out '{out_dir}'", out)
    t |> equal(rc_other, 1, out)
    t |> success(find(out, "not of c2das-re") >= 0, out)
    let fake_ports = path_join(work, "ports")
    mkdir_rec(path_join(fake_ports, "lua/readable/lua"))
    fwrite(path_join(fake_ports, "lua/readable/lua/lua.das"), "")
    let rc_no_interp = build_site("--ports '{fake_ports}' --out '{out_dir}'", out)
    t |> equal(rc_no_interp, 1, out)
    t |> success(find(out, "--interp <dir> is required") >= 0, out)
    let rc_empty_interp = build_site("--ports '{fake_ports}' --interp '{work}' --out '{out_dir}'", out)
    t |> equal(rc_empty_interp, 1, out)
    t |> success(find(out, "no daslang_static.js in") >= 0, out)
    let interp = path_join(work, "interp")
    mkdir_rec(interp)
    fwrite(path_join(interp, "daslang_static.js"), "")
    fwrite(path_join(interp, "daslang_static.wasm"), "")
    fwrite(path_join(interp, "interp.json"), "\{\"daslang\": \"0000000000\", \"crt\": \"0000000000\"\}")
    let rc_pin = build_site("--ports '{fake_ports}' --interp '{interp}' --out '{out_dir}'", out)
    t |> equal(rc_pin, 1, out)
    t |> success(find(out, "VERSIONS.md pins") >= 0 && find(out, "rebuild it") >= 0, out)
    let pin = slice(fread("VERSIONS.md") |> find_pin(), 0, 10)
    fwrite(path_join(interp, "interp.json"), "\{\"daslang\": \"{pin}\", \"crt\": \"0000000000\"\}")
    let rc_crt = build_site("--ports '{fake_ports}' --interp '{interp}' --out '{out_dir}'", out)
    t |> equal(rc_crt, 1, out)
    t |> success(find(out, "names no crt commit of this repository") >= 0, out)
    // 2ca8718 bound functions dasCRuntime/src has kept since: its crt is not this tree's
    fwrite(path_join(interp, "interp.json"), "\{\"daslang\": \"{pin}\", \"crt\": \"2ca8718\"\}")
    let rc_old = build_site("--ports '{fake_ports}' --interp '{interp}' --out '{out_dir}'", out)
    t |> equal(rc_old, 1, out)
    t |> success(find(out, "dasCRuntime/src changed since the interpreter's crt") >= 0, out)
    t |> success(!fexist(out_dir), "no refusal created the --out folder")
    rmdir_rec(work)
}

[test(description = "bundle.das writes a module folder's .das_module and registered .das files as one JSON object, path to text, and refuses a folder that is no module, a module with no .das file, an unwritable output and a bad call")]
def test_bundle(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_translator_bundle", dir_error)
    t |> equal(dir_error, "")
    let out_json = path_join(work, "c_runtime.json")
    var out : string
    let rc = run_and_capture(["{get_das_root()}/bin/daslang", "web/translator/bundle.das", "--", "c_runtime", out_json], out, 120.0)
    t |> equal(rc, 0, out)
    var error : string
    var bundle = read_json(fread(out_json), error)
    t |> success(bundle != null, error)
    if (bundle != null) {
        t |> equal(bundle?["c_runtime/c_function.das"] ?? "", fread("c_runtime/c_runtime/c_function.das"))
        t |> equal(bundle?["c_runtime/printf.das"] ?? "", fread("c_runtime/c_runtime/printf.das"))
        t |> equal(bundle?[".das_module"] ?? "", fread("c_runtime/.das_module"))
        t |> success(!key_exists(bundle, "REVIEW.das"), "only the registered folder")
    }
    let rc_empty = run_and_capture(["{get_das_root()}/bin/daslang", "web/translator/bundle.das", "--", work, path_join(work, "x.json")], out, 120.0)
    t |> equal(rc_empty, 1, out)
    let rc_usage = run_and_capture(["{get_das_root()}/bin/daslang", "web/translator/bundle.das", "--", work], out, 120.0)
    t |> equal(rc_usage, 2, out)
    let bare = path_join(work, "bare")
    mkdir_rec(path_join(bare, "bare"))
    fwrite(path_join(bare, ".das_module"), "")
    let rc_bare = run_and_capture(["{get_das_root()}/bin/daslang", "web/translator/bundle.das", "--", bare, path_join(work, "y.json")], out, 120.0)
    t |> equal(rc_bare, 1, out)
    t |> success(find(out, "no .das file in") >= 0, out)
    let rc_write = run_and_capture(["{get_das_root()}/bin/daslang", "web/translator/bundle.das", "--", "c_runtime", path_join(work, "missing/dir/z.json")], out, 120.0)
    t |> equal(rc_write, 1, out)
    t |> success(find(out, "cannot write") >= 0, out)
    rmdir_rec(work)
}

[test(description = "build_interp.sh refuses a bad call, and a work folder whose daScript is not the pin, before it writes or fetches anything")]
def test_build_interp_refusals(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_translator_interp", dir_error)
    t |> equal(dir_error, "")
    var out : string
    let rc_usage = run_and_capture(["bash", "web/translator/interp/build_interp.sh"], out, 30.0)
    t |> equal(rc_usage, 2, out)
    t |> success(find(out, "usage:") >= 0 && find(out, "set -euo") < 0, out)
    let other = path_join(work, "daScript")
    let rc_init = run_and_capture(["sh", "-c", "git init -q '{other}' && git -C '{other}' -c user.name=t -c user.email=t@t commit -q --allow-empty -m other"], out, 30.0)
    t |> equal(rc_init, 0, out)
    let rc_pin = run_and_capture(["bash", "web/translator/interp/build_interp.sh", work], out, 30.0)
    t |> equal(rc_pin, 1, out)
    t |> success(find(out, "is not at the pin") >= 0, out)
    t |> success(!fexist(path_join(work, "emsdk")), "nothing fetched")
    rmdir_rec(work)
}

[test(description = "with an interpreter named by C2DAS_INTERP, an example converted here runs in it as the page's Run runs it, with the output of the native interpreter")]
def test_run_in_interpreter(t : T?) {
    if (!has_env_variable("C2DAS_INTERP")) {
        t |> skip("no C2DAS_INTERP: the interpreter is built by web/translator/interp/build_interp.sh")
        return
    }
    if (!executable_on_path("node")) {
        t |> skip("no node: the run is checked where node runs")
        return
    }
    var dir_error : string
    let work = create_temp_directory("c2das_translator_run", dir_error)
    t |> equal(dir_error, "")
    fwrite(path_join(work, "hi.c"), fread("web/translator/examples/hello.c"))
    let manifest = path_join(work, "examples.json")
    fwrite(manifest, "\{\"examples\": [\{\"id\": \"hello\", \"file\": \"hi.c\"\}], \"lua\": []\}")
    var out : string
    let rc_pre = precompute([manifest, path_join(work, "out.json"), path_join(work, "w")], out)
    t |> equal(rc_pre, 0, out)
    let rc_lib = run_and_capture(["{get_das_root()}/bin/daslang", "web/translator/bundle.das", "--", "c_runtime", path_join(work, "c_runtime.json")], out, 120.0)
    t |> equal(rc_lib, 0, out)
    let rc = run_and_capture(["node", "web/translator/interp/run_examples.js", get_env_variable("C2DAS_INTERP"), path_join(work, "out.json"), path_join(work, "c_runtime.json")], out, 600.0)
    t |> equal(rc, 0, out)
    t |> success(find(out, "hello ok") >= 0, out)
    rmdir_rec(work)
}

