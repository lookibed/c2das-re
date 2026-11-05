options gen2

module pipeline public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/rtti
require daslib/ast
require daslib/clargs
require daslib/das_source_formatter
require daslib/json_boost
require cir
require link
require layout
require dumper_a
require emit
require sidecar

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
    // the port-progress metric of docs/lowering-examples.md "Pointers": how many
    // function bodies needed [c_function], out of all the unit defines
    c_functions : int
    function_count : int
    // the bytes of clang's JSON dump, and the seconds the dumper (clang included), the emitter
    // (the formatter included) and the compile check took
    json_bytes : int64
    dump_seconds : double
    emit_seconds : double
    check_seconds : double
    // a program of several files: the link's seconds and its report (`converter/link.das`)
    link_seconds : double
    renamed : array<string>
    bound : array<string>
    deduplicated : array<string>
    // a program in the source layout: every file written under `out_dir` (each module's `.das`,
    // each fragment's `.das.inc`), relative to it, and the partition's report (`layout_report`)
    files : array<string>
    partition : array<string>
    // the edge census of its cycles, when asked (`edge_census`)
    census : array<string>
}

//! The report of a program's source layout beside its modules: the modules, each cluster's edges,
//! and the cycle cut's late-bound functions with their edges and weights (`layout_report`).
let LAYOUT_REPORT = "program.layout.txt"

//! The edge census of a program's cycles beside its modules, written only when asked
//! (`--edge-census`, `edge_census`).
let EDGE_REPORT = "program.edges.txt"

//! The files a program's source or source-cut layout wrote under the output folder, one relative
//! path a line: the modules and fragments a publisher copies, and nothing an earlier conversion
//! left.
let MODULE_LIST = "program.modules.txt"

// the modules and fragments an earlier conversion listed in `out_dir`'s module list removed, and
// the list, before this conversion writes, so none of them stays beside the new ones; a file the
// list does not name stays, whatever its kind (`--out` may hold hand-written das)
def private clear_owned(out_dir : string) {
    let list = path_join(out_dir, MODULE_LIST)
    if (!fexist(list)) {
        return
    }
    for (line in split(fread(list), "\n")) {
        let rel = strip(line)
        if (!empty(rel) && !rel |> starts_with("/") && find(rel, "..") < 0) {
            remove(path_join(out_dir, rel))
        }
    }
    remove(list)
}

// the seconds since `t0`, a `ref_time_ticks` reading
def private seconds_since(t0 : int64) : double => double(get_time_usec(t0)) / 1000000.0lf


// `as_written` keeps every `unsafe` scope and every symbol and turns optimization off
def private compile_with(das_path : string; as_written : bool; blk : block<(ok : bool; program : ProgramPtr; output : string) : void>) {
    var inscope access <- make_file_access("")
    using() $(var mg : ModuleGroup) {
        using() $(var cop : CodeOfPolicies) {
            cop.no_fold_unsafe = as_written
            cop.no_optimizations = as_written
            cop.export_all = as_written
            compile_file(das_path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                invoke(blk, ok, program, ok || !empty(output) ? string(output) : "compile failed without a message")
            }
        }
    }
}

//! `das_path` compiled with the default policies, as the compile check runs it; `blk` sees
//! whether it compiled, the program and the compiler's output, never empty on a failure.
def compile_checked(das_path : string; blk : block<(ok : bool; program : ProgramPtr; output : string) : void>) {
    compile_with(das_path, false, blk)
}

//! `das_path` compiled with every `unsafe` scope kept, no optimization and no unused symbol
//! removed, so the program's AST is the text's own; `blk` sees what `compile_checked`'s does.
def compile_as_written(das_path : string; blk : block<(ok : bool; program : ProgramPtr; output : string) : void>) {
    compile_with(das_path, true, blk)
}

def private compile_errors(das_path : string) : string {
    var report = ""
    compile_checked(das_path) $(ok, _program, output) {
        if (!ok) {
            report = output
        }
    }
    return report
}

// why an option value given to `convert` is refused, "" when each is empty or a mode
def private option_error(param_writes, loops, layout, first_member : string; switch_dispatch : string = "") : string {
    if (!empty(param_writes) && !is_param_writes(param_writes)) {
        return "--param-writes is in-place or copy, not `{param_writes}`"
    }
    if (!empty(layout) && !is_layout(layout)) {
        return "--layout is source, source-cut or single, not `{layout}`"
    }
    if (!empty(first_member) && !is_first_member(first_member)) {
        return "--first-member is addr or reinterpret, not `{first_member}`"
    }
    if (!empty(switch_dispatch) && !is_switch_dispatch(switch_dispatch)) {
        return "--switch-dispatch is chain or goto, not `{switch_dispatch}`"
    }
    return !empty(loops) && !is_loops(loops) ? "--loops is range or while, not `{loops}`" : ""
}

// the sidecar of a conversion, read from `sidecar` ("" for none), the options' values over its
// keys; `error` the refusal of the options, the output folder or the sidecar
def private conversion_setup(out_dir, sidecar, param_writes, loops : string; var error : string&; layout : string = ""; first_member : string = ""; switch_dispatch : string = "") : Sidecar {
    error = option_error(param_writes, loops, layout, first_member, switch_dispatch)
    if (empty(error) && !mkdir_rec(out_dir) && !stat(out_dir).is_dir) {
        error = "cannot create {out_dir}"
    }
    var side_error : string
    var side <- empty(error) ? read_sidecar(sidecar, side_error) : Sidecar()
    if (!empty(side_error)) {
        error = "sidecar: {side_error}"
    }
    if (!empty(param_writes)) {
        side.param_writes = param_writes
    }
    if (!empty(loops)) {
        side.loops = loops
    }
    if (!empty(layout)) {
        side.layout = layout
    }
    if (!empty(first_member)) {
        side.first_member = first_member
    }
    if (!empty(switch_dispatch)) {
        side.switch_dispatch = switch_dispatch
    }
    return <- side
}

//! The dumper's inputs a sidecar carries: its defines, include folders and files, and the
//! program root.
def dump_inputs(side : Sidecar) : DumpInputs => DumpInputs(defines := side.defines, include_dirs := side.include_dirs, include_files := side.include_files, program_root = side.program_root)

// one unit dumped under the sidecar's `defines`, `include_dirs` and `program_root`, its C-IR
// written to `<out_dir>/<stem>.cir.json`, read back and rewritten (the bytes must match); the
// dumper's tree, which the caller deletes, and `res` carrying the C-IR, the dump's bytes and
// seconds, or the error
def private dump_unit(c_path, out_dir : string; target : CirTarget; clang : string; side : Sidecar; var res : ConvertResult) : CirTu {
    let dump_started = ref_time_ticks()
    var d <- dump_tu(c_path, target, empty(clang) ? default_clang() : clang, dump_inputs(side))
    res.dump_seconds += seconds_since(dump_started)
    res.json_bytes += d.json_bytes
    if (!empty(d.error)) {
        res.error = "dumper: {d.error}"
        return <- d.tu
    }
    res.cir_text = write_cir(d.tu)
    res.cir_path = path_join(out_dir, "{file_stem(c_path)}.cir.json")
    if (!fwrite(res.cir_path, res.cir_text)) {
        res.error = "cannot write {res.cir_path}"
        return <- d.tu
    }
    var read_error : string
    var reread <- read_cir(res.cir_text, read_error)
    if (!empty(read_error)) {
        res.error = "reader: {read_error}"
        return <- d.tu
    }
    let rewritten = write_cir(reread)
    delete_tu(reread)
    if (rewritten != res.cir_text) {
        res.error = "reader and writer disagree on {res.cir_path}"
    }
    return <- d.tu
}

// `tu` emitted, formatted, written to `<out_dir>/<stem>.das` and compile-checked; `tu` is deleted
def private emit_unit(var tu : CirTu; side : Sidecar; out_dir, stem : string; var res : ConvertResult) {
    let emit_started = ref_time_ticks()
    let em <- emit_tu(tu, side)
    delete_tu(tu)
    if (!empty(em.error)) {
        res.error = "emitter: {em.error}"
        return
    }
    res.c_functions = em.c_functions
    res.function_count = em.function_count
    res.das_text = format_source_string(em.text)
    res.emit_seconds = seconds_since(emit_started)
    res.das_path = path_join(out_dir, "{stem}.das")
    if (!fwrite(res.das_path, res.das_text)) {
        res.error = "cannot write {res.das_path}"
        return
    }
    let check_started = ref_time_ticks()
    let errors = compile_errors(res.das_path)
    res.check_seconds = seconds_since(check_started)
    if (!empty(errors)) {
        res.error = "compile check: {errors}"
        return
    }
    res.ok = true
}

// the files a source layout's program `tu` emits into (`emit_program`), each formatted and
// written under `out_dir` at its path; the modules no other module requires (the entry's and any
// the program never reaches) compile-checked, which compiles every module they require; `tu` is
// deleted
def private emit_modules(var tu : CirTu; owners : array<int>; plan : LayoutPlan; side : Sidecar; out_dir : string; var res : ConvertResult) {
    let emit_started = ref_time_ticks()
    var emitted <- emit_program(tu, side, plan, owners)
    delete_tu(tu)
    if (!empty(emitted.error)) {
        res.error = "emitter: {emitted.error}"
        return
    }
    res.c_functions = emitted.c_functions
    res.function_count = emitted.function_count
    res.files |> reserve(length(emitted.files))
    for (f in emitted.files) {
        let path = path_join(out_dir, f.path)
        let text = format_source_string(f.text)
        if ((!mkdir_rec(dir_name(path)) && !stat(dir_name(path)).is_dir) || !fwrite(path, text)) {
            res.error = "cannot write {path}"
            return
        }
        res.files |> push(f.path)
        if (f.path == emitted.entry) {
            res.das_path = path
            res.das_text = text
        }
    }
    if (!fwrite(path_join(out_dir, MODULE_LIST), join(res.files, "\n") + "\n")) {
        res.error = "cannot write {path_join(out_dir, MODULE_LIST)}"
        return
    }
    res.emit_seconds = seconds_since(emit_started)
    var required : table<int>
    for (mod in plan.modules) {
        for (r in mod.requires) {
            required |> insert(r)
        }
    }
    let check_started = ref_time_ticks()
    for (mi, mod in count(), plan.modules) {
        if (!key_exists(required, mi)) {
            let rel = empty(mod.dir) ? "{mod.name}.das" : "{mod.dir}/{mod.name}.das"
            let errors = compile_errors(path_join(out_dir, rel))
            if (!empty(errors)) {
                res.error = "compile check: {errors}"
                return
            }
        }
    }
    res.check_seconds = seconds_since(check_started)
    res.ok = true
}

def convert(c_path : string; out_dir : string; target_name : string; clang : string = ""; sidecar_path : string = ""; param_writes : string = ""; loops : string = ""; first_member : string = ""; switch_dispatch : string = "") : ConvertResult {
    var res : ConvertResult
    let side <- conversion_setup(out_dir, find_sidecar(c_path, sidecar_path), param_writes, loops, res.error, "", first_member, switch_dispatch)
    if (!empty(res.error)) {
        return <- res
    }
    var tu <- dump_unit(c_path, out_dir, target_by_name(target_name), clang, side, res)
    if (!empty(res.error)) {
        delete_tu(tu)
        return <- res
    }
    emit_unit(tu, side, out_dir, file_stem(c_path), res)
    return <- res
}

// the sidecar of a program of several files: `given`, else the one `<stem>.c2das` beside one of
// the files, which must be the entry file's (`sidecar_stem` names its stem for the check after
// the link), else the `.c2das` of the first file's folder, else none; `error` when several files
// have their own
def private program_sidecar(c_paths : array<string>; given : string; var sidecar_stem : string&; var error : string&) : string {
    if (!empty(given)) {
        return given
    }
    var own : array<string>
    for (c_path in c_paths) {
        let path = path_join(dir_name(c_path), "{file_stem(c_path)}.c2das")
        if (fexist(path)) {
            own |> push(path)
            sidecar_stem = file_stem(c_path)
        }
    }
    if (length(own) > 1) {
        error = "{join(own, " and ")} are each a file's sidecar; a program's is its entry file's: pass --sidecar"
        return ""
    }
    if (length(own) == 1) {
        return own[0]
    }
    let folder_wide = path_join(dir_name(c_paths[0]), ".c2das")
    return fexist(folder_wide) ? folder_wide : ""
}

//! A program of several C files, each dumped as `convert` dumps one (its C-IR written and
//! round-tripped), then linked in the given order (`converter/link.das`). In the `source` layout,
//! the default, the program is a module per C file and a cluster of mutually dependent files one
//! module of fragments (`converter/layout.das`), written under `out_dir` as its C files lie under
//! their common folder; in the `source-cut` layout the cycles among the files are cut by late
//! binding instead; in the `single` layout it is one module named by the unit defining `main`,
//! else the first. `layout` ("" for the sidecar's `layout`, else `source`) chooses.
//! `<out_dir>/program.cir.json` names the units' C-IR files and the entry. The sidecar is
//! `sidecar_path`, else the entry file's `<stem>.c2das`, else the `.c2das` of the first file's
//! folder. A file stemmed `program` is refused, since its C-IR would be the manifest's file. One
//! file is `convert` of it, one module in either layout. With `census` the source layouts also write
//! the edge census of the program's cycles (`EDGE_REPORT`); one file or the single layout is refused.
def convert_program(c_paths : array<string>; out_dir : string; target_name : string; clang : string = ""; sidecar_path : string = ""; param_writes : string = ""; loops : string = ""; entry : string = "main"; layout : string = ""; census : bool = false; first_member : string = ""; switch_dispatch : string = "") : ConvertResult {
    if (length(c_paths) == 1 && entry == "main") {
        if (census || (!empty(layout) && !is_layout(layout))) {
            var refused : ConvertResult
            refused.error = census ? "--edge-census reports the cycles among a program's files; one file has none" : option_error("", "", layout, "")
            return <- refused
        }
        return <- convert(c_paths[0], out_dir, target_name, clang, sidecar_path, param_writes, loops, first_member, switch_dispatch)
    }
    var res : ConvertResult
    res.error = refused_files(c_paths, out_dir)
    if (!empty(res.error)) {
        return <- res
    }
    var sidecar_stem : string
    let sidecar = program_sidecar(c_paths, sidecar_path, sidecar_stem, res.error)
    if (!empty(res.error)) {
        return <- res
    }
    let side <- conversion_setup(out_dir, sidecar, param_writes, loops, res.error, layout, first_member, switch_dispatch)
    if (!empty(res.error)) {
        return <- res
    }
    let per_file_modules = side.layout != "single"
    if (census && !per_file_modules) {
        res.error = "--edge-census reports the cycles among a program's modules; the single layout has one module"
        return <- res
    }
    let opts <- cut_options(side, res.error)
    if (!empty(res.error)) {
        return <- res
    }
    clear_owned(out_dir)
    // an earlier conversion's census never stays beside a conversion that did not ask for one
    remove(path_join(out_dir, EDGE_REPORT))
    var units : array<CirTu>
    var cir_names : array<string>
    dump_units(c_paths, out_dir, target_by_name(target_name), clang, side, res, units, cir_names)
    if (empty(res.error)) {
        let link_started = ref_time_ticks()
        var plan = LayoutPlan()
        var linked <- link_tus(units, entry, reserved_das_names()) $(tus, types, facts, scopes) : string {
            if (!per_file_modules) {
                return ""
            }
            delete plan
            plan <- plan_layout(tus, types, facts, c_paths, opts, census)
            scopes := unit_scopes(plan)
            return plan.error
        }
        res.link_seconds = seconds_since(link_started)
        res.renamed <- linked.renamed
        res.bound <- linked.bound
        res.deduplicated <- linked.deduplicated
        res.cir_text = write_program(target_by_name(target_name), cir_names, entry)
        res.cir_path = path_join(out_dir, "program.cir.json")
        if (!empty(linked.error)) {
            res.error = "link: {linked.error}"
            delete_tu(linked.program)
        } elif (!empty(sidecar_stem) && sidecar_stem != file_stem(linked.program.tu)) {
            res.error = "{sidecar} is the sidecar of {sidecar_stem}, but the program's entry file is {linked.program.tu}: a program's sidecar is its entry file's"
            delete_tu(linked.program)
        } elif (!fwrite(res.cir_path, res.cir_text)) {
            res.error = "cannot write {res.cir_path}"
            delete_tu(linked.program)
        } elif (per_file_modules) {
            write_layout_reports(plan, census, out_dir, res)
            emit_modules(linked.program, linked.owners, plan, side, out_dir, res)
        } else {
            emit_unit(linked.program, side, out_dir, file_stem(linked.program.tu), res)
        }
    }
    for (tu in units) {
        delete_tu(tu)
    }
    return <- res
}

// why a program of the C files `c_paths` is refused before any is read, "" when it is not: no file,
// or a file stemmed `program`, whose C-IR would be the manifest's file
def private refused_files(c_paths : array<string>; out_dir : string) : string {
    if (empty(c_paths)) {
        return "a program needs at least one C file"
    }
    for (c_path in c_paths) {
        if (file_stem(c_path) == "program") {
            return "{c_path}: its C-IR would be {out_dir}/program.cir.json, the program manifest's file; rename the file"
        }
    }
    return ""
}

// the partition's report beside the modules, and with `census` the edge census of its cycles
def private write_layout_reports(plan : LayoutPlan; census : bool; out_dir : string; var res : ConvertResult) {
    res.partition <- layout_report(plan)
    fwrite(path_join(out_dir, LAYOUT_REPORT), join(res.partition, "\n") + "\n")
    if (census) {
        res.census <- clone_to_move(plan.census)
        fwrite(path_join(out_dir, EDGE_REPORT), join(res.census, "\n") + "\n")
    }
}

// every file of a program dumped as `convert` dumps one, into `units`, its C-IR file's name into
// `cir_names`, until the first error
def private dump_units(c_paths : array<string>; out_dir : string; target : CirTarget; clang : string; side : Sidecar; var res : ConvertResult; var units : array<CirTu>; var cir_names : array<string>) {
    units |> reserve(length(c_paths))
    cir_names |> reserve(length(c_paths))
    for (c_path in c_paths) {
        var tu <- dump_unit(c_path, out_dir, target, clang, side, res)
        units |> emplace(tu)
        cir_names |> push(base_name(res.cir_path))
        break if (!empty(res.error))
    }
}

// the cycle cut's options from the sidecar: cut in the `source-cut` layout alone, not in `source`
// (the default); the profile the sidecar's `layout.profile` names read, `error` when it is no
// object of symbols holding an object of calling file stems and counts
def private cut_options(side : Sidecar; var error : string&) : CutOptions {
    var opts = CutOptions(cut_cycles = side.layout == "source-cut", threshold = side.layout_threshold)
    for (name in side.layout_keep_symbols) {
        opts.keep_symbols |> insert(name)
    }
    opts.keep_units := side.layout_keep_units
    for (name in side.layout_cut) {
        opts.always_cut |> insert(name)
    }
    if (empty(side.layout_profile)) {
        return <- opts
    }
    var js = read_json_file(side.layout_profile, error)
    if (js == null) {
        error = "layout.profile: {error}"
        return <- opts
    }
    if (!(js is _object)) {
        error = "layout.profile: {side.layout_profile} is no object of symbols"
    } else {
        for (name, by_unit in keys(js as _object), values(js as _object)) {
            if (!(by_unit is _object)) {
                error = "layout.profile: `{name}` in {side.layout_profile} holds no object of calling files"
                break
            }
            for (unit, count in keys(by_unit as _object), values(by_unit as _object)) {
                let calls = json_count(count)
                if (calls < 0l) {
                    error = "layout.profile: `{name}`'s count from `{unit}` in {side.layout_profile} is no count of 0 or more: {write_json(count)}"
                    break
                }
                opts.profile[name][unit] = calls
            }
            break if (!empty(error))
        }
    }
    delete_json(js)
    return <- opts
}

//! A program manifest (docs/c-ir-spec.md section 7) as the converter takes it: `tus` the C files
//! of the program in link order, each relative to the manifest's folder (an absolute path taken as
//! is), and `entry` (default `main`); a `target` member must name `target_name`'s triple.
struct ProgramInput {
    c_paths : array<string>
    entry : string
}

//! The manifest at `path`; `error` names why it is refused.
def read_program_input(path, target_name : string; var error : string&) : ProgramInput {
    var input = ProgramInput(entry = "main")
    let text = fread(path)
    if (empty(text)) {
        error = "cannot read {path}"
        return <- input
    }
    var js = read_json(text, error)
    if (js == null) {
        error = "{path} is not JSON: {error}"
        return <- input
    }
    let tus = js?["tus"]
    let triple = js?["target"]?["triple"] ?? ""
    if (tus == null || !(tus is _array) || empty(tus as _array)) {
        error = "{path}: `tus` is no list of C files"
    } elif (!empty(triple) && triple != target_by_name(target_name).triple) {
        error = "{path}: the manifest's target is {triple}, the conversion's {target_by_name(target_name).triple}"
    } else {
        input.entry = js?["entry"] ?? "main"
        for (tu in tus as _array) {
            let name = tu ?? ""
            if (empty(name)) {
                error = "{path}: an entry of `tus` is no file name"
                break
            }
            if (name |> ends_with(".cir.json")) {
                error = "{path}: `{name}` in `tus` is no C file; the link runs on the dumper's trees, so a manifest names the C sources"
                break
            }
            input.c_paths |> push(path_join(dir_name(path), name))
        }
    }
    delete_json(js)
    return <- input
}

//! The opening every command-line main shares: `args` parsed for `prog`, the help printed under
//! `-?`; the exit code to return at once, or -1 to go on.
def cli_prologue(var args : auto(ArgsT); prog : string) : int {
    let parsed = _::parse_args_with_help(args, prog)
    if (parsed >= 0) {
        return parsed
    }
    if (args.show_help) {
        print_help(_::get_command_info(type<ArgsT>), prog)
        return 0
    }
    return -1
}
