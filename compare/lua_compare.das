options gen2

module lua_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/cir.das
require ../converter/sidecar.das
require ../suites/suite_files.das
require ../lua/sources.das
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
//! `source`: from its `fn <name>(` line to the `}` that closes it at that line's indentation.
[arch(at="ARCHITECTURE.md#lua-gap")]
def match_arm_names(source, fn_name : string) : array<string> {
    var names : array<string>
    var closing = ""
    for (line in split(source, "\n")) {
        if (empty(closing)) {
            let at = find(line, "fn {fn_name}(")
            if (at >= 0) {
                let indent = length(line) - length(strip_left(line))
                closing = repeat(" ", indent) + "\}"
            }
            continue
        }
        if (line == closing) {
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
        for (name in match_arm_names(fread(path), source._1)) {
            known |> insert(name)
            if (source._1 == "libm_function") {
                known |> insert("{name}f")
            }
        }
    }
    return <- known
}

//! The symbols of `nm` output `text` whose type letter is `U` (`undefined`) or any other
//! (`defined`), each once.
def nm_symbols(text : string; undefined : bool) : table<string> {
    var names : table<string>
    for (line in split(text, "\n")) {
        var inscope fields <- [for (f in split(strip(line), " ")); f; where !empty(f)]
        let n = length(fields)
        if (n >= 2 && (fields[n - 2] == "U") == undefined && length(fields[n - 2]) == 1) {
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
let GAP_METHOD = "gcc -c -O0 -fno-builtin -fno-stack-protector of the program's units with the sidecar's defines, nm -u less the symbols any unit defines, glibc's redirected names mapped to the C names, less the names the match arms of the Rust translator's std_function, std_stream, jmp_call, libm_function (and each stem's f form) and canonical_runtime_function lower"

//! The `lua` section: the interpreter `lua` of `program_sources` as a compilation database with the
//! sidecar's defines, translated by `bin` with `translate_db` into `LUA_WORK`, its status
//! (`refused` with the translator's error, else `translated` with the file count), the seconds, and
//! the gap; our side's numbers are the ports capture's.
[arch(at="ARCHITECTURE.md#lua")]
def lua_section(bin : string; stamps : Stamps) : JsonValue? {
    rmdir_rec(LUA_WORK)
    mkdir_rec(LUA_WORK)
    var side_error : string
    let side <- read_sidecar(SIDECAR, side_error)
    let c_paths <- program_sources("lua")
    let db = path_join(LUA_WORK, "compile_commands.json")
    write_compile_commands(db, c_paths, side.defines, get_full_file_name("."))
    let no_flags : array<string>
    let t <- translate_db(bin, db, path_join(LUA_WORK, "rust"), LUA_RUNTIME_MODULE, no_flags, LUA_TRANSLATE_TIMEOUT)
    var gap_error : string
    let gap <- program_gap(c_paths, side.defines, path_join(LUA_WORK, "obj"), path_join(rust_checkout(), "c2dascript-transpile/src/translator"), gap_error)
    var root <- {
        "rust_commit" => JV(stamps.rust_commit),
        "date" => JV(stamps.date),
        "program" => JV("lua"),
        "units" => JV(length(c_paths)),
        "status" => JV(t.ok ? "translated" : "refused"),
        "error" => JV(t.error),
        "files" => JV(length(t.files)),
        "seconds" => JV(t.seconds),
        "gap" => JV(gap),
        "gap_error" => JV(gap_error),
        "gap_method" => JV(GAP_METHOD),
        "ours" => JV("see ports"),
        "speed" => JV(t.ok ? "not measured here" : "refused on the Rust side")
    }
    return JV(root)
}

//! Why the Lua comparison cannot start, "" when it can: the Rust translator or the fetched release
//! is missing.
def lua_missing : string {
    var reason : string
    if (!rust_available(reason)) {
        return reason
    }
    return fexist(SOURCES) ? "" : "{SOURCES} is missing: run lua/fetch.sh"
}

//! The line a run logs of the `lua` section: the status, the error, and the gap.
def lua_line(section : JsonValue?) : string {
    let gap = section?["gap"]
    let names = gap != null && gap.value is _array ? join([for (g in gap.value as _array); g ?? ""], " ") : ""
    return "lua: {section?["status"] ?? ""} {section?["error"] ?? ""}; gap: {names}"
}

//! The `doom` section: PureDOOM waits for P6.
def doom_section() : JsonValue? => JV({"status" => JV("pending"), "reason" => JV("P6")})
