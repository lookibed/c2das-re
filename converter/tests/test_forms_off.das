options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../tiers.das
require ../dumper_a.das
require ../sidecar.das

//! `forms_off` and `--forms-off`: each form spelled as before it was introduced, the program
//! printing what its native build prints; the sidecar's list read and refused.

// each form, its fixture and the text the form gives (`default`) and the old spelling (`off`)
struct FormCase {
    form : string
    fixture : string
    default_text : string
    off_text : string
}

def private form_cases : array<FormCase> {
    return <- [
        FormCase(form = "pointer_steps", fixture = "p9_ptr_steps", default_text = "    p++\n", off_text = "    p = p + 1\n"),
        FormCase(form = "ranged_loops", fixture = "p9_counted_for", default_text = "    for (i in range(s.n)) \{\n", off_text = "        while (i < s.n) \{\n"),
        FormCase(form = "c_switch", fixture = "p9_switch", default_text = "require c_runtime/c_switch\n", off_text = "    let _cond = p9_switch__next(k)\n")
    ]
}

// `fixture` converted by `converter/main.das` into `<dir>/<name>` with `extra` and run under the
// interpreter; its exit code, its output in `out`
def private convert_run(dir, name, fixture : string; extra : array<string>; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", "converter/tests/fixtures/{fixture}.c", "--out", path_join(dir, name), "--target", "linux", "--run", "interp"], extra)
    return run_and_capture(argv, out, 300.0)
}

// `text` without the `info` lines (`[I] `) a run's log adds to the program's output
def private printed(text : string) : string => join([for (ln in split(text, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")

// the native build of `fixture` run; its exit code, its output in `out`
def private native_run(dir, fixture : string; var out : string&) : int {
    let bin = path_join(dir, "{fixture}_native")
    if (run_and_capture([default_clang(), "-w", "-funsigned-char", "-o", bin, "converter/tests/fixtures/{fixture}.c", "-lm"], out, 120.0) != 0) {
        return -1
    }
    return run_and_capture([bin], out, 120.0)
}

[test]
def test_forms_off(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_forms_off", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    for (c in form_cases()) {
        t |> run("--forms-off {c.form}: the old spelling, the native build's output; the default keeps the form, and the sidecar's list does what the option does") @(t : T?) {
            var want, have, plain, side_out : string
            let want_rc = native_run(dir, c.fixture, want)
            t |> success(want_rc >= 0, want)
            t |> equal(convert_run(dir, "{c.form}_off", c.fixture, ["--forms-off", c.form], have), want_rc, have)
            t |> equal(printed(have), printed(want))
            let off = fread(path_join(dir, "{c.form}_off/{c.fixture}.das"))
            t |> success(off |> contains(c.off_text) && !(off |> contains(c.default_text)), off)
            t |> equal(convert_run(dir, "{c.form}_default", c.fixture, array<string>(), plain), want_rc, plain)
            let kept = fread(path_join(dir, "{c.form}_default/{c.fixture}.das"))
            t |> success(kept |> contains(c.default_text), kept)
            let sidecar = path_join(dir, "{c.form}.c2das")
            fwrite(sidecar, "\{\"forms_off\": [\"{c.form}\"]\}\n")
            t |> equal(convert_run(dir, "{c.form}_sidecar", c.fixture, ["--sidecar", sidecar], side_out), want_rc, side_out)
            t |> equal(fread(path_join(dir, "{c.form}_sidecar/{c.fixture}.das")), off)
        }
    }
    t |> run("--forms-off takes the forms comma-separated; any other name is a usage error") @(t : T?) {
        var out : string
        t |> equal(convert_run(dir, "all_off", "p9_ptr_steps", ["--forms-off", "pointer_steps,ranged_loops,c_switch"], out), 0, out)
        t |> equal(convert_run(dir, "bad_off", "p9_ptr_steps", ["--forms-off", "pointer_steps,loops"], out), 2, out)
        t |> success(out |> contains("--forms-off takes pointer_steps, ranged_loops, c_switch, comma-separated, not `loops`"), out)
    }
    rmdir_rec(dir)
}

// `text` written as `<dir>/<name>.c2das` and read as a sidecar
def private read_text(dir, name, text : string; var error : string&) : Sidecar {
    let path = path_join(dir, "{name}.c2das")
    fwrite(path, text)
    return <- read_sidecar(path, error)
}

[test]
def test_sidecar_forms_off(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_forms_off", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`forms_off` is a list of the forms; absent it is empty; anything else is refused naming the key") @(t : T?) {
        var error : string
        let all <- read_text(dir, "all", "\{\"forms_off\": [\"pointer_steps\", \"ranged_loops\", \"c_switch\"]\}\n", error)
        t |> equal(error, "")
        t |> equal(all.forms_off, FORMS)
        let none <- read_text(dir, "none", "\{\}\n", error)
        t |> equal(length(none.forms_off), 0)
        read_text(dir, "not_list", "\{\"forms_off\": \"c_switch\"\}\n", error)
        t |> success(error |> ends_with("not_list.c2das: `forms_off` is a list of \"pointer_steps\", \"ranged_loops\", \"c_switch\", not \"c_switch\""), error)
        error = ""
        read_text(dir, "unknown", "\{\"forms_off\": [\"c_switch\", \"goto\"]\}\n", error)
        t |> success(error |> ends_with("unknown.c2das: `forms_off` holds \"pointer_steps\", \"ranged_loops\", \"c_switch\", not \"goto\""), error)
    }
    rmdir_rec(dir)
}
