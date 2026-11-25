options gen2

module _header_scan

require strings
require daslib/strings_boost

//! The line scanner of the own libc headers (`frontend/include/ARCHITECTURE.md` section 3): every
//! line of a header is one of the forms the section lists, and a line of no form is an error, so
//! the scan is the format gate of the headers as well as the reader of what they declare.

struct Prototype {
    name : string
    result : string
    params : array<string>
    header : string
}

struct HeaderScan {
    prototypes : array<Prototype>
    objects : array<string>
    macros : array<string>
    includes : array<string>
    errors : array<string>
}

let RECORD = "record"
let UNBOUND = "unbound"

//! The base types a prototype may spell, each with the das type `crt` binds it as
//! (`dasCRuntime/ARCHITECTURE.md` section 3): `RECORD` for a record, which `crt` knows only behind
//! a pointer, `UNBOUND` for a type no `crt` function takes.
let BASE_TYPES <- {
    "void" => "void", "char" => "uint8", "int" => "int", "unsigned int" => "uint", "long" => "int64",
    "long long" => "int64", "unsigned long" => "uint64", "unsigned long long" => "uint64",
    "float" => "float", "double" => "double", "size_t" => "uint64", "time_t" => "int64",
    "clock_t" => "int64", "clockid_t" => "int", "mode_t" => "uint", "FILE" => RECORD,
    "jmp_buf" => UNBOUND, "__gnuc_va_list" => UNBOUND, "__compar_fn_t" => UNBOUND, "__sighandler_t" => UNBOUND
}

let private DIRECTIVES <- {"ifndef", "ifdef", "if", "else", "endif", "undef", "define", "include"}

def private is_identifier_char(ch : int) : bool => is_alpha(ch) || is_number(ch) || ch == '_'

def is_identifier(text : string) : bool {
    if (empty(text) || is_number(first_character(text))) {
        return false
    }
    for (ch in text) {
        if (!is_identifier_char(ch)) {
            return false
        }
    }
    return true
}

// the identifier `text` ends in, "" when it ends in none
def private trailing_identifier(text : string) : string {
    var from = length(text)
    peek_data(text) $(chars) {
        while (from > 0 && is_identifier_char(int(chars[from - 1]))) {
            from--
        }
        while (from < length(chars) && is_number(int(chars[from]))) {
            from++
        }
    }
    return slice(text, from)
}

//! The das spelling of the C type `c_type` as `crt` binds it, "" when `c_type` is not in the rigid
//! form: an optional `const`, a base type of `BASE_TYPES` or `struct <tag>`, then for a pointer one
//! space and its stars. A pointer to `void` or to a record is `void?`, const or not.
def das_spelling(c_type : string) : string {
    var inscope words <- split(c_type, " ")
    var stars = 0
    if (!empty(words) && !empty(words[length(words) - 1]) && empty(replace(words[length(words) - 1], "*", ""))) {
        stars = length(words[length(words) - 1])
        words |> pop()
    }
    let is_const = !empty(words) && words[0] == "const"
    if (is_const) {
        words |> erase(0)
    }
    let base = join(words, " ")
    let is_tagged = length(words) == 2 && words[0] == "struct" && is_identifier(words[1])
    if (!is_tagged && !key_exists(BASE_TYPES, base)) {
        return ""
    }
    let bound = is_tagged ? RECORD : BASE_TYPES?[base] ?? ""
    if (stars == 0) {
        return is_const || bound == RECORD ? "" : bound
    }
    return (bound == RECORD || bound == "void" ? "void" : is_const ? "{bound} const" : bound) + repeat("?", stars)
}

def private scan_error(var scan : HeaderScan; at, line, why : string) {
    scan.errors |> push("{at}: `{line}`: {why}")
}

// where the macro name `rest` starts with ends: its parameter list at `paren`, a space, or the end
def private space_or_end(rest : string; paren : int) : int {
    let space = find(rest, " ")
    let stop = space < 0 ? length(rest) : space
    return paren >= 0 && paren < stop ? paren : stop
}

def private scan_directive(var scan : HeaderScan; at, line : string) {
    let space = find(line, " ")
    let directive = slice(line, 1, space < 0 ? length(line) : space)
    let rest = space < 0 ? "" : slice(line, space + 1)
    if (!key_exists(DIRECTIVES, directive)) {
        scan_error(scan, at, line, "a directive is one of #ifndef, #ifdef, #if, #else, #endif, #undef, #define and #include")
    } elif (line |> ends_with("\\")) {
        scan_error(scan, at, line, "a directive is one line")
    } elif (directive == "define") {
        let paren = find(rest, "(")
        let name = slice(rest, 0, space_or_end(rest, paren))
        if (!is_identifier(name)) {
            scan_error(scan, at, line, "a #define names a macro")
        } else {
            scan.macros |> push(name)
        }
    } elif (directive == "include") {
        if (length(rest) < 3 || !(rest |> starts_with("<")) || !(rest |> ends_with(">"))) {
            scan_error(scan, at, line, "an #include is `#include <name>`")
        } else {
            scan.includes |> push(slice(rest, 1, length(rest) - 1))
        }
    }
}

def private scan_prototype(var scan : HeaderScan; header, at, line : string) {
    let open = find(line, "(")
    let head = slice(line, 0, open)
    let inner = slice(line, open + 1, length(line) - 2)
    let name = trailing_identifier(head)
    let before = slice(head, 0, length(head) - length(name))
    let result = before |> ends_with("*") ? before : before |> ends_with(" ") ? slice(before, 0, length(before) - 1) : ""
    var inscope params <- split(inner, ", ")
    if (inner == "void") {
        params |> clear()
    }
    var well_formed = !empty(name) && !empty(das_spelling(result))
    for (param, index in params, count()) {
        well_formed = well_formed && (!empty(das_spelling(param)) || (param == "..." && index > 0 && index == length(params) - 1))
    }
    if (!well_formed) {
        scan_error(scan, at, line, "a prototype is `<type> <name>(<type>, ...);` over the scanner's base types, its parameters unnamed, `(void)` for none")
        return
    }
    scan.prototypes |> emplace(Prototype(name = name, result = result, params <- params, header = header))
}

def private scan_line(var scan : HeaderScan; var in_record : bool&; header, at, line : string) {
    for (ch in line) {
        if (ch < ' ' || ch > '~') {
            scan_error(scan, at, line, "a header is printable ASCII, no tab")
            return
        }
    }
    if (line |> ends_with(" ")) {
        scan_error(scan, at, line, "a line ends in no blank")
    } elif (in_record) {
        if (line == "\};") {
            in_record = false
        } elif (!(line |> starts_with("    ")) || !(line |> ends_with(";")) || find(line, "(") >= 0 || find(line, "\{") >= 0 || find(line, "\}") >= 0) {
            scan_error(scan, at, line, "a record member is `    <type> <name>;`, the record's last line `\};`")
        }
    } elif (empty(line)) {
        return
    } elif (line |> starts_with("/*")) {
        if (find(line, "*/") != length(line) - 2) {
            scan_error(scan, at, line, "a comment is one line, `/* ... */`")
        }
    } elif (line |> starts_with("#")) {
        scan_directive(scan, at, line)
    } elif (line |> starts_with("typedef ") && line |> ends_with(";")) {
        return
    } elif (line |> starts_with("struct ") && line |> ends_with(" \{") && is_identifier(slice(line, 7, length(line) - 2))) {
        in_record = true
    } elif (line |> starts_with("extern ") && line |> ends_with(";") && find(line, "(") < 0) {
        scan.objects |> push(trailing_identifier(slice(line, 0, length(line) - 1)))
    } elif (line |> ends_with(");") && find(line, "(") > 0) {
        scan_prototype(scan, header, at, line)
    } else {
        scan_error(scan, at, line, "no form a header line takes")
    }
}

//! Adds what the header `header` of text `text` declares to `scan`: its prototypes, its `extern`
//! objects, the macros it defines and the headers it includes, and an error per line of no form.
def scan_header(var scan : HeaderScan; header, text : string) {
    var in_record = false
    var inscope lines <- split(text, "\n")
    if (!empty(lines) && empty(lines[length(lines) - 1])) {
        lines |> pop()
    }
    for (line, line_no in lines, count(1)) {
        scan_line(scan, in_record, header, "{header}:{line_no}", line)
    }
    if (in_record) {
        scan.errors |> push("{header}: a record is open at the end of the file")
    }
}
