options gen2

module criteria_defines public

require strings
require daslib/strings_boost
require daslib/fio
require ../converter/dumper_a.das
require ../converter/cir.das
require criteria_scan

//! The program's numeric-constant macros (`metrics/ARCHITECTURE_CRITERIA.md`, constant names):
//! the object-like `#define`s of its own files whose expansion, under the macros clang reports
//! for each translation unit, is a numeric constant expression; and the lines each unit's
//! preprocessing keeps.

//! One macro of `clang -E -dD`: its parameters when it is function-like, and its body's tokens.
struct Macro {
    function_like : bool
    params : array<string>
    body : array<Tok>
}

// one `#define NAME[(params)] body` line's macro, its name in `name`
def private macro_of(ln : string; var name : string&) : Macro {
    let rest = slice(ln, length("#define "))
    var name_end = 0
    peek_data(rest) $(b) {
        while (name_end < length(b) && (is_alnum(int(b[name_end])) || int(b[name_end]) == '_')) {
            name_end++
        }
    }
    name = slice(rest, 0, name_end)
    var m : Macro
    var body = slice(rest, name_end)
    if (body |> starts_with("(")) {
        let close = find(body, ")")
        m.function_like = true
        m.params <- [for (p in split(slice(body, 1, close), ",")); strip(p); where !empty(strip(p))]
        body = slice(body, close + 1)
    }
    m.body <- lex(body, false).toks
    return <- m
}

// a line marker: `# <number> "<file>"`
def private is_line_marker(ln : string) : bool {
    var digit = false
    peek_data(ln) $(b) {
        digit = length(b) > 2 && is_number(int(b[2]))
    }
    return digit
}

//! One translation unit preprocessed: the macros defined at its end, by line of the main file
//! (from 0) whether the preprocessor emitted the line, and the same per other file it includes, by
//! the name its line markers spell.
struct Preprocessed {
    macros : table<string; Macro>
    emitted : array<bool>
    included : table<string; array<bool>>
}

// line `line` of `lines` marked emitted
def private mark(var lines : array<bool>; line : int) {
    if (line >= length(lines)) {
        lines |> resize(line + 1)
    }
    lines[line] = true
}

//! The output of `clang -E -C -dD` over the file `main_path`: each `#define` and `#undef` in order,
//! and every non-empty line the line markers place in the main file or in another file.
def read_preprocessed(text, main_path : string) : Preprocessed {
    var pp : Preprocessed
    var file = ""
    var line = 0
    for (ln in split(text, "\n")) {
        if (ln |> starts_with("# ") && is_line_marker(ln)) {
            var inscope words <- split(ln, " ")
            line = to_int(words[1]) - 1
            file = length(words) > 2 ? slice(words[2], 1, length(words[2]) - 1) : file
            continue
        }
        if (ln |> starts_with("#define ")) {
            var name : string
            var m <- macro_of(ln, name)
            pp.macros[name] <- m
        } elif (ln |> starts_with("#undef ")) {
            pp.macros |> erase(strip(slice(ln, length("#undef "))))
        } elif (file == main_path && !empty(strip(ln))) {
            mark(pp.emitted, line)
        } elif (!empty(file) && !empty(strip(ln))) {
            mark(pp.included[file], line)
        }
        line++
    }
    return <- pp
}

//! `c_path` preprocessed by the pinned clang with `-D` for each of `defines`, `-I` for each of
//! `include_dirs` and `-include` for each of `include_files`, as the dumper passes a sidecar's,
//! under the frontend flags the dumper gives the `linux` dialect: its triple, macros and the own
//! libc headers; `error` names a unit clang refused.
def preprocess(c_path : string; defines, include_dirs, include_files : array<string>; var error : string&) : Preprocessed {
    var argv <- [default_clang(), "-E", "-C", "-dD"]
    let frontend <- dumper_frontend_flags(target_by_name("linux"), error)
    if (!empty(error)) {
        return <- Preprocessed()
    }
    argv |> push_from(frontend, [for (d in defines); "-D{d}"], [for (d in include_dirs); "-I{d}"])
    for (f in include_files) {
        argv |> push_from(["-include", f])
    }
    argv |> push(c_path)
    var text : string
    if (run_and_capture(argv, text, 120.0) != 0) {
        error = "clang -E {c_path}: {text}"
        return <- Preprocessed()
    }
    return <- read_preprocessed(text, c_path)
}

// the arguments of a call whose `(` is at `at`, and the index of its `)`
def private call_args(toks : array<Tok>; at : int; var args : array<array<Tok>>) : int {
    var depth = 0
    var cur : array<Tok>
    for (i in range(at, length(toks))) {
        let t = toks[i].text
        if (t == "(") {
            depth++
            if (depth == 1) {
                continue
            }
        } elif (t == ")") {
            depth--
            if (depth == 0) {
                args |> emplace(cur)
                return i
            }
        } elif (t == "," && depth == 1) {
            args |> emplace(cur)
            continue
        }
        cur |> push(toks[i])
    }
    return -1
}

// `toks` with every macro expanded, `active` the macros being expanded; false past `depth` 32 or
// on a call without its parenthesis
def private expand(toks : array<Tok>; macros : table<string; Macro>; active : array<string>; depth : int; var out : array<Tok>) : bool {
    if (depth > 32) {
        return false
    }
    var i = 0
    while (i < length(toks)) {
        let t = toks[i]
        var expanded = false
        if (t.kind == TokKind.ident && !has_value(active, t.text)) {
            var ok = true
            macros |> get(t.text) $(m) {
                var inscope inner : array<Tok>
                var inscope next_active := active
                next_active |> push(t.text)
                if (!m.function_like) {
                    ok = expand(m.body, macros, next_active, depth + 1, inner)
                } elif (i + 1 < length(toks) && toks[i + 1].text == "(") {
                    var inscope args : array<array<Tok>>
                    let close = call_args(toks, i + 1, args)
                    var inscope substituted : array<Tok>
                    for (b in m.body) {
                        let p = find_index(m.params, b.text)
                        if (p >= 0 && p < length(args)) {
                            substituted |> push_from(args[p])
                        } else {
                            substituted |> push(b)
                        }
                    }
                    ok = close > 0 && expand(substituted, macros, next_active, depth + 1, inner)
                    i = close
                } else {
                    return
                }
                out |> push_from(inner)
                expanded = true
            }
            if (!ok) {
                return false
            }
        }
        if (!expanded) {
            out |> push(t)
        }
        i++
    }
    return true
}

let private CONSTANT_PUNCT <- ["+", "-", "*", "/", "%", "<<", ">>", "&", "|", "^", "~", "!", "<", ">", "<=", ">=", "==", "!=", "&&", "||", "?", ":", "(", ")"]

// whether the token at `at` can start an operand that follows a cast: a sign would make `(x) - 1`
// a cast
def private starts_operand(toks : array<Tok>; at : int) : bool {
    if (at >= length(toks)) {
        return false
    }
    let t = toks[at]
    return t.kind != TokKind.punct || t.text == "(" || t.text == "~" || t.text == "!"
}

//! Whether expanded tokens are a numeric constant expression: numbers and character literals
//! under arithmetic, after dropping each cast `(T)` (identifiers and `*` in parentheses before an
//! operand) and each `sizeof(...)`.
def is_constant_expression(toks : array<Tok>) : bool {
    var numbers = 0
    var i = 0
    while (i < length(toks)) {
        let t = toks[i]
        if (t.text == "sizeof" && i + 1 < length(toks) && toks[i + 1].text == "(") {
            var depth = 0
            i++
            while (i < length(toks)) {
                depth += toks[i].text == "(" ? 1 : toks[i].text == ")" ? -1 : 0
                if (depth == 0) {
                    break
                }
                i++
            }
            numbers++
        } elif (t.text == "(") {
            var k = i + 1
            while (k < length(toks) && (toks[k].kind == TokKind.ident || toks[k].text == "*")) {
                k++
            }
            if (!(k > i + 1 && k < length(toks) && toks[k].text == ")" && starts_operand(toks, k + 1))) {
                k = i
            }
            i = k
        } elif (t.kind == TokKind.number || t.kind == TokKind.chr) {
            numbers++
        } elif (t.kind != TokKind.punct || !has_value(CONSTANT_PUNCT, t.text)) {
            return false
        }
        i++
    }
    return numbers > 0
}

//! The names among `own` whose macro in `macros` is object-like and expands to a numeric constant.
def constant_names(own : array<string>; macros : table<string; Macro>) : table<string; bool> {
    var names : table<string; bool>
    for (name in own) {
        macros |> get(name) $(m) {
            var inscope out : array<Tok>
            if (!m.function_like && expand(m.body, macros, [name], 0, out) && is_constant_expression(out)) {
                names[name] = true
            }
        }
    }
    return <- names
}

// the file a quoted `#include` of `inc` in a file of the folder `dir` names: beside it, else in the
// first of `include_dirs` holding it; "" when none does
def private quoted_include(dir, inc : string; include_dirs : array<string>) : string {
    let beside = path_join(dir, inc)
    if (fexist(beside)) {
        return beside
    }
    for (d in include_dirs) {
        let path = path_join(d, inc)
        if (fexist(path)) {
            return path
        }
    }
    return ""
}

//! The program's own files: `c_paths` and every header they include by a quoted name, found
//! beside the file that includes it or in the first of `include_dirs` holding it, transitively.
def own_files(c_paths, include_dirs : array<string>) : array<string> {
    var files := c_paths
    var i = 0
    while (i < length(files)) {
        let dir = dir_name(files[i])
        for (inc in scan_c(fread(files[i]), array<bool>()).quoted_includes) {
            let path = quoted_include(dir, inc, include_dirs)
            if (!empty(path) && !has_value(files, path)) {
                files |> push(path)
            }
        }
        i++
    }
    return <- files
}

//! The numeric-constant macros of a program of `c_paths` with the include folders `include_dirs`,
//! preprocessed as `units`: the names its own files define whose macro is a numeric constant in some unit.
[arch(at="ARCHITECTURE_CRITERIA.md#constants")]
def program_constants(c_paths, include_dirs : array<string>; units : array<Preprocessed>) : table<string; bool> {
    var own : array<string>
    for (f in own_files(c_paths, include_dirs)) {
        own |> push_from(scan_c(fread(f), array<bool>()).defined)
    }
    var inscope found : array<string>
    for (pp in units) {
        // bound first: a `for` over the keys of a returned table reads freed memory (daScript#55)
        var inscope names <- constant_names(own, pp.macros)
        found |> push_from([for (k in keys(names)); k])
    }
    return <- {for (k in found); k => true}
}

//! The function-like macros of a program of `c_paths` with the include folders `include_dirs`,
//! preprocessed as `units`: the names its own files define whose macro takes parameters in some
//! unit. Every C use of one is an expansion the output spells in place.
def program_function_macros(c_paths, include_dirs : array<string>; units : array<Preprocessed>) : table<string; bool> {
    var names : table<string; bool>
    for (f in own_files(c_paths, include_dirs)) {
        for (name in scan_c(fread(f), array<bool>()).defined) {
            for (pp in units) {
                pp.macros |> get(name) $(m) {
                    if (m.function_like) {
                        names[name] = true
                    }
                }
            }
        }
    }
    return <- names
}

//! The lines of the file `path` the preprocessing of any of `units` emitted, by line (from 0); empty
//! when none emitted any. A unit's line markers name a file as its include resolved it, so the
//! names compare as full paths.
def emitted_lines(path : string; units : array<Preprocessed>) : array<bool> {
    let full = get_full_file_name(path)
    var lines : array<bool>
    for (pp in units) {
        for (name, marked in keys(pp.included), values(pp.included)) {
            if (get_full_file_name(name) == full) {
                for (l, on in range(length(marked)), marked) {
                    if (on) {
                        mark(lines, l)
                    }
                }
            }
        }
    }
    return <- lines
}
