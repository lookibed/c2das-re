options gen2

module lua_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/cir.das
require ../converter/sidecar.das
require ../suites/suite_files.das
require rust_translator
require suite_compare

//! Lua 5.4.8 through the Rust translator: the interpreter's sources as one compilation database,
//! translated in the source layout, and the C library functions Lua calls that the translator's
//! tables do not lower (`compare/ARCHITECTURE.md`).

let LUA_WORK = "compare/work/lua"

//! seconds the Rust translator may take over the whole interpreter
let LUA_TRANSLATE_TIMEOUT = 600.0

//! the runtime module the source layout shares between the units
let LUA_RUNTIME_MODULE = "lua_rt"

//! the flags each unit is compiled with to list the functions it calls: every call stays a call,
//! and the compiler adds none of its own
let GAP_CFLAGS <- ["-c", "-O0", "-fno-builtin", "-fno-stack-protector"]

//! glibc's assembler names for a C function a header redirects, each with the C name the Rust
//! translator sees in clang's declaration
let GLIBC_ALIASES <- [("fopen64", "fopen"), ("freopen64", "freopen"), ("tmpfile64", "tmpfile"), ("__sysv_signal", "signal")]

//! The Rust functions whose match arms name what the translator lowers, each as `<file under
//! c2dascript-transpile/src/translator/>` and the function's name.
let KNOWN_NAME_TABLES <- [("libc.rs", "std_function"), ("libc.rs", "std_stream"), ("libc.rs", "jmp_call"), ("libc.rs", "libm_function"), ("runtime.rs", "canonical_runtime_function")]

//! The string literals on the left of each `=>` in the body of the Rust function `fn_name` in
//! `source`: from its `fn <name>(` line to the `}` that closes it at that line's indentation,
//! trailing blanks ignored; `error` says why when there is no such function, its closing brace is
//! never found, or it names nothing.
[arch(at="ARCHITECTURE.md#lua-gap")]
def match_arm_names(source, fn_name : string; var error : string&) : array<string> {
    var names : array<string>
    var closing = ""
    var closed = false
    for (raw in split(source, "\n")) {
        let line = strip_right(raw)
        if (empty(closing)) {
            let at = find(line, "fn {fn_name}(")
            if (at >= 0) {
                let indent = length(line) - length(strip_left(line))
                closing = repeat(" ", indent) + "\}"
            }
            continue
        }
        if (line == closing) {
            closed = true
            break
        }
        let arrow = find(line, "=>")
        if (arrow < 0) {
            continue
        }
        var inscope parts <- split(slice(line, 0, arrow), "\"")
        for (i in range(length(parts))) {
            if (i % 2 == 1) {
                names |> push(parts[i])
            }
        }
    }
    if (empty(closing)) {
        error = "no fn {fn_name}( in the source"
    } elif (!closed) {
        error = "fn {fn_name} has no closing brace"
    } elif (empty(names)) {
        error = "fn {fn_name} names nothing"
    }
    return <- names
}

//! The C names the Rust translator lowers, from the match arms of each `KNOWN_NAME_TABLES` function
//! in `translator_dir`, a `<math.h>` stem with its `float` form `<stem>f` too; `error` names a file
//! that is missing.
[arch(at="ARCHITECTURE.md#lua-gap")]
def known_names(translator_dir : string; var error : string&) : table<string> {
    var known : table<string>
    for (source in KNOWN_NAME_TABLES) {
        let path = path_join(translator_dir, source._0)
        if (!fexist(path)) {
            error = "no Rust source at {path}"
            return <- known
        }
        var table_error : string
        var inscope names <- match_arm_names(fread(path), source._1, table_error)
        if (!empty(table_error)) {
            error = "{path}: {table_error}"
            return <- known
        }
        for (name in names) {
            known |> insert(name)
            if (source._1 == "libm_function") {
                known |> insert("{name}f")
            }
        }
    }
    return <- known
}

//! the `nm` type letters of a symbol a unit refers to without defining it: undefined, and weak
//! undefined (an object or other)
let UNDEFINED_TYPES <- ["U", "w", "v"]

//! The symbols of `nm` output `text` whose type letter is in `UNDEFINED_TYPES` (`undefined`) or any
//! other (`defined`), each once.
def nm_symbols(text : string; undefined : bool) : table<string> {
    var names : table<string>
    for (line in split(text, "\n")) {
        var inscope fields <- [for (f in split(strip(line), " ")); f; where !empty(f)]
        let n = length(fields)
        if (n >= 2 && length(fields[n - 2]) == 1 && has_value(UNDEFINED_TYPES, fields[n - 2]) == undefined) {
            names |> insert(fields[n - 1])
        }
    }
    return <- names
}

//! The C name of a symbol: glibc's redirected name mapped back by `GLIBC_ALIASES`, `__isoc99_`
//! dropped.
def c_name_of(symbol : string) : string {
    for (alias in GLIBC_ALIASES) {
        if (alias._0 == symbol) {
            return alias._1
        }
    }
    return symbol |> starts_with("__isoc99_") ? slice(symbol, length("__isoc99_")) : symbol
}

//! The gap, sorted: each symbol of `undefined` no object of the program defines, by its C name,
//! that `known` does not hold.
[arch(at="ARCHITECTURE.md#lua-gap")]
def libc_gap(undefined, defined, known : table<string>) : array<string> {
    var gap : table<string>
    for (symbol in keys(undefined)) {
        let name = c_name_of(symbol)
        if (!key_exists(defined, symbol) && !key_exists(known, name)) {
            gap |> insert(name)
        }
    }
    var names <- [for (name in keys(gap)); name]
    names |> sort()
    return <- names
}

// the `nm` output of `args` over `objects`, appended to `text`; false when nm fails
def private nm_into(args : array<string>; objects : array<string>; var text : string&) : bool {
    var argv <- ["nm"]
    argv |> push_from(args, objects)
    return run_and_capture(argv, text, 120.0) == 0
}

//! The gap of the program whose C files are `c_paths`, compiled with `defines` into `obj_dir` by
//! `GAP_CFLAGS`, against the names `translator_dir`'s tables know; none, with `error` set, when it
//! is not known.
[arch(at="ARCHITECTURE.md#lua-gap")]
def program_gap(c_paths, defines : array<string>; obj_dir, translator_dir : string; var error : string&) : array<string> {
    let known <- known_names(translator_dir, error)
    if (!empty(error)) {
        return <- array<string>()
    }
    mkdir_rec(obj_dir)
    var objects : array<string>
    objects |> reserve(length(c_paths))
    for (c_path in c_paths) {
        let obj = path_join(obj_dir, "{file_stem(c_path)}.o")
        var inscope argv <- ["gcc"]
        argv |> push_from(GAP_CFLAGS, [for (d in defines); "-D{d}"], [c_path, "-o", obj])
        var out : string
        if (run_and_capture(argv, out, 300.0) != 0) {
            error = "gcc refused {c_path}: {first_line(out)}"
            return <- array<string>()
        }
        objects |> push(obj)
    }
    var undefined_text, defined_text : string
    if (!nm_into(["-u"], objects, undefined_text) || !nm_into(["--defined-only"], objects, defined_text)) {
        error = "nm failed over {obj_dir}"
        return <- array<string>()
    }
    return <- libc_gap(nm_symbols(undefined_text, true), nm_symbols(defined_text, false), known)
}

//! How the gap is derived, the text the capture carries beside it.
def gap_method : string {
    let tables = join([for (t in KNOWN_NAME_TABLES); "{t._1} ({t._0})"], ", ")
    return "gcc {join(GAP_CFLAGS, " ")} of the program's units with the sidecar's defines; nm's undefined symbols ({join(UNDEFINED_TYPES, ", ")}) less those any unit defines, glibc's redirected names mapped to the C names; less the names the match arms of the Rust translator's {tables} lower, each libm_function stem also in its f form"
}

//! The `lua` section of the program whose C files are `c_paths` (`program_sources("lua")`): a
//! compilation database with the defines of the sidecar at `sidecar_path` (none for ""), translated by `bin`
//! with `translate_db` into `work`, its status (`refused` with the translator's error, else
//! `translated` with the file count), the seconds and the gap; our side's numbers are the ports
//! capture's. Null, with `error` set, when the sidecar cannot be read.
[arch(at="ARCHITECTURE.md#lua")]
def lua_section(bin : string; c_paths : array<string>; sidecar_path, work : string; stamps : Stamps; var error : string&) : JsonValue? {
    var side_error : string
    let side <- read_sidecar(sidecar_path, side_error)
    if (!empty(side_error) || (!empty(sidecar_path) && !fexist(sidecar_path))) {
        error = "cannot read the sidecar {sidecar_path}: {side_error}"
        return null
    }
    rmdir_rec(work)
    mkdir_rec(work)
    let db = path_join(work, "compile_commands.json")
    write_compile_commands(db, c_paths, side.defines, get_full_file_name("."))
    let no_flags : array<string>
    let t <- translate_db(bin, db, path_join(work, "rust"), LUA_RUNTIME_MODULE, no_flags, LUA_TRANSLATE_TIMEOUT)
    var gap_error : string
    let gap <- program_gap(c_paths, side.defines, path_join(work, "obj"), path_join(rust_checkout(), "c2dascript-transpile/src/translator"), gap_error)
    var root <- {
        "rust_commit" => JV(stamps.rust_commit),
        "rust_commit_error" => JV(stamps.rust_commit_error),
        "date" => JV(stamps.date),
        "cpu" => JV(stamps.cpu),
        "box" => JV(stamps.box),
        "program" => JV("lua"),
        "units" => JV(length(c_paths)),
        "status" => JV(t.ok ? "translated" : "refused"),
        "error" => JV(t.error),
        "files" => JV(length(t.files)),
        "seconds" => JV(t.seconds),
        "gap" => JV(gap),
        "gap_error" => JV(gap_error),
        "gap_method" => JV(gap_method()),
        "ours" => JV("see ports"),
        "speed" => JV(t.ok ? "not measured here" : "refused on the Rust side")
    }
    return JV(root)
}

//! The C files of `folder`, sorted, each by its full path: the program `--lua-from` names.
def folder_sources(folder : string) : array<string> => <- [for (id in c_file_ids(folder, "")); get_full_file_name(path_join(folder, "{id}.c"))]

//! The work folder of the program `--lua-from` names: `<folder>/work`.
def folder_work(folder : string) : string => path_join(folder, "work")

//! Why the Lua comparison cannot start, "" when it can: the Rust translator is missing, or the
//! program's folder lacks `lua.c`: the fetched release's sources (`SOURCES`), or the folder
//! `--lua-from` names when `from_folder`.
def lua_missing(folder : string; from_folder : bool) : string {
    var reason : string
    if (!rust_available(reason)) {
        return reason
    }
    if (fexist(path_join(folder, "lua.c"))) {
        return ""
    }
    return from_folder ? "{folder} has no lua.c" : "{folder} is missing: run lua/fetch.sh"
}

//! The sidecar of the program `--lua-from` names: `<folder>/lua.c2das` when present, else "" (no
//! defines); never Lua's own.
def folder_sidecar(folder : string) : string {
    let path = path_join(folder, "lua.c2das")
    return fexist(path) ? path : ""
}

//! The line a run logs of the `lua` section: the status, the error, and the gap.
def lua_line(section : JsonValue?) : string {
    let gap = section?["gap"]
    let names = gap != null && gap.value is _array ? join([for (g in gap.value as _array); g ?? ""], " ") : ""
    return "lua: {section?["status"] ?? ""} {section?["error"] ?? ""}; gap: {names}"
}

//! The `doom` section: PureDOOM waits for P6.
def doom_section() : JsonValue? => JV({"status" => JV("pending"), "reason" => JV("P6")})
