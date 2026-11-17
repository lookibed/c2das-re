options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost

//! The translator page's build (web/ARCHITECTURE.md section 8): `web/translator/precompute.das` over a
//! small manifest, and `scripts/build_translator_site.sh`'s refusals, which come before its first write.

// precompute.das run by the daslang running the test, its output in `out`
def private precompute(args : array<string>; var out : string&) : int {
    var argv <- ["{get_das_root()}/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime", "web/translator/precompute.das", "--"]
    argv |> push_from(args)
    return run_and_capture(argv, out, 300.0)
}

[test(description = "precompute converts each example, records its C, C-IR, module and output, passes the Lua snippets through, and refuses a bad call")]
def test_precompute(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_translator_pre", dir_error)
    t |> equal(dir_error, "")
    let manifest = path_join(work, "examples.json")
    fwrite(path_join(work, "hi.c"), "#include <stdio.h>\nint main(void) \{ printf(\"hi %d\\n\", 6 * 7); return 0; \}\n")
    fwrite(manifest, "\{\"examples\": [\{\"id\": \"hi\", \"title\": \"hi\", \"file\": \"hi.c\", \"about\": \"a test\"\}], \"lua\": [\{\"id\": \"l\", \"title\": \"l\", \"code\": \"print(1)\"\}]\}")
    fwrite(path_join(work, "doom.c2das"), "\{\"defines\": []\}")
    let out_json = path_join(work, "out.json")
    var out : string
    let rc = precompute([manifest, path_join(work, "doom.c2das"), out_json, path_join(work, "w")], out)
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
    rmdir_rec(work)
}

// build_translator_site.sh with `args`, its output in `out`
def private build_site(args : string; var out : string&) : int => run_and_capture(["sh", "-c", "bash scripts/build_translator_site.sh {args} 2>&1"], out, 120.0)

[test(description = "build_translator_site.sh refuses --commit without --pages, a missing --ports, a ports checkout without Lua, and a --pages that is no gh-pages checkout")]
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
    t |> success(!fexist(out_dir), "no refusal created the --out folder")
    rmdir_rec(work)
}
