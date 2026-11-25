options gen2

module _header_scan

require strings
require daslib/strings_boost
require dastest/review_gate

//! The line scanner of the own libc headers (`frontend/include/ARCHITECTURE.md` section 3): every
//! line of a header is one of the forms the section lists, and a line of no form is an error, so
//! the scan is the format gate of the headers as well as the reader of what they declare. It
//! evaluates no condition: a declaration counts only where no conditional but the file's include
//! guard is open, and a macro of a conditional only when both of its arms define it.

struct Prototype {
    name : string
    result : string
    params : array<string>
    header : string
    at : string
}

struct Define {
    name : string
    //! the line after `#define `: the name, its parameters and its body
    text : string
    at : string
}

struct HeaderScan {
    prototypes : array<Prototype>
    objects : array<string>
    //! the macros defined whatever a conditional decides, a later `#undef` taking one out
    macros : array<string>
    //! every `#define`d name but an include guard's, counted or not
    defined : array<string>
    defines : array<Define>
    //! every identifier a declaration line or a record's line spells: the names a macro may not take
    declared : table<string>
    guards : array<string>
    includes : array<string>
    //! a typedef name with the type it is declared as; `UNBOUND` for an array or a function pointer
    typedefs : table<string; string>
    errors : array<string>
}

let RECORD = "record"
let UNBOUND = "unbound"

//! The types a declaration bottoms out in, each with the das type `crt` binds it as
//! (`dasCRuntime/ARCHITECTURE.md` section 3): C's own, and the type macros the compiler predefines,
//! pinned at the width both dialects give them. `UNBOUND` is a type no `crt` function takes.
let BASE_TYPES <- {
    "void" => "void", "char" => "uint8", "signed char" => "int8", "unsigned char" => "uint8", "short" => "int16",
    "unsigned short" => "uint16", "int" => "int", "unsigned int" => "uint", "long" => "int64", "long long" => "int64",
    "unsigned long" => "uint64", "unsigned long long" => "uint64", "float" => "float", "double" => "double",
    "__SIZE_TYPE__" => "uint64", "__PTRDIFF_TYPE__" => "int64", "__INT64_TYPE__" => "int64",
    "unsigned __INT64_TYPE__" => "uint64", "__WCHAR_TYPE__" => UNBOUND, "__builtin_va_list" => UNBOUND
}

//! The macros that may share a name with a declaration, each with the lines that may define it:
//! glibc's self-definitions of the standard streams, its `setjmp` over `_setjmp`, and the two type
//! macros `<stdint.h>` picks by the width of `long`.
let MIRRORS <- {
    "stdin" => ["stdin stdin"], "stdout" => ["stdout stdout"], "stderr" => ["stderr stderr"],
    "setjmp" => ["setjmp(env) _setjmp (env)"],
    "__FAST16_TYPE" => ["__FAST16_TYPE long", "__FAST16_TYPE short"],
    "__FAST32_TYPE" => ["__FAST32_TYPE long", "__FAST32_TYPE int"]
}

let private C_KEYWORDS <- {
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float",
    "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static",
    "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Bool", "_Complex", "_Imaginary"
}

// what no line of a header holds: a line splice and its trigraph, a character literal, and the
// characters C has no use for
let private BANNED_TEXT <- ["\\", "??", "'", "`", "@", "$"]

// what opens or closes a comment: no line but a whole-line comment holds one
let private COMMENT_MARKS <- ["/*", "*/", "//"]

let private CONDITIONALS <- {"ifndef", "ifdef", "if"}

let private DIRECTIVES <- {"ifndef", "ifdef", "if", "else", "endif", "undef", "define", "include"}

// how deep a chain of typedefs may run before it is taken for a cycle
let private TYPEDEF_HOPS = 8

// what the scan of one header keeps between its lines
struct private FileState {
    header : string
    in_record : bool
    seen_code : bool
    guard : string
    guard_wants_define : bool
    guard_closed : bool
    in_conditional : bool
    in_else : bool
    if_macros : array<string>
    else_macros : array<string>
}

//! The identifiers of `text` in order: its runs of letters, digits and underscores.
def identifier_words(text : string) : array<string> {
    let spaced = build_string() $(var writer) {
        for (ch in text) {
            writer |> write_char(is_ident_byte(ch) ? ch : ' ')
        }
    }
    return <- [for (word in split(spaced, " ")); word; where !empty(word)]
}

def is_identifier(text : string) : bool {
    if (empty(text) || is_number(first_character(text))) {
        return false
    }
    for (ch in text) {
        if (!is_ident_byte(ch)) {
            return false
        }
    }
    return true
}

// the identifier `text` ends in, "" when it ends in none
def private trailing_identifier(text : string) : string {
    var from = length(text)
    peek_data(text) $(chars) {
        while (from > 0 && is_ident_byte(int(chars[from - 1]))) {
            from--
        }
        while (from < length(chars) && is_number(int(chars[from]))) {
            from++
        }
    }
    return slice(text, from)
}

//! The include guard the header `header` carries: `_`, then its name in capitals with every other
//! character an underscore (`sys/stat.h` is `_SYS_STAT_H`).
def guard_of(header : string) : string {
    return build_string() $(var writer) {
        writer |> write_char('_')
        for (ch in to_upper(header)) {
            writer |> write_char(is_ident_byte(ch) ? ch : '_')
        }
    }
}

// the words of the type `c_type` in the rigid form, its stars counted and a leading `const` noted:
// an optional `const`, identifiers one space apart, then for a pointer one space and the stars
def private type_words(c_type : string; var stars : int&; var is_const : bool&) : array<string> {
    var words <- split(c_type, " ")
    stars = 0
    if (!empty(words) && !empty(words[length(words) - 1]) && empty(replace(words[length(words) - 1], "*", ""))) {
        stars = length(words[length(words) - 1])
        words |> pop()
    }
    is_const = !empty(words) && words[0] == "const"
    if (is_const) {
        words |> erase(0)
    }
    return <- words
}

// whether `c_type` is written in the rigid form, whatever its words name
def private is_type_shaped(c_type : string) : bool {
    var stars = 0
    var is_const = false
    var inscope words <- type_words(c_type, stars, is_const)
    for (word in words) {
        if (!is_identifier(word)) {
            return false
        }
    }
    return !empty(words)
}

//! The das spelling of the C type `c_type` as `crt` binds it, "" when it has none: its base is read
//! through `typedefs` down to a type of `BASE_TYPES` or a `struct <tag>`, so a typedef name stands
//! for what a header declares it as and a name no header declares for nothing. A pointer to `void`
//! or to a record is `void?`, const or not; a `const` value and a record by value have no spelling.
def das_spelling(typedefs : table<string; string>; c_type : string) : string {
    var stars = 0
    var is_const = false
    var inscope words <- type_words(c_type, stars, is_const)
    var base = join(words, " ")
    var hops = 0
    while (!key_exists(BASE_TYPES, base) && key_exists(typedefs, base) && hops < TYPEDEF_HOPS) {
        base = typedefs?[base] ?? ""
        hops++
    }
    var inscope base_words <- split(base, " ")
    let is_tagged = length(base_words) == 2 && base_words[0] == "struct" && is_identifier(base_words[1])
    let bound = is_tagged ? RECORD : base == UNBOUND ? UNBOUND : BASE_TYPES?[base] ?? ""
    if (empty(bound) || !is_type_shaped(c_type)) {
        return ""
    }
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

def private sorted_names(names : array<string>) : string {
    var inscope sorted := names
    sort(sorted)
    return join(sorted, " ")
}

def private scan_define(var scan : HeaderScan; var state : FileState; at, line, rest : string) {
    let name = slice(rest, 0, space_or_end(rest, find(rest, "(")))
    if (!is_identifier(name)) {
        scan_error(scan, at, line, "a #define names a macro")
    } elif (name == guard_of(state.header)) {
        scan_error(scan, at, line, "the include guard is defined once, on the line after its #ifndef")
    } else {
        scan.defined |> push(name)
        scan.defines |> emplace(Define(name = name, text = rest, at = at))
        if (!state.in_conditional) {
            scan.macros |> push(name)
        } elif (state.in_else) {
            state.else_macros |> push(name)
        } else {
            state.if_macros |> push(name)
        }
    }
}

// a conditional's last line: its macros are defined whatever it decides when both arms define them
def private scan_endif(var scan : HeaderScan; var state : FileState; at, line : string) {
    if (state.in_conditional) {
        if (!state.in_else || sorted_names(state.if_macros) != sorted_names(state.else_macros)) {
            scan_error(scan, at, line, "a conditional has an #else, and both arms define the same macros")
        } else {
            scan.macros |> push_from(state.if_macros)
        }
        state.in_conditional = false
        state.in_else = false
        state.if_macros |> clear()
        state.else_macros |> clear()
    } elif (!empty(state.guard) && !state.guard_closed) {
        state.guard_closed = true
    } else {
        scan_error(scan, at, line, "an #endif closes a conditional")
    }
}

def private scan_directive(var scan : HeaderScan; var state : FileState; at, line : string) {
    let space = find(line, " ")
    let directive = slice(line, 1, space < 0 ? length(line) : space)
    let rest = space < 0 ? "" : slice(line, space + 1)
    let is_first = !state.seen_code
    state.seen_code = true
    if (!key_exists(DIRECTIVES, directive)) {
        scan_error(scan, at, line, "a directive is one of #ifndef, #ifdef, #if, #else, #endif, #undef, #define and #include")
    } elif (line |> ends_with("\\")) {
        scan_error(scan, at, line, "a directive is one line")
    } elif (directive == "ifndef" && is_first && rest == guard_of(state.header)) {
        state.guard = rest
        state.guard_wants_define = true
        scan.guards |> push(rest)
    } elif (key_exists(CONDITIONALS, directive)) {
        if (state.in_conditional) {
            scan_error(scan, at, line, "a conditional holds no conditional")
        }
        state.in_conditional = true
    } elif (directive == "else") {
        if (!state.in_conditional || state.in_else || !empty(rest)) {
            scan_error(scan, at, line, "an #else is the one of a conditional that is not the include guard")
        }
        state.in_else = true
    } elif (directive == "endif") {
        scan_endif(scan, state, at, line)
    } elif (directive == "define") {
        scan_define(scan, state, at, line, rest)
    } elif (state.in_conditional) {
        scan_error(scan, at, line, "a conditional holds #define lines only")
    } elif (directive == "undef") {
        var inscope kept <- [for (name in scan.macros); name; where name != rest]
        scan.macros := kept
    } elif (length(rest) < 3 || !(rest |> starts_with("<")) || !(rest |> ends_with(">"))) {
        scan_error(scan, at, line, "an #include is `#include <name>`")
    } else {
        scan.includes |> push(slice(rest, 1, length(rest) - 1))
    }
}

// `typedef <type> <name>;`, `typedef <type> <name>[<count>];` or `typedef <type> (*<name>)(<types>);`:
// one declaration, the line's only `;` its last character
def private scan_typedef(var scan : HeaderScan; at, line : string) {
    let body = slice(line, 8, length(line) - 1)
    let pointer = find(body, " (*")
    let bracket = find(body, "[")
    var name = ""
    var declared = UNBOUND
    if (pointer > 0 && body |> ends_with(")") && find(body, ")(") > pointer) {
        name = slice(body, pointer + 3, find(body, ")("))
    } elif (bracket > 0 && body |> ends_with("]") && is_identifier(slice(body, 0, bracket) |> trailing_identifier())) {
        name = slice(body, 0, bracket) |> trailing_identifier()
        declared = is_type_shaped(slice(body, 0, bracket - length(name) - 1)) ? UNBOUND : ""
    } elif (find(body, "(") < 0 && find(body, "*") < 0 && find(body, ",") < 0) {
        name = trailing_identifier(body)
        declared = length(body) > length(name) + 1 ? slice(body, 0, length(body) - length(name) - 1) : ""
        declared = is_type_shaped(declared) ? declared : ""
    }
    if (find(body, ";") >= 0 || find(body, "\{") >= 0 || !is_identifier(name) || empty(declared)) {
        scan_error(scan, at, line, "a typedef is one declaration, `typedef <type> <name>;`, an array `<name>[<count>]` or a function pointer `(*<name>)(<types>)`")
    } elif (key_exists(scan.typedefs, name)) {
        scan_error(scan, at, line, "`{name}` is a typedef of another line already")
    } else {
        scan.typedefs |> insert(name, declared)
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
    var well_formed = !empty(name) && is_type_shaped(result)
    for (param, index in params, count()) {
        well_formed = well_formed && (is_type_shaped(param) || (param == "..." && index > 0 && index == length(params) - 1))
    }
    if (!well_formed) {
        scan_error(scan, at, line, "a prototype is `<type> <name>(<type>, ...);`, its parameters unnamed, `(void)` for none")
        return
    }
    scan.prototypes |> emplace(Prototype(name = name, result = result, params <- params, header = header, at = at))
}

def private note_declared(var scan : HeaderScan; line : string) {
    var inscope words <- identifier_words(line)
    for (word in words) {
        scan.declared |> insert(word)
    }
}

// a prototype, an object, a typedef or a record: it counts where it cannot be compiled out
def private scan_declaration(var scan : HeaderScan; var state : FileState; at, line : string) {
    let is_type = line |> starts_with("typedef ") || line |> starts_with("struct ")
    state.seen_code = true
    note_declared(scan, line)
    if (state.in_conditional) {
        scan_error(scan, at, line, "a declaration stands in no conditional but the include guard")
    } elif (is_type && empty(state.guard)) {
        scan_error(scan, at, line, "a header that declares a type starts with its include guard, `#ifndef {guard_of(state.header)}`")
    } elif (line |> starts_with("typedef ") && line |> ends_with(";")) {
        scan_typedef(scan, at, line)
    } elif (line |> starts_with("struct ") && line |> ends_with(" \{") && is_identifier(slice(line, 7, length(line) - 2))) {
        state.in_record = true
    } elif (line |> starts_with("extern ") && line |> ends_with(";") && find(line, "(") < 0) {
        scan.objects |> push(trailing_identifier(slice(line, 0, length(line) - 1)))
    } elif (line |> ends_with(");") && find(line, "(") > 0) {
        scan_prototype(scan, state.header, at, line)
    } else {
        scan_error(scan, at, line, "no form a header line takes")
    }
}

def private scan_line(var scan : HeaderScan; var state : FileState; at, line : string) {
    for (ch in line) {
        if (ch < ' ' || ch > '~') {
            scan_error(scan, at, line, "a header is printable ASCII, no tab")
            return
        }
    }
    let is_comment = line |> starts_with("/*")
    let quotes = length(line) - length(replace(line, "\"", ""))
    for (text in BANNED_TEXT) {
        if (find(line, text) >= 0) {
            scan_error(scan, at, line, "a header holds no `{text}`")
            return
        }
    }
    for (mark in COMMENT_MARKS) {
        if (!is_comment && find(line, mark) >= 0) {
            scan_error(scan, at, line, "a comment is a line of its own: no other line holds `{mark}`")
            return
        }
    }
    if (quotes % 2 != 0 || (quotes > 0 && !(line |> starts_with("#define ")))) {
        scan_error(scan, at, line, "a string literal stands whole in a #define, nowhere else")
        return
    }
    let wants_define = state.guard_wants_define
    state.guard_wants_define = false
    if (wants_define && line != "#define {state.guard}") {
        scan_error(scan, at, line, "the include guard's `#define {state.guard}` follows its #ifndef")
    } elif (wants_define || empty(line)) {
        return
    } elif (line |> ends_with(" ")) {
        scan_error(scan, at, line, "a line ends in no blank")
    } elif (state.guard_closed) {
        scan_error(scan, at, line, "the include guard's #endif is the header's last line")
    } elif (state.in_record) {
        note_declared(scan, line)
        if (line == "\};") {
            state.in_record = false
        } elif (!(line |> starts_with("    ")) || !(line |> ends_with(";")) || find(line, "(") >= 0 || find(line, "\{") >= 0 || find(line, "\}") >= 0) {
            scan_error(scan, at, line, "a record member is `    <type> <name>;`, the record's last line `\};`")
        }
    } elif (is_comment) {
        if (length(line) < 4 || find(line, "*/", 2) != length(line) - 2) {
            scan_error(scan, at, line, "a comment is one line, `/* ... */`")
        }
    } elif (line |> starts_with("#")) {
        scan_directive(scan, state, at, line)
    } else {
        scan_declaration(scan, state, at, line)
    }
}

//! Adds what the header `header` of text `text` declares to `scan`: its prototypes, its `extern`
//! objects, its typedefs, the macros it defines and the headers it includes, and an error per line
//! of no form. `finish_scan` judges the prototypes and the macros once every header is scanned.
def scan_header(var scan : HeaderScan; header, text : string) {
    var inscope state <- FileState(header = header)
    var inscope lines <- split(text, "\n")
    if (!empty(lines) && empty(lines[length(lines) - 1])) {
        lines |> pop()
    }
    for (line, line_no in lines, count(1)) {
        scan_line(scan, state, "{header}:{line_no}", line)
    }
    if (state.in_record) {
        scan.errors |> push("{header}: a record is open at the end of the file")
    }
    if (state.in_conditional || (!empty(state.guard) && !state.guard_closed)) {
        scan.errors |> push("{header}: a conditional is open at the end of the file")
    }
}

//! An error for every prototype type that reaches no base type through the typedefs the scanned
//! headers declare: a name no header declares, a named parameter, a record by value.
def private check_types(var scan : HeaderScan) {
    for (proto in scan.prototypes) {
        var inscope types := proto.params
        types |> push(proto.result)
        for (c_type in types) {
            if (c_type != "..." && empty(das_spelling(scan.typedefs, c_type))) {
                scan.errors |> push("{proto.at}: `{proto.name}`: `{c_type}` is no type the headers declare")
            }
        }
    }
}

//! An error for every macro that takes a name a header declares, in any header and in any order, or
//! a C keyword: such a macro rewrites declarations the scan has read as they stand. A name of
//! `MIRRORS` is defined by one of its listed lines and no other.
def private check_macros(var scan : HeaderScan) {
    for (define in scan.defines) {
        if (key_exists(MIRRORS, define.name)) {
            if (!has_value(MIRRORS?[define.name] ?? [""], define.text)) {
                scan.errors |> push("{define.at}: `#define {define.text}`: `{define.name}` is defined as its listed mirror and nothing else")
            }
        } elif (key_exists(scan.declared, define.name) || key_exists(C_KEYWORDS, define.name)) {
            scan.errors |> push("{define.at}: `#define {define.text}`: a macro takes no name a header declares and no C keyword")
        }
    }
}

//! What is judged once every header is scanned: the prototypes' types and the macros' names.
def finish_scan(var scan : HeaderScan) {
    check_types(scan)
    check_macros(scan)
}
