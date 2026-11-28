options gen2
options indenting = 4

module pp_directives public

require strings
require daslib/strings_boost
require daslib/fio
require pp_lexer public
require pp_eval public
require c_defines

//! Where the preprocessor reads a file: `exists` answers whether `path` names a readable file,
//! `read` fills `bytes` with it and one byte of spare capacity, as `pp_open` wants, and
//! `identity` names the file `path` reaches, the same for every path that reaches it.
class PpFileProvider {
    def abstract exists(path : string) : bool
    def abstract read(path : string; var bytes : array<uint8>) : bool
    def abstract identity(path : string) : string
}

//! The provider of the file system, read through `fio`: a file's identity is its real path, every
//! link and `..` resolved by the file system.
[arch(at="ARCHITECTURE_PP.md#pp-files")]
class PpFioProvider : PpFileProvider {
    def override exists(path : string) : bool => stat(path).is_reg
    def override read(path : string; var bytes : array<uint8>) : bool => pp_read_file(path, bytes)
    def override identity(path : string) : string => get_full_file_name(path)
}

//! A provider over texts in memory, a path each: `add` sets one, `link` makes a folder path stand
//! for another, as a symbolic link does, before the files under it are added.
[arch(at="ARCHITECTURE_PP.md#pp-files")]
class PpMemoryProvider : PpFileProvider {
    files : table<string; string>
    links : table<string; string>
    def add(path, text : string) {
        files |> insert(identity(path), text)
    }
    def link(path, target : string) {
        links |> insert(path, target)
    }
    def override exists(path : string) : bool => key_exists(files, identity(path))
    def override identity(path : string) : string {
        var parts : array<string>
        if (starts_with(path, "/")) {
            parts |> push("")
        }
        for (part in split(path, "/")) {
            if (empty(part) || part == ".") {
                continue
            } elif (part == ".." && !empty(parts) && parts[length(parts) - 1] != ".." && !empty(parts[length(parts) - 1])) {
                parts |> pop()
            } else {
                parts |> push(part)
                let target = links?[join(parts, "/")] ?? ""
                if (!empty(target)) {
                    delete parts
                    parts <- split(identity(target), "/")
                }
            }
        }
        return join(parts, "/")
    }
    def override read(path : string; var bytes : array<uint8>) : bool {
        let key = identity(path)
        return false if (!key_exists(files, key))
        let text = files?[key] ?? ""
        bytes |> reserve(length(text) + 1)
        peek_data(text) $(chars) {
            for (c in chars) {
                bytes |> push(c)
            }
        }
        return true
    }
}

//! How bad a directive's diagnostic is; only a fatal one stops the preprocessor.
enum PpSeverity {
    warning
    error
    fatal
}

//! A diagnostic of the directive layer, at a token's physical place and its presumed one (`#line`).
struct PpDiagnostic {
    severity : PpSeverity
    file : int
    offset : int
    line : int
    col : int
    pname : int     //!< the presumed file name, an index of `Preprocessor.names`
    pline : uint
    what : string
}

//! A token kept past its lexer: its spelling is `len` bytes at `at` of the owner's text pool.
struct PpHeld {
    kind : int
    sym : int
    file : int
    offset : int
    line : int
    col : int
    at : int
    len : int
    has_space : bool
}

//! One `#define`: the body is `count` tokens of `Preprocessor.macro_body` from `first`; a
//! variadic macro's last parameter is `__VA_ARGS__`, or the name a GNU `name...` gives it.
struct PpMacro {
    name : int
    function_like : bool
    variadic : bool
    params : array<int>
    first : int
    count : int
    file : int
    line : int
    col : int
}

//! Why an `#include` read no file.
enum PpIncludeSkip {
    none
    pragma_once         //!< the file said `#pragma once` and was read before
    guard               //!< the file's include guard is defined
    not_found
    too_deep
    needs_expansion     //!< the name is not a header name: PP.3 expands it
}

//! One `#include` met in an active group, read or not.
struct PpInclusion {
    file : int          //!< the file read or skipped, -1 when none was found
    spelled : string    //!< the header name as written, `<...>` or `"..."`
    from : int
    line : int
    col : int
    skip : PpIncludeSkip
}

//! A `#pragma`, or an `#ident` (`ident`), kept for the C-IR ledger, after `emitted` tokens of the
//! translation unit.
struct PpPragma {
    file : int
    line : int
    col : int
    pname : int
    pline : uint
    emitted : int
    ident : bool        //!< an `#ident` or `#sccs` line, `text` its string literal
    text : string       //!< the tokens after `pragma`, a blank where the source had space
}

//! What a `#pragma pack` does.
enum PpPackAction {
    set
    reset
    push
    pop
    show
}

//! One `#pragma pack`, after `emitted` tokens: its action, the alignment and the tag it names
//! (0 and "" when none), and the alignment in force after it (0: the target's default).
struct PpPack {
    file : int
    line : int
    col : int
    emitted : int
    action : PpPackAction
    value : int
    tag : string
    current : int
}

//! A file the preprocessor opened, known by its provider's `identity`: `path` and `name` are those
//! of its first inclusion.
struct PpFile {
    path : string
    identity : string
    name : int
    once : bool         //!< it said `#pragma once`, or an `#import` named it
    guard : int         //!< the macro of its whole-file include guard, -1 when it has none
    entered : int
}

//! Where a handed-out token's spelling lies.
enum PpSpelled {
    source      //!< `len` bytes at `at` of the file buffer `buffer` (`pp_buffer_data`), past translation phase 2
    body        //!< `len` bytes at `at` of `Preprocessor.macro_text`, a macro body's token
    symbol      //!< the text of the identifier's symbol `tok.sym`
    scratch     //!< `len` bytes at `at` of the expansion's `text` pool: a pasted or stringified token, or a copy
}

//! A token of the translation unit: `tok` placed where it was spelled (a macro body's token in its
//! `#define`), `pline` and `pname` the line and file name `#line` makes it report - for a token of an
//! expansion, the place of the outermost macro name; `call` the macro call it came from, an index of
//! the expansion's `calls`, -1 for a token of the source. `spelled`, `buffer`, `at` and `len` say
//! where its spelling lies (`pp_span_of`). `painted` marks a name read while its macro was
//! disabled: it never expands again.
struct PpOutToken {
    tok : PpToken
    pline : uint
    pname : int
    call : int
    spelled : PpSpelled
    buffer : int
    at : int
    len : int
    painted : bool
}

//! One macro call: the macro (an index of `Preprocessor.macros`), its name token's place and the
//! call that token came from (-1: the source), the presumed place of the outermost name and the
//! presumed line of its end (the `)`, or the name of an object-like macro), and its arguments,
//! `arg_count` entries of the expansion's `call_args` from `first_arg`.
struct PpCall {
    macro : int
    name : PpToken
    parent : int
    pline : uint
    pname : int
    end_pline : uint
    first_arg : int
    arg_count : int
}

//! One argument of a call as written: its file and the byte span from its first token's offset to
//! its last token's end, -1 offsets when it is empty or not spelled in one stretch of a file.
struct PpCallArg {
    file : int
    from : int
    to : int
}

//! The macro expansion over the directive layer, PP.3's (`pp_expand.das`): `next_token` hands out
//! the next expanded token into `pp.tok`; `expand_line` expands the tokens of `pp.line` in place,
//! leaving the operands of `defined` alone when `condition`; `macro_changed` hears of a `#define`
//! of a name no macro defines and of every `#undef`, before the table changes. It keeps the call
//! record and the pool of the spellings it made.
class PpExpansion {
    calls : array<PpCall>
    call_args : array<PpCallArg>
    text : array<uint8>
    def abstract next_token(var pp : Preprocessor) : bool
    def abstract expand_line(var pp : Preprocessor; condition : bool) : void
    def macro_changed(var pp : Preprocessor; name : PpToken; undef : bool) : void {
        pass
    }
    def is_builtin(pp : Preprocessor; sym : int) : bool => false
}

//! An open conditional: `active` while its current group is read, `taken` once a group was (or
//! the conditional sits in a skipped group, so none will be).
struct PpCond {
    active : bool
    taken : bool
    seen_else : bool
    file : int
    line : int
    col : int
}

//! where a file stands on the include-guard pattern
enum private GuardState {
    start
    inside
    closed
    none
}

//! the state of the inclusion being read that a nested `#include` suspends: `dir` is its quote
//! directory, `found_at` the include-path folder `#include_next` searches after (-1: none)
struct PpFileState {
    file : int
    dir : string
    found_at : int
    line_delta : uint
    markers : int       //!< the line markers with flag 1 not yet closed by a flag 2
    pname : int
    cond_base : int
    guard : GuardState
    guard_sym : int
    buffer : int        //!< the id of this inclusion's working buffer, an index of `Preprocessor.buffer_data`
}

//! a suspended file: its lexer with the next token, and its state
struct PpFrame {
    lx : PpLexer
    state : PpFileState
    pending : bool
}

enum private PpDirective {
    unknown
    define
    undef
    hash_include
    hash_include_next
    hash_import
    hash_if
    ifdef
    ifndef
    hash_elif
    hash_elifdef
    hash_elifndef
    hash_else
    endif
    line
    error
    warning
    pragma
    ident
}

//! The nesting of `#include` clang allows: the main file and 199 more.
let PP_MAX_INCLUDE_DEPTH = 200

//! The name the predefined macros' buffer reports.
let PP_BUILTIN_NAME = "<built-in>"

//! The preprocessor over one translation unit: one lexer, the files it suspended for an
//! `#include`, the macro table and the ledgers. Read it with `pp_next_token`; every field is the
//! caller's to read and the preprocessor's to write.
struct Preprocessor {
    provider : PpFileProvider?
    lx : PpLexer
    state : PpFileState
    frames : array<PpFrame>
    pending : bool                      //!< `lx.tok` is the next token, read past a directive's line
    search : array<string>              //!< the include path, in order
    files : array<PpFile>
    file_of : table<string; int>
    names : array<string>               //!< the presumed file names: every file's path, every `#line` name
    name_of : table<string; int>
    tok : PpOutToken                    //!< the token `pp_next_token` read
    emitted : int                       //!< the tokens `pp_next_token` handed out
    directives_read : int               //!< the directive lines read in active and skipped groups
    conds : array<PpCond>
    macros : array<PpMacro>             //!< every definition in order, an `#undef` leaves it here
    macro_of : table<int; int>          //!< a defined name's index in `macros`
    macro_body : array<PpHeld>
    macro_text : array<uint8>
    line : array<PpHeld>                //!< the tokens of the directive being read
    line_text : array<uint8>
    diags : array<PpDiagnostic>
    pragmas : array<PpPragma>
    packs : array<PpPack>
    pack_stack : array<PpPack>
    pack_now : int
    inclusions : array<PpInclusion>
    directive_of : table<int; PpDirective>
    fatal : bool                        //!< a fatal diagnostic ended the translation unit
    sym_defined : int
    sym_va_args : int
    sym_va_opt : int
    sym_once : int
    sym_pack : int
    sym_push : int
    sym_pop : int
    sym_show : int
    sym_push_macro : int
    sym_pop_macro : int
    pushed_macros : table<int; array<int>>  //!< `#pragma push_macro`'s saved definitions of a name, -1 for none
    last_tok : PpToken                  //!< the directive's last token read
    expansion : PpExpansion?            //!< the macro expansion `pp_next_token` hands out through; none: the directive layer's tokens
    buffer_data : array<uint8?>         //!< per buffer id, the first byte of a file's working buffer, valid for the unit's life
    closed : array<array<uint8>>        //!< the working buffers of the closed files, kept so their spellings outlive them
    eval : PpEval                       //!< the `#if` evaluator: its line, target, feature table (the caller's to set) and last diagnostics
}

def private intern_text(var pp : Preprocessor; text : string) : int => intern_name(pp.lx.flex.syms, text)

def private name_id(var pp : Preprocessor; name : string) : int {
    let known = pp.name_of?[name] ?? -1
    return known if (known >= 0)
    pp.names |> push(name)
    pp.name_of |> insert(name, length(pp.names) - 1)
    return length(pp.names) - 1
}

def private intern_directives(var pp : Preprocessor) {
    let names <- [("define", PpDirective.define), ("undef", PpDirective.undef), ("include", PpDirective.hash_include),
                  ("include_next", PpDirective.hash_include_next), ("if", PpDirective.hash_if), ("ifdef", PpDirective.ifdef),
                  ("ifndef", PpDirective.ifndef), ("elif", PpDirective.hash_elif), ("elifdef", PpDirective.hash_elifdef),
                  ("elifndef", PpDirective.hash_elifndef), ("else", PpDirective.hash_else), ("endif", PpDirective.endif),
                  ("line", PpDirective.line), ("error", PpDirective.error), ("warning", PpDirective.warning),
                  ("pragma", PpDirective.pragma), ("import", PpDirective.hash_import), ("ident", PpDirective.ident),
                  ("sccs", PpDirective.ident)]
    for (entry in names) {
        pp.directive_of |> insert(intern_text(pp, entry._0), entry._1)
    }
    pp.sym_defined = intern_text(pp, "defined")
    pp.sym_va_args = intern_text(pp, "__VA_ARGS__")
    pp.sym_va_opt = intern_text(pp, "__VA_OPT__")
    pp.sym_once = intern_text(pp, "once")
    pp.sym_pack = intern_text(pp, "pack")
    pp.sym_push = intern_text(pp, "push")
    pp.sym_pop = intern_text(pp, "pop")
    pp.sym_show = intern_text(pp, "show")
    pp.sym_push_macro = intern_text(pp, "push_macro")
    pp.sym_pop_macro = intern_text(pp, "pop_macro")
}

//! `path` with its `.` components and doubled `/` removed; a `..` stays, since only the file
//! system knows where it leads past a link
[arch(at="ARCHITECTURE_PP.md#pp-files")]
def normalized_path(path : string) : string {
    var parts : array<string>
    for (part in split(path, "/")) {
        continue if (part == "." || (empty(part) && !empty(parts)))
        parts |> push(part)
    }
    return length(parts) == 1 && empty(parts[0]) ? "/" : join(parts, "/")
}

def private register_file(var pp : Preprocessor; path, identity : string) : int {
    let id = length(pp.files)
    pp.files |> push(PpFile(path = path, identity = identity, name = name_id(pp, path), guard = -1))
    pp.file_of |> insert(identity, id)
    return id
}

def private presumed_line(pp : Preprocessor; line : int) : uint => uint(line) + pp.state.line_delta

def private diagnose_at(var pp : Preprocessor; severity : PpSeverity; at : PpToken; what : string) {
    pp.diags |> push(PpDiagnostic(severity = severity, file = at.file, offset = at.offset, line = at.line, col = at.col,
                                  pname = pp.state.pname, pline = presumed_line(pp, at.line), what = what))
}

def private diagnose_held(var pp : Preprocessor; severity : PpSeverity; at : PpHeld; what : string) {
    pp.diags |> push(PpDiagnostic(severity = severity, file = at.file, offset = at.offset, line = at.line, col = at.col,
                                  pname = pp.state.pname, pline = presumed_line(pp, at.line), what = what))
}

def private diagnose(var pp : Preprocessor; severity : PpSeverity; what : string) {
    diagnose_at(pp, severity, pp.lx.tok, what)
}

//! the definitions of the predefined-macro entries as directive text, the buffer clang reads first
[arch(at="ARCHITECTURE_PP.md#pp-start")]
def private builtin_text(var pp : Preprocessor; predefines : array<string>) : string {
    return build_string() $(var out) {
        var parsed : Define
        for (entry in predefines) {
            if (!parse_define(entry, parsed)) {
                pp.diags |> push(PpDiagnostic(severity = PpSeverity.error, what = "not a macro definition: {entry}"))
                continue
            }
            out |> write("#define {parsed.name}")
            if (parsed.fn_like) {
                out |> write("({join(parsed.params, ",")})")
            }
            out |> write(" {parsed.value}\n")
        }
    }
}

//! read file `id` by `path`, found in the include-path folder `found_at` (-1: none)
[arch(at="ARCHITECTURE_PP.md#pp-search")]
def private open_file(var pp : Preprocessor; id : int; path : string; found_at : int; var bytes : array<uint8>) {
    pp_open(pp.lx, bytes, id, path)
    pp.files[id].entered++
    pp.pending = false
    pp.state = PpFileState(file = id, dir = dir_name(path), found_at = found_at, pname = name_id(pp, path),
                           cond_base = length(pp.conds), guard = GuardState.start, guard_sym = -1, buffer = length(pp.buffer_data))
    pp.buffer_data |> push(pp.lx.flex.data)
}

//! suspend the file being read, with its next token, and open file `id`
def private push_file(var pp : Preprocessor; id : int; path : string; found_at : int; var bytes : array<uint8>) {
    var frame = PpFrame(lx <- pp.lx, state = pp.state, pending = pp.pending)
    pp.lx.flex.syms <- frame.lx.flex.syms
    pp.lx.diags <- frame.lx.diags
    pp.frames |> emplace(frame)
    open_file(pp, id, path, found_at, bytes)
}

//! close the file being read and resume the one that included it, at the token it stopped on;
//! the interner lets go of the closed file's bytes first, and the bytes move to `pp.closed`
def private pop_file(var pp : Preprocessor) {
    flex_symbols_detach(pp.lx.flex.syms)
    var frame <- pp.frames[length(pp.frames) - 1]
    pp.frames |> pop()
    var syms <- pp.lx.flex.syms
    var diags <- pp.lx.diags
    pp.closed |> emplace(pp.lx.flex.bytes)
    delete pp.lx.splices
    pp.lx <- frame.lx
    pp.lx.flex.syms <- syms
    pp.lx.diags <- diags
    pp.state = frame.state
    pp.pending = frame.pending
}

//! Start preprocessing `main` read through `provider`: the `predefines` (entries of
//! `parse_define`, `read_predefined`'s table then the sidecar's) are defined before its first
//! line, and `<...>` names are searched in `search`, in order. False, with a diagnostic, when
//! `main` cannot be read.
[arch(at="ARCHITECTURE_PP.md#pp-start")]
def pp_start(var pp : Preprocessor; var provider : PpFileProvider?; main : string; predefines : array<string>;
             search : array<string>) : bool {
    pp.provider = provider
    pp.search := search
    pp.eval.target = pp_eval_target(predefines)
    intern_directives(pp)
    var bytes : array<uint8>
    let path = normalized_path(main)
    if (!provider->exists(path) || !provider->read(path, bytes)) {
        pp.diags |> push(PpDiagnostic(severity = PpSeverity.error, what = "cannot read {main}"))
        return false
    }
    open_file(pp, register_file(pp, path, provider->identity(path)), path, -1, bytes)
    var builtin : array<uint8>
    let text = builtin_text(pp, predefines)
    builtin |> reserve(length(text) + 1)
    peek_data(text) $(chars) {
        for (c in chars) {
            builtin |> push(c)
        }
    }
    let id = length(pp.files)
    pp.files |> push(PpFile(path = PP_BUILTIN_NAME, name = name_id(pp, PP_BUILTIN_NAME), guard = -1))
    push_file(pp, id, PP_BUILTIN_NAME, -1, builtin)
    return true
}

def private skipping(pp : Preprocessor) : bool => !empty(pp.conds) && !pp.conds[length(pp.conds) - 1].active

//! the next raw token: the one a directive read past its line, or the lexer's next; false at the
//! end of the file being read
def private fetch(var pp : Preprocessor) : bool {
    if (pp.pending) {
        pp.pending = false
        return pp.lx.tok.kind != int(PpTok.EOF)
    }
    return pp_next(pp.lx)
}

//! the next token of the directive's line; false at its end, the token after it then pending
def private next_on_line(var pp : Preprocessor) : bool {
    return false if (pp.pending)
    if (!pp_next(pp.lx) || pp.lx.tok.at_bol) {
        pp.pending = true
        return false
    }
    pp.last_tok = pp.lx.tok
    return true
}

//! skip the rest of the directive's line; the tokens skipped
def private skip_rest(var pp : Preprocessor) : int {
    var n = 0
    while (next_on_line(pp)) {
        n++
    }
    return n
}

def private extra_tokens(var pp : Preprocessor; name : string) {
    if (next_on_line(pp)) {
        diagnose(pp, PpSeverity.warning, "extra tokens at end of #{name} directive")
        skip_rest(pp)
    }
}

//! the current token kept in `held`, its spelling appended to `text`
def private hold(pp : Preprocessor; var held : array<PpHeld>; var text : array<uint8>) {
    let ft & = unsafe(pp.lx.flex.tok)
    let at = length(text)
    text |> resize(at + ft.len)
    for (i in range(ft.len)) {
        text[at + i] = pp.lx.flex.bytes[ft.start + i]
    }
    let t & = unsafe(pp.lx.tok)
    held |> push(PpHeld(kind = t.kind, sym = t.sym, file = t.file, offset = t.offset, line = t.line, col = t.col,
                        at = at, len = ft.len, has_space = t.has_space))
}

//! the rest of the directive's line into `pp.line`, from the current token when `from_current`
def private read_line(var pp : Preprocessor; from_current : bool) {
    pp.line |> clear()
    pp.line_text |> clear()
    if (from_current) {
        hold(pp, pp.line, pp.line_text)
    }
    while (next_on_line(pp)) {
        hold(pp, pp.line, pp.line_text)
    }
}

//! The spelling of a held token of `text`.
def held_spelling(h : PpHeld; text : array<uint8>) : string => slice(text, h.at, h.at + h.len)

//! Whether a held token of `text` is spelled `s`.
def held_is(h : PpHeld; text : array<uint8>; s : string) : bool {
    return false if (h.len != length(s))
    var same = true
    peek_data(s) $(chars) {
        for (i in range(h.len)) {
            same = same && text[h.at + i] == chars[i]
        }
    }
    return same
}

//! The tokens `held` of `text` spelled, a blank where the source had space.
def held_text(held : array<PpHeld>; text : array<uint8>) : string {
    return build_string() $(var out) {
        for (h, i in held, count()) {
            if (i > 0 && h.has_space) {
                out |> write(" ")
            }
            out |> write(held_spelling(h, text))
        }
    }
}

//! The first byte of working buffer `buffer`, a file's text past translation phase 2 (section 5).
def pp_buffer_data(pp : Preprocessor; buffer : int) : uint8 const? => pp.buffer_data[buffer]

//! The bytes of token `t`'s spelling: of a file, valid for the unit's life; of a macro body, until
//! the next `#define` grows the pool; of the expansion's pool, until the next `pp_next_token`; of a
//! symbol, for the interner's life.
[arch(at="ARCHITECTURE_PP.md#pp-directives")]
def pp_span_of(var pp : Preprocessor; t : PpOutToken) : tuple<data : uint8 const?; len : int> {
    if (t.spelled == PpSpelled.source) {
        return (data = unsafe(pp.buffer_data[t.buffer] + t.at), len = t.len)
    } elif (t.spelled == PpSpelled.body) {
        return (data = unsafe(addr(pp.macro_text[t.at])), len = t.len)
    } elif (t.spelled == PpSpelled.scratch) {
        return (data = unsafe(addr(pp.expansion.text[t.at])), len = t.len)
    }
    let name = pp_symbol_text(pp.lx, t.tok.sym)
    return (data = unsafe(reinterpret<uint8 const?>(name)), len = length(name))
}

//! The bytes of the token `pp_next_token` read, as `pp_span_of` gives them.
def pp_token_span(var pp : Preprocessor) : tuple<data : uint8 const?; len : int> => pp_span_of(pp, pp.tok)

//! The text of token `t`'s spelling, a new string.
def pp_spelling_of(var pp : Preprocessor; t : PpOutToken) : string {
    return pp_symbol_text(pp.lx, t.tok.sym) if (t.spelled == PpSpelled.symbol)
    let span = pp_span_of(pp, t)
    return build_string() $(var out) {
        for (i in range(span.len)) {
            out |> write_char(int(unsafe(span.data[i])))
        }
    }
}

//! The text of the token `pp_next_token` read.
def pp_token_spelling(var pp : Preprocessor) : string => pp_spelling_of(pp, pp.tok)

//! The name of symbol `sym`.
def pp_name(var pp : Preprocessor; sym : int) : string => pp_symbol_text(pp.lx, sym)

//! Whether the macro `sym` is defined now.
def pp_defined(pp : Preprocessor; sym : int) : bool => key_exists(pp.macro_of, sym)

//! The macro the name `name` defines now, by index in `pp.macros`; -1 when none.
def pp_macro_index(var pp : Preprocessor; name : string) : int => pp.macro_of?[intern_text(pp, name)] ?? -1

//! The body of macro `m`, spelled as `held_text` spells it.
def pp_macro_body_text(pp : Preprocessor; m : PpMacro) : string {
    let body <- [for (i in range(m.first, m.first + m.count)); pp.macro_body[i]]
    return held_text(body, pp.macro_text)
}

// Conditionals

def private push_cond(var pp : Preprocessor; value : int; at : PpToken) {
    let outer = !skipping(pp)
    pp.conds |> push(PpCond(active = outer && value == 1, taken = !outer || value == 1, file = at.file,
                            line = at.line, col = at.col))
}

//! the guard pattern of `#if`'s line: `!defined X` or `!defined(X)`; the macro, -1 when not
[arch(at="ARCHITECTURE_PP.md#pp-guards")]
def private if_guard_sym(pp : Preprocessor) : int {
    let n = length(pp.line)
    return -1 if (n < 3 || pp.line[0].kind != int(PpTok.EXCLAIM) || pp.line[1].sym != pp.sym_defined)
    if (n == 3 && pp.line[2].kind == int(PpTok.IDENTIFIER)) {
        return pp.line[2].sym
    }
    if (n == 5 && pp.line[2].kind == int(PpTok.LPAREN) && pp.line[3].kind == int(PpTok.IDENTIFIER) && pp.line[4].kind == int(PpTok.RPAREN)) {
        return pp.line[3].sym
    }
    return -1
}

//! Whether `sym` is defined: a macro, or a builtin name of the expansion (`__FILE__`, the `__has_*`
//! family) that no `#undef` removed, as `defined` and `#ifdef` answer in clang.
def pp_is_defined(var pp : Preprocessor; sym : int) : bool => pp_defined(pp, sym) || (pp.expansion != null && pp.expansion->is_builtin(pp, sym))

//! the header name the tokens `first` to `last` of `pp.line` spell: one `"..."` string literal, or
//! the spellings from `<` to `>` joined, a blank where a token has space, as clang builds the name
def private line_header_name(pp : Preprocessor; first, last : int) : string {
    return held_spelling(pp.line[first], pp.line_text) if (first == last)
    return build_string() $(var out) {
        out |> write("<")
        for (i in range(first + 1, last + 1)) {
            if (pp.line[i].has_space) {
                out |> write(" ")
            }
            out |> write(held_spelling(pp.line[i], pp.line_text))
        }
    }
}

//! where `#include_next` and `__has_include_next` search from: past the current inclusion's
//! include-path folder; 0 with the reason when there is none (the main file, or a file found by an
//! absolute path or by the main file's folder)
def private next_search_from(pp : Preprocessor) : tuple<from : int; why : string> {
    let found_at = pp.state.found_at
    return (from = 0, why = "in primary source file") if (empty(pp.frames))
    return (from = 0, why = "in file found relative to primary source file or found by absolute path; will search from start of include path") if (found_at < 0)
    return (from = found_at + 1, why = "")
}

//! the answer of `__has_include` (`next`: `__has_include_next`) for the header name of
//! `pp.line`'s tokens `first` to `last`: 1 when the search finds a file; `embed`: `__has_embed`'s,
//! 0 for none, 2 for an empty file, 1 for another
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-queries")]
def private include_answer(var pp : Preprocessor; first, last : int; next, embed : bool) : int {
    let spelled = line_header_name(pp, first, last)
    let name = slice(spelled, 1, length(spelled) - 1)
    return 0 if (empty(name))
    var tried : array<string>
    let found = search_file(pp, name, first_character(spelled) == '<', next ? next_search_from(pp).from : 0, tried)
    return 0 if (empty(found._0))
    return 1 if (!embed)
    var bytes : array<uint8>
    return 0 if (!pp.provider->read(found._0, bytes))
    return empty(bytes) ? 2 : 1
}

//! The `#if`/`#elif` condition of `pp.line` through the evaluator (`pp_eval.das`): 1 or 0, and -1
//! when an error fails it, so its group is skipped as clang skips it. Its diagnostics go to
//! `pp.diags` at their tokens.
[arch(at="ARCHITECTURE_PP.md#pp-if-hook")]
def private eval_condition(var pp : Preprocessor; at : PpToken) : int {
    pp.eval.toks |> clear()
    pp.eval.toks |> reserve(length(pp.line))
    for (h in pp.line) {
        pp.eval.toks |> push(PpEvalToken(kind = h.kind, sym = h.sym, at = h.at, len = h.len))
    }
    pp.eval.text |> clear()
    pp.eval.text |> reserve(length(pp.line_text))
    pp.eval.text |> push_from(pp.line_text)
    let result = pp_eval_condition(pp.eval) $(what, sym, first, last) {
        if (what == PpEvalAsk.defined) {
            return pp_is_defined(pp, sym) ? 1 : 0
        } elif (what == PpEvalAsk.builtin) {
            return pp.expansion == null || pp.expansion->is_builtin(pp, sym) ? 1 : 0
        }
        return include_answer(pp, first, last, what == PpEvalAsk.has_include_next, what == PpEvalAsk.has_embed)
    }
    for (d in pp.eval.diags) {
        let severity = d.error ? PpSeverity.error : PpSeverity.warning
        if (d.token >= 0) {
            diagnose_held(pp, severity, pp.line[d.token], d.what)
        } else {
            diagnose_at(pp, severity, !empty(pp.line) ? pp.last_tok : at, d.what)
        }
    }
    return -1 if (result.failed)
    return result.value ? 1 : 0
}

//! a directive outside the guard's group ends the file's chance of an include guard
def private guard_touched(var pp : Preprocessor) {
    if (pp.state.guard != GuardState.inside) {
        pp.state.guard = GuardState.none
    }
}

def private guard_opened(var pp : Preprocessor; sym : int) {
    if (pp.state.guard == GuardState.start && length(pp.conds) == pp.state.cond_base + 1 && sym >= 0) {
        pp.state.guard = GuardState.inside
        pp.state.guard_sym = sym
    } else {
        guard_touched(pp)
    }
}

//! `#ifdef`, `#ifndef` (`negate`), and `#elifdef`/`#elifndef` through `do_elif`: the macro named, or
//! -1 with a diagnostic
def private read_macro_name(var pp : Preprocessor; at : PpToken; name : string) : int {
    if (!next_on_line(pp)) {
        diagnose_at(pp, PpSeverity.error, at, "macro name missing in #{name}")
        return -1
    }
    if (pp.lx.tok.kind != int(PpTok.IDENTIFIER)) {
        diagnose(pp, PpSeverity.error, "macro names must be identifiers")
        skip_rest(pp)
        return -1
    }
    return pp.lx.tok.sym
}

def private do_ifdef(var pp : Preprocessor; at : PpToken; negate : bool) {
    let name = negate ? "ifndef" : "ifdef"
    let sym = read_macro_name(pp, at, name)
    if (sym >= 0) {
        extra_tokens(pp, name)
    }
    push_cond(pp, sym >= 0 && pp_is_defined(pp, sym) != negate ? 1 : 0, at)
    if (negate) {
        guard_opened(pp, sym)
    }
}

//! the macros of the `#if` expression in `pp.line` expanded, `defined`'s operands left alone
[arch(at="ARCHITECTURE_PP.md#pp-if-hook")]
def private expand_condition(var pp : Preprocessor) {
    if (pp.expansion != null) {
        pp.expansion->expand_line(pp, true)
    }
}

def private do_if(var pp : Preprocessor; at : PpToken) {
    read_line(pp, false)
    expand_condition(pp)
    let value = eval_condition(pp, at)
    push_cond(pp, value, at)
    guard_opened(pp, if_guard_sym(pp))
}

//! whether a `#elif`/`#else`/`#endif` has a conditional of this file to close
def private has_open_cond(var pp : Preprocessor; at : PpToken; name : string) : bool {
    if (length(pp.conds) > pp.state.cond_base) {
        return true
    }
    diagnose_at(pp, PpSeverity.error, at, "#{name} without #if")
    skip_rest(pp)
    return false
}

//! the guard's own conditional gets another group: no include guard
def private guard_branched(var pp : Preprocessor) {
    if (pp.state.guard == GuardState.inside && length(pp.conds) == pp.state.cond_base + 1) {
        pp.state.guard = GuardState.none
    }
}

def private do_elif(var pp : Preprocessor; at : PpToken; d : PpDirective) {
    let name = d == PpDirective.hash_elif ? "elif" : d == PpDirective.hash_elifdef ? "elifdef" : "elifndef"
    return if (!has_open_cond(pp, at, name))
    guard_branched(pp)
    let top = length(pp.conds) - 1
    if (pp.conds[top].seen_else) {
        diagnose_at(pp, PpSeverity.error, at, "#{name} after #else")
    }
    if (pp.conds[top].taken) {
        pp.conds[top].active = false
        skip_rest(pp)
        return
    }
    var value = false
    if (d == PpDirective.hash_elif) {
        read_line(pp, false)
        expand_condition(pp)
        let answer = eval_condition(pp, at)
        value = answer == 1
    } else {
        let sym = read_macro_name(pp, at, name)
        if (sym >= 0) {
            extra_tokens(pp, name)
        }
        value = sym >= 0 && pp_is_defined(pp, sym) == (d == PpDirective.hash_elifdef)
    }
    pp.conds[top].active = value
    pp.conds[top].taken = value
}

def private do_else(var pp : Preprocessor; at : PpToken) {
    return if (!has_open_cond(pp, at, "else"))
    guard_branched(pp)
    let top = length(pp.conds) - 1
    let was_skipped = pp.conds[top].taken && !pp.conds[top].active
    if (pp.conds[top].seen_else) {
        diagnose_at(pp, PpSeverity.error, at, "#else after #else")
    }
    pp.conds[top].active = !pp.conds[top].taken
    pp.conds[top].taken = true
    pp.conds[top].seen_else = true
    if (was_skipped) {
        skip_rest(pp)
    } else {
        extra_tokens(pp, "else")
    }
}

def private do_endif(var pp : Preprocessor; at : PpToken) {
    return if (!has_open_cond(pp, at, "endif"))
    pp.conds |> pop()
    let quiet = skipping(pp)
    if (pp.state.guard == GuardState.inside && length(pp.conds) == pp.state.cond_base) {
        pp.state.guard = GuardState.closed
    }
    if (quiet) {
        skip_rest(pp)
    } else {
        extra_tokens(pp, "endif")
    }
}

// Macro definitions

//! the parameter list after `(`, into `m`; false with a diagnostic when it is malformed
[arch(at="ARCHITECTURE_PP.md#pp-macros")]
def private read_params(var pp : Preprocessor; var m : PpMacro) : bool {
    let missing = "missing ')' in macro parameter list"
    if (!next_on_line(pp)) {
        diagnose_at(pp, PpSeverity.error, pp.last_tok, missing)
        return false
    }
    return true if (pp.lx.tok.kind == int(PpTok.RPAREN))
    while (true) {
        if (pp.lx.tok.kind == int(PpTok.ELLIPSIS)) {
            m.variadic = true
            m.params |> push(pp.sym_va_args)
        } elif (pp.lx.tok.kind != int(PpTok.IDENTIFIER)) {
            diagnose(pp, PpSeverity.error, "invalid token in macro parameter list")
            return false
        } elif (pp.lx.tok.sym == pp.sym_va_args) {
            diagnose(pp, PpSeverity.error, "__VA_ARGS__ can only appear in the expansion of a C99 variadic macro")
            return false
        } elif (find_index(m.params, pp.lx.tok.sym) >= 0) {
            diagnose(pp, PpSeverity.error, "duplicate macro parameter name")
            return false
        } else {
            m.params |> push(pp.lx.tok.sym)
        }
        if (!next_on_line(pp)) {
            diagnose_at(pp, PpSeverity.error, pp.last_tok, missing)
            return false
        }
        if (!m.variadic && pp.lx.tok.kind == int(PpTok.ELLIPSIS)) {
            m.variadic = true
            if (!next_on_line(pp)) {
                diagnose_at(pp, PpSeverity.error, pp.last_tok, missing)
                return false
            }
        }
        return true if (pp.lx.tok.kind == int(PpTok.RPAREN))
        if (m.variadic || pp.lx.tok.kind != int(PpTok.COMMA)) {
            diagnose(pp, PpSeverity.error, m.variadic ? missing : "expected comma in macro parameter list")
            return false
        }
        if (!next_on_line(pp)) {
            diagnose_at(pp, PpSeverity.error, pp.last_tok, missing)
            return false
        }
    }
    return false
}

//! the body's own errors: `##` at either end, and in a function-like macro a `#` before no parameter
//! (`__VA_OPT__` is one)
[arch(at="ARCHITECTURE_PP.md#pp-macros")]
def private body_error(pp : Preprocessor; m : PpMacro) : string {
    return "" if (m.count == 0)
    let last = m.first + m.count - 1
    if (pp.macro_body[m.first].kind == int(PpTok.HASHHASH) || pp.macro_body[last].kind == int(PpTok.HASHHASH)) {
        return "'##' cannot appear at either end of a macro expansion"
    }
    if (m.function_like) {
        for (i in range(m.first, last + 1)) {
            if (pp.macro_body[i].kind == int(PpTok.HASH) && (i == last || pp.macro_body[i + 1].kind != int(PpTok.IDENTIFIER)
                    || (find_index(m.params, pp.macro_body[i + 1].sym) < 0 && pp.macro_body[i + 1].sym != pp.sym_va_opt))) {
                return "'#' is not followed by a macro parameter"
            }
        }
    }
    return ""
}

//! whether two definitions of one name are the same (C11 6.10.3p2): parameters, spellings, and
//! whitespace between the body's tokens
def private same_definition(pp : Preprocessor; a, b : PpMacro) : bool {
    return false if (a.function_like != b.function_like || a.variadic != b.variadic || length(a.params) != length(b.params) || a.count != b.count)
    for (x, y in a.params, b.params) {
        return false if (x != y)
    }
    for (i in range(a.count)) {
        let x = pp.macro_body[a.first + i]
        let y = pp.macro_body[b.first + i]
        return false if (x.kind != y.kind || x.len != y.len || (i > 0 && x.has_space != y.has_space))
        for (k in range(x.len)) {
            return false if (pp.macro_text[x.at + k] != pp.macro_text[y.at + k])
        }
    }
    return true
}

def private do_define(var pp : Preprocessor; at : PpToken) {
    if (!next_on_line(pp)) {
        diagnose_at(pp, PpSeverity.error, at, "macro name missing")
        return
    }
    if (pp.lx.tok.kind != int(PpTok.IDENTIFIER) || pp.lx.tok.sym == pp.sym_defined) {
        diagnose(pp, PpSeverity.error, pp.lx.tok.kind != int(PpTok.IDENTIFIER) ? "macro name must be an identifier" : "'defined' cannot be used as a macro name")
        skip_rest(pp)
        return
    }
    let name_at = pp.lx.tok
    var m = PpMacro(name = pp.lx.tok.sym, file = pp.lx.tok.file, line = pp.lx.tok.line, col = pp.lx.tok.col,
                    first = length(pp.macro_body))
    var more = next_on_line(pp)
    if (more && pp.lx.tok.kind == int(PpTok.LPAREN) && !pp.lx.tok.has_space) {
        m.function_like = true
        if (!read_params(pp, m)) {
            skip_rest(pp)
            return
        }
        more = next_on_line(pp)
    } elif (more && !pp.lx.tok.has_space) {
        diagnose(pp, PpSeverity.warning, "ISO C99 requires whitespace after the macro name")
    }
    while (more) {
        hold(pp, pp.macro_body, pp.macro_text)
        more = next_on_line(pp)
    }
    m.count = length(pp.macro_body) - m.first
    let error = body_error(pp, m)
    if (!empty(error)) {
        diagnose_at(pp, PpSeverity.error, at, error)
        return
    }
    if (!m.variadic) {
        for (i in range(m.first, m.first + m.count)) {
            if (pp.macro_body[i].sym == pp.sym_va_opt) {
                diagnose_held(pp, PpSeverity.warning, pp.macro_body[i], "__VA_OPT__ can only appear in the expansion of a variadic macro")
                break
            }
        }
    }
    let old = pp.macro_of?[m.name] ?? -1
    if (old >= 0 && !same_definition(pp, pp.macros[old], m)) {
        diagnose_at(pp, PpSeverity.warning, at, "'{pp_name(pp, m.name)}' macro redefined")
    } elif (old < 0 && pp.expansion != null) {
        pp.expansion->macro_changed(pp, name_at, false)
    }
    pp.macro_of |> insert(m.name, length(pp.macros))
    pp.macros |> emplace(m)
}

def private do_undef(var pp : Preprocessor; at : PpToken) {
    if (!next_on_line(pp)) {
        diagnose_at(pp, PpSeverity.error, at, "macro name missing")
        return
    }
    if (pp.lx.tok.kind != int(PpTok.IDENTIFIER) || pp.lx.tok.sym == pp.sym_defined) {
        diagnose(pp, PpSeverity.error, pp.lx.tok.kind != int(PpTok.IDENTIFIER) ? "macro name must be an identifier" : "'defined' cannot be used as a macro name")
        skip_rest(pp)
        return
    }
    if (pp.expansion != null) {
        pp.expansion->macro_changed(pp, pp.lx.tok, true)
    }
    pp.macro_of |> erase(pp.lx.tok.sym)
    extra_tokens(pp, "undef")
}

// #include

//! the file `name` names, searched as clang does: a `"..."` name first in the includer's
//! directory, then the include path from `from` on; "" and the folders searched when none has it.
//! The second value is the include-path folder it was found in; a file found in the includer's
//! directory has the includer's.
[arch(at="ARCHITECTURE_PP.md#pp-search")]
def private search_file(var pp : Preprocessor; name : string; angled : bool; from : int; var tried : array<string>) : tuple<string; int> {
    if (starts_with(name, "/")) {
        let path = normalized_path(name)
        return (path, -1) if (pp.provider->exists(path))
        tried |> push(name)
        return ("", -1)
    }
    if (!angled && from == 0) {
        let dir = pp.state.dir
        let path = normalized_path(path_join(dir, name))
        return (path, pp.state.found_at) if (pp.provider->exists(path))
        tried |> push(dir)
    }
    tried |> reserve(length(tried) + length(pp.search))
    for (i in range(from, length(pp.search))) {
        let path = normalized_path(path_join(pp.search[i], name))
        return (path, i) if (pp.provider->exists(path))
        tried |> push(pp.search[i])
    }
    return ("", -1)
}

def private record_inclusion(var pp : Preprocessor; at : PpToken; spelled : string; file : int; skip : PpIncludeSkip) {
    pp.inclusions |> push(PpInclusion(file = file, spelled = spelled, from = pp.state.file, line = at.line, col = at.col, skip = skip))
}

//! the include that found no file, or no readable one: a fatal error, so the unit ends here
def private include_failed(var pp : Preprocessor; at : PpToken; spelled, what : string) {
    diagnose_at(pp, PpSeverity.fatal, at, what)
    record_inclusion(pp, at, spelled, -1, PpIncludeSkip.not_found)
    pp.fatal = true
}

//! read the file `spelled` names, unless its `#pragma once` or include guard says it adds
//! nothing; `#import` (`import`) marks it once first
[arch(at="ARCHITECTURE_PP.md#pp-search")]
def private enter_file(var pp : Preprocessor; at : PpToken; spelled : string; next, import : bool) {
    let angled = first_character(spelled) == '<'
    let name = slice(spelled, 1, length(spelled) - 1)
    if (empty(name)) {
        diagnose_at(pp, PpSeverity.error, at, "empty filename")
        return
    }
    if (length(pp.frames) >= PP_MAX_INCLUDE_DEPTH - 1) {
        diagnose_at(pp, PpSeverity.error, at, "#include nested depth {PP_MAX_INCLUDE_DEPTH} exceeds maximum of {PP_MAX_INCLUDE_DEPTH}")
        record_inclusion(pp, at, spelled, -1, PpIncludeSkip.too_deep)
        return
    }
    var from = 0
    if (next) {
        let start = next_search_from(pp)
        if (!empty(start.why)) {
            diagnose_at(pp, PpSeverity.warning, at, "#include_next {start.why}")
        }
        from = start.from
    }
    var tried : array<string>
    let found = search_file(pp, name, angled, from, tried)
    if (empty(found._0)) {
        include_failed(pp, at, spelled, "'{name}' file not found; searched: {join(tried, ", ")}")
        return
    }
    let identity = pp.provider->identity(found._0)
    var id = pp.file_of?[identity] ?? -1
    if (id >= 0 && import) {
        pp.files[id].once = true
    }
    if (id >= 0 && pp.files[id].once && pp.files[id].entered > 0) {
        record_inclusion(pp, at, spelled, id, PpIncludeSkip.pragma_once)
        return
    }
    if (id >= 0 && pp.files[id].guard >= 0 && pp_defined(pp, pp.files[id].guard)) {
        record_inclusion(pp, at, spelled, id, PpIncludeSkip.guard)
        return
    }
    var bytes : array<uint8>
    if (!pp.provider->read(found._0, bytes)) {
        include_failed(pp, at, spelled, "cannot read '{found._0}'")
        return
    }
    if (id < 0) {
        id = register_file(pp, found._0, identity)
        pp.files[id].once = import
    }
    record_inclusion(pp, at, spelled, id, PpIncludeSkip.none)
    push_file(pp, id, found._0, found._1, bytes)
}

//! the name of an inclusion directive `d`, as its diagnostics spell it
def private include_name(d : PpDirective) : string =>
    d == PpDirective.hash_include_next ? "include_next" : d == PpDirective.hash_import ? "import" : "include"

//! `#include`, `#include_next` and `#import`: a header name, or the tokens PP.3 expands into one
[arch(at="ARCHITECTURE_PP.md#pp-search")]
def private do_include(var pp : Preprocessor; at : PpToken; d : PpDirective) {
    let next = d == PpDirective.hash_include_next
    let name = include_name(d)
    if (!pp_next_header_name(pp.lx) || pp.lx.tok.at_bol) {
        pp.pending = true
        diagnose_at(pp, PpSeverity.error, at, "expected \"FILENAME\" or <FILENAME>")
        return
    }
    pp.last_tok = pp.lx.tok
    if (pp.lx.tok.kind != int(PpTok.HEADER_NAME)) {
        read_line(pp, true)
        if (pp.expansion != null) {
            pp.expansion->expand_line(pp, false)
            include_expanded(pp, at, d)
            return
        }
        let text = held_text(pp.line, pp.line_text)
        diagnose_at(pp, PpSeverity.error, at, "#{name} of macro-expanded tokens needs PP.3: {text}")
        record_inclusion(pp, at, text, -1, PpIncludeSkip.needs_expansion)
        return
    }
    let spelled = pp_spelling(pp.lx)
    let name_at = pp.lx.tok
    extra_tokens(pp, name)
    enter_file(pp, name_at, spelled, next, d == PpDirective.hash_import)
}

//! `#include` of the macro-expanded tokens in `pp.line`: one `"..."` string literal, or the
//! spellings from `<` to `>` joined, a blank where a token has space, as clang builds the name
[arch(at="ARCHITECTURE_PP.md#pp-search")]
def private include_expanded(var pp : Preprocessor; at : PpToken; d : PpDirective) {
    let n = length(pp.line)
    var spelled = ""
    var used = 0
    if (n >= 1 && pp.line[0].kind == int(PpTok.STRING_LITERAL) && pp.line_text[pp.line[0].at] == '"'u8) {
        spelled = line_header_name(pp, 0, 0)
        used = 1
    } elif (n >= 1 && pp.line[0].kind == int(PpTok.LESS)) {
        var close = 1
        while (close < n && pp.line[close].kind != int(PpTok.GREATER)) {
            close++
        }
        if (close == n) {
            diagnose_at(pp, PpSeverity.error, at, "expected '>'")
            return
        }
        spelled = line_header_name(pp, 0, close)
        used = close + 1
    }
    if (empty(spelled)) {
        diagnose_at(pp, PpSeverity.error, at, "expected \"FILENAME\" or <FILENAME>")
        return
    }
    if (used < n) {
        diagnose_at(pp, PpSeverity.warning, at, "extra tokens at end of #{include_name(d)} directive")
    }
    enter_file(pp, at, spelled, d == PpDirective.hash_include_next, d == PpDirective.hash_import)
}

// #line

//! the digits of a `#line` number as a value, -1 when it is no simple digit sequence, -2 when
//! it is past 4294967295, clang's unsigned line
def private line_number(text : string) : int64 {
    var value = 0l
    for (c in text) {
        return -1l if (!is_number(c))
        value = value * 10l + int64(c - '0')
        return -2l if (value > 4294967295l)
    }
    return empty(text) ? -1l : value
}

//! clang's error for a `#line` number of token kind `kind` that `line_number` read as `number`: no
//! number at all or one past 4294967295 asks for a positive integer, any other a simple digit sequence
def private line_number_error(what : string; kind : int; number : int64) : string {
    return (kind != int(PpTok.PP_NUMBER) || number == -2l ? "{what} directive requires a positive integer argument"
                                                         : "{what} directive requires a simple digit sequence")
}

//! the file name of a `#line` string literal: its quotes off, `\\` and `\"` read as one character
def private line_file_name(spelled : string) : string {
    return build_string() $(var out) {
        var escaped = false
        for (c in slice(spelled, 1, length(spelled) - 1)) {
            if (c == '\\' && !escaped) {
                escaped = true
                continue
            }
            escaped = false
            out |> write_char(c)
        }
    }
}

//! `#line N "name"`, and the line marker `# N "name" flags...` (`marker`, the number already read):
//! the next line reports line N, and of file `name` when one is given
[arch(at="ARCHITECTURE_PP.md#pp-line")]
def private do_line(var pp : Preprocessor; at : PpToken; marker : bool) {
    let what = marker ? "line marker" : "#line"
    if (!marker && !next_on_line(pp)) {
        diagnose_at(pp, PpSeverity.error, at, "#line directive requires a positive integer argument")
        return
    }
    if (pp.lx.tok.kind == int(PpTok.IDENTIFIER)) {
        read_line(pp, true)
        if (pp.expansion != null) {
            pp.expansion->expand_line(pp, false)
            line_expanded(pp, at)
            return
        }
        diagnose_at(pp, PpSeverity.error, at, "#line of macro-expanded tokens needs PP.3: {held_text(pp.line, pp.line_text)}")
        return
    }
    let number = line_number(pp_spelling(pp.lx))
    if (pp.lx.tok.kind != int(PpTok.PP_NUMBER) || number < 0l) {
        diagnose(pp, PpSeverity.error, line_number_error(what, pp.lx.tok.kind, number))
        skip_rest(pp)
        return
    }
    var name = -1
    if (next_on_line(pp)) {
        let spelled = pp_spelling(pp.lx)
        if (pp.lx.tok.kind != int(PpTok.STRING_LITERAL) || first_character(spelled) != '"') {
            diagnose(pp, PpSeverity.error, "invalid filename for {what} directive")
            skip_rest(pp)
            return
        }
        name = name_id(pp, line_file_name(spelled))
        if (marker) {
            return if (!marker_flags(pp))
        } else {
            extra_tokens(pp, "line")
        }
    }
    pp.state.line_delta = uint(number) - uint(pp.last_tok.line + 1)
    if (name >= 0) {
        pp.state.pname = name
    }
}

//! a line marker's flags: 1 enters a presumed file, 2 leaves one this file entered; false, the
//! marker ignored, when a 2 has none to leave
[arch(at="ARCHITECTURE_PP.md#pp-line")]
def private marker_flags(var pp : Preprocessor) : bool {
    while (next_on_line(pp)) {
        if (current_is_number(pp, "1")) {
            pp.state.markers++
        } elif (current_is_number(pp, "2") && pp.state.markers == 0) {
            diagnose(pp, PpSeverity.error, "invalid line marker flag '2': cannot pop empty include stack")
            skip_rest(pp)
            return false
        } elif (current_is_number(pp, "2")) {
            pp.state.markers--
        }
    }
    return true
}

def private current_is_number(pp : Preprocessor; digits : string) : bool => pp.lx.tok.kind == int(PpTok.PP_NUMBER) && pp_spelling(pp.lx) == digits

//! `#line` of the macro-expanded tokens in `pp.line`: a number, then a file name or nothing
[arch(at="ARCHITECTURE_PP.md#pp-line")]
def private line_expanded(var pp : Preprocessor; at : PpToken) {
    let n = length(pp.line)
    let number = n >= 1 ? line_number(held_spelling(pp.line[0], pp.line_text)) : -1l
    if (n == 0 || pp.line[0].kind != int(PpTok.PP_NUMBER) || number < 0l) {
        diagnose_at(pp, PpSeverity.error, at, line_number_error("#line", n == 0 ? int(PpTok.EOF) : pp.line[0].kind, number))
        return
    }
    var name = -1
    if (n >= 2) {
        let spelled = held_spelling(pp.line[1], pp.line_text)
        if (pp.line[1].kind != int(PpTok.STRING_LITERAL) || first_character(spelled) != '"') {
            diagnose_at(pp, PpSeverity.error, at, "invalid filename for #line directive")
            return
        }
        name = name_id(pp, line_file_name(spelled))
        if (n > 2) {
            diagnose_at(pp, PpSeverity.warning, at, "extra tokens at end of #line directive")
        }
    }
    pp.state.line_delta = uint(number) - uint(pp.last_tok.line + 1)
    if (name >= 0) {
        pp.state.pname = name
    }
}

// #pragma

//! the warning a malformed `#pragma pack` gets at token `i` of `pp.line`, the line's end past its
//! last token; false, the pragma ignored
def private pack_ignored(var pp : Preprocessor; i : int; what : string) : bool {
    let n = length(pp.line)
    var place = pp.line[i < n ? i : n - 1]
    if (i >= n) {
        place.col += place.len
    }
    diagnose_held(pp, PpSeverity.warning, place, what)
    return false
}

//! whether token `i` of `pp.line` is of `kind`
def private line_is(pp : Preprocessor; i : int; kind : PpTok) : bool => i < length(pp.line) && pp.line[i].kind == int(kind)

//! `pack(...)` of `pp.line` from token 1 into the pack ledger, read by clang's grammar: `(` then
//! `N`, `show`, or `push` or `pop` with `, N`, `, tag` or `, tag, N`, then `)`; false with clang's
//! warning when it is malformed
[arch(at="ARCHITECTURE_PP.md#pp-pragmas")]
def private read_pack(var pp : Preprocessor; at : PpToken) : bool {
    let missing_paren = "missing ')' after '#pragma pack' - ignoring"
    let malformed = "expected integer or identifier in '#pragma pack' - ignored"
    return pack_ignored(pp, 1, "missing '(' after '#pragma pack' - ignoring") if (!line_is(pp, 1, PpTok.LPAREN))
    var entry = PpPack(file = at.file, line = at.line, col = at.col, emitted = pp.emitted, action = PpPackAction.reset)
    var i = 2
    if (line_is(pp, i, PpTok.PP_NUMBER)) {
        entry.action = PpPackAction.set
        entry.value = int(line_number(held_spelling(pp.line[i], pp.line_text)))
        i++
    } elif (line_is(pp, i, PpTok.IDENTIFIER)) {
        let sym = pp.line[i].sym
        return pack_ignored(pp, i, "unknown action for '#pragma pack' - ignored") if (sym != pp.sym_push && sym != pp.sym_pop && sym != pp.sym_show)
        entry.action = sym == pp.sym_push ? PpPackAction.push : sym == pp.sym_pop ? PpPackAction.pop : PpPackAction.show
        i++
        if (sym != pp.sym_show && line_is(pp, i, PpTok.COMMA)) {
            i++
            if (line_is(pp, i, PpTok.IDENTIFIER)) {
                entry.tag = held_spelling(pp.line[i], pp.line_text)
                i++
                if (line_is(pp, i, PpTok.COMMA)) {
                    i++
                    return pack_ignored(pp, i, malformed) if (!line_is(pp, i, PpTok.PP_NUMBER))
                    entry.value = int(line_number(held_spelling(pp.line[i], pp.line_text)))
                    i++
                }
            } elif (line_is(pp, i, PpTok.PP_NUMBER)) {
                entry.value = int(line_number(held_spelling(pp.line[i], pp.line_text)))
                i++
            } else {
                return pack_ignored(pp, i, malformed)
            }
        }
    }
    return pack_ignored(pp, i, missing_paren) if (!line_is(pp, i, PpTok.RPAREN))
    return pack_ignored(pp, i + 1, "extra tokens at end of '#pragma pack' - ignored") if (i + 1 < length(pp.line))
    if (entry.value != 0 && entry.value != 1 && entry.value != 2 && entry.value != 4 && entry.value != 8 && entry.value != 16) {
        return pack_ignored(pp, 0, "expected #pragma pack parameter to be '1', '2', '4', '8', or '16'")
    }
    if (entry.action == PpPackAction.pop && empty(pp.pack_stack)) {
        diagnose_held(pp, PpSeverity.warning, pp.line[0], "#pragma pack(pop, ...) failed: stack empty")
    }
    apply_pack(pp, entry)
    pp.packs |> push(entry)
    return true
}

//! the alignment `entry` leaves in force, as clang keeps its pack stack
def private apply_pack(var pp : Preprocessor; var entry : PpPack) {
    if (entry.action == PpPackAction.set) {
        pp.pack_now = entry.value
    } elif (entry.action == PpPackAction.reset) {
        pp.pack_now = 0
    } elif (entry.action == PpPackAction.push) {
        pp.pack_stack |> push(PpPack(tag = entry.tag, current = pp.pack_now))
        if (entry.value != 0) {
            pp.pack_now = entry.value
        }
    } elif (entry.action == PpPackAction.pop) {
        var k = length(pp.pack_stack) - 1
        while (k >= 0 && !empty(entry.tag) && pp.pack_stack[k].tag != entry.tag) {
            k--
        }
        if (k >= 0) {
            pp.pack_now = pp.pack_stack[k].current
            pp.pack_stack |> resize(k)
        }
        if (entry.value != 0) {
            pp.pack_now = entry.value
        }
    }
    entry.current = pp.pack_now
}

//! `push_macro("NAME")` or `pop_macro("NAME")` of `pp.line`: the definition of `NAME` saved, or
//! the last one saved made current again (none: undefined); false when malformed
[arch(at="ARCHITECTURE_PP.md#pp-pragmas")]
def private push_pop_macro(var pp : Preprocessor) : bool {
    let n = length(pp.line)
    return false if (n != 4 || pp.line[1].kind != int(PpTok.LPAREN) || pp.line[2].kind != int(PpTok.STRING_LITERAL) || pp.line[3].kind != int(PpTok.RPAREN))
    let spelled = held_spelling(pp.line[2], pp.line_text)
    return false if (first_character(spelled) != '"')
    let sym = intern_text(pp, slice(spelled, 1, length(spelled) - 1))
    if (pp.line[0].sym == pp.sym_push_macro) {
        let current = pp.macro_of?[sym] ?? -1
        pp.pushed_macros[sym] |> push(current)
        return true
    }
    var saved = -2
    get(pp.pushed_macros, sym) $(var stack) {
        if (!empty(stack)) {
            saved = stack[length(stack) - 1]
            stack |> pop()
        }
    }
    if (saved == -2) {
        let name = pp_name(pp, sym)
        diagnose_held(pp, PpSeverity.warning, pp.line[0], "pragma pop_macro could not pop '{name}', no matching push_macro")
        return true
    }
    if (saved < 0) {
        pp.macro_of |> erase(sym)
    } else {
        pp.macro_of[sym] = saved
    }
    return true
}

def private do_pragma(var pp : Preprocessor; at : PpToken) {
    read_line(pp, false)
    pp_pragma_line(pp, at)
}

//! The pragma whose tokens after `pragma` are `pp.line`, at `at`: `#pragma`'s, or `_Pragma`'s
//! destringized operand (C11 6.10.9).
[arch(at="ARCHITECTURE_PP.md#pp-pragmas")]
def pp_pragma_line(var pp : Preprocessor; at : PpToken) {
    let n = length(pp.line)
    if (n >= 1 && pp.line[0].sym == pp.sym_once) {
        if (n > 1) {
            diagnose_at(pp, PpSeverity.warning, at, "extra tokens at end of #pragma once directive")
        }
        if (empty(pp.frames)) {
            diagnose_at(pp, PpSeverity.warning, at, "#pragma once in main file")
        }
        pp.files[pp.state.file].once = true
        return
    }
    if (n >= 1 && (pp.line[0].sym == pp.sym_push_macro || pp.line[0].sym == pp.sym_pop_macro)) {
        if (!push_pop_macro(pp)) {
            diagnose_at(pp, PpSeverity.warning, at, "malformed #pragma {pp_name(pp, pp.line[0].sym)}, ignored")
        }
        return
    }
    if (n >= 1 && pp.line[0].sym == pp.sym_pack) {
        read_pack(pp, at)
        return
    }
    pp.pragmas |> push(PpPragma(file = at.file, line = at.line, col = at.col, pname = pp.state.pname, pline = presumed_line(pp, at.line),
                                emitted = pp.emitted, text = held_text(pp.line, pp.line_text)))
}

//! `#ident "text"` and its `#sccs` spelling: a pragma ledger entry, which clang's `-E` prints as an
//! `#ident` line; anything but a plain or wide string literal is an error
[arch(at="ARCHITECTURE_PP.md#pp-pragmas")]
def private do_ident(var pp : Preprocessor; at : PpToken) {
    let has = next_on_line(pp)
    let spelled = has ? pp_spelling(pp.lx) : ""
    if (!has || pp.lx.tok.kind != int(PpTok.STRING_LITERAL) || (!starts_with(spelled, "\"") && !starts_with(spelled, "L\""))) {
        diagnose_at(pp, PpSeverity.error, has ? pp.lx.tok : at, "invalid #ident directive")
        skip_rest(pp)
        return
    }
    extra_tokens(pp, "ident")
    pp.pragmas |> push(PpPragma(file = at.file, line = at.line, col = at.col, pname = pp.state.pname, pline = presumed_line(pp, at.line),
                                emitted = pp.emitted, ident = true, text = spelled))
}

// Directives

//! the directive whose `#` is the current token; in a skipped group only the conditionals count
[arch(at="ARCHITECTURE_PP.md#pp-directives")]
def private directive(var pp : Preprocessor) {
    pp.directives_read++
    let skipped = skipping(pp)
    pp.last_tok = pp.lx.tok
    return if (!next_on_line(pp))
    let at = pp.lx.tok
    let d = pp.lx.tok.kind == int(PpTok.IDENTIFIER) ? pp.directive_of?[pp.lx.tok.sym] ?? PpDirective.unknown : PpDirective.unknown
    if (skipped) {
        if (d == PpDirective.hash_if || d == PpDirective.ifdef || d == PpDirective.ifndef) {
            push_cond(pp, 0, at)
            skip_rest(pp)
        } elif (d == PpDirective.hash_elif || d == PpDirective.hash_elifdef || d == PpDirective.hash_elifndef) {
            do_elif(pp, at, d)
        } elif (d == PpDirective.hash_else) {
            do_else(pp, at)
        } elif (d == PpDirective.endif) {
            do_endif(pp, at)
        } else {
            skip_rest(pp)
        }
        return
    }
    if (d != PpDirective.hash_if && d != PpDirective.ifndef && d != PpDirective.endif && d != PpDirective.hash_elif
            && d != PpDirective.hash_elifdef && d != PpDirective.hash_elifndef && d != PpDirective.hash_else) {
        guard_touched(pp)
    }
    active_directive(pp, at, d)
}

def private active_directive(var pp : Preprocessor; at : PpToken; d : PpDirective) {
    if (d == PpDirective.define) {
        do_define(pp, at)
    } elif (d == PpDirective.undef) {
        do_undef(pp, at)
    } elif (d == PpDirective.hash_include || d == PpDirective.hash_include_next || d == PpDirective.hash_import) {
        do_include(pp, at, d)
    } elif (d == PpDirective.hash_if) {
        do_if(pp, at)
    } elif (d == PpDirective.ifdef || d == PpDirective.ifndef) {
        do_ifdef(pp, at, d == PpDirective.ifndef)
    } elif (d == PpDirective.hash_elif || d == PpDirective.hash_elifdef || d == PpDirective.hash_elifndef) {
        do_elif(pp, at, d)
    } elif (d == PpDirective.hash_else) {
        do_else(pp, at)
    } elif (d == PpDirective.endif) {
        do_endif(pp, at)
    } elif (d == PpDirective.line) {
        do_line(pp, at, false)
    } elif (d == PpDirective.error || d == PpDirective.warning) {
        read_line(pp, false)
        let what = "#{d == PpDirective.error ? "error" : "warning"} {held_text(pp.line, pp.line_text)}"
        diagnose_at(pp, d == PpDirective.error ? PpSeverity.error : PpSeverity.warning, at, what)
    } elif (d == PpDirective.pragma) {
        do_pragma(pp, at)
    } elif (d == PpDirective.ident) {
        do_ident(pp, at)
    } elif (pp.lx.tok.kind == int(PpTok.PP_NUMBER)) {
        do_line(pp, at, true)
    } else {
        diagnose_at(pp, PpSeverity.error, at, "invalid preprocessing directive")
        skip_rest(pp)
    }
}

//! the end of the file being read: its open conditionals reported, its include guard recorded, the
//! file that included it resumed; false at the end of the translation unit
def private end_file(var pp : Preprocessor) : bool {
    while (length(pp.conds) > pp.state.cond_base) {
        let c = pp.conds[length(pp.conds) - 1]
        pp.diags |> push(PpDiagnostic(severity = PpSeverity.error, file = c.file, line = c.line, col = c.col, pname = pp.state.pname,
                                      pline = presumed_line(pp, c.line), what = "unterminated conditional directive"))
        pp.conds |> pop()
    }
    if (pp.state.guard == GuardState.closed) {
        pp.files[pp.state.file].guard = pp.state.guard_sym
    }
    return false if (empty(pp.frames))
    pop_file(pp)
    return true
}

//! Read the next token of the translation unit into `pp.tok`: the expansion's next token when one
//! is set (`pp.expansion`), else the directive layer's; false at its end.
def pp_next_token(var pp : Preprocessor) : bool {
    let got = pp.expansion != null ? pp.expansion->next_token(pp) : pp_next_directive_token(pp)
    if (got) {
        pp.emitted++
    }
    return got
}

//! Read the next token of the directive layer into `pp.tok`, every directive done and every
//! skipped group left out, no macro expanded; false at its end.
[arch(at="ARCHITECTURE_PP.md#pp-directives")]
def pp_next_directive_token(var pp : Preprocessor) : bool {
    while (!pp.fatal) {
        if (!fetch(pp)) {
            return false if (!end_file(pp))
            continue
        }
        if (pp.lx.tok.kind == int(PpTok.HASH) && pp.lx.tok.at_bol) {
            directive(pp)
            continue
        }
        continue if (skipping(pp))
        if (pp.state.guard != GuardState.inside) {
            pp.state.guard = GuardState.none
        }
        pp.tok.tok = pp.lx.tok
        pp.tok.pline = presumed_line(pp, pp.lx.tok.line)
        pp.tok.pname = pp.state.pname
        pp.tok.call = -1
        pp.tok.spelled = PpSpelled.source
        pp.tok.buffer = pp.state.buffer
        pp.tok.at = pp.lx.flex.tok.start
        pp.tok.len = pp.lx.flex.tok.len
        pp.tok.painted = false
        return true
    }
    return false
}
