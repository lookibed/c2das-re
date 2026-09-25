options gen2

module pipeline public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/rtti
require daslib/ast
require daslib/das_source_formatter
require cir
require dumper_a
require emit

//! One C file through the whole chain: clang dump, C-IR (written, read back, rewritten and
//! compared byte for byte), das emission, the formatter, a compile check. Nothing is
//! hand-edited between the steps and every artifact lands under `out_dir`.

struct ConvertResult {
    ok : bool
    error : string
    cir_path : string
    das_path : string
    cir_text : string
    das_text : string
}

def private write_text(path : string; text : string) : bool {
    var ok = false
    fopen(path, "wb") $(f) {
        if (f != null) {
            fwrite(f, text)
            ok = true
        }
    }
    return ok
}

def private compile_errors(das_path : string) : string {
    var report = ""
    var inscope access <- make_file_access("")
    using() $(var mg : ModuleGroup) {
        using() $(var cop : CodeOfPolicies) {
            compile_file(das_path, access, unsafe(addr(mg)), cop) $(ok, _program, output) {
                if (!ok) {
                    report = string(output)
                    if (empty(report)) {
                        report = "compile failed without a message"
                    }
                }
            }
        }
    }
    return report
}

def private file_stem(c_path : string) : string {
    let name = base_name(c_path)
    let dot = find(name, ".")
    return dot < 0 ? name : slice(name, 0, dot)
}

def convert(c_path : string; out_dir : string; target_name : string; clang : string = "") : ConvertResult {
    var res : ConvertResult
    if (!mkdir_rec(out_dir) && !stat(out_dir).is_dir) {
        res.error = "cannot create {out_dir}"
        return <- res
    }
    var d <- dump_tu(c_path, target_by_name(target_name), empty(clang) ? default_clang() : clang)
    if (!empty(d.error)) {
        res.error = "dumper: {d.error}"
        delete_tu(d.tu)
        return <- res
    }
    res.cir_text = write_cir(d.tu)
    res.cir_path = path_join(out_dir, "{file_stem(c_path)}.cir.json")
    if (!write_text(res.cir_path, res.cir_text)) {
        res.error = "cannot write {res.cir_path}"
        delete_tu(d.tu)
        return <- res
    }
    var read_error : string
    var reread <- read_cir(res.cir_text, read_error)
    if (!empty(read_error)) {
        res.error = "reader: {read_error}"
        delete_tu(d.tu)
        return <- res
    }
    let rewritten = write_cir(reread)
    delete_tu(reread)
    if (rewritten != res.cir_text) {
        res.error = "reader and writer disagree on {res.cir_path}"
        delete_tu(d.tu)
        return <- res
    }
    let em <- emit_tu(d.tu)
    delete_tu(d.tu)
    if (!empty(em.error)) {
        res.error = "emitter: {em.error}"
        return <- res
    }
    res.das_text = format_source_string(em.out)
    res.das_path = path_join(out_dir, "{file_stem(c_path)}.das")
    if (!write_text(res.das_path, res.das_text)) {
        res.error = "cannot write {res.das_path}"
        return <- res
    }
    let errors = compile_errors(res.das_path)
    if (!empty(errors)) {
        res.error = "compile check: {errors}"
        return <- res
    }
    res.ok = true
    return <- res
}
