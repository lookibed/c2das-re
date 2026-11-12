options gen2

module emit public

require daslib/cmp
require strings
require daslib/strings_boost
require daslib/strings_convert
require daslib/fio
require math
require crt
require cir
require sidecar
require bit_units
require layout
require line_wrap
require summaries
require macro_fold
require daslib/rtti
require daslib/ast

//! The das emitter: C-IR in, gen2 source text out, one pass that spells nodes and lowers the
//! shapes `docs/lowering-examples.md` names as it meets them (statement-ification, the loop
//! flags, the `if` chains). Fails closed on any node outside the lowered subset; `error`
//! carries the first such node.

struct Em {
    text : string
    prec : int
    is_bool : bool
    // the C source wrote the expression in parentheses: an operand keeps them (`wrap`)
    paren : bool
    // a zero test's exact negation (`x == 0` for `x != 0`), "" for any other expression
    inverse : string
}

struct Emitter {
    out : array<string>
    text : string
    depth : int
    error : string
    has_c_main : bool
    // C `main` takes `argc` and `argv`, which the wrapper passes
    main_args : bool
    pre : array<string>
    temp_counter : int
    // the names the function being emitted spells, which a temporary never takes
    spelled : table<string>
    first_counter : int
    for_counter : int
    requires : table<string>
    global_stores : array<string>
    in_global_init : bool
    c_functions : int
    function_count : int
    // the names the body assigns, steps or takes the address of
    written : table<string>
    // the declarations of a block that nothing after them in the block assigns, steps or takes
    // the address of (`plan_let_locals`)
    unwritten_decls : table<uint64>
    renames : table<string; string>
    unsafe_used : bool
    empty_literal : bool
    global_order : table<string; int>
    global_initialized : table<string>
    // das's initialization-loop graph over the part: its globals with an initializer and its
    // functions, each by C name to its index in the unit's declarations, and the names each
    // function's body references, filled on first use (`init_reaches_itself`)
    init_globals : table<string; int>
    body_functions : table<string; int>
    body_refs : table<string; array<string>>
    // values already evaluated into temporaries, by node: `hoist_items` and `pin_value` write it,
    // `unpin` erases
    hoisted : table<uint64; Em>
    globals_seen : int
    switch_counter : int
    // the case values the switch being emitted labels with a character literal
    char_cases : table<int64>
    // the C sources' comments by file (`c_comments`), read on first use
    c_comments : table<string; CComments>
    // per C file, the line (from 1) up to which the output carries its comments
    comments_done : table<string; int>
    // the C file of the function being emitted: a statement carries only that file's comments
    comment_file : string
    // the `#define` constants the module spells by name, each its das value, in first-use order;
    // a function body names them, a global's initializer does not
    constants : table<string; string>
    constant_order : array<string>
    in_body : bool
    // whether a builtin module (`$`, `math`) holds a global of the name, by name
    builtin_globals : table<string; bool>
    setjmp_counter : int
    // the names the function being emitted takes the address of, and the variables whose storage
    // it points at: those an `&` or an array's decay roots (`storage_root`), `&s.n` and `a` included
    addressed : table<string>
    pointed : table<string>
    // of those, the variables a pointer may reach once the statement forming it ends: an address
    // kept in an object or passed to a parameter that may keep it (`address_escapes`)
    escaped : table<string>
    // the function being emitted: its body, whether it holds a `goto`, the type of each parameter
    // and of each local it declares once, by name, the counters whose every reference sits in a
    // counted loop that assigns them, whose declaration the range loops replace, and the free
    // name of every other counter a range loop counts in (`plan_counted_loops`)
    @do_not_delete fn_body : CirStmt const?
    has_goto : bool
    local_types : table<string; int>
    range_counters : table<string>
    range_fresh : table<string; string>
    // the function's C labels by das number, and the blocks emitted without braces so a goto
    // into them finds its label in an enclosing scope
    labels : table<string; int>
    flatten : table<uint64>
    // the `if`, loop and switch statements a goto enters from outside, or whose case labels sit
    // below their switch's level (Duff's device), spelled open with das labels and gotos at their
    // parent's level; the `if` arms spelled flat among them; the das label of each case label of an
    // open switch; and the highest das label number taken
    opened : table<uint64>
    entered : table<uint64>
    case_labels : table<uint64; int>
    label_count : int
    // a label a goto from another case group of its switch reaches (`goto dflt` in lstrlib.c's
    // `match`), by the switch body it splits; the switch bodies that hold one, which take the
    // matched-flag loop, each with the das label that restarts it; and, once the switch is
    // spelled, each such label's number among its switch's, the switch's flag and the variable
    // a goto stores that number into before it restarts the switch
    group_labels : table<string; uint64>
    flag_switches : table<uint64; int>
    label_index : table<string; int>
    label_flags : table<string; string>
    label_gotos : table<string; string>
    // the assignment a goto to such a label makes before the restart so no case value matches,
    // "" when the switch's case tests keep the pending goto's test (`restart_sentinel`)
    label_conds : table<string; string>
    // each switch body that takes the jump table (`dispatch_plan`), and the das label a goto to a
    // label of such a switch's case group jumps to, in place of the re-dispatch
    goto_switches : table<uint64; GotoDispatch>
    label_jumps : table<string; int>
    // an open switch's jump table under `switch_dispatch` `goto` (`open_table`): the labels of the
    // values no case holds, by the `default` they stand before, else by the switch body
    case_holes : table<uint64; array<string>>
    // what a C `continue` spells at the current nesting: "" inside a loop body, the `_cont`
    // flag inside a matched-flag switch loop whose `continue` reaches the loop around it, the
    // `goto` to the test or increment of an open loop
    cont_flags : array<string>
    // what a C `break` spells at the current nesting: "" for das's, the `goto` to the end of an
    // open loop or switch
    break_gotos : array<string>
    // the name the `[variadic]` prologue binds the trailing arguments to in the function being
    // emitted, "" in a function that is not variadic
    va_name : string
    // the das result type of the function being emitted, "void" for none
    fn_ret : string
    // a `return` in a setjmp site's `try` or `recover` arm, which das refuses: such an arm is a
    // block invoked for whether it returned, the value left in `sj_ret` ("" in a void function)
    // and the answer in `sj_returned`, both declared by the outermost site ("" outside one);
    // `sj_arms` counts the arm blocks open around the statement being spelled
    sj_ret : string
    sj_returned : string
    sj_arms : int
    sj_result_counter : int
    // the compound literal objects: the next number a function's `_cl<N>` tries, the module
    // globals a file-scope literal declares (their names and the lines that go before the global
    // that reads them), the declarations of the objects a conditional arm initializes, which go
    // before the statement, and how many conditional arms enclose the expression being spelled
    literal_counter : int
    literal_globals : table<string>
    global_literals : array<string>
    literal_decls : array<string>
    narrow : int
    // how many statements enclose the one being spelled, itself included; the count a matched-flag
    // switch's group-level statements have (0 outside one), and the declarations of the compound
    // literal objects those statements make, which go before the switch's loop
    stmt_depth : int
    case_depth : int
    case_literal_decls : array<string>
    // the facts of the whole program, which every module of it reads
    prog : EmitProgram
    // the part of the program being emitted, unless `whole`: the indices of its globals and
    // functions in the unit's declarations and the records and enums it defines
    whole : bool
    // a module of a source layout: the file its layout check moves to, included where the check
    // stood (`<module>.layout.das.inc`), and that file's text once emitted
    layout_file : string
    layout_text : string
    part_decls : table<int>
    part_types : table<int>
    // the cycle cut: each late-bound function the module calls that it also sees itself, with the
    // `<module>::` its calls take, and the late-bound functions the module defines, which its
    // `[init]` binds to their slots, each with its slot
    late_quals : table<string; string>
    late_defs : table<string; string>
    // the function-like macros the module prints as `[c_macro] def`s (`fold_macro`): what a
    // verdict reads of the function being spelled, the chain level each expansion node is spelled
    // at while a def body spells it, the defs by das name in first-use order and each macro's das
    // name, how deep in def bodies the spelling is, and per reason how many expansion sites of the
    // functions folded or stayed expanded, each counted once
    fold_scope : FoldScope
    fold_levels : table<uint64; int>
    macro_defs : table<string; MacroDef>
    macro_def_order : array<string>
    macro_names : table<int; string>
    // per macro index, which parameters its def takes `var` (`var_parameters`), for the macros
    // folded around it
    macro_var : table<int; array<bool>>
    def_depth : int
    fold_counts : table<string; int>
    fold_counted : table<int>
    // the expressions a def body spells as its parameters or as nothing, in `hoisted`
    fold_seeds : table<uint64>
    // the arms of a pointer `?:` with a `null` arm, which stay expanded (`emit_cond`)
    fold_blocked : table<uint64>
    // the function being spelled folds no expansion: its first spelling declared a folded call in
    // a block with a label (`labeled_fold`)
    fold_function_off : bool
}

//! The facts of a whole program the emitter reads in each of its modules: the functions it
//! defines, the wrapper's renames, its defined and declared global names, the sidecar's records and
//! options, the layout memo, and the scoping facts `unshadow_locals` finds.
struct EmitProgram {
    functions : table<string>
    // a function of the unit named like a mapped libc one or one the `main` wrapper calls, to the
    // free name it takes
    function_renames : table<string; string>
    // the globals the program defines (no `extern` declaration), and every global name it declares
    defined_globals : table<string>
    global_names : table<string>
    marshal : table<int>
    layout : LayoutMemo
    // the alloca arena's bytes per function (the sidecar's `alloca_limit`) and the module's
    // `options stack` (the sidecar's `stack`)
    alloca_limit : int
    stack_option : int
    // the sidecar's `solid_context`: every module carries `options solid_context`
    solid_context : bool
    // the sidecar's `jit_whole_program`: the module holding `main` pins the cached JIT's one-unit
    // build, `options jit_split_modules = 0` and `require c_runtime/c_jit_build`
    jit_whole_program : bool
    // the sidecar's `strict_aliasing`: false makes the module holding `main` turn the JIT's typed
    // aliasing off for the whole program, `options strict_aliasing = false`
    strict_aliasing : bool
    // the sidecar's or the option's `checks` is `off`: every converted function carries
    // `unsafe_deref` and `hint(unsafe_range_check)`, the module a comment saying so
    unchecked : bool
    // the sidecar's or the option's `param_writes` is `copy`: a written scalar or pointer
    // parameter gets a local copy instead of being written in place
    param_copy : bool
    // the sidecar's or the option's `loops` is not `while`: a canonical counting `for` is a das
    // range loop (`for_range`)
    range_loops : bool
    // the sidecar's or the option's `first_member` is `reinterpret`: the address of a member at
    // offset 0 reinterprets its record's pointer (`first_member_address`)
    reinterpret_members : bool
    // the sidecar's or the option's `switch_dispatch` is `goto`: a dense switch jumps to its case
    // (`dispatch_plan`), and a switch a goto from another case re-dispatches is spelled open, by a
    // table where it can (`open_redispatched`, `open_table`)
    goto_dispatch : bool
    // the sidecar's or the option's `past_end` is `inline`: `&a[k]` of a plain-load index is
    // `k == N ? addr(a[0]) + N : addr(a[k])` (`one_past_end_address`)
    past_end_inline : bool
    // the sidecar's or the option's `inline_helpers`: each pure `static` helper a direct call
    // spells as its expression, by C name to its index in the unit's declarations
    // (`flag_inline_helpers`)
    inline_helpers : table<string; int>
    // the declarations at a switch body's own level that a statement under a later label reads
    // or writes, which the lowered switch declares before itself (`carried_decls`)
    carried : table<uint64>
    // the trailing array members the sidecar lists under `over_indexed`, by record and field
    // (`member_key`)
    over_indexed : table<int64>
    // the array members the sidecar lists under `padded`, whose index reaches the members on
    // either side of them, by record and field (`member_key`)
    padded : table<int64>
    // the references named like a libc object (`stdout`) that a parameter or local binds, which
    // are no libc object (`unshadow_locals`)
    bound_objects : table<uint64>
    // every name some function or global initializer of the program points at (`mark_pointed`):
    // a global outside it, and defined by the program, no pointer reaches
    pointed : table<string>
    // what each function may store to, whether it returns, which parameters keep no pointer
    // (`summarize`), for the counted loops' bounds; empty under `loops` `while`
    summaries : Summaries
    // the macros the sidecar's `no_fold` keeps expanded, and every name a function, global or
    // type of the program, das or the runtime takes, which a folded macro's def does not take
    no_fold : table<string>
    taken_names : table<string>
}

let GENERATED_BANNER = "// generated by c2das - regenerate, never edit"

//! The tail of a source layout module's layout file, `<module>.layout.das.inc`, which the module
//! includes in place of its layout check (`ARCHITECTURE_LAYOUT.md`, The layout file).
let LAYOUT_FILE_SUFFIX = ".layout.das.inc"

// the annotations `--checks off` puts on every converted function: no null check on a dereference,
// no range check on an index (docs/probe-findings.md F84)
let UNCHECKED_ANNOTATIONS <- ["unsafe_deref", "hint(unsafe_range_check)"]

// the line under the banner of a module converted with `--checks off`
let UNCHECKED_BANNER = "// converted with --checks off: no null or range checks (the AOT host keeps its range checks), a wrong C program reads garbage or dies by SIGSEGV instead of panicking"

// the names the emitter spells bare in a module: the c_runtime helpers it calls or sets, the
// `main` wrapper's calls and its own generated functions and objects
let VOLATILE_LOAD = "c_volatile_load"
let VOLATILE_STORE = "c_volatile_store"
let VA_BEGIN = "va_begin"
let VA_INT = "va_i"
let VA_DOUBLE = "va_d"
let VA_POINTER = "va_p"
let VA_REST = "va_rest"
let END_INDEX = "end_index"
let ENUM_FROM_INT = "enum_from_int"
let CSTR_ARRAY = "cstr_array"
let CSTR = "cstr"
let INT_OF = "int_of"
let DO_WHILE = "c_do_while"
let C_SWITCH = "c_switch"
let JMP_TARGET = "c_jmp_target"
let UNIT_BYTES = "c_unit_bytes"
let LONG_BITS_GLOBAL = "c_long_bits"
let SIGNAL_MSVC = "c_signal_msvc"
let RUNTIME_INIT = "c_runtime_init"
let ARGC = "c_argc"
let ARGV = "c_argv"
let C_MAIN = "c_main"
let LAYOUT_CHECK = "c2das_layout_check"
let LATE_BIND = "c2das_late_bind"
let INIT_GLOBALS = "c2das_init_globals"
let DIALECT_INIT = "c2das_dialect"
let EMPTY_LITERAL = "c2das_empty"

//! Every name the emitter spells bare in a module besides the program's own (`reserved_das_names`).
let EMITTED_NAMES <- [VOLATILE_LOAD, VOLATILE_STORE, VA_BEGIN, VA_INT, VA_DOUBLE, VA_POINTER, VA_REST, END_INDEX, ENUM_FROM_INT, CSTR_ARRAY, CSTR, INT_OF, DO_WHILE, JMP_TARGET, UNIT_BYTES, LONG_BITS_GLOBAL, SIGNAL_MSVC, RUNTIME_INIT, ARGC, ARGV, C_MAIN, "main", LAYOUT_CHECK, LATE_BIND, INIT_GLOBALS, DIALECT_INIT, EMPTY_LITERAL, "memcpy"]

//! The public names of the c_runtime modules a converted module may require, each top-level
//! function, global, type and call macro of `c_runtime/c_runtime/*.das` (repo root);
//! `converter/tests/test_link.das` fails when a definition there is missing from it.
let C_RUNTIME_EXPORTS <- ["BitAccess", "BitStore", "CBitfieldsAnnotation", "CCompare", "CDoWhileMacro", "CFormatDirective", "CFunctionAnnotation", "CJmpBuf", "CMacroAnnotation", "CSignalHandler", "CStorage", "CSwitchMacro", "CUnionAnnotation", "CVaCursor", "CVaList", "CVal", "CVolatileLoadMacro", "C_EINVAL", "C_EOF", "C_SIGNAL_LIMIT", "C_SIG_ERR_BITS", "C_SIG_IGN_BITS", "C_STORAGES", "CstrArrayMacro", "CstrMacro", "EnumFromIntMacro", "IntOfMacro", "VaNone", "VariadicAnnotation", "VariadicCallMacro", "add_bit_pair", "bit_getter", "bit_setter", "c_abort", "c_argc", "c_argv", "c_assert_fail", "c_atexit", "c_bsearch", "c_bswap16", "c_bswap32", "c_bswap64", "c_clrsb", "c_clz", "c_ctz", "c_dialect_spec", "c_do_while", "c_exit", "c_ffs", "c_is_float_conversion", "c_is_int_conversion", "c_is_wide_length", "c_jmp_target", "c_long_bits", "c_longjmp", "c_parity", "c_parse_directive", "c_popcount", "c_prefetch", "c_qsort", "c_run_atexit", "c_runtime_init", "c_signal", "c_signal_msvc", "c_signbit", "c_switch", "c_unit_bytes", "c_unreachable", "c_vformat", "c_vfprintf", "c_volatile_load", "c_volatile_load_jit", "c_volatile_read", "c_volatile_store", "c_vprintf", "c_vsnprintf", "c_vsprintf", "c_vsscanf", "cstr", "cstr_array", "end_index", "enum_from_int", "field_index", "fprintf", "int_of", "printf", "register_llvm_code_generators", "snprintf", "sprintf", "sscanf", "storage_of", "storage_of_bytes", "to_cvalist", "va_args", "va_begin", "va_d", "va_i", "va_p", "va_rest"]

let PREC_PRIMARY = 14
let PREC_UNARY = 13
let PREC_MUL = 12
let PREC_ADD = 11
let PREC_SHIFT = 10
let PREC_REL = 9
let PREC_EQ = 8
let PREC_BAND = 7
let PREC_BXOR = 6
let PREC_BOR = 5
let PREC_LAND = 4
let PREC_LOR = 3
let PREC_COND = 2

let BIN_SPELLING <- {"add" => "+", "sub" => "-", "mul" => "*", "div" => "/", "rem" => "%", "shl" => "<<", "shr" => ">>", "lt" => "<", "gt" => ">", "le" => "<=", "ge" => ">=", "eq" => "==", "ne" => "!=", "band" => "&", "bor" => "|", "bxor" => "^", "land" => "&&", "lor" => "||"}

let BIN_PREC <- {"add" => 11, "sub" => 11, "mul" => 12, "div" => 12, "rem" => 12, "shl" => 10, "shr" => 10, "lt" => 9, "gt" => 9, "le" => 9, "ge" => 9, "eq" => 8, "ne" => 8, "band" => 7, "bor" => 5, "bxor" => 6, "land" => 4, "lor" => 3}

// a libc function a c_runtime piece lowers: the module that holds the piece and its das name
struct RuntimeCall {
    piece : string
    das_name : string
}

let C_RUNTIME_CALLS <- {
    "printf" => RuntimeCall(piece = "c_runtime/printf", das_name = "printf"),
    "sprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "sprintf"),
    "snprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "snprintf"),
    "vprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "c_vprintf"),
    "vsprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "c_vsprintf"),
    "vsnprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "c_vsnprintf"),
    "sscanf" => RuntimeCall(piece = "c_runtime/scanf", das_name = "sscanf"),
    "vsscanf" => RuntimeCall(piece = "c_runtime/scanf", das_name = "c_vsscanf"),
    "exit" => RuntimeCall(piece = "c_runtime/c_exit", das_name = "c_exit"),
    "abort" => RuntimeCall(piece = "c_runtime/c_exit", das_name = "c_abort"),
    "__assert_fail" => RuntimeCall(piece = "c_runtime/c_exit", das_name = "c_assert_fail"),
    "signal" => RuntimeCall(piece = "c_runtime/c_signal", das_name = "c_signal"),
    "longjmp" => RuntimeCall(piece = "c_runtime/setjmp", das_name = "c_longjmp"),
    "_longjmp" => RuntimeCall(piece = "c_runtime/setjmp", das_name = "c_longjmp"),
    "fprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "fprintf"),
    "vfprintf" => RuntimeCall(piece = "c_runtime/printf", das_name = "c_vfprintf"),
    "qsort" => RuntimeCall(piece = "c_runtime/c_sort", das_name = "c_qsort"),
    "bsearch" => RuntimeCall(piece = "c_runtime/c_sort", das_name = "c_bsearch"),
    // the GCC builtins with a direct meaning (c_runtime/c_builtins.das); an `l` or `ll` spelling
    // reaches the overload of its operand's width through the argument's type
    "__builtin_ffs" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_ffs"),
    "__builtin_ffsl" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_ffs"),
    "__builtin_ffsll" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_ffs"),
    "__builtin_ctz" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_ctz"),
    "__builtin_ctzl" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_ctz"),
    "__builtin_ctzll" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_ctz"),
    "__builtin_clz" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_clz"),
    "__builtin_clzl" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_clz"),
    "__builtin_clzll" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_clz"),
    "__builtin_popcount" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_popcount"),
    "__builtin_popcountl" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_popcount"),
    "__builtin_popcountll" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_popcount"),
    "__builtin_parity" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_parity"),
    "__builtin_parityl" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_parity"),
    "__builtin_parityll" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_parity"),
    "__builtin_clrsb" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_clrsb"),
    "__builtin_clrsbl" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_clrsb"),
    "__builtin_clrsbll" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_clrsb"),
    "__builtin_bswap16" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_bswap16"),
    "__builtin_bswap32" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_bswap32"),
    "__builtin_bswap64" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_bswap64"),
    "__builtin_signbit" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_signbit"),
    "__builtin_signbitf" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_signbit"),
    "__builtin_unreachable" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_unreachable"),
    "__builtin_prefetch" => RuntimeCall(piece = "c_runtime/c_builtins", das_name = "c_prefetch"),
    "__builtin_trap" => RuntimeCall(piece = "c_runtime/c_exit", das_name = "c_abort"),
    // <math.h>'s surface das math covers at `double` (docs/stdlib-examples.md "math.h"), each the
    // function C names, by the same libm (probes/test_stdlib.das)
    "floor" => RuntimeCall(piece = "math", das_name = "math::floor"),
    "ceil" => RuntimeCall(piece = "math", das_name = "math::ceil"),
    "fabs" => RuntimeCall(piece = "math", das_name = "math::abs"),
    "sqrt" => RuntimeCall(piece = "math", das_name = "math::sqrt"),
    "sin" => RuntimeCall(piece = "math", das_name = "math::sin"),
    "cos" => RuntimeCall(piece = "math", das_name = "math::cos"),
    "tan" => RuntimeCall(piece = "math", das_name = "math::tan"),
    "asin" => RuntimeCall(piece = "math", das_name = "math::asin"),
    "acos" => RuntimeCall(piece = "math", das_name = "math::acos"),
    "atan" => RuntimeCall(piece = "math", das_name = "math::atan"),
    "atan2" => RuntimeCall(piece = "math", das_name = "math::atan2"),
    "exp" => RuntimeCall(piece = "math", das_name = "math::exp"),
    "log" => RuntimeCall(piece = "math", das_name = "math::log"),
    "log2" => RuntimeCall(piece = "math", das_name = "math::log2"),
    "log10" => RuntimeCall(piece = "math", das_name = "math::log10"),
    "pow" => RuntimeCall(piece = "math", das_name = "math::pow"),
    // glibc's `errno` is `(*__errno_location())`
    "__errno_location" => RuntimeCall(piece = "crt", das_name = "crt::c_errno_location")
}

// the crt functions returning C's `long` whose C result is ranged at the dialect's `long`: where
// that is 32 bits, the crt forwarder that applies C's range rule there (LONG_MAX, LONG_MIN or
// ULONG_MAX with ERANGE, `ftell`'s -1 with ERANGE) rather than the host's 64-bit value narrowed
let LONG32_CALLS <- {"strtol" => "crt::c_strtol32", "strtoul" => "crt::c_strtoul32", "atol" => "crt::c_atol32", "ftell" => "crt::c_ftell32"}

// the libc objects a program reads, each the crt accessor that returns it
let CRT_OBJECTS <- {"stdin" => "crt::c_stdin", "stdout" => "crt::c_stdout", "stderr" => "crt::c_stderr"}

// a reference: a libc object (`stderr`) is its crt accessor, a `FILE *` as `void?` converted to the
// program's pointer; anything else is its das name
def private emit_ref(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let object = crt_object(em, unsafe(addr(x)))
    if (empty(object)) {
        return value(das_name(em, x.name), PREC_PRIMARY)
    }
    em.requires |> insert("crt")
    return unsafe_value(em, "reinterpret<{das_type(em, tu, x.t, loc)}>({object}())", PREC_PRIMARY)
}

// the crt accessor of the libc object `x` reads (`stderr`), "" for any other expression: a name
// a parameter, a local or a program global binds is the program's own
def private crt_object(em : Emitter; x : CirExpr const?) : string {
    var at = x
    while (at != null && at.e == "cast" && (at.cast_kind == "LValueToRValue" || at.cast_kind == "NoOp")) {
        at = at.a
    }
    if (at == null || at.e != "ref" || key_exists(em.prog.defined_globals, at.name) || key_exists(em.prog.bound_objects, intptr(at))) {
        return ""
    }
    return CRT_OBJECTS?[at.name] ?? ""
}

// the builtins that are a constant of the crt module (`HUGE_VAL` expands to one)
let CRT_CONSTANT_CALLS <- {"__builtin_huge_val" => "crt::HUGE_VAL"}

let SETJMP_NAMES <- {"setjmp", "_setjmp", "__sigsetjmp"}

let SETVBUF = "setvbuf"

let ALLOCA_NAMES <- {"alloca", "__builtin_alloca"}

let EXPECT = "__builtin_expect"

let ALLOCA_LIMIT = 65536

// the context stack every converted module asks for, C's default on linux (8 MiB): das's own
// is 16 KiB, which a record parameter's copy or an alloca arena outgrows
let MODULE_STACK = 8388608

// a `__builtin_` name whose libc twin the tables carry is that twin (the shim list)
def private libc_name(name : string) : string =>
    name |> starts_with("__builtin_") && !empty(libc_call(slice(name, length("__builtin_")))) ? slice(name, length("__builtin_")) : name

let VA_LIST = "va_list"

// the name `[variadic]` gives the trailing tuple parameter (c_runtime/variadic.das)
let VA_TUPLE = "_va_tuple"

// the builtins `va_start`, `va_end` and `va_copy` expand to (C23's `va_start` included)
let VA_START_NAMES <- {"__builtin_va_start", "__builtin_c23_va_start"}

let VA_END = "__builtin_va_end"

let VA_COPY = "__builtin_va_copy"

// the C macro a `va_*` builtin expands from, for the messages
def private va_macro_name(builtin : string) : string =>
    builtin == VA_END ? "va_end" : builtin == VA_COPY ? "va_copy" : "va_start"

// the libc functions the crt module binds under their C names (dasCRuntime/ARCHITECTURE.md),
// <math.h>'s exotica among them
let CRT_CALLS <- {"fmod", "frexp", "ldexp", "modf", "nextafter", "hypot", "cbrt", "expm1", "log1p", "copysign", "remainder", "trunc", "round", "erf", "erfc", "tgamma", "lgamma", "fma", "clock", "c_monotonic_ns", "clock_gettime", "time", "difftime", "mktime", "localtime", "gmtime", "strftime", "setlocale", "localeconv", "fopen", "freopen", "fclose", "fread", "fwrite", "fgets", "fputs", "getc", "ungetc", "feof", "ferror", "clearerr", "fflush", "fseek", "ftell", "setvbuf", "tmpfile", "tmpnam", "remove", "rename", "system", "rand", "srand", "getenv", "malloc", "calloc", "realloc", "free", "memcpy", "memmove", "memset", "memcmp", "memchr", "strlen", "strcpy", "strncpy", "strcat", "strncat", "strcmp", "strncmp", "strchr", "strrchr", "strstr", "strpbrk", "strspn", "strcoll", "strerror", "strtol", "strtoul", "strtoll", "strtoull", "strtod", "atoi", "atol", "atof", "abs", "llabs", "isalpha", "isdigit", "isalnum", "isspace", "isupper", "islower", "isxdigit", "ispunct", "isprint", "iscntrl", "isgraph", "toupper", "tolower"}

//! Every name a converted module can resolve besides the program's own: the C names the emitter
//! maps to a libc, crt or c_runtime entity (`libc_call`, the libc objects, the ranged `long` calls,
//! `setjmp`, `alloca`) and their unqualified das names, the names it spells bare
//! (`EMITTED_NAMES`), the public names of the c_runtime modules (`C_RUNTIME_EXPORTS`) and every
//! function and global the crt module binds: a program's own function or object of one of these
//! names would take their calls or make them ambiguous (`converter/link.das`).
def reserved_das_names : array<string> {
    var names <- [for (name in keys(C_RUNTIME_CALLS)); name]
    names |> push_from([for (name in keys(CRT_CALLS)); name])
    names |> push_from([for (name in keys(CRT_OBJECTS)); name])
    names |> push_from([for (name in keys(LONG32_CALLS)); name])
    names |> push_from([for (name in keys(SETJMP_NAMES)); name])
    names |> push_from([for (name in keys(ALLOCA_NAMES)); name])
    names |> push_from([for (call in values(C_RUNTIME_CALLS)); call.das_name; where find(call.das_name, "::") < 0])
    names |> push_from(EMITTED_NAMES, C_RUNTIME_EXPORTS)
    let crt = get_module("crt")
    module_for_each_function(crt) $(info) {
        names |> push(info.name)
    }
    module_for_each_global(crt) $(info) {
        names |> push(info.name)
    }
    sort(names)
    return <- names
}

// C name -> das spelling, and the module it needs
def private libc_call(name : string) : string {
    if (key_exists(C_RUNTIME_CALLS, name)) {
        return C_RUNTIME_CALLS?[name]?.das_name ?? name
    }
    return key_exists(CRT_CALLS, name) ? "crt::{name}" : ""
}

// the separator of a list's items (arguments, elements, fields): `, ` with the mark a long line breaks at
let private LIST_SEPARATOR = ",{LIST_MARK} "

// the separator of a function's parameters: `; ` with the mark a long line breaks at
let private PARAMETER_SEPARATOR = ";{LIST_MARK} "

def private libc_module(name : string) : string => C_RUNTIME_CALLS?[name]?.piece ?? (key_exists(CRT_CALLS, name) ? "crt" : "")

def private fail(var em : Emitter; what : string; loc : CirLoc) {
    if (empty(em.error)) {
        em.error = "{loc.file}:{loc.line}:{loc.col}: {what}"
    }
}

def private line(var em : Emitter; text : string) {
    em.out |> push(repeat("    ", em.depth) + text + "\n")
}

def private flush_pre(var em : Emitter) {
    flush_literal_decls(em)
    for (stmt in em.pre) {
        line(em, stmt)
    }
    em.pre |> clear()
}

// the declarations of the compound literal objects conditional arms assign, which precede the
// statement, and a loop whose condition the lowering moves into its body
def private flush_literal_decls(var em : Emitter) {
    for (stmt in em.literal_decls) {
        line(em, stmt)
    }
    em.literal_decls |> clear()
}

// statements that run before the statement being emitted, in order
def private hoist(var em : Emitter; stmts : array<string>) {
    em.pre |> push_from(stmts)
}

def private temp_name(var em : Emitter) : string {
    var name = "_t{em.temp_counter}"
    em.temp_counter++
    while (key_exists(em.spelled, name)) {
        name = "_t{em.temp_counter}"
        em.temp_counter++
    }
    return name
}

def private das_name(em : Emitter; c_name : string) : string {
    let renamed = em.renames?[c_name] ?? ""
    return !empty(renamed) ? renamed : reserved_rename(c_name)
}

// das reserves a name that starts with `__` (glibc's `struct tm` field `__tm_gmtoff`) as it does a
// keyword: such a C name is spelled `_c_<name>`
def private reserved_rename(c_name : string) : string =>
    key_exists(DAS_KEYWORDS, c_name) || c_name |> starts_with("__") ? "_c_{c_name}" : c_name

// false with the error set when a C name das reserves renames onto another identifier of the
// program (`__h` and a local `_c___h`): the two would be one das name
def private check_reserved_renames(var em : Emitter; tu : CirTu) {
    var names : table<string; CirLoc>
    for (d in tu.decls) {
        if (d.k == "global" || d.k == "func") {
            names |> insert(d.name, d.loc)
        }
        for (p in d.params) {
            names |> insert(p.name, d.loc)
        }
        each_stmt(d.body) $(st) {
            if (st.s == "decl") {
                names |> insert(st.name, st.loc)
            }
        }
    }
    var sorted <- [for (name in keys(names)); name]
    sort(sorted)
    for (name in sorted) {
        let renamed = reserved_rename(name)
        if (renamed != name && key_exists(names, renamed)) {
            fail(em, "C names `{name}` and `{renamed}` are both `{renamed}` in das, which reserves `{name}`; not lowered", names?[renamed] ?? CirLoc(file = tu.tu))
            return
        }
    }
}

def private unsafe_value(var em : Emitter; text : string; prec : int) : Em {
    em.unsafe_used = true
    return em.in_global_init ? value("unsafe({text})", PREC_PRIMARY) : value(text, prec)
}

def private value(text : string; prec : int) : Em => Em(text = text, prec = prec, is_bool = false)

def private truth(text : string; prec : int) : Em => Em(text = text, prec = prec, is_bool = true)

[arch(at="ARCHITECTURE_EMITTER_TEXT.md#parentheses")]
def private wrap(e : Em; need : int) : string => e.prec < need || (e.paren && e.prec < PREC_PRIMARY) ? "({e.text})" : e.text

def private kind_of(tu : CirTu; t : int) : string => t >= 0 && t < length(tu.types) ? tu.types[t].k : ""

def private is_small_int(tu : CirTu; t : int) : bool =>
    kind_of(tu, t) == "int" && tu.types[t].w < 32 && tu.types[t].spell != "_Bool"

def private is_unsigned(tu : CirTu; t : int) : bool => kind_of(tu, t) == "int" && !tu.types[t].is_signed

def private is_function_pointer(tu : CirTu; t : int) : bool => kind_of(tu, t) == "ptr" && kind_of(tu, tu.types[t].to) == "func"

// a C `long` or `unsigned long` where the dialect's `long` is 32 bits (`msvc`): the crt module
// binds C's `long` as 64 bits (dasCRuntime/ARCHITECTURE.md), so a call to it widens such an
// argument and narrows such a result
def private is_narrow_long(tu : CirTu; t : int) : bool =>
    tu.target.long_w == 32 && kind_of(tu, t) == "int" && (tu.types[t].spell == "long" || tu.types[t].spell == "unsigned long")

// a C `va_list`: the dumper's opaque record, or linux's decay of it, `struct __va_list_tag *`
// (a parameter, an argument), which the lowering spells alike as the runtime's cursor
def private is_va_list(tu : CirTu; t : int) : bool {
    let rec = kind_of(tu, t) == "ptr" ? tu.types[t].to : t
    // a C record tagged `va_list` is spelled `struct va_list`; the opaque record is `va_list`
    return kind_of(tu, rec) == "struct" && tu.types[rec].spell == VA_LIST
}

// a pointer to an object, which das spells `T?`; a function pointer is a function value
def private is_data_pointer(tu : CirTu; t : int) : bool => kind_of(tu, t) == "ptr" && !is_function_pointer(tu, t)

def private is_record(tu : CirTu; t : int) : bool => kind_of(tu, t) == "struct" || kind_of(tu, t) == "union"

// a pointer to a C record (`FILE *`, `struct tm *`), which a library function takes and returns
// as `void?` (dasCRuntime/ARCHITECTURE.md): `jmp_buf` and `va_list` are the protocol's own
// records, passed as they are
def private is_record_pointer(tu : CirTu; t : int) : bool {
    if (kind_of(tu, t) != "ptr" || !is_record(tu, tu.types[t].to) || is_va_list(tu, t)) {
        return false
    }
    return !is_jmp_buf(tu, tu.types[t].to)
}

// whether a value of type `t` holds a data pointer
def private holds_data_pointer(tu : CirTu; t : int) : bool {
    if (is_data_pointer(tu, element_under(tu, t))) {
        return true
    }
    let rec = record_under(tu, t)
    if (rec >= 0) {
        for (f in tu.types[rec].fields) {
            if (holds_data_pointer(tu, f.t)) {
                return true
            }
        }
    }
    return false
}

// whether a parameter of type `t` is `var` (F3): a data pointer, and a record holding one,
// since das takes no `let` pointer where a `var` one is expected and reads every pointer
// reached through a `let` parameter as a const pointee; a `va_list` is the caller's cursor
def private is_var_parameter(tu : CirTu; t : int) : bool =>
    is_va_list(tu, t) || ((is_data_pointer(tu, t) || is_record(tu, t)) && holds_data_pointer(tu, t))

//! The das spelling of type `t`, or "" with `error` set.
def das_type(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    if (t < 0 || t >= length(tu.types)) {
        fail(em, "type index {t} out of range", loc)
        return ""
    }
    let k = tu.types[t].k
    if (k == "void") {
        return "void"
    }
    if (k == "int") {
        if (tu.types[t].spell == "_Bool") {
            return "bool"
        }
        let w = tu.types[t].w
        let base = w == 8 ? "int8" : w == 16 ? "int16" : w == 64 ? "int64" : "int"
        return tu.types[t].is_signed ? base : "u" + base
    }
    if (k == "float") {
        return tu.types[t].w == 32 ? "float" : "double"
    }
    if (is_va_list(tu, t)) {
        em.requires |> insert("c_runtime/variadic")
        return "CVaCursor"
    }
    if (k == "ptr") {
        if (kind_of(tu, tu.types[t].to) == "func") {
            return das_type(em, tu, tu.types[t].to, loc)
        }
        // a marshal-only record lives in C memory as bytes: a pointer to one is a byte pointer
        if (is_marshal(em, tu, tu.types[t].to)) {
            return "uint8?"
        }
        let to = das_type(em, tu, tu.types[t].to, loc)
        return empty(to) ? "" : to + "?"
    }

    if (k == "func") {
        return function_value_type(em, tu, t, loc)
    }
    if (k == "array") {
        let bare : array<CirDim>
        return array_type(em, tu, t, loc, bare)
    }
    if (is_jmp_buf(tu, t)) {
        em.requires |> insert("c_runtime/setjmp")
        return "CJmpBuf"
    }
    if (k == "struct" || k == "union" || k == "enum") {
        return tag_name(em, tu, t)
    }
    fail(em, "type kind `{k}` is not lowered yet", loc)
    return ""
}

// dimensions read outermost first, as in C; `? [` keeps a pointer element from lexing as
// the safe-index operator; a dimension the declarator spells by an enum constant keeps it
// (`[int(E.COUNT)]`, which das folds), one `spelled` slot per dimension
def private array_type(var em : Emitter; tu : CirTu; t : int; loc : CirLoc; spelled : array<CirDim>) : string {
    var dims : array<string>
    var elem = t
    while (kind_of(tu, elem) == "array") {
        if (is_marshal(em, tu, tu.types[elem].elem)) {
            fail(em, "an array of the marshal-only record `{tag_name(em, tu, tu.types[elem].elem)}` is not lowered yet", loc)
            return ""
        }
        if (tu.types[elem].count == 0) {
            fail(em, "a zero-length array (a GNU extension) is not lowered yet", loc)
            return ""
        }
        if (tu.types[elem].count < 0) {
            fail(em, "an array of unknown length (`extern int a[];`) is not lowered yet", loc)
            return ""
        }
        let level = length(dims)
        let named = level < length(spelled) && !empty(spelled[level].item)
        dims |> push(named ? "[int({enum_item(em, tu, spelled[level].enum_t, spelled[level].item)})]" : "[{tu.types[elem].count}]")
        elem = tu.types[elem].elem
    }
    let base = das_type(em, tu, elem, loc)
    return empty(base) ? "" : base + (base |> ends_with("?") ? " " : "") + join(dims, "")
}

//! The das spelling of a declarator of type `t` whose array dimensions `dims` spells.
def das_type_dims(var em : Emitter; tu : CirTu; t : int; loc : CirLoc; dims : array<CirDim>) : string =>
    kind_of(tu, t) == "array" ? array_type(em, tu, t, loc, dims) : das_type(em, tu, t, loc)

// a C function pointer is a das function value: `function<(a0 : T; ...) : R>`, the
// parameters named by position since the C type carries no names; a position is `var` where
// a parameter of its type is, since das types a parameter's constness (F34)
def private function_value_type(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    if (tu.types[t].variadic) {
        fail(em, "a pointer to a variadic function is not lowered yet", loc)
        return ""
    }
    var params : array<string>
    params |> reserve(length(tu.types[t].params))
    for (idx in range(length(tu.types[t].params))) {
        let mode = is_var_parameter(tu, tu.types[t].params[idx]) ? "var " : ""
        params |> push("{mode}a{idx} : {das_type(em, tu, tu.types[t].params[idx], loc)}")
    }
    let ret = das_type(em, tu, tu.types[t].ret, loc)
    return "function<({join(params, "; ")}) : {ret}>"
}

// `E.X`: an enumerator through its enum's das name
def private enum_item(em : Emitter; tu : CirTu; t : int; item : string) : string => "{tag_name(em, tu, t)}.{das_name(em, item)}"

// a tagged type keeps its C name; an unnamed one is named by its type slot
def private tag_name(em : Emitter; tu : CirTu; t : int) : string =>
    empty(tu.types[t].name) ? "anon_{t}" : das_name(em, tu.types[t].name)

// a field by index; a record libclang never saw defined (size -1) has none, and a member of
// one is the dumper's error to raise, so here it is a fault
def private field_name(var em : Emitter; tu : CirTu; rec : int; field : int) : string {
    if (field < 0 || field >= length(tu.types[rec].fields)) {
        fail(em, "record `{tag_name(em, tu, rec)}` has no field {field}: the dump and libclang disagree on its definition", CirLoc())
        return "_"
    }
    return member_name(em, tu.types[rec].fields[field], field)
}

// whether record `t` has an anonymous member, an unnamed field that is no bitfield
def private has_anonymous_member(tu : CirTu; t : int) : bool {
    for (f in tu.types[t].fields) {
        if (empty(f.name) && !f.is_bitfield) {
            return true
        }
    }
    return false
}

// a field's das name; an anonymous member (an unnamed field that is no bitfield) is named by
// its index, `_anon<N>`
def private member_name(em : Emitter; f : CirField; idx : int) : string => empty(f.name) ? "_anon{idx}" : das_name(em, f.name)

// the bool view of a C scalar: a comparison stays one, a pointer tests against null, an
// integer against zero
def private to_bool(e_in : Em; tu : CirTu; t : int) : Em {
    if (e_in.is_bool) {
        return e_in
    }
    return zero_test(e_in, tu, t, "!=")
}

// C scalar `e_in` of type `t` against its zero by `op` (`!=` or `==`): a pointer against null, a
// float against its zero, an enum's int, an integer against 0
def private zero_test(e_in : Em; tu : CirTu; t : int; op : string) : Em {
    let e = enum_as_int(e_in, tu, t)
    let zero = kind_of(tu, t) == "ptr" ? "null" : kind_of(tu, t) == "float" ? (tu.types[t].w == 32 ? "0.0f" : "0.0lf") : "0"
    var test = truth("{wrap(e, PREC_EQ + 1)} {op} {zero}", PREC_EQ)
    test.inverse = "{wrap(e, PREC_EQ + 1)} {op == "!=" ? "==" : "!="} {zero}"
    return test
}

// the text of `!c` for truth `c` the emitter tests the other way (a loop's exit, a flattened
// branch): a zero test's inverse (`x == 0` for `x != 0`, exact for every value, NaN included),
// `!(c)` for any other
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#truth-tests")]
def private negation(c : Em) : string => empty(c.inverse) ? "!({c.text})" : c.inverse

// the truth test of C expression `x` (an `if`, a loop, `!`, `&&`, `||`, `?:`): the bool view of
// what is left past a `__builtin_expect` hint, an integer conversion that keeps every value's
// zero and a truth value's `!= 0`, none of which can change the test (`l_likely(x)`'s
// `(long) (x != 0)` is `x != 0`, `l_likely(a < b)` is `a < b`)
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#truth-tests")]
def private truth_of(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    let operand = truth_operand(em, tu, x)
    return to_bool(emit_expr(em, tu, operand, loc), tu, operand.t)
}

// the falsity test of C expression `x`, C's `!x`: a das bool negated (`!(a < b)`, `!b`), any other
// scalar the inverted zero test truth_of would print (`x == 0`, `p == null`, `f == 0.0f`), exact
// for every value, a float's NaN included (`!NaN` is 0, `NaN == 0.0f` false); `!!x` is the truth of `x`
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#truth-tests")]
def private falsity_of(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    let operand = truth_operand(em, tu, x)
    if (operand.e == "un" && operand.op == "not") {
        // `!!x` is the truth of `x`
        return truth_of(em, tu, operand.a, loc)
    }
    if (operand.e == "bin" && operand.op == "ne" && operand.b != null && operand.b.e == "int_lit" && operand.b.v == "0" && kind_of(tu, operand.a.t) == "int") {
        // `!(x != 0)` the C text spelled (`!l_unlikely(c)`) is `x == 0`
        return zero_test(emit_expr(em, tu, operand.a, loc), tu, operand.a.t, "==")
    }
    let e = emit_expr(em, tu, operand, loc)
    return e.is_bool ? truth("!{wrap(e, PREC_UNARY)}", PREC_UNARY) : zero_test(e, tu, operand.t, "==")
}

// what truth_of tests of C expression `x`: `x` past a `__builtin_expect` hint, an integer
// conversion that keeps every value's zero and a truth value's `!= 0`
def private truth_operand(em : Emitter; tu : CirTu; x : CirExpr const?) : CirExpr const? {
    var operand = x
    while (operand != null && !key_exists(em.hoisted, intptr(operand))) {
        if (operand.e == "call" && called_name(*operand) == EXPECT && length(operand.args) == 2) {
            operand = operand.args[0]
        } elif (operand.e == "cast" && operand.cast_kind == "IntegralCast" && keeps_zero(tu, operand.a.t, operand.t)) {
            operand = operand.a
        } elif (operand.e == "bin" && operand.op == "ne" && operand.b != null && operand.b.e == "int_lit" && operand.b.v == "0" && is_truth_value(operand.a)) {
            operand = operand.a
        } else {
            break
        }
    }
    return operand
}

// whether C expression `x` is a truth value, 0 or 1: a comparison, `&&`, `||` or `!`
def private is_truth_value(x : CirExpr const?) : bool =>
    x != null && ((x.e == "bin" && (x.op == "eq" || x.op == "ne" || x.op == "lt" || x.op == "gt" || x.op == "le" || x.op == "ge" || x.op == "land" || x.op == "lor")) || (x.e == "un" && x.op == "not"))

// whether converting integer type `from` to `to` keeps zero and nonzero apart: `to` is no narrower
def private keeps_zero(tu : CirTu; from, to : int) : bool => kind_of(tu, from) == "int" && kind_of(tu, to) == "int" && tu.types[to].w >= tu.types[from].w

// an enum operand where C reads an integer (an index, a pointer step, a truth test): das
// enums have no arithmetic, so the value goes through `int`
def private enum_as_int(e : Em; tu : CirTu; t : int) : Em => kind_of(tu, t) == "enum" ? value(enum_to_integer(tu, t, e.text, "int"), PREC_PRIMARY) : e

// the integer type C promotes enum `t` to: `int`, or `uint` when clang chose an unsigned
// underlying type (the linux dialect does for an enum without a negative enumerator)
def private enum_promoted(tu : CirTu; t : int) : string => tu.types[t].is_signed ? "int" : "uint"

// an enum value as the number type `target`: das converts an enum to every integer type directly,
// with the bits `int(e)` gives (`uint(e)`, `int64(e)`, `uint8(e)`; F106), through `uint` first
// where a wider target would otherwise read an unsigned-underlying enum's high bit as a sign, and
// to a floating type through its promoted integer, the one way das takes it there
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#enum-conversions")]
def private enum_to_integer(tu : CirTu; t : int; text : string; target : string) : string {
    let promoted = enum_promoted(tu, t)
    if (target == "float" || target == "double" || (promoted == "uint" && (target == "int64" || target == "uint64"))) {
        return "{target}({promoted}({text}))"
    }
    return "{target}({text})"
}

// the int view of a C expression das spelled as a bool: `int_of(c)`, c_runtime's call macro that
// expands in place to `c ? 1 : 0`
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#truth-as-int")]
def private to_int(var em : Emitter; e : Em) : Em {
    if (!e.is_bool) {
        return e
    }
    em.requires |> insert("c_runtime/int_of")
    return value("{INT_OF}({e.text})", PREC_PRIMARY)
}

def private is_c_bool(tu : CirTu; t : int) : bool => kind_of(tu, t) == "int" && tu.types[t].spell == "_Bool"

// a value stored into a slot of type `t`: a `_Bool` slot is a das `bool` and takes the truth
// as it is, every other slot its integer
def private stored(var em : Emitter; e : Em; tu : CirTu; t : int) : Em => is_c_bool(tu, t) ? e : to_int(em, e)

def private literal(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let spelled = das_type(em, tu, x.t, loc)
    if (x.e == "float_lit") {
        let text = unsafe(reinterpret<uint8?>(x.v))
        let v = unsafe(crt::strtod(text, null))
        if (spelled == "float") {
            return value("{float(v)}f", PREC_PRIMARY)
        }
        var digits = "{v}"
        if (find(digits, ".") < 0 && find(digits, "e") < 0 && find(digits, "n") < 0) {
            digits += ".0"
        }
        return value(digits + "lf", PREC_PRIMARY)
    }
    if (x.is_char && spelled == "int") {
        let spelling = char_literal(to_int(x.v))
        if (!empty(spelling)) {
            return value(spelling, PREC_PRIMARY)
        }
    }
    let negative = x.v |> starts_with("-")
    let prec = negative ? PREC_UNARY : PREC_PRIMARY
    let suffixed = int_literal(spelled, x.v)
    if (!empty(suffixed)) {
        return value(suffixed, prec)
    }
    if (spelled == "bool") {
        return value(x.v != "0" ? "true" : "false", PREC_PRIMARY)
    }
    return value("{spelled}({x.v})", PREC_PRIMARY)
}

// the comments of one C source by line (from 0): each line's comment text, "" for none,
// whether the line holds a comment and no code, and the line's last byte of code (0 for none)
struct CComments {
    texts : array<string>
    alone : array<bool>
    last : array<int>
}

// one comment's text as the readability criterion reads it (metrics/criteria_scan.das):
// whitespace collapsed, the `*` and `/` decoration at either end dropped
def private comment_text(text : string) : string {
    let words <- [for (w in split(replace(replace(text, "\t", " "), "\r", " "), " ")); w; where !empty(w)]
    let joined = join(words, " ")
    var first = 0
    var last = 0
    peek_data(joined) $(b) {
        last = length(b)
        while (first < last && (int(b[first]) == '*' || int(b[first]) == '/' || int(b[first]) == ' ')) {
            first++
        }
        while (last > first && (int(b[last - 1]) == '*' || int(b[last - 1]) == '/' || int(b[last - 1]) == ' ')) {
            last--
        }
    }
    return slice(joined, first, last)
}

// the comments of C text `text`, a block comment's lines each its own; a string or a character
// literal is skipped, so a `//` inside one is no comment
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#comments")]
def private c_comments(text : string) : CComments {
    var cc : CComments
    var pieces : array<tuple<line : int; a : int; b : int>>
    var line = 0
    cc.texts |> push("")
    cc.last |> push(0)
    peek_data(text) $(b) {
        let n = length(b)
        var i = 0
        while (i < n) {
            let c = int(b[i])
            if (c == '\n') {
                line++
                cc.texts |> push("")
                cc.last |> push(0)
                i++
            } elif (c == '/' && i + 1 < n && int(b[i + 1]) == '/') {
                var e = i
                while (e < n && int(b[e]) != '\n') {
                    e++
                }
                pieces |> push((line = line, a = i + 2, b = e))
                i = e
            } elif (c == '/' && i + 1 < n && int(b[i + 1]) == '*') {
                var a = i + 2
                var e = a
                while (e < n && !(int(b[e]) == '*' && e + 1 < n && int(b[e + 1]) == '/')) {
                    if (int(b[e]) == '\n') {
                        pieces |> push((line = line, a = a, b = e))
                        line++
                        cc.texts |> push("")
                        cc.last |> push(0)
                        a = e + 1
                    }
                    e++
                }
                pieces |> push((line = line, a = a, b = e))
                i = min(e + 2, n)
            } else {
                if (!is_white_space(c)) {
                    cc.last[line] = c
                }
                i++
                if (c == '"' || c == '\'') {
                    // the literal ends at its quote or, unterminated, before the newline, which
                    // the loop counts; a backslash-newline splice inside it is a line too
                    while (i < n && int(b[i]) != c && int(b[i]) != '\n') {
                        if (int(b[i]) == '\\' && i + 1 < n && int(b[i + 1]) == '\n') {
                            line++
                            cc.texts |> push("")
                            cc.last |> push(c)
                        }
                        i += int(b[i]) == '\\' && i + 1 < n ? 2 : 1
                    }
                    if (i < n && int(b[i]) == c) {
                        i++
                    }
                }
            }
        }
        cc.alone |> resize(length(cc.texts))
        for (p in pieces) {
            cc.alone[p.line] = cc.last[p.line] == 0
            let piece = comment_text(slice(b, p.a, p.b))
            if (!empty(piece)) {
                cc.texts[p.line] = empty(cc.texts[p.line]) ? piece : "{cc.texts[p.line]} {piece}"
            }
        }
    }
    return <- cc
}

// the comments of the C file at `file`, read on first use; none for a file that is not there
def private comments_of(var em : Emitter; file : string) : CComments? {
    if (!key_exists(em.c_comments, file)) {
        em.c_comments[file] <- stat(file).is_reg ? c_comments(fread(file)) : CComments()
    }
    return unsafe(addr(em.c_comments[file]))
}

// the comments of the lines from the last carried one up to `loc`'s, each a `//` line above the
// statement there, when `loc` is in the file of the function being emitted
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#comments")]
def private carry_comments(var em : Emitter; loc : CirLoc) {
    if (empty(loc.file) || loc.file != em.comment_file) {
        return
    }
    let done = em.comments_done?[loc.file] ?? 0
    if (loc.line <= done) {
        return
    }
    let cc = comments_of(em, loc.file)
    for (l in range(done, min(loc.line, length(cc.texts)))) {
        if (!empty(cc.texts[l])) {
            line(em, "// {cc.texts[l]}")
        }
    }
    em.comments_done[loc.file] = loc.line
}

// whether a line whose last byte of code is `c` can end a declaration's specifiers: an
// identifier's character or a pointer's `*`, not a statement's or a block's end
def private is_specifier_end(c : int) : bool => is_alnum(c) || c == '_' || c == '*'

// the comment lines right above a function's header (a block of lines that hold a comment and no
// code), above its `def`; the body then carries from the header's line on
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#comments")]
def private carry_comments_above(var em : Emitter; loc : CirLoc) {
    em.comment_file = loc.file
    if (empty(loc.file) || loc.line <= 0) {
        return
    }
    let cc = comments_of(em, loc.file)
    let done = em.comments_done?[loc.file] ?? 0
    var first = min(loc.line - 1, length(cc.alone))
    // a GNU-style header puts the specifiers on a line of their own (`static int` above the
    // name's line): the comment block stands above that line
    if (first > done && !cc.alone[first - 1] && empty(cc.texts[first - 1]) && is_specifier_end(cc.last[first - 1])) {
        first--
    }
    while (first > done && cc.alone[first - 1]) {
        first--
    }
    for (l in range(first, min(loc.line - 1, length(cc.texts)))) {
        if (!empty(cc.texts[l])) {
            line(em, "// {cc.texts[l]}")
        }
    }
    em.comments_done[loc.file] = max(done, loc.line - 1)
}

// the das character literal of C character `c`, "" where das has none (a negative value, a
// multi-character one): the printable ASCII, the named escapes `\0 \a \b \t \n \v \f \r \\ \'`,
// and `\xHH` for any other byte (docs/probe-findings.md F94)
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#character-literals")]
def private char_literal(c : int) : string {
    if (c == '\\' || c == '\'') {
        return "'\\{to_char(c)}'"
    }
    if (c >= 32 && c < 127) {
        return "'{to_char(c)}'"
    }
    if (c < 0 || c > 255) {
        return ""
    }
    let named = NAMED_ESCAPES?[c] ?? ""
    return empty(named) ? "'\\x{hex_byte(c)}'" : "'\\{named}'"
}

// the letter of a C escape das reads the same way, by the byte it spells
let private NAMED_ESCAPES <- {0 => "0", 7 => "a", 8 => "b", 9 => "t", 10 => "n", 11 => "v", 12 => "f", 13 => "r"}

// `digits` as a literal of the das integer type `spelled` by its suffix; "" for a type that has
// no literal of its own (the small integers, `bool`)
def private int_literal(spelled, digits : string) : string {
    if (spelled == "int") {
        return digits
    }
    if (spelled == "uint") {
        return digits + "u"
    }
    if (spelled == "int64") {
        return digits + "l"
    }
    return spelled == "uint64" ? digits + "ul" : ""
}

// a das literal is a legal read-only C string, except the empty one, which is a null pointer
// (docs/probe-findings.md F10): C's `""` points at one NUL byte, so it is the module's
// one-byte array
def private string_literal(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (length(x.bytes) <= 1) {
        em.empty_literal = true
        return unsafe_value(em, "addr({EMPTY_LITERAL}[0])", PREC_PRIMARY)
    }
    // `cstr` expands in place to the literal's `reinterpret<uint8?>`, safe and no call
    em.requires |> insert("c_runtime/cstr")
    return value("{CSTR}({quoted_literal(em, tu, x, loc)})", PREC_PRIMARY)
}

// one hex digit of a value below 16
def private hex_digit(v : int) : string => to_char(v < 10 ? '0' + v : 'a' + v - 10)

// whether literal `x` holds a NUL before its own terminating one, among its first `limit` bytes
def private interior_nul(x : CirExpr; limit : int) : bool {
    for (idx in range(length(x.bytes) - 1)) {
        if (idx >= limit) {
            break
        }
        if (x.bytes[idx] == uint8(0)) {
            return true
        }
    }
    return false
}

// two hex digits of a byte, spelled without `fmt`, whose format parsing rejects a zero
def private hex_byte(b : int) : string => "{hex_digit(b >> 4)}{hex_digit(b & 15)}"

// the das literal spelling of the bytes before the terminating NUL, at most `limit` of them when
// it is not negative: the named escapes, an interior NUL `\0` unless an octal digit follows,
// which `\0` would swallow (`\012` is a newline), then `\x00`, and `\xHH` for any other byte
// outside the printable ASCII; das keeps the bytes after a NUL (docs/probe-findings.md F94)
def private quoted_literal(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc; limit : int = -1) : string {
    if (kind_of(tu, x.t) == "array" && tu.types[tu.types[x.t].elem].w != 8) {
        // the bytes are the dump's narrow ones: a wide element needs its own literal
        fail(em, "a wide string literal (`L\"...\"`, `u\"...\"`, `U\"...\"`) is not lowered yet", loc)
        return "\"\""
    }
    let n = limit < 0 || limit >= length(x.bytes) ? length(x.bytes) - 1 : limit
    return build_string() $(var w) {
        w |> write("\"")
        for (idx in range(n)) {
            let b = int(x.bytes[idx])
            if (b == '"' || b == '\\' || b == '{' || b == '}') {
                w |> write("\\")
                w |> write(to_char(b))
            } elif (b == 0) {
                let next = idx + 1 < n ? int(x.bytes[idx + 1]) : 0
                w |> write(next >= '0' && next <= '7' ? "\\x00" : "\\0")
            } elif (key_exists(NAMED_ESCAPES, b)) {
                w |> write("\\{NAMED_ESCAPES?[b] ?? ""}")
            } elif (b < 32 || b >= 127) {
                w |> write("\\x{hex_byte(b)}")
            } else {
                w |> write(to_char(b))
            }
        }
        w |> write("\"")
    }
}

// the statement of assignment `x`; a compound store spells its target more than once
// (`lhs = lhs op v`, a marshal record's reader and writer), so a target with an effect is pinned
// first and every spelling reads the same temporaries
def private assignment_line(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    var keys : array<uint64>
    if (!empty(x.op)) {
        pin_lvalue(em, tu, x.a, loc, keys)
    }
    let text = assignment_text(em, tu, x, loc)
    unpin(em, keys)
    return text
}

def private assignment_text(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    if (volatile_kept(em, tu, x.a)) {
        return volatile_assignment(em, tu, x, loc)
    }
    // the left side's effects hoist before the right side's: the dialect's fixed order
    var bytes : Em
    let of_field = marshal_field(em, tu, *x.a, loc, bytes)
    let whole = of_field < 0 && empty(x.op) ? marshal_site(em, tu, x.a, loc, bytes) : -1
    let lhs = of_field < 0 && whole < 0 ? emit_expr(em, tu, x.a, loc) : value("", PREC_PRIMARY)
    let compound = empty(x.op) && of_field < 0 && whole < 0 ? self_operation(tu, x) : null
    if (compound != null) {
        // `x = x op y` is das's `x op= y`, `y` the integer it is in the plain form's sum
        let y = wrap_pair(tu, x.b) != null ? wrap_operand(em, tu, compound.b, x.a.t, loc) : stored(em, emit_expr(em, tu, compound.b, loc), tu, x.a.t)
        return "{lhs.text} {BIN_SPELLING?[compound.op] ?? ""}= {wrap(y, (BIN_PREC?[compound.op] ?? 0) + 1)}"
    }
    var rhs = stored(em, emit_expr(em, tu, x.b, loc), tu, x.a.t)
    if (of_field >= 0) {
        return marshal_store(em, tu, x, of_field, x.a.field, bytes, rhs, loc)
    }
    if (whole >= 0) {
        return marshal_store(em, tu, x, whole, -1, bytes, rhs, loc)
    }
    if (empty(x.op)) {
        return "{lhs.text} = {rhs.text}"
    }
    let spelled = BIN_SPELLING?[x.op] ?? ""
    let prec = BIN_PREC?[x.op] ?? 0
    if (kind_of(tu, x.a.t) == "ptr") {
        em.unsafe_used = true
        let scale = marshal_pointee(em, tu, x.a.t)
        // das's `p += n` and `p -= n` step a pointer lvalue by `n` elements (probe F102)
        if (scale >= 0) {
            return "{lhs.text} {spelled}= {wrap(rhs, PREC_MUL)} * {type_size(tu, scale)}"
        }
        return "{lhs.text} {spelled}= {rhs.text}"
    }
    // C computes `a op= b` in the common type of the converted operands, which clang gives
    // the right side; a shift computes in the promoted left side alone
    let shift = x.op == "shl" || x.op == "shr"
    let wide = shift ? promoted_type(em, tu, x.a.t, loc) : das_type(em, tu, x.b.t, loc)
    if (shift) {
        rhs = shift_count(em, tu, *x.b, rhs, wide, loc)
    }
    if (kind_of(tu, x.a.t) == "enum") {
        let sum = "{enum_to_integer(tu, x.a.t, lhs.text, wide)} {spelled} {wrap(rhs, prec + 1)}"
        let as_int = wide == "int" ? sum : "int({sum})"
        return "{lhs.text} = {int_to_enum(em, tu, x.a.t, as_int)}"
    }
    if (is_c_bool(tu, x.a.t)) {
        // C computes `b op= v` in the promoted type and stores the truth of the result
        return "{lhs.text} = ({wide}({to_int(em, lhs).text}) {spelled} {wrap(rhs, prec + 1)}) != 0"
    }
    let narrow = das_type(em, tu, x.a.t, loc)
    if (narrow != wide) {
        return "{lhs.text} = {narrow}({wide}({lhs.text}) {spelled} {wrap(rhs, prec + 1)})"
    }
    return "{lhs.text} {spelled}= {rhs.text}"
}

// whether an access of volatile lvalue `x` goes through `c_volatile_load`/`c_volatile_store`: a
// number, `_Bool`, a data or function pointer, a field of a plain record, an element. A bitfield,
// a `[c_union]` or marshal-only record's member and an enum are properties or tagged values with
// no address, and a whole record is a copy of many fields, no single access: their access stays
// the plain one
def private volatile_kept(var em : Emitter; tu : CirTu; x : CirExpr const?) : bool {
    let k = x == null ? "" : kind_of(tu, x.t)
    let rec = x != null && x.e == "member" ? (x.arrow ? tu.types[x.base.t].to : x.base.t) : -1
    let kept = x != null && x.vol && (k == "int" || k == "float" || k == "ptr") && !is_bitfield_member(tu, x) && (rec < 0 || (kind_of(tu, rec) == "struct" && !is_marshal(em, tu, rec)))
    if (kept) {
        em.requires |> insert("c_runtime/c_volatile")
    }
    return kept
}

// a read of volatile lvalue `x`: one `c_volatile_load` through its address, which no tier folds
def private volatile_load(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em => value("{VOLATILE_LOAD}({emit_expr(em, tu, x, loc).text})", PREC_PRIMARY)

// the value of lvalue `x` read back after a store or a step: a volatile one is read again
def private lvalue_read(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em => volatile_kept(em, tu, x) ? volatile_load(em, tu, x, loc) : emit_expr(em, tu, x, loc)

// `a = v` and `a op= v` into volatile `a`: one store, a compound one after one load, the
// arithmetic in the type the plain form computes in; the target, pinned, is spelled twice
def private volatile_assignment(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    let target = emit_expr(em, tu, x.a, loc).text
    var rhs = stored(em, emit_expr(em, tu, x.b, loc), tu, x.a.t)
    if (empty(x.op)) {
        return "{VOLATILE_STORE}({target}, {rhs.text})"
    }
    let spelled = BIN_SPELLING?[x.op] ?? ""
    let prec = BIN_PREC?[x.op] ?? 0
    let current = "{VOLATILE_LOAD}({target})"
    if (kind_of(tu, x.a.t) == "ptr") {
        // the plain form's pointer step, a marshal-only pointee's in its C size
        em.unsafe_used = true
        let scale = marshal_pointee(em, tu, x.a.t)
        let step = scale >= 0 ? "{wrap(rhs, PREC_MUL)} * {type_size(tu, scale)}" : wrap(rhs, prec + 1)
        // das's pointer `-` takes only a variable (probes/test_pointers.das): the load's value
        // steps back as the sum of the negated count
        return x.op == "sub" ? "{VOLATILE_STORE}({target}, {current} + -({step}))" : "{VOLATILE_STORE}({target}, {current} {spelled} {step})"
    }
    let shift = x.op == "shl" || x.op == "shr"
    let wide = shift ? promoted_type(em, tu, x.a.t, loc) : das_type(em, tu, x.b.t, loc)
    if (shift) {
        rhs = shift_count(em, tu, *x.b, rhs, wide, loc)
    }
    if (is_c_bool(tu, x.a.t)) {
        // C computes `b op= v` in the promoted type and stores the truth of the result
        return "{VOLATILE_STORE}({target}, ({wide}({current} ? 1 : 0) {spelled} {wrap(rhs, prec + 1)}) != 0)"
    }
    let narrow = das_type(em, tu, x.a.t, loc)
    let combined = narrow == wide ? "{current} {spelled} {wrap(rhs, prec + 1)}" : "{narrow}({wide}({current}) {spelled} {wrap(rhs, prec + 1)})"
    return "{VOLATILE_STORE}({target}, {combined})"
}

// `++a` / `a--` of volatile `a`: one load and one store of the stepped value; `loaded` names the
// temporary a used old value was loaded into, the step's one load then, "" for none
def private volatile_step(var em : Emitter; tu : CirTu; x : CirExpr; up : bool; loaded : string; loc : CirLoc) : string {
    let narrow = das_type(em, tu, x.a.t, loc)
    let float_step = kind_of(tu, x.a.t) == "float"
    if (is_c_bool(tu, x.a.t)) {
        fail(em, "a `_Bool` step (`b++`, `s.f++`) is not lowered yet", loc)
        return ""
    }
    let target = emit_expr(em, tu, x.a, loc).text
    let current = empty(loaded) ? "{VOLATILE_LOAD}({target})" : loaded
    let sign = up ? "+" : "-"
    var stepped = ""
    if (kind_of(tu, x.a.t) == "ptr") {
        em.unsafe_used = true
        let scale = marshal_pointee(em, tu, x.a.t)
        stepped = "{current} + {up ? "" : "-"}{scale >= 0 ? type_size(tu, scale) : 1l}"
    } elif (float_step) {
        stepped = "{current} {sign} {narrow == "float" ? "1.0f" : "1.0lf"}"
    } elif (is_small_int(tu, x.a.t)) {
        stepped = "{narrow}({is_unsigned(tu, x.a.t) ? "uint" : "int"}({current}) {sign} 1)"
    } else {
        stepped = "{current} {sign} {int_literal(narrow, "1")}"
    }
    return "{VOLATILE_STORE}({target}, {stepped})"
}

// `x = x op y`, with `x` read on the right as the same object, no call, effect or volatile read in
// it (C reads a volatile index or pointer of `x` on both sides), and the operation in `x`'s own
// type (a number of 32 or 64 bits or a float, never a pointer, a small integer, an enum or
// `_Bool`), or a wrapping sum of it (`wrap_pair`): the `bin` node das spells as `x op= y`; null
// for any other assignment
def private self_operation(tu : CirTu; x : CirExpr) : CirExpr const? {
    let wrapped = wrap_pair(tu, x.b)
    var op : CirExpr const? = x.b
    if (wrapped != null) {
        op = wrapped
    }
    if (!self_target(tu, x.a) || op == null || op.e != "bin" || !key_exists(SELF_OPS, op.op) || has_effects(x.a) || reads_volatile(x.a) || has_effects(op.b) || (wrapped == null && op.b.t != x.a.t)) {
        return null
    }
    let read = wrapped == null ? op.a : op.a.a
    return read != null && read.e == "cast" && read.cast_kind == "LValueToRValue" && same_lvalue(read.a, x.a) ? op : null
}

// whether lvalue `a` takes `op=`: a number of 32 or 64 bits or a float that is not volatile; a
// bitfield or a `[c_union]` member is a property, which takes it through its getter and setter
def private self_target(tu : CirTu; a : CirExpr const?) : bool {
    let k = kind_of(tu, a.t)
    return (k == "int" || k == "float") && !is_small_int(tu, a.t) && !is_c_bool(tu, a.t) && !a.vol
}

let SELF_OPS <- {"add", "sub", "mul", "band", "bor", "bxor"}

// whether C-IR lvalues `a` and `b` name the same object: one variable, or the same field or
// element chain over equal bases and literal or variable indexes
def private same_lvalue(a, b : CirExpr const?) : bool {
    if (a == null || b == null || a.e != b.e || a.t != b.t) {
        return false
    }
    if (a.e == "ref") {
        return a.name == b.name
    }
    if (a.e == "member") {
        return a.field == b.field && a.arrow == b.arrow && same_lvalue(a.base, b.base)
    }
    if (a.e == "index") {
        return same_lvalue(a.base, b.base) && same_lvalue(a.i, b.i)
    }
    if (a.e == "cast") {
        return a.cast_kind == b.cast_kind && same_lvalue(a.a, b.a)
    }
    if (a.e == "un") {
        return a.op == "deref" && b.op == "deref" && same_lvalue(a.a, b.a)
    }
    return a.e == "int_lit" && a.v == b.v
}

// C promotes a shift's count apart from its left side, and das shifts a value only by a count
// of its own type (`docs/probe-findings.md` F40): the count takes the left side's spelling
def private shift_count(var em : Emitter; tu : CirTu; count : CirExpr; rhs : Em; left_type : string; loc : CirLoc) : Em {
    if (das_type(em, tu, count.t, loc) == left_type) {
        return rhs
    }
    if (count.e == "enum_ref") {
        // an enumerator count converts directly, as its enum does (`1u << uint(TMS.TM_EQ)`)
        return value(enum_to_integer(tu, count.enum_t, enum_item(em, tu, count.enum_t, count.item), left_type), PREC_PRIMARY)
    }
    // a `#define` constant's name stays (`~0u << uint(SIZE_A)`)
    let named = !empty(count.macro) && rhs.text == reserved_rename(count.macro)
    let literal = count.e == "int_lit" && !named ? int_literal(left_type, count.v) : ""
    return value(empty(literal) ? "{left_type}({rhs.text})" : literal, PREC_PRIMARY)
}

// the type C's integer promotion gives a value of type `t`: `int` or `uint` for the small
// integers and the enums, the type itself otherwise
def private promoted_type(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    // a `_Bool` promotes to `int`, as C reads every `_Bool` as a number
    if (is_c_bool(tu, t)) {
        return "int"
    }
    if (is_small_int(tu, t)) {
        return is_unsigned(tu, t) ? "uint" : "int"
    }
    if (kind_of(tu, t) == "enum") {
        return enum_promoted(tu, t)
    }
    return das_type(em, tu, t, loc)
}

// the statement of step `x`; every step but das's own `x++` spells its target twice
// (`x = x + 1`), so a target with an effect is pinned first
def private step_line(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    var keys : array<uint64>
    pin_lvalue(em, tu, x.a, loc, keys)
    let text = volatile_kept(em, tu, x.a) ? volatile_step(em, tu, x, x.op == "preinc" || x.op == "postinc", "", loc) : step_text(em, tu, x, loc)
    unpin(em, keys)
    return text
}

// the step of a pointer lvalue `operand` of type `t`: a byte pointer to a marshal-only record steps
// by the record's C size; das's `p++` and `p--` step any other by one element (probe F102)
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#pointer-steps")]
def private pointer_step(var em : Emitter; tu : CirTu; t : int; operand : Em; up : bool) : string {
    em.unsafe_used = true
    let scale = marshal_pointee(em, tu, t)
    if (scale >= 0) {
        return "{operand.text} {up ? "+" : "-"}= {type_size(tu, scale)}"
    }
    return "{wrap(operand, PREC_PRIMARY)}{up ? "++" : "--"}"
}

def private step_text(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    let up = x.op == "preinc" || x.op == "postinc"
    var bytes : Em
    let field = marshal_field(em, tu, *x.a, loc, bytes)
    if (field >= 0) {
        let current = "{reader_name(em, tu, field, x.a.field)}({bytes.text}, 0)"
        let narrow = das_type(em, tu, x.a.t, loc)
        let wide = is_small_int(tu, x.a.t) ? (is_unsigned(tu, x.a.t) ? "uint" : "int") : narrow
        let stepped = narrow == wide ? "{current} {up ? "+" : "-"} 1" : "{narrow}({wide}({current}) {up ? "+" : "-"} 1)"
        return "{writer_name(em, tu, field, x.a.field)}({bytes.text}, 0, {stepped})"
    }
    let operand = emit_expr(em, tu, x.a, loc)
    if (is_small_int(tu, x.a.t)) {
        let narrow = das_type(em, tu, x.a.t, loc)
        let wide = is_unsigned(tu, x.a.t) ? "uint" : "int"
        return "{operand.text} = {narrow}({wide}({operand.text}) {up ? "+" : "-"} 1)"
    }
    if (kind_of(tu, x.a.t) == "ptr") {
        return pointer_step(em, tu, x.a.t, operand, up)
    }
    if (kind_of(tu, x.a.t) == "enum") {
        let stepped = "int({operand.text}) {up ? "+" : "-"} 1"
        return "{operand.text} = {int_to_enum(em, tu, x.a.t, stepped)}"
    }
    if (is_c_bool(tu, x.a.t)) {
        fail(em, "a `_Bool` step (`b++`, `s.f++`) is not lowered yet", loc)
        return ""
    }
    if (is_bitfield_member(tu, x.a)) {
        // das has no `++` on a property: a compound store steps it
        let spelled = das_type(em, tu, x.a.t, loc)
        let one = int_literal(spelled, "1")
        if (empty(one)) {
            fail(em, "a step of a `{spelled}` bitfield is not lowered yet", loc)
            return ""
        }
        return "{operand.text} {up ? "+" : "-"}= {one}"
    }
    // `(*p)++`: das reads `*p++` so too (probe F102), the parentheses read it as C does
    return "{wrap(operand, PREC_PRIMARY)}{up ? "++" : "--"}"
}

// the callee's das spelling: a function of this unit by name, a libc function by its
// mapping, and "" for a call through a pointer, which `emit_call` spells as `invoke`
def private callee_name(var em : Emitter; tu : CirTu; fn : CirExpr?; loc : CirLoc) : string {
    var target = fn
    if (target != null && target.e == "cast" && target.cast_kind == "FunctionToPointerDecay") {
        target = target.a
    }
    if (target == null || target.e != "ref") {
        return ""
    }
    if (key_exists(SETJMP_NAMES, target.name)) {
        fail(em, "setjmp whose value is not tested against zero by the `if` around it (the general trampoline form) is not lowered yet", loc)
        return ""
    }
    let libc = libc_name(target.name)
    if (!key_exists(em.prog.functions, target.name) && empty(libc_call(libc))) {
        // a name of function type is an external function; a pointer-typed one is a call
        // through the pointer
        if (kind_of(tu, target.t) == "func") {
            fail(em, "external function `{target.name}` has no c_runtime mapping", loc)
        }
        return ""
    }
    if (key_exists(em.prog.functions, target.name)) {
        // a late-bound function the module also sees itself, as its definer or through a require,
        // names its module, since the link module's wrapper of its name is in sight too
        return "{em.late_quals?[target.name] ?? ""}{function_name(em, target.name)}"
    }
    em.requires |> insert(libc_module(libc))
    if (libc == SETVBUF) {
        // a buffer the program hands the CRT lives in das memory: c_exit flushes every stream
        // before the context that holds it dies
        em.requires |> insert("c_runtime/c_exit")
    }
    // every crt bind is an unsafe operation (dasCRuntime/ARCHITECTURE.md): the body takes
    // [c_function] for it
    if (libc_module(libc) == "crt") {
        em.unsafe_used = true
    }
    return libc_call(libc)
}

// `alloca(n)`: a bump on the function's arena (docs/stdlib-examples.md "alloca"): the guard
// panics past the limit, since das's `assert` is a debug check; the offset rounds to 16
def private emit_alloca(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (length(x.args) != 1) {
        fail(em, "alloca takes one size", loc)
        return value("", PREC_PRIMARY)
    }
    let n = to_int(em, emit_expr(em, tu, x.args[0], loc))
    let size = das_type(em, tu, x.args[0].t, loc) == "int" ? n.text : "int({n.text})"
    let tmp = temp_name(em)
    em.unsafe_used = true
    hoist(em, ["if (_c_aoff + {size} > {em.prog.alloca_limit}) \{", "    panic(\"alloca past the function's {em.prog.alloca_limit} byte arena\")", "\}", "var {tmp} = reinterpret<void?>(addr(_c_astack[_c_aoff]))", "_c_aoff += ({size} + 15) & ~15"])
    return value(tmp, PREC_PRIMARY)
}

// whether `x`, below casts and a deref, is a call
def private is_call_value(x : CirExpr const?) : bool {
    var at = x
    while (at != null && (at.e == "cast" || (at.e == "un" && at.op == "deref"))) {
        at = at.a
    }
    return at != null && at.e == "call"
}

// the function type a call through a pointer calls, -1 for a direct call
def private called_type(tu : CirTu; fn : CirExpr const?) : int {
    if (fn == null) {
        return -1
    }
    return is_function_pointer(tu, fn.t) ? tu.types[fn.t].to : kind_of(tu, fn.t) == "func" ? fn.t : -1
}

// false with the error set when a call goes through a pointer whose type says another number
// of arguments (an unprototyped `T (*)()`, which the C-IR spells as `T (*)(void)`)
def private check_call_arity(var em : Emitter; tu : CirTu; x : CirExpr; through_pointer : bool; loc : CirLoc) : bool {
    let ft = through_pointer ? called_type(tu, x.fn) : -1
    if (ft >= 0 && !tu.types[ft].variadic && length(tu.types[ft].params) != length(x.args)) {
        fail(em, "a call with {length(x.args)} arguments through a function pointer whose type takes {length(tu.types[ft].params)} (an unprototyped `T (*)()`) is not lowered yet", loc)
        return false
    }
    return true
}

// `va_start(v, last)` is `v = va_begin(va)` over the list the `[variadic]` prologue bound,
// `va_copy(w, v)` is `w = v`, `va_end(v)` is no statement at all
def private emit_va_builtin(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let callee = called_name(x)
    let list = emit_expr(em, tu, x.args[0], loc).text
    if (callee == VA_END) {
        return value("", PREC_PRIMARY)
    }
    if (callee == VA_COPY) {
        return value("{list} = {emit_expr(em, tu, x.args[1], loc).text}", PREC_PRIMARY)
    }
    return value("{list} = {VA_BEGIN}({em.va_name})", PREC_PRIMARY)
}

def private is_va_builtin(x : CirExpr) : bool {
    let callee = called_name(x)
    return key_exists(VA_START_NAMES, callee) || callee == VA_END || callee == VA_COPY
}

// the name C spells a function or global by, which a `static` one's TU-qualified name hides
def private c_name_of(tu : CirTu; name : string) : string {
    for (d in tu.decls) {
        if (d.name == name && !empty(d.c_name)) {
            return d.c_name
        }
    }
    return name
}

// false with the error set when an argument past a variadic callee's fixed parameters is a
// record or a `va_list`, which the trailing tuple's promotions do not carry
def private check_trailing_arguments(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : bool {
    let ft = called_type(tu, x.fn)
    if (ft < 0 || !tu.types[ft].variadic) {
        return true
    }
    let fixed = length(tu.types[ft].params)
    for (idx in range(fixed, length(x.args))) {
        let what = is_va_list(tu, x.args[idx].t) ? "a `va_list`" : is_record(tu, x.args[idx].t) ? "a record" : ""
        if (!empty(what)) {
            fail(em, "{what} passed through `...` (argument {idx} of `{c_name_of(tu, called_name(x))}`) is not lowered yet", loc)
            return false
        }
    }
    return true
}

// the index of a call's first trailing argument, past a variadic callee's fixed parameters; the
// argument count for any other callee
def private trailing_from(tu : CirTu; x : CirExpr) : int {
    let ft = called_type(tu, x.fn)
    return ft >= 0 && tu.types[ft].variadic ? length(tu.types[ft].params) : length(x.args)
}

// a call of a `[variadic]` function of this module, spelled as the call macro expands it:
// `f`va(fixed..., (t1, t2))`, `(t,)` for one trailing argument, `VaNone()` for none. A generic
// body keeps a call macro uninferred, and daScript's module cache refuses to write one the
// module itself owns; the spelled call also resolves at inference, above its definition and
// inside it (`docs/probe-findings.md` F37). The library's variadics keep C's spelling
def private variadic_call(name : string; fixed : int; args : array<string>) : string {
    var parts : array<string>
    parts |> reserve(fixed + 1)
    for (idx in range(fixed)) {
        parts |> push(args[idx])
    }
    let trailing = length(args) - fixed
    if (trailing == 0) {
        parts |> push("VaNone()")
    } elif (trailing == 1) {
        parts |> push("({args[fixed]},)")
    } else {
        parts |> push("({join([for (idx in range(fixed, length(args))); args[idx]], LIST_SEPARATOR)})")
    }
    return "{name}`va({join(parts, LIST_SEPARATOR)})"
}

// the spelling of argument `arg` (spelled `text`) of a call, `fixed` when it meets a parameter of
// the prototype, `library` when the callee is a libc function, `crt` when the crt module binds it
def private call_argument(var em : Emitter; tu : CirTu; arg : CirExpr const?; text : string; fixed, library, crt : bool) : string {
    if (library && is_va_list(tu, arg.t)) {
        // a library function taking a `va_list` takes the list from the cursor on, as a
        // `CVaList` (`c_vprintf`): the forwarding of a `va_list`
        return "{VA_REST}({text})"
    } elif (crt && fixed && is_narrow_long(tu, arg.t)) {
        return "{is_unsigned(tu, arg.t) ? "uint64" : "int64"}({text})"
    } elif (library && fixed && is_record_pointer(tu, arg.t)) {
        em.unsafe_used = true
        // `stderr` passed on is the accessor's `void?` as it is
        let object = crt_object(em, arg)
        return empty(object) ? "reinterpret<void?>({text})" : "{object}()"
    }
    return text
}

def private emit_call(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (key_exists(ALLOCA_NAMES, called_name(x))) {
        return emit_alloca(em, tu, x, loc)
    }
    if (called_name(x) == EXPECT && length(x.args) == 2) {
        // GCC's branch hint is its first operand's value; the second is a constant
        return emit_expr(em, tu, x.args[0], loc)
    }
    if (key_exists(CRT_CONSTANT_CALLS, called_name(x)) && empty(x.args)) {
        em.requires |> insert("crt")
        return value(CRT_CONSTANT_CALLS?[called_name(x)] ?? "", PREC_PRIMARY)
    }
    if (is_va_builtin(x)) {
        // `emit_effect` spells them as statements; as a value there is nothing to spell
        fail(em, "`{va_macro_name(called_name(x))}` used as a value is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    if (!check_trailing_arguments(em, tu, x, loc)) {
        return value("", PREC_PRIMARY)
    }
    let name = callee_name(em, tu, x.fn, loc)
    if (!check_call_arity(em, tu, x, empty(name), loc)) {
        return value("", PREC_PRIMARY)
    }
    var args : array<string>
    args |> reserve(length(x.args) + 1)
    if (empty(name)) {
        // a call through a pointer: `invoke` on the function value, which `fp(...)` and
        // `(*fp)(...)` both spell once the casts and the deref fall away; a callee that is
        // itself a call goes through a temporary, since the JIT crashes on `invoke(invoke(...))`
        // of a local function value (probes/test_functions.das)
        let callee = emit_expr(em, tu, x.fn, loc)
        if (is_call_value(x.fn)) {
            let tmp = temp_name(em)
            hoist(em, ["let {tmp} = {callee.text}"])
            args |> push(tmp)
        } else {
            args |> push(callee.text)
        }
    }
    let library = !empty(name) && !key_exists(em.prog.functions, called_name(x))
    let fixed_count = trailing_from(tu, x)
    let crt = name |> starts_with("crt::")
    for (idx, arg in range(length(x.args)), x.args) {
        let text = stored(em, emit_expr(em, tu, arg, loc), tu, arg.t).text
        args |> push(call_argument(em, tu, arg, text, idx < fixed_count, library, crt))
    }
    if (empty(name)) {
        return value("invoke({join(args, LIST_SEPARATOR)})", PREC_PRIMARY)
    }
    let ft = called_type(tu, x.fn)
    if (!library && ft >= 0 && tu.types[ft].variadic) {
        // the trailing arguments' `VaNone` and tuples are c_runtime/variadic's, which a caller in
        // another module than the function's requires too
        em.requires |> insert("c_runtime/variadic")
        return value(variadic_call(name, length(tu.types[ft].params), args), PREC_PRIMARY)
    }
    if (crt && is_narrow_long(tu, x.t)) {
        // a parse or a position C ranges at the dialect's 32 bits clamps or fails there, never wraps
        let ranged = LONG32_CALLS?[libc_name(called_name(x))] ?? ""
        if (!empty(ranged)) {
            return value("{ranged}({join(args, LIST_SEPARATOR)})", PREC_PRIMARY)
        }
        return value("{is_unsigned(tu, x.t) ? "uint" : "int"}({name}({join(args, LIST_SEPARATOR)}))", PREC_PRIMARY)
    }
    if (library && is_record_pointer(tu, x.t)) {
        // `localtime`'s `struct tm *` comes back as `void?`
        return unsafe_value(em, "reinterpret<{das_type(em, tu, x.t, loc)}>({name}({join(args, LIST_SEPARATOR)}))", PREC_PRIMARY)
    }
    return value("{name}({join(args, LIST_SEPARATOR)})", PREC_PRIMARY)
}

// the body of a pure helper (`inline_helper`): `return <result>`, or the clamp shape, an `if`
// chain whose every arm assigns `param` (`guards[k]` true assigns `values[k]`, a last bare `else`
// assigns `otherwise`) followed by `return <result>`, the result a read of `param` under casts
struct private HelperShape {
    @do_not_delete result : CirExpr const?
    param : string
    @do_not_delete guards : array<CirExpr const?>
    @do_not_delete values : array<CirExpr const?>
    @do_not_delete otherwise : CirExpr const?
}

// the one statement a branch holds, below one level of braces; null for any other branch
def private only_statement(st : CirStmt const?) : CirStmt const? {
    if (st == null || st.s != "compound") {
        return st
    }
    let kept <- [for (child in st.body); child; where child.s != "null"]
    return length(kept) == 1 ? kept[0] : null
}

// the value statement `st` assigns parameter `param` (`param = v;`), null for any other statement
def private param_assignment(st : CirStmt const?; param : string) : CirExpr const? {
    let only = only_statement(st)
    if (only == null || only.s != "expr" || only.e == null || only.e.e != "assign" || !empty(only.e.op)) {
        return null
    }
    let target = only.e.a
    return target != null && target.e == "ref" && target.name == param ? only.e.b : null
}

// the clamp shape's `if` chain from `st` on into `shape`: false when an arm is anything but an
// assignment of `shape.param`
def private clamp_chain(st : CirStmt const?; var shape : HelperShape) : bool {
    var at = st
    while (at != null && at.s == "if") {
        let assigned = param_assignment(at.then_s, shape.param)
        if (at.cond == null || assigned == null) {
            return false
        }
        shape.guards |> push(at.cond)
        shape.values |> push(assigned)
        let next = only_statement(at.else_s)
        if (at.else_s != null && next == null) {
            return false
        }
        if (next != null && next.s != "if") {
            shape.otherwise = param_assignment(next, shape.param)
            return shape.otherwise != null
        }
        at = next
    }
    return true
}

// helper `d`'s body as a `HelperShape`: false for a body of any other shape
def private helper_shape(d : CirDecl; var shape : HelperShape) : bool {
    if (d.body == null || d.body.s != "compound") {
        return false
    }
    let stmts <- [for (st in d.body.body); st; where st.s != "null"]
    let last = !empty(stmts) ? stmts[length(stmts) - 1] : null
    if (last == null || last.s != "return" || last.e == null || length(stmts) > 2) {
        return false
    }
    shape.result = last.e
    if (length(stmts) == 1) {
        return true
    }
    let read = below_casts(last.e)
    if (read == null || !has_value([for (p in d.params); p.name], read.name) || stmts[0].s != "if") {
        return false
    }
    shape.param = read.name
    return clamp_chain(stmts[0], shape)
}

// the expressions of `shape` a call site's arguments reach: everything but the clamp's result,
// which reads the chain
def private helper_operands(shape : HelperShape) : array<CirExpr const?> {
    var out : array<CirExpr const?>
    if (empty(shape.param)) {
        out |> push(shape.result)
    }
    out |> push_from(shape.guards, shape.values)
    if (shape.otherwise != null) {
        out |> push(shape.otherwise)
    }
    return <- out
}

// a parameter or result type a helper substitutes: an integer other than `_Bool`, or a floating type
def private helper_scalar(tu : CirTu; t : int) : bool => (kind_of(tu, t) == "int" && !is_c_bool(tu, t)) || kind_of(tu, t) == "float"

let private HELPER_CASTS <- {"LValueToRValue", "NoOp", "IntegralCast", "IntegralToFloating", "FloatingToIntegral", "FloatingCast", "IntegralToBoolean", "FloatingToBoolean"}
let private HELPER_UNARY <- {"neg", "plus", "bnot", "not"}

// whether `x` reads only `params`, literals and enumerators through operators, value casts, a
// conditional and the calls of other helpers (`calls` collects their names), with no call at all
// when `calls_allowed` is false
def private pure_helper_expr(tu : CirTu; x : CirExpr const?; params : array<string>; calls_allowed : bool; var calls : array<string>) : bool {
    var pure = true
    // a call's callee, which the walk reaches after the call
    var callees : table<uint64>
    each_subexpr(x) $(sub) {
        if (key_exists(callees, intptr(sub))) {
            pass
        } elif (sub.e == "ref") {
            pure = pure && has_value(params, sub.name) && helper_scalar(tu, sub.t)
        } elif (sub.e == "cast") {
            pure = pure && key_exists(HELPER_CASTS, sub.cast_kind)
        } elif (sub.e == "un") {
            pure = pure && key_exists(HELPER_UNARY, sub.op)
        } elif (sub.e == "call") {
            pure = pure && calls_allowed && !empty(called_name(*sub))
            calls |> push(called_name(*sub))
            callees |> insert(intptr(sub.fn))
            if (sub.fn != null && sub.fn.e == "cast") {
                callees |> insert(intptr(sub.fn.a))
            }
        } else {
            pure = pure && (sub.e == "int_lit" || sub.e == "float_lit" || sub.e == "enum_ref" || sub.e == "bin" || sub.e == "cond" || sub.e == "sizeof_v" || sub.e == "alignof_v")
        }
    }
    return pure
}

// whether function `di` of `tu` is a pure helper (`inline_helper`), `functions` each defined
// function's index by name, `taken` the functions whose value the program takes; `memo` holds the
// answers, false for a helper being decided, so recursion through helpers is none
def private is_pure_helper(tu : CirTu; di : int; functions : table<string; int>; taken : table<string>; var memo : table<string; bool>) : bool {
    let d = tu.decls[di]
    if (key_exists(memo, d.name)) {
        return memo?[d.name] ?? false
    }
    memo[d.name] = false
    let ft = d.t
    if (!d.is_static || key_exists(taken, d.name) || kind_of(tu, ft) != "func" || tu.types[ft].variadic || !helper_scalar(tu, tu.types[ft].ret) || length(d.params) > 4 || length(d.params) != length(tu.types[ft].params)) {
        return false
    }
    for (p, pt in d.params, tu.types[ft].params) {
        // a K&R definition's parameter arrives at its promoted type and converts on entry
        if (!helper_scalar(tu, p.t) || p.t != pt) {
            return false
        }
    }
    var shape : HelperShape
    if (!helper_shape(*d, shape)) {
        return false
    }
    let params <- [for (p in d.params); p.name]
    var calls : array<string>
    let calls_allowed = empty(shape.param)
    var pure = pure_helper_expr(tu, shape.result, params, calls_allowed, calls)
    for (x in helper_operands(shape)) {
        pure = pure && pure_helper_expr(tu, x, params, calls_allowed, calls)
    }
    for (callee in calls) {
        let at = functions?[callee] ?? -1
        pure = pure && at >= 0 && is_pure_helper(tu, at, functions, taken, memo)
    }
    memo[d.name] = pure
    return pure
}

// the functions whose value the program takes: a reference to a function anywhere but as the
// callee of a direct call
def private taken_functions(tu : CirTu) : table<string> {
    var exprs : array<CirExpr const?>
    for (d in tu.decls) {
        if (d.k == "func") {
            each_expr(d.body) $(x) {
                exprs |> push(x)
            }
        } elif (d.k == "global") {
            each_subexpr(d.init) $(x) {
                exprs |> push(x)
            }
        }
    }
    var direct : table<uint64>
    for (x in exprs) {
        if (x.e == "call" && x.fn != null) {
            direct |> insert(intptr(x.fn))
            if (x.fn.e == "cast" && x.fn.cast_kind == "FunctionToPointerDecay") {
                direct |> insert(intptr(x.fn.a))
            }
        }
    }
    var taken : table<string>
    for (x in exprs) {
        if (x.e == "ref" && kind_of(tu, x.t) == "func" && !key_exists(direct, intptr(x))) {
            taken |> insert(x.name)
        }
    }
    return <- taken
}

// the pure helpers of the program under `inline_helpers`: each `static` function of at most four
// integer or floating parameters and such a result, whose body is `return <expr>` or the clamp
// shape over its parameters, literals and enumerators (the clamp calling nothing, `return <expr>`
// only other such helpers), whose value the program never takes and whose name no other function of
// the program defines
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#inline-helpers")]
def private flag_inline_helpers(var em : Emitter; tu : CirTu) {
    let functions <- {for (di, d in count(), tu.decls); d.name => di; where d.k == "func" && d.body != null}
    var taken <- taken_functions(tu)
    // a name two files of a program each define `static` names one function per module, which a call
    // names by its module alone: neither is substituted
    var defined : table<string>
    for (d in tu.decls) {
        if (d.k == "func" && d.body != null) {
            if (key_exists(defined, d.name)) {
                taken |> insert(d.name)
            }
            defined |> insert(d.name)
        }
    }
    var memo : table<string; bool>
    for (name, di in keys(functions), values(functions)) {
        if (is_pure_helper(tu, di, functions, taken, memo)) {
            em.prog.inline_helpers[name] = di
        }
    }
}

// whether argument `x` reads as often as it is spelled: a variable, a literal or an enumerator
// under value casts; a parameter of an enclosing helper's expansion only while what it reads as is
// one operand (`k`, `_t0`), never a sum it spells again at every read
def private plain_argument(em : Emitter; x : CirExpr const?) : bool {
    let at = below_casts(x)
    if (at == null || has_effects(x) || reads_volatile(x)) {
        return false
    }
    if (at.e == "ref" && key_exists(em.hoisted, intptr(at))) {
        return (em.hoisted?[intptr(at)] ?? Em()).prec == PREC_PRIMARY
    }
    return at.e == "ref" || at.e == "int_lit" || at.e == "float_lit" || at.e == "enum_ref"
}

// how many times the operands of `shape` read parameter `name`; the clamp's chain falls through to
// it once more when it has no bare `else`
def private parameter_reads(shape : HelperShape; name : string) : int {
    var reads = name == shape.param && shape.otherwise == null ? 1 : 0
    for (x in helper_operands(shape)) {
        each_subexpr(x) $(sub) {
            if (sub.e == "ref" && sub.name == name) {
                reads++
            }
        }
    }
    return reads
}

// every reference to parameter `name` in `x` read as `e` until `unpin` drops `keys`
def private bind_parameter(var em : Emitter; x : CirExpr const?; name : string; e : Em; var keys : array<uint64>) {
    each_subexpr(x) $(sub) {
        if (sub.e == "ref" && sub.name == name) {
            em.hoisted[intptr(sub)] = e
            keys |> push(intptr(sub))
        }
    }
}

// the clamp shape's chain over the bound parameters, `c0 ? v0 : (c1 ? v1 : p)`, each value at the
// parameter's type
def private clamp_value(var em : Emitter; tu : CirTu; shape : HelperShape; param : Em; param_t : int; loc : CirLoc) : Em {
    var guards, values : array<Em>
    guards |> reserve(length(shape.guards))
    values |> reserve(length(shape.values))
    for (guard, v in shape.guards, shape.values) {
        guards |> push(truth_of(em, tu, guard, loc))
        values |> push(stored(em, emit_expr(em, tu, v, loc), tu, param_t))
    }
    var chain = shape.otherwise != null ? stored(em, emit_expr(em, tu, shape.otherwise, loc), tu, param_t) : param
    for (idx in range(length(guards))) {
        let at = length(guards) - 1 - idx
        chain = value("{wrap(guards[at], PREC_COND + 1)} ? {wrap(values[at], PREC_COND + 1)} : {wrap(chain, PREC_COND + 1)}", PREC_COND)
    }
    return chain
}

// a direct call of a pure helper (`flag_inline_helpers`) as the helper's expression into `out`:
// each argument crosses at its parameter's type as a call's does, evaluated once, ahead, into a
// temporary when it has an effect or the body reads a non-plain one twice; false keeps the call,
// for a function that is no such helper and a site in a conditional arm that would need a temporary
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#inline-helpers")]
def private inline_helper(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc; var out : Em&) : bool {
    let name = called_name(x)
    let di = em.prog.inline_helpers?[name] ?? -1
    if (di < 0 || !em.in_body || em.in_global_init) {
        return false
    }
    let d = tu.decls[di]
    var shape : HelperShape
    if (length(d.params) != length(x.args) || !helper_shape(*d, shape)) {
        return false
    }
    let needs_temp <- [for (p, arg in d.params, x.args); has_effects(arg) || reads_volatile(arg) || (parameter_reads(shape, p.name) > 1 && !plain_argument(em, arg))]
    if (em.narrow > 0 && has_value(needs_temp, true)) {
        return false
    }
    // every argument is spelled before any parameter is bound: an argument that is itself a call of a
    // helper binds and drops that helper's parameters, which a binding made earlier would lose
    var args : array<Em>
    args |> reserve(length(x.args))
    for (arg, temp in x.args, needs_temp) {
        var e = stored(em, emit_expr(em, tu, arg, loc), tu, arg.t)
        if (temp) {
            let tmp = temp_name(em)
            em.pre |> push("let {tmp} = {e.text}")
            e = value(tmp, PREC_PRIMARY)
        }
        args |> push(e)
    }
    var keys : array<uint64>
    var chain_param : Em
    var param_t = -1
    for (p, e in d.params, args) {
        for (operand in helper_operands(shape)) {
            bind_parameter(em, operand, p.name, e, keys)
        }
        if (p.name == shape.param) {
            chain_param = e
            param_t = p.t
        }
    }
    if (!empty(shape.param)) {
        bind_parameter(em, shape.result, shape.param, clamp_value(em, tu, shape, chain_param, param_t, loc), keys)
    }
    out = stored(em, emit_expr(em, tu, shape.result, loc), tu, shape.result.t)
    unpin(em, keys)
    return true
}

// a call read for its value: a pure helper's expression under `inline_helpers`, else the call
def private call_value(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    var inlined : Em
    return inline_helper(em, tu, x, loc, inlined) ? inlined : emit_call(em, tu, x, loc)
}

// a `BitCast` is a `reinterpret`, except between two C function pointer types that spell one
// das type (they differ in a pointee's `const`), which is the value itself; the operand comes
// as its text, since a caller returning this result may hold its own operand in the result slot
def private bit_cast(var em : Emitter; tu : CirTu; x : CirExpr; text : string; prec : int; target : string; loc : CirLoc) : Em {
    if (is_function_pointer(tu, x.t) && is_function_pointer(tu, x.a.t) && das_type(em, tu, x.a.t, loc) == target) {
        return value(text, prec)
    }
    return unsafe_value(em, "reinterpret<{target}>({text})", PREC_PRIMARY)
}

def private emit_cast(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let k = x.cast_kind
    if (k == "ArrayToPointerDecay" && x.a != null && x.a.e == "str_lit") {
        return string_literal(em, tu, *x.a, loc)
    }
    if (k == "ArrayToPointerDecay") {
        let first = decay_in_place(em, tu, x, loc)
        if (!empty(first.text)) {
            return first
        }
    }
    if ((k == "IntegralCast" || k == "FloatingToIntegral") && kind_of(tu, x.t) == "enum") {
        return emit_enum_cast(em, tu, x, loc)
    }
    let inner = emit_expr(em, tu, x.a, loc)
    if (k == "LValueToRValue" || k == "NoOp" || k == "ToVoid") {
        return inner
    }
    if (k == "IntegralToBoolean" || k == "FloatingToBoolean" || k == "PointerToBoolean") {
        return to_bool(inner, tu, x.a.t)
    }
    if (k == "BooleanToSignedIntegral") {
        return to_int(em, inner)
    }
    if (k == "NullToPointer") {
        // a das function value takes no `null`; its zero is `default<T>` (probes/test_globals.das)
        return is_function_pointer(tu, x.t) ? value("default<{target_of(em, tu, x.t, loc)}>", PREC_PRIMARY) : value("null", PREC_PRIMARY)
    }
    let target = das_type(em, tu, x.t, loc)
    if (k == "IntegralCast" || k == "IntegralToFloating" || k == "FloatingToIntegral" || k == "FloatingCast") {
        return numeric_cast(em, tu, x, inner, target)
    }
    if (k == "BitCast") {
        return bit_cast(em, tu, x, inner.text, inner.prec, target, loc)
    }
    if (k == "PointerToIntegral") {
        return value("{target}(intptr({inner.text}))", PREC_PRIMARY)
    }
    if (k == "IntegralToPointer") {
        return unsafe_value(em, "reinterpret<{target}>(uint64({to_int(em, inner).text}))", PREC_PRIMARY)
    }
    if (k == "FunctionToPointerDecay") {
        // a function's name decays to its `@@` value; a function designator reached
        // through a pointer (`*fp`) is that pointer's value already
        return x.a.e == "ref" ? function_value(em, *x.a, loc) : inner
    }
    if (k == "ArrayToPointerDecay" && is_va_list(tu, x.a.t)) {
        // linux's `va_list` is a one-element array whose decay passes it by reference, which a
        // `var` cursor parameter is
        return inner
    }
    if (k == "ArrayToPointerDecay") {
        return decayed(em, tu, x, inner, loc)
    }
    fail(em, "cast `{k}` is not lowered yet", loc)
    return inner
}

// a decimal `int` literal converted to `target` as das spells it with a suffix (`0l`, `1ul`, `7u8`,
// `10.0lf`); "" for a type without one (`int8`, `int16`, `uint16`), a negative value of an unsigned
// type, a value past `uint8` or a float's exact integers, or a text that is no literal (a named
// constant, a character literal)
// `text` converted to `target`: the suffixed literal where one spells it, else the conversion
def private converted_text(text, target : string) : string {
    let literal = suffixed_literal(text, target)
    return empty(literal) ? "{target}({text})" : literal
}

// C's conversion `x` of number `inner` to the das type `target`: a bool read as a number is
// `int_of(b)`, an `int` already; an enum goes through its integer; a number das already spells as
// `target` (C's `char` and `unsigned char` both `uint8`) is itself, and a `sizeof` read as an `int`
// is das's `typeinfo sizeof`, an `int` already
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#same-type-conversions")]
def private numeric_cast(var em : Emitter; tu : CirTu; x : CirExpr; inner : Em; target : string) : Em {
    let source = to_int(em, inner)
    if (target == "bool") {
        return to_bool(source, tu, x.a.t)
    }
    if (inner.is_bool && target == "int") {
        return source
    }
    if (kind_of(tu, x.a.t) == "enum") {
        return value(enum_to_integer(tu, x.a.t, source.text, target), PREC_PRIMARY)
    }
    if (x.a.e == "enum_ref") {
        // an enumerator C reads as an integer converts directly, as its enum does
        return value(enum_to_integer(tu, x.a.enum_t, enum_item(em, tu, x.a.enum_t, x.a.item), target), PREC_PRIMARY)
    }
    if (!inner.is_bool && das_type(em, tu, x.a.t, CirLoc()) == target) {
        return inner
    }
    let sized = "{das_type(em, tu, x.a.t, CirLoc())}("
    if (target == "int" && x.a.e == "sizeof_v" && starts_with(source.text, sized)) {
        return value(slice(source.text, length(sized), length(source.text) - 1), PREC_PRIMARY)
    }
    return value(converted_text(source.text, target), PREC_PRIMARY)
}

[arch(at="ARCHITECTURE_EMITTER_TEXT.md#literal-suffixes")]
def private suffixed_literal(text, target : string) : string {
    let negative = starts_with(text, "-")
    let digits = negative ? slice(text, 1) : text
    if (!is_digit_run(digits, 0)) {
        return ""
    }
    if (target == "int64") {
        return "{text}l"
    }
    if (target == "double") {
        return "{text}.0lf"
    }
    if (target == "float") {
        // a float holds every integer to 2^24 exactly; past it the conversion stays explicit
        return to_int64(digits) <= 16777216l ? "{text}.0f" : ""
    }
    if (negative) {
        return ""
    }
    if (target == "uint64") {
        return "{text}ul"
    }
    if (target == "uint") {
        return "{text}u"
    }
    return target == "uint8" && to_int64(digits) <= 255l ? "{text}u8" : ""
}

// a decay spelled without its array's value: an array field of a marshal-only record in C memory
// (`marshal_elements`), a member at offset 0 under `first_member` `reinterpret`
// (`first_member_address`); an empty text for any other
def private decay_in_place(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em =>
    marshal_array_member(em, tu, x.a) ? marshal_elements(em, tu, *x.a, loc) : first_member_address(em, tu, x, loc)

// an array's decay to a pointer to its first element; a `jmp_buf` is one record here, not
// glibc's one-element array: its decay is its address, or the pointer a `*p` read it through
def private decayed(var em : Emitter; tu : CirTu; x : CirExpr; inner : Em; loc : CirLoc) : Em {
    if (is_jmp_buf(tu, x.a.t)) {
        return x.a.e == "un" && x.a.op == "deref" ? emit_expr(em, tu, x.a.a, loc) : unsafe_value(em, "addr({inner.text})", PREC_PRIMARY)
    }
    if (is_marshal(em, tu, element_under(tu, x.a.t))) {
        // a value's array of the record has das's layout, which is not what a byte pointer reads
        fail(em, "the decay of an array of the marshal-only record `{tag_name(em, tu, element_under(tu, x.a.t))}` held by value is not lowered yet", loc)
    }
    return unsafe_value(em, "addr({wrap(inner, PREC_PRIMARY)}[0])", PREC_PRIMARY)
}

// C's wrapping signed arithmetic: `(T) ((U) a op (U) b)`, `op` one of `+ - * & | ^`, with `T` a
// signed integer of 32 or 64 bits, `U` its unsigned twin and `a`, `b` of type `T` or a narrower
// integer (lua's `intop` of an `int` immediate), which `(U)` extends as `(T)` does; the `bin` node,
// null for any other cast. das `int` and `int64` arithmetic wraps on every tier
// (probes/test_scalars.das), so the operation is `a op T(b)` in `T`
def private wrap_pair(tu : CirTu; x : CirExpr const?) : CirExpr const? {
    if (x == null) {
        return null
    }
    return wrap_pair(tu, *x)
}

def private wrap_pair(tu : CirTu; x : CirExpr) : CirExpr const? {
    let sum = x.a
    if (x.e != "cast" || x.cast_kind != "IntegralCast" || sum == null || sum.e != "bin" || !key_exists(SELF_OPS, sum.op) || !unsigned_twin(tu, sum.t, x.t)) {
        return null
    }
    for (side in fixed_array<CirExpr const?>(sum.a, sum.b)) {
        if (side == null || side.e != "cast" || side.cast_kind != "IntegralCast" || side.a == null || !(side.a.t == x.t || narrower_integer(tu, side.a.t, x.t))) {
            return null
        }
    }
    return sum
}

// `u` is the unsigned twin of `t`, a signed integer of 32 or 64 bits that is no `_Bool`
def private unsigned_twin(tu : CirTu; u, t : int) : bool {
    if (kind_of(tu, t) != "int" || kind_of(tu, u) != "int" || is_c_bool(tu, t)) {
        return false
    }
    let w = tu.types[t].w
    return tu.types[t].is_signed && !tu.types[u].is_signed && tu.types[u].w == w && (w == 32 || w == 64)
}

// an integer type narrower than `t`, a `_Bool` included, whose value `t` holds as it is
def private narrower_integer(tu : CirTu; from, t : int) : bool => kind_of(tu, from) == "int" && tu.types[from].w < tu.types[t].w

// the wrapping operation `wrap_pair` matched, spelled in the signed type
def private emit_wrap_pair(var em : Emitter; tu : CirTu; sum : CirExpr; t : int; loc : CirLoc) : Em {
    let prec = BIN_PREC?[sum.op] ?? 0
    let lhs = wrap_operand(em, tu, sum.a, t, loc)
    let rhs = wrap_operand(em, tu, sum.b, t, loc)
    return value("{wrap(lhs, prec)} {BIN_SPELLING?[sum.op] ?? ""} {wrap(rhs, prec + 1)}", prec)
}

// one operand `(U) a` of a wrapping operation in signed type `t`: `a`, or `T(a)` for a narrower one
def private wrap_operand(var em : Emitter; tu : CirTu; side : CirExpr const?; t : int; loc : CirLoc) : Em {
    let e = to_int(em, emit_expr(em, tu, side.a, loc))
    return side.a.t == t ? e : value("{das_type(em, tu, t, loc)}({e.text})", PREC_PRIMARY)
}

// `enum_from_int(type<E>, i)` over an int-typed spelling, C's implicit int-to-enum conversion
def private int_to_enum(var em : Emitter; tu : CirTu; t : int; i : string) : string {
    em.requires |> insert("c_runtime/enum_from_int")
    return "{ENUM_FROM_INT}(type<{tag_name(em, tu, t)}>, {i})"
}

// the enumerator of enum `t` with value `v`, "" when none has it
def private enumerator_of(tu : CirTu; t : int; v : string) : string {
    for (it in tu.types[t].items) {
        if ("{it.v}" == v) {
            return it.name
        }
    }
    return ""
}

// a conversion into enum `x.t`: its own enumerator is `E.X`, a value of the same enum stays, a
// literal with an enumerator's value is that enumerator, a ternary of two of its values
// stays one; anything else is `enum_from_int` over its int value
def private emit_enum_cast(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let operand = enum_operand(tu, x.a, x.t)
    if (operand != null) {
        return enum_operand_text(em, tu, operand, loc, PREC_PRIMARY)
    }
    var arms = x.a
    while (arms != null && arms.e != "cond" && arms.e == "cast" && is_value_preserving_cast(tu, arms, tu.types[x.t].is_signed)) {
        arms = arms.a
    }
    if (arms != null && arms.e == "cond") {
        let a = enum_operand(tu, arms.a, x.t)
        let b = enum_operand(tu, arms.b, x.t)
        if (a != null && b != null) {
            // the shortcut holds only for pure arms: an arm with hoisted statements needs
            // `emit_cond`'s if-chain, which the generic path below reaches
            let mark = length(em.pre)
            let c = truth_of(em, tu, arms.c, loc)
            let a_text = enum_operand_text(em, tu, a, loc, PREC_COND + 1)
            let b_text = enum_operand_text(em, tu, b, loc, PREC_COND + 1)
            if (length(em.pre) == mark) {
                return value("{wrap(c, PREC_COND + 1)} ? {a_text.text} : {b_text.text}", PREC_COND)
            }
            em.pre |> resize(mark)
        }
    }
    if (x.a.e == "int_lit") {
        let named = enumerator_of(tu, x.t, x.a.v)
        if (!empty(named)) {
            return value(enum_item(em, tu, x.t, named), PREC_PRIMARY)
        }
    }
    let source = enum_as_int(to_int(em, emit_expr(em, tu, x.a, loc)), tu, x.a.t)
    let i = das_type(em, tu, x.a.t, loc) == "int" || kind_of(tu, x.a.t) == "enum" ? source.text : "int({source.text})"
    return value(int_to_enum(em, tu, x.t, i), PREC_PRIMARY)
}

// whether cast `x` keeps the value of an enum whose promoted type is signed or not: C's
// promotion of the enum and a widening that keeps its sign do, a narrowing or a sign change
// does not
def private is_value_preserving_cast(tu : CirTu; x : CirExpr const?; enum_signed : bool) : bool {
    if (x.cast_kind == "LValueToRValue" || x.cast_kind == "NoOp") {
        return true
    }
    if (x.cast_kind != "IntegralCast" || kind_of(tu, x.t) != "int" || tu.types[x.t].spell == "_Bool") {
        return false
    }
    let w = tu.types[x.t].w
    return tu.types[x.t].is_signed ? (w > 32 || enum_signed) : (w >= 32 && !enum_signed)
}

// the value of enum `want` under C's conversions of it: the node of that enum type, or its
// enumerator, below casts that keep its value; null for anything else
def private enum_operand(tu : CirTu; x : CirExpr?; want : int) : CirExpr const? {
    let enum_signed = tu.types[want].is_signed
    var at = x
    while (at != null && kind_of(tu, at.t) != "enum" && at.e == "cast" && is_value_preserving_cast(tu, at, enum_signed)) {
        at = at.a
    }
    if (at != null && enum_of(at) == want && (kind_of(tu, at.t) == "enum" || at.e == "enum_ref")) {
        return at
    }
    return null
}

def private enum_of(x : CirExpr const?) : int => x.e == "enum_ref" ? x.enum_t : x.t

// the enum both sides of `==`/`!=` are values of, when they are: the innermost enum node of
// the left side names it; -1 otherwise
def private common_enum(tu : CirTu; x : CirExpr?) : int {
    var at = x
    while (at != null && kind_of(tu, at.t) != "enum" && at.e == "cast") {
        at = at.a
    }
    return at != null && (kind_of(tu, at.t) == "enum" || at.e == "enum_ref") ? enum_of(at) : -1
}

// `e == E.X` for two values of one enum, which das compares directly: C converts both sides to
// an integer first, and the readable form drops the conversions (docs/lowering-examples.md)
def private enum_equality(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    let want = common_enum(tu, x.a)
    if (want < 0) {
        return ""
    }
    let lhs = enum_operand(tu, x.a, want)
    let rhs = enum_operand(tu, x.b, want)
    if (lhs == null || rhs == null) {
        return ""
    }
    let spelled = BIN_SPELLING?[x.op] ?? ""
    return "{enum_operand_text(em, tu, lhs, loc, PREC_EQ + 1).text} {spelled} {enum_operand_text(em, tu, rhs, loc, PREC_EQ + 1).text}"
}

// das's storage integers: they compare only by `==` and `!=`, against a bare literal in their range
// or a value of their own type (F106)
let private STORAGE_INTEGERS <- {"uint8", "int8", "uint16", "int16"}

// whether integer value `v` lies in the range of C integer type `t`
def private in_range(tu : CirTu; t : int; v : int64) : bool {
    let w = tu.types[t].w
    if (w >= 64) {
        return tu.types[t].is_signed || v >= 0l
    }
    let span = 1l << int64(tu.types[t].is_signed ? w - 1 : w)
    return tu.types[t].is_signed ? v >= -span && v < span : v >= 0l && v < span
}

// whether the range of C integer type `t` holds every value of integer type `from`
def private holds_range(tu : CirTu; from, t : int) : bool {
    let fw = tu.types[from].w
    let tw = tu.types[t].w
    return tu.types[from].is_signed ? tu.types[t].is_signed && tw >= fw : tw > fw || (!tu.types[t].is_signed && tw == fw)
}

// whether `x` is an integer conversion between two integer types, `_Bool` and enums apart
def private integral_step(tu : CirTu; x : CirExpr const?) : bool =>
    x.e == "cast" && x.cast_kind == "IntegralCast" && x.a != null && kind_of(tu, x.a.t) == "int" && kind_of(tu, x.t) == "int" && !is_c_bool(tu, x.a.t) && !is_c_bool(tu, x.t)

// the operand of the longest chain of integer conversions atop `x` that keep its every value (the
// promotion `int(ts.extra)`, then `unsigned` for a `5u` beside it), null when none does
def private promoted_operand(tu : CirTu; x : CirExpr const?) : CirExpr const? {
    var kept : CirExpr const?
    var at = x
    while (integral_step(tu, at)) {
        at = at.a
        var holds = true
        var step = x
        while (step != at) {
            holds = holds && holds_range(tu, at.t, step.t)
            step = step.a
        }
        if (holds) {
            kept = at
        }
    }
    return kept
}

struct private BareLiteral {
    v : int64
    text : string
}

// the value and das text of integer literal `x` below conversions that keep it: its digits, `-n`
// for a negated one of a signed type, a character's literal; an empty text for anything else, a literal a `#define`
// names included, whose name das reads as an `int`
def private bare_literal(tu : CirTu; x : CirExpr const?) : BareLiteral {
    var at = x
    var casts : array<int>
    var named = !empty(x.macro)
    while (integral_step(tu, at)) {
        casts |> push(at.t)
        at = at.a
        named ||= !empty(at.macro)
    }
    let negated = at.e == "un" && at.op == "neg" && at.a != null
    var lit = at
    if (negated) {
        lit = at.a
        named ||= !empty(lit.macro)
        if (kind_of(tu, at.t) != "int" || !tu.types[at.t].is_signed) {
            // C's `-1u` is UINT_MAX, no negative value
            return BareLiteral()
        }
    }
    let digits = lit.e == "int_lit" && !named ? lit.v : ""
    if (!is_digit_run(digits, 0) || length(digits) > 18) {
        return BareLiteral()
    }
    let v = negated ? -to_int64(digits) : to_int64(digits)
    for (t in casts) {
        if (!in_range(tu, t, v)) {
            return BareLiteral()
        }
    }
    let text = lit.is_char && !negated ? char_literal(int(v)) : "{v}"
    return BareLiteral(v = v, text = text)
}

// `==`/`!=` of a promoted storage integer against a literal in its range or a value of its das
// type, compared narrow (`ts.extra == 0`, `a == b`), exact since the promotion keeps every value;
// "" for any other
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#narrow-equality")]
def private narrow_equality(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : string {
    let lhs = promoted_operand(tu, x.a)
    let rhs = promoted_operand(tu, x.b)
    let lhs_type = lhs != null ? das_type(em, tu, lhs.t, loc) : ""
    let rhs_type = rhs != null ? das_type(em, tu, rhs.t, loc) : ""
    let spelled = BIN_SPELLING?[x.op] ?? ""
    if (key_exists(STORAGE_INTEGERS, lhs_type) && lhs_type == rhs_type) {
        let a = emit_expr(em, tu, lhs, loc)
        let b = emit_expr(em, tu, rhs, loc)
        return "{wrap(a, PREC_EQ + 1)} {spelled} {wrap(b, PREC_EQ + 1)}"
    }
    let narrow_left = key_exists(STORAGE_INTEGERS, lhs_type)
    if (!narrow_left && !key_exists(STORAGE_INTEGERS, rhs_type)) {
        return ""
    }
    let narrow = narrow_left ? lhs : rhs
    let literal = bare_literal(tu, narrow_left ? x.b : x.a)
    if (empty(literal.text) || !in_range(tu, narrow.t, literal.v)) {
        return ""
    }
    let e = wrap(emit_expr(em, tu, narrow, loc), PREC_EQ + 1)
    return narrow_left ? "{e} {spelled} {literal.text}" : "{literal.text} {spelled} {e}"
}

// an enum operand spelled symbolically: `E.X` for an enumerator, the value's own text
// otherwise, wrapped for precedence `need`
def private enum_operand_text(var em : Emitter; tu : CirTu; side : CirExpr const?; loc : CirLoc; need : int) : Em {
    if (side.e == "enum_ref") {
        return value(enum_item(em, tu, side.enum_t, side.item), PREC_PRIMARY)
    }
    let e = emit_expr(em, tu, side, loc)
    return value(wrap(e, need), PREC_PRIMARY)
}

// the das type of a cast's target, computed before the operand so neither read of `em` races
def private target_of(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string => das_type(em, tu, t, loc)

// `@@name`: a function of this unit as a value; C `main` is `c_main`; an external function has
// no das value C's type would fit, since a call table spells its calls
def private function_value(var em : Emitter; f : CirExpr; loc : CirLoc) : Em {
    if (!key_exists(em.prog.functions, f.name)) {
        fail(em, "the value of external function `{f.name}` (a pointer to a function this file does not define) is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    return value("@@{function_name(em, f.name)}", PREC_PRIMARY)
}

// whether `x` is a null pointer constant below its casts: `0` or `(void *)0` converted
def private reaches_null(x : CirExpr?) : bool {
    var at = x
    while (at != null && at.e == "cast") {
        if (at.cast_kind == "NullToPointer") {
            return true
        }
        at = at.a
    }
    return false
}

// a null function pointer: `0` converted, or a null data pointer (`NULL` as `(void *)0`) cast
def private is_null_function(tu : CirTu; x : CirExpr?) : bool =>
    x != null && x.e == "cast" && is_function_pointer(tu, x.t) && (x.cast_kind == "NullToPointer" || (x.cast_kind == "BitCast" && reaches_null(x.a)))

// `e == null` or `e != null`: a comparison with a null constant on either side of C's operator
def private null_compare(e : Em; spelled : string; prec : int) : Em => truth("{wrap(e, prec + 1)} {spelled} null", prec)

def private emit_binary(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let prec = BIN_PREC?[x.op] ?? 0
    let spelled = BIN_SPELLING?[x.op] ?? ""
    if (x.op == "land" || x.op == "lor") {
        let lhs = truth_of(em, tu, x.a, loc)
        let mark = length(em.pre)
        em.narrow++
        let rhs = truth_of(em, tu, x.b, loc)
        em.narrow--
        if (length(em.pre) == mark) {
            return truth("{wrap(lhs, prec)} {spelled}{LOGIC_MARK} {wrap(rhs, prec + 1)}", prec)
        }
        let rhs_pre <- [for (idx in range(mark, length(em.pre))); em.pre[idx]]
        em.pre |> resize(mark)
        let tmp = temp_name(em)
        hoist(em, ["var {tmp} = {lhs.text}", "if ({x.op == "land" ? tmp : "!" + tmp}) \{"])
        hoist(em, [for (stmt in rhs_pre); "    {stmt}"])
        hoist(em, ["    {tmp} = {rhs.text}", "\}"])
        return truth(tmp, PREC_PRIMARY)
    }
    if (x.op == "eq" || x.op == "ne") {
        let direct = enum_equality(em, tu, x, loc)
        if (!empty(direct)) {
            return truth(direct, prec)
        }
        let narrow = narrow_equality(em, tu, x, loc)
        if (!empty(narrow)) {
            return truth(narrow, prec)
        }
        // a function value compares with `null`, though it is not initialized from one
        if (is_null_function(tu, x.b)) {
            return null_compare(emit_expr(em, tu, x.a, loc), spelled, prec)
        }
        if (is_null_function(tu, x.a)) {
            return null_compare(emit_expr(em, tu, x.b, loc), spelled, prec)
        }
    }
    let lhs = to_int(em, emit_expr(em, tu, x.a, loc))
    var rhs = to_int(em, emit_expr(em, tu, x.b, loc))
    let pointer_lhs = kind_of(tu, x.a.t) == "ptr"
    let pointer_rhs = kind_of(tu, x.b.t) == "ptr"
    if (x.op == "lt" || x.op == "gt" || x.op == "le" || x.op == "ge") {
        if (pointer_lhs && pointer_rhs) {
            return truth("intptr({lhs.text}) {spelled} intptr({rhs.text})", prec)
        }
        return truth("{wrap(lhs, prec + 1)} {spelled}{OPERATOR_MARK} {wrap(rhs, prec + 1)}", prec)
    }
    if (x.op == "eq" || x.op == "ne") {
        if (pointer_lhs && pointer_rhs && is_data_pointer(tu, x.a.t)) {
            // das compares only pointers of one constness, and a `let` pointer's pointee is
            // const (`docs/probe-findings.md` F44): a null constant compares with `null`, any
            // other pair as addresses
            if (reaches_null(x.b)) {
                return null_compare(lhs, spelled, prec)
            }
            if (reaches_null(x.a)) {
                return null_compare(rhs, spelled, prec)
            }
            return truth("intptr({lhs.text}) {spelled} intptr({rhs.text})", prec)
        }
        return truth("{wrap(lhs, prec + 1)} {spelled}{OPERATOR_MARK} {wrap(rhs, prec + 1)}", prec)
    }
    if (x.op == "shl" || x.op == "shr") {
        rhs = shift_count(em, tu, *x.b, rhs, das_type(em, tu, x.t, loc), loc)
    }
    if (pointer_lhs || pointer_rhs) {
        return pointer_arithmetic(em, tu, x, lhs, rhs, loc)
    }
    return value("{wrap(lhs, prec)} {spelled}{OPERATOR_MARK} {wrap(rhs, prec + 1)}", prec)
}

// `p + n`, `p - n`, `p - q`: das scales a pointer step by the element and gives a difference
// in elements, as C does, as int64; a byte pointer to a marshal-only record steps and counts
// in that record's C size
def private pointer_arithmetic(var em : Emitter; tu : CirTu; x : CirExpr; lhs, rhs : Em; loc : CirLoc) : Em {
    let prec = BIN_PREC?[x.op] ?? 0
    let spelled = BIN_SPELLING?[x.op] ?? ""
    let pointer_lhs = kind_of(tu, x.a.t) == "ptr"
    let scale = marshal_pointee(em, tu, pointer_lhs ? x.a.t : x.b.t)
    if (pointer_lhs && kind_of(tu, x.b.t) == "ptr" && x.op == "sub") {
        // the subtrahend is wrapped as a right operand of `-`: `top - (base + a)` keeps its parentheses
        let operands = "{wrap(lhs, PREC_ADD)} - {wrap(rhs, PREC_ADD + 1)}"
        let diff = scale >= 0 ? "({operands}) / {type_size(tu, scale)}" : operands
        return unsafe_value(em, "{das_type(em, tu, x.t, loc)}({diff})", PREC_PRIMARY)
    }
    if (scale >= 0) {
        let count = pointer_lhs ? rhs : lhs
        let bytes = pointer_lhs ? lhs : rhs
        return unsafe_value(em, "{wrap(bytes, prec)} {spelled} {wrap(count, PREC_MUL)} * {type_size(tu, scale)}", prec)
    }
    if (pointer_lhs && x.op == "sub" && !(x.a.e == "cast" && x.a.cast_kind == "LValueToRValue")) {
        // das subtracts from a pointer variable only, so a computed pointer (`buf + k - n`) adds
        // the negated count (probes/test_pointers.das)
        let negated = is_unsigned(tu, x.b.t) ? "-int64({rhs.text})" : "-({rhs.text})"
        return unsafe_value(em, "{wrap(lhs, prec)} + {negated}", prec)
    }
    if (!pointer_lhs) {
        // das adds a count to a pointer only: `n + p` is the sum commuted, `p + n`
        return unsafe_value(em, "{wrap(rhs, prec)} + {wrap(lhs, prec + 1)}", prec)
    }
    return unsafe_value(em, "{wrap(lhs, prec)} {spelled} {wrap(rhs, prec + 1)}", prec)
}

def private emit_cond(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (kind_of(tu, x.t) == "void") {
        // `emit_effect` spells one as a statement (`void_conditional`)
        fail(em, "a `void` conditional (`c ? f() : g()`) used as a value is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    let c = truth_of(em, tu, x.c, loc)
    let mark = length(em.pre)
    em.narrow++
    if (is_data_pointer(tu, x.t) && (reaches_null(x.a) || reaches_null(x.b))) {
        // das inlines no `[inline]` call inside an arm of a `?:` whose other arm is `null`
        for (arm in fixed_array<CirExpr const?>(x.a, x.b)) {
            each_subexpr(arm) $(sub) {
                em.fold_blocked |> insert(intptr(sub))
            }
        }
    }
    var a = emit_expr(em, tu, x.a, loc)
    if (is_data_pointer(tu, x.t) && reaches_null(x.a)) {
        // das types `?:` by its first arm, and its `null` is a `void?` no other pointer takes
        // (probes/test_pointers.das): the null arm is the conditional's own pointer type
        a = value("default<{das_type(em, tu, x.t, loc)}>", PREC_PRIMARY)
    }
    let a_end = length(em.pre)
    let b = emit_expr(em, tu, x.b, loc)
    em.narrow--
    if (length(em.pre) == mark) {
        if (a.is_bool && b.is_bool) {
            return truth("{wrap(c, PREC_COND + 1)} ?{LOGIC_MARK} {wrap(a, PREC_COND + 1)} :{LOGIC_MARK} {wrap(b, PREC_COND + 1)}", PREC_COND)
        }
        return value("{wrap(c, PREC_COND + 1)} ?{LOGIC_MARK} {wrap(to_int(em, a), PREC_COND + 1)} :{LOGIC_MARK} {wrap(to_int(em, b), PREC_COND + 1)}", PREC_COND)
    }
    let a_pre <- [for (idx in range(mark, a_end)); em.pre[idx]]
    let b_pre <- [for (idx in range(a_end, length(em.pre))); em.pre[idx]]
    em.pre |> resize(mark)
    let tmp = temp_name(em)
    let spelled = das_type(em, tu, x.t, loc)
    hoist(em, ["var {tmp} : {spelled}", "if ({c.text}) \{"])
    hoist(em, [for (stmt in a_pre); "    {stmt}"])
    hoist(em, ["    {tmp} = {stored(em, a, tu, x.t).text}", "\} else \{"])
    hoist(em, [for (stmt in b_pre); "    {stmt}"])
    hoist(em, ["    {tmp} = {stored(em, b, tu, x.t).text}", "\}"])
    return value(tmp, PREC_PRIMARY)
}

// the operand of `&x`: a compound literal's object
def private address_operand(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em =>
    x.a.e == "compound_lit" ? literal_object(em, tu, *x.a, loc) : emit_expr(em, tu, x.a, loc)

[arch(at="ARCHITECTURE_EMITTER_TEXT.md#pointer-steps")]
def private emit_unary(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (x.op == "not") {
        return falsity_of(em, tu, x.a, loc)
    }
    // the step and the read of its value go through one pinned target, so an effect in the
    // target runs once
    if (x.op == "preinc" || x.op == "predec") {
        var keys : array<uint64>
        pin_lvalue(em, tu, x.a, loc, keys)
        em.pre |> push(step_line(em, tu, x, loc))
        let after = lvalue_read(em, tu, x.a, loc)
        unpin(em, keys)
        return after
    }
    if (x.op == "postinc" || x.op == "postdec") {
        var keys : array<uint64>
        pin_lvalue(em, tu, x.a, loc, keys)
        let tmp = temp_name(em)
        let before = lvalue_read(em, tu, x.a, loc)
        // a `let` copy of a value holding a pointer takes a const pointee (F3): the old value of
        // a stepped pointer that `*p++ = v` writes through is a `var`
        let keep = holds_data_pointer(tu, x.a.t) ? "var" : "let"
        // a volatile object is loaded once: the step stores from the old value's temporary
        let step = volatile_kept(em, tu, x.a) ? volatile_step(em, tu, x, x.op == "postinc", tmp, loc) : step_line(em, tu, x, loc)
        hoist(em, ["{keep} {tmp} = {before.text}", step])
        unpin(em, keys)
        return value(tmp, PREC_PRIMARY)
    }
    let direct = direct_address(em, tu, x, loc)
    if (!empty(direct.text)) {
        return direct
    }
    let indexed = pointer_sum_index(em, tu, x, loc)
    if (!empty(indexed.text)) {
        return indexed
    }
    // the arithmetic operators read a number; `&` and `*` take the operand as it is; the address
    // of a compound literal is its object's
    let operand = x.op == "addr" ? address_operand(em, tu, x, loc) : emit_expr(em, tu, x.a, loc)
    let a = x.op == "addr" || x.op == "deref" ? operand : to_int(em, operand)
    if (x.op == "neg") {
        // `--x` is das's pre-decrement: a negated operand that spells a leading `-` is parenthesized
        let inner = wrap(a, PREC_UNARY)
        return value(inner |> starts_with("-") ? "-({inner})" : "-{inner}", PREC_UNARY)
    }
    if (x.op == "plus") {
        return a
    }
    if (x.op == "bnot") {
        return value("~{wrap(a, PREC_UNARY)}", PREC_UNARY)
    }
    if (x.op == "addr") {
        // `&f` of a function is its value, not an address
        if (x.a.e == "ref" && kind_of(tu, x.a.t) == "func") {
            return function_value(em, *x.a, loc)
        }
        if (is_marshal(em, tu, x.a.t)) {
            // a value of the record has das's layout, which is not what C memory holds
            fail(em, "the address of a value of the marshal-only record `{tag_name(em, tu, x.a.t)}` is not lowered yet", loc)
        }
        return unsafe_value(em, "addr({a.text})", PREC_PRIMARY)
    }
    if (x.op == "deref") {
        if (kind_of(tu, x.t) == "func") {
            return a
        }
        if (is_marshal(em, tu, x.t)) {
            return value("{reader_name(em, tu, x.t, -1)}({a.text}, 0)", PREC_PRIMARY)
        }
        // `*p` is the node `deref(p)` is (probe F102)
        return unsafe_value(em, "*{wrap(a, PREC_UNARY)}", PREC_UNARY)
    }
    fail(em, "unary `{x.op}` is not lowered yet", loc)
    return a
}

// `&x` (`x` the `&`) spelled without `addr` of its operand: an array field of a marshal-only
// record in C memory or its element (`marshal_element_address`), one past an array's end
// (`one_past_end_address`), a member at offset 0 under `first_member` `reinterpret`
// (`first_member_address`); an empty text for any other operand
def private direct_address(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (x.op != "addr") {
        return Em()
    }
    let marshal = marshal_element_address(em, tu, x, loc)
    if (!empty(marshal.text)) {
        return marshal
    }
    let past_end = one_past_end_address(em, tu, x, loc)
    return empty(past_end.text) ? first_member_address(em, tu, x, loc) : past_end
}

// the value of a subscript that is a plain decimal literal within `int64`, -1 for any other
// subscript, a literal past `int64` (`18446744073709551615u`) included, which then takes the
// checked form
def private literal_index(i : CirExpr const?) : int64 {
    if (i == null || i.e != "int_lit" || !is_digit_run(i.v, 0)) {
        return -1l
    }
    return try_to_int64(i.v) ?? -1l
}

// the value of a subscript that is a `literal_index` or an enumerator, under integer casts each
// of which holds it (`int(E.X)`); below 0 for any other subscript or a negative enumerator
def private constant_index(tu : CirTu; i : CirExpr const?) : int64 {
    if (i != null && i.e == "cast") {
        let v = constant_index(tu, i.a)
        return v >= 0l && holds_value(tu, i.t, v) ? v : -1l
    }
    if (i != null && i.e == "enum_ref") {
        for (item in tu.types[i.enum_t].items) {
            if (item.name == i.item) {
                return item.v
            }
        }
        return -1l
    }
    return literal_index(i)
}

// whether integer type `t` (not `_Bool`) holds the value `v`, which is at least 0
def private holds_value(tu : CirTu; t : int; v : int64) : bool {
    if (kind_of(tu, t) != "int" || is_c_bool(tu, t)) {
        return false
    }
    let bits = tu.types[t].w - (tu.types[t].is_signed ? 1 : 0)
    return bits >= 63 || v < (1l << int64(bits))
}

// whether subscript `i` is a plain load: a variable or a field, under casts, read without a
// volatile access, which a spelling may repeat; a bitfield or a union member reads through an
// accessor call, so it is none
def private plain_load(tu : CirTu; i : CirExpr const?) : bool {
    var at = i
    while (at != null && (at.e == "cast" || at.e == "member")) {
        if (at.e == "member") {
            let rec = at.arrow ? tu.types[at.base.t].to : at.base.t
            if (kind_of(tu, rec) == "union" || tu.types[rec].fields[at.field].is_bitfield) {
                return false
            }
        }
        at = at.e == "cast" ? at.a : at.base
    }
    return at != null && at.e == "ref" && !is_c_bool(tu, i.t) && !reads_volatile(i)
}

// `&a[k]` of an array (`x` the `&`): C may form the address one past the end, and das
// range-checks `addr(a[N])` (`docs/probe-findings.md` F45). A constant index (`constant_index`)
// that is the length is the decayed array plus `N`; one below or past the length keeps
// `addr(a[k])`, das's range check standing for C's undefined behaviour past the end. Under
// `past_end` `inline` a plain load of an array without effects is `k == N ? addr(a[0]) + N :
// addr(a[k])`, das's own range check on every index but the length, with no call; any other
// index is the decayed array plus `end_index(k, N)` (`c_runtime/c_bounds`), which spells the
// index once. In a global initializer
// the decay and the sum each wrap themselves (F48). An empty text for any other operand.
def private one_past_end_address(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let at = x.a
    if (x.op != "addr" || at.e != "index" || at.base.e != "cast" || at.base.cast_kind != "ArrayToPointerDecay" || kind_of(tu, at.base.a.t) != "array" || at.base.a.e == "str_lit" || !empty(unchecked_access(em, tu, at.base.a))) {
        return Em()
    }
    let count = tu.types[at.base.a.t].count
    let k = constant_index(tu, at.i)
    if (count <= 0 || (k >= 0l && k != int64(count))) {
        return Em()
    }
    let arr = emit_expr(em, tu, at.base.a, loc)
    let decay = unsafe_value(em, "addr({wrap(arr, PREC_PRIMARY)}[0])", PREC_PRIMARY)
    let index = index_value(em, tu, at.i, loc)
    if (k >= 0l) {
        // an enumerator keeps its name
        let offset = below_casts(at.i).e == "enum_ref" ? index.text : "{count}"
        return unsafe_value(em, "{decay.text} + {offset}", PREC_ADD)
    }
    if (em.prog.past_end_inline && plain_load(tu, at.i) && !has_effects(at.base.a) && !reads_volatile(at.base.a)) {
        let length = int_literal(index_type(em, tu, at.i, loc), "{count}")
        let element = unsafe_value(em, "addr({wrap(arr, PREC_PRIMARY)}[{index.text}])", PREC_PRIMARY)
        return value("{index.text} == {length} ? {decay.text} + {count} : {element.text}", PREC_COND)
    }
    em.requires |> insert("c_runtime/c_bounds")
    return unsafe_value(em, "{decay.text} + {END_INDEX}({index.text}, {count})", PREC_ADD)
}

//! The das text of expression `x`; a `_Bool` expression is a das `bool` (`is_bool`), so a truth
//! test takes it as it is and a sink that wants a number spells `b ? 1 : 0`.
def emit_expr(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    if (x != null && key_exists(em.hoisted, intptr(x))) {
        return em.hoisted?[intptr(x)] ?? Em()
    }
    var folded : Em
    let loaded = x != null && x.e == "cast" && x.cast_kind == "LValueToRValue" && x.a != null && !empty(x.a.fn_macro) && !x.a.vol
    let whole = x != null && !empty(x.fn_macro) && !is_lvalue(x) && kind_of(tu, x.t) != "void"
    if ((loaded && fold_macro(em, tu, x.a, x, null, "value", loc, folded)) || (whole && fold_macro(em, tu, x, x, null, "value", loc, folded))) {
        return folded
    }
    var e = emit_node(em, tu, x, loc)
    if (x != null && !empty(x.macro) && em.in_body && is_constant_tree(tu, x)) {
        e = named_constant(em, x.macro, e)
    }
    if (x != null && is_c_bool(tu, x.t)) {
        e.is_bool = true
    }
    if (x != null && x.paren) {
        e.paren = true
    }
    return e
}

// an lvalue expression, whose expansion a def can only read: the load of it folds, a store into it,
// its address and its field stay expanded
def private is_lvalue(x : CirExpr const?) : bool => x.e == "ref" || x.e == "member" || x.e == "index" || (x.e == "un" && x.op == "deref")

// one text of a folded macro's def, the part after its parameters, and the das types of the
// parameters it was spelled for, one signature per line-joined list ("" an argument with no copy)
struct MacroVariant {
    text : string
    sigs : array<string>
}

//! A function-like macro the module prints as `[c_macro] def`s: its das name, the comment above it,
//! its parameters (`var` where a copy holds a pointer the body needs writable, `ref` where the body
//! writes a caller's local through it), whether a body needs `[c_function]`, and its texts.
struct MacroDef {
    name : string
    comment : string
    params : array<string>
    modes : array<string>
    c_function : bool
    variants : array<MacroVariant>
}

// an identifier byte: a letter, a digit or `_`
def private ident_byte(c : int) : bool => is_alpha(c) || is_number(c) || c == '_'

// whether `text` spells identifier `name` as a whole token
def private names_token(text, name : string) : bool {
    var found = false
    peek_data(text) $(b) {
        var at = find(text, name)
        while (at >= 0 && !found) {
            let stop = at + length(name)
            found = (at == 0 || !ident_byte(int(b[at - 1]))) && (stop >= length(b) || !ident_byte(int(b[stop])))
            at = find(text, name, at + 1)
        }
    }
    return found
}

// a name the program, das or the runtime already gives a function, global or type, which a def
// named like it would shadow or overload
def private name_taken(var em : Emitter; tu : CirTu; name : string) : bool {
    if (empty(em.prog.taken_names)) {
        for (n in reserved_das_names()) {
            em.prog.taken_names |> insert(n)
        }
        for (d in tu.decls) {
            em.prog.taken_names |> insert(d.name)
        }
        for (t in tu.types) {
            em.prog.taken_names |> insert(t.name)
        }
        program_for_each_registered_module() $(mod) {
            module_for_each_function(mod) $(info) {
                em.prog.taken_names |> insert(info.name)
            }
            for_each_generic(mod) $(fn) {
                em.prog.taken_names |> insert(string(fn.name))
            }
        }
    }
    return key_exists(em.prog.taken_names, name) || key_exists(DAS_KEYWORDS, name) || key_exists(em.constants, name)
}

// the das name of macro `m`'s defs in the module: the macro's own, `<name>_m` where a function,
// global, type or keyword takes it, numbered past another macro of the module of that name (an
// `#undef` and a new `#define`)
def private macro_def_name(var em : Emitter; tu : CirTu; m : int) : string {
    let have = em.macro_names?[m] ?? ""
    if (!empty(have)) {
        return have
    }
    let raw = reserved_rename(tu.macros[m].name)
    let base = name_taken(em, tu, raw) ? "{raw}_m" : raw
    var name = base
    var n = 2
    while (key_exists(em.macro_defs, name)) {
        name = "{base}_{n}"
        n++
    }
    em.macro_names[m] = name
    return name
}

let private POISON = "\x01"

// the spelling state a def body replaces and the caller's comes back to
struct private SavedSpelling {
    pre : array<string>
    out : array<string>
    hoisted : table<uint64; Em>
    fold_seeds : table<uint64>
    spelled : table<string>
    literal_decls : array<string>
    depth : int
    temp_counter : int
    unsafe_used : bool
    comment_file : string
    literal_counter : int
    narrow : int
    case_depth : int
    error : string
}

def private save_spelling(var em : Emitter) : SavedSpelling {
    var s = SavedSpelling(depth = em.depth, temp_counter = em.temp_counter, unsafe_used = em.unsafe_used, comment_file = em.comment_file, literal_counter = em.literal_counter, narrow = em.narrow, case_depth = em.case_depth, error = em.error)
    s.pre <- em.pre
    s.out <- em.out
    s.hoisted <- em.hoisted
    s.fold_seeds <- em.fold_seeds
    s.spelled <- em.spelled
    s.literal_decls <- em.literal_decls
    return <- s
}

def private restore_spelling(var em : Emitter; var s : SavedSpelling) {
    // a move leaves its target's old storage to whoever frees it: the def body's is freed here
    delete em.pre
    delete em.out
    delete em.hoisted
    delete em.fold_seeds
    delete em.spelled
    delete em.literal_decls
    em.pre <- s.pre
    em.out <- s.out
    em.hoisted <- s.hoisted
    em.fold_seeds <- s.fold_seeds
    em.spelled <- s.spelled
    em.literal_decls <- s.literal_decls
    em.depth = s.depth
    em.temp_counter = s.temp_counter
    em.unsafe_used = s.unsafe_used
    em.comment_file = s.comment_file
    em.literal_counter = s.literal_counter
    em.narrow = s.narrow
    em.case_depth = s.case_depth
    em.error = s.error
}

// every copy of argument `k` of `site` spelled as parameter `params[k]` while a def body is spelled,
// every node inside a copy as the marker that refuses the def; the names of the caller's locals
// the copies read
def private seed_parameters(var em : Emitter; site : FoldSite; params : array<string>; args : array<Em>) : array<string> {
    var caller_names : array<string>
    for (k, copies in count(), site.copies) {
        em.spelled |> insert(params[k])
        for (c in copies) {
            em.hoisted[intptr(c)] = Em(text = params[k], prec = PREC_PRIMARY, is_bool = args[k].is_bool)
            em.fold_seeds |> insert(intptr(c))
            each_subexpr(c) $(sub) {
                if (sub != c) {
                    em.hoisted[intptr(sub)] = Em(text = POISON, prec = PREC_PRIMARY)
                    em.fold_seeds |> insert(intptr(sub))
                }
                if (sub.e == "ref" && key_exists(em.fold_scope.locals, sub.name)) {
                    caller_names |> push(das_name(em, sub.name))
                }
            }
        }
    }
    return <- caller_names
}

// the body of a def as the expanded C reads it: the value's text for `kind` "value", its
// statements in `em.out` and `em.pre`
def private spell_expansion(var em : Emitter; tu : CirTu; x, spelled : CirExpr const?; st : CirStmt const?; kind : string; loc : CirLoc; var is_bool : bool&) : string {
    if (kind == "value") {
        let e = emit_expr(em, tu, spelled, loc)
        is_bool = e.is_bool
        return e.text
    }
    if (kind == "effect") {
        emit_effect(em, tu, unsafe(reinterpret<CirExpr?>(x)), loc)
    } elif (st.s == "do") {
        collect_spelled_names(st, em.spelled)
        emit_body(em, tu, st.body_s)
    } else {
        collect_spelled_names(st, em.spelled)
        emit_body(em, tu, st)
    }
    return ""
}

// the def's text after its parameters from the body's statements and its value `result`; a
// pointer result names its type, since das types a bare `null` as `void?`
def private def_text(var em : Emitter; tu : CirTu; spelled : CirExpr const?; kind, result : string; loc : CirLoc) : string {
    var inscope lines <- [for (l in em.out); l]
    lines |> push_from([for (l in em.pre); "    {l}\n"])
    let ret = kind == "value" && is_data_pointer(tu, spelled.t) ? " : {das_type(em, tu, spelled.t, loc)}" : ""
    if (empty(lines)) {
        return kind == "value" ? "{ret} => {result}" : ""
    }
    if (kind == "value") {
        lines |> push("    return {result}\n")
    }
    return "{ret} \{\n{join(lines, "")}\}"
}

// whether def text `text` reads only its parameters: no marker of an argument's inside, every
// parameter with copies named (a literal shift count spelled in would read as an ignored argument),
// no caller's local but one a parameter of its name takes as it is
def private reads_parameters(text : string; site : FoldSite; params : array<string>; args : array<Em>; caller_names : array<string>) : bool {
    if (empty(text) || find(text, POISON) >= 0) {
        return false
    }
    for (k, copies in count(), site.copies) {
        if (!empty(copies) && !names_token(text, params[k])) {
            return false
        }
    }
    for (name in caller_names) {
        var inscope same <- [for (p, a in params, args); p == name && a.text == name]
        if (!has_value(same, true) && names_token(text, name)) {
            return false
        }
    }
    return true
}

// the def text of expansion `site` at `level` of node `x` (an expression read for its value or its
// effect, `spelled` the node read) or `st` (a statement macro): each copy of argument `k` spelled as
// parameter `params[k]`, the chain's next level free to fold inside; "" when the text reads more
// than its parameters (`reads_parameters`) or needs a declaration before the statement
def private spell_macro_body(var em : Emitter; tu : CirTu; x, spelled : CirExpr const?; st : CirStmt const?; level : int; site : FoldSite; params : array<string>; args : array<Em>; kind : string; loc : CirLoc; var is_bool : bool&; var c_function : bool&; var no_op : bool&; var statements : bool&) : string {
    var inscope saved <- save_spelling(em)
    em.depth = 1
    em.temp_counter = 0
    em.unsafe_used = false
    em.comment_file = ""
    em.literal_counter = 0
    em.narrow = 0
    em.case_depth = 0
    em.def_depth++
    var inscope caller_names <- seed_parameters(em, site, params, args)
    if (x != null) {
        each_subexpr(x) $(sub) {
            if (sub.e == "ref") {
                em.spelled |> insert(das_name(em, sub.name))
            }
        }
    }
    let node = x != null ? intptr(x) : intptr(st)
    let had = em.fold_levels?[node] ?? 0
    em.fold_levels[node] = level + 1
    let result = spell_expansion(em, tu, x, spelled, st, kind, loc, is_bool)
    em.fold_levels[node] = had
    em.def_depth--
    statements = !empty(em.out) || !empty(em.pre)
    let text = def_text(em, tu, spelled, kind, result, loc)
    no_op = kind != "value" && empty(text)
    let clean = empty(em.error) && empty(em.literal_decls) && reads_parameters(text, site, params, args, caller_names)
    c_function = em.unsafe_used
    restore_spelling(em, saved)
    return clean ? text : ""
}

// the das type an argument crosses at, the signature of an overload: a truth value's `bool`, else
// its C type's; "" for an argument with no copy, which stays generic
def private argument_type(var em : Emitter; tu : CirTu; site : FoldSite; args : array<Em>; k : int; loc : CirLoc) : string {
    if (empty(site.copies[k])) {
        return ""
    }
    let t = args[k].is_bool ? "bool" : das_type(em, tu, site.copies[k][0].t, loc)
    return site.refs[k] ? "{t}&" : t
}

// `text` as a variant of def `md` for signature `sig`: false when another of its texts takes the
// signature, since two overloads cannot share one
def private take_variant(var md : MacroDef; text : string; sig : string) : bool {
    var at = -1
    for (idx, v in count(), md.variants) {
        if (v.text == text) {
            at = idx
        } elif (has_value(v.sigs, sig)) {
            return false
        }
    }
    if (at < 0) {
        at = length(md.variants)
        md.variants |> emplace(MacroVariant(text = text))
    }
    if (!has_value(md.variants[at].sigs, sig)) {
        md.variants[at].sigs |> push(sig)
    }
    return true
}

// one expansion site's verdict counted once, at the function's level: `folded` or the reason it
// stays expanded
def private count_fold(var em : Emitter; site : int; reason : string) {
    if (em.def_depth == 0 && !key_exists(em.fold_counted, site)) {
        em.fold_counted |> insert(site)
        em.fold_counts[empty(reason) ? "folded" : reason]++
    }
}

// the arguments of `use` spelled in the caller, each from its first copy; one with no copy is its
// text, a decimal literal or a local's name (`fold_expr_site`)
def private fold_arguments(var em : Emitter; tu : CirTu; site : FoldSite; use : CirMacroUse; loc : CirLoc) : array<Em> {
    var args : array<Em>
    args |> reserve(length(site.copies))
    for (k, copies in count(), site.copies) {
        if (!empty(copies)) {
            args |> push(emit_expr(em, tu, copies[0], loc))
        } else {
            args |> push(value(is_number(first_character(use.args[k])) ? use.args[k] : das_name(em, use.args[k]), PREC_PRIMARY))
        }
    }
    return <- args
}

// the def of macro `m` (index `mi`) the module prints under `name`, made on its first fold: a
// parameter is `ref` where the body writes a caller's local through it, `var` where its argument
// carries a pointer and some fold's body needs it writable (`needs`, `var_parameters`), a later
// fold's need making it `var` too
def private macro_def_of(var em : Emitter; tu : CirTu; name : string; m : CirMacro; mi : int; site : FoldSite; needs : array<bool>) {
    var inscope modes <- [for (copies, by_ref, need in site.copies, site.refs, needs); by_ref ? "ref" : need && !empty(copies) && is_var_parameter(tu, copies[0].t) ? "var" : ""]
    if (!key_exists(em.macro_defs, name)) {
        em.macro_def_order |> push(name)
        em.macro_defs[name] = MacroDef(name = name, comment = "// {base_name(m.file)}:{m.line}: {m.text}", params <- [for (p in m.params); reserved_rename(p)], modes <- modes)
    } else {
        em.macro_defs |> get(name) $(var md) {
            for (k, mode in count(), modes) {
                if (mode == "var" && empty(md.modes[k])) {
                    md.modes[k] = "var"
                }
            }
        }
    }
    em.macro_defs |> get(name) $(md) {
        em.macro_var[mi] <- [for (mode in md.modes); mode == "var"]
    }
}

// the parameters of macro `m` the fold of `use` needs `var` (`var_parameters`), none for a site
// whose text is not taken
def private site_var_needs(em : Emitter; tu : CirTu; m : CirMacro; use : CirMacroUse; x : CirExpr const?; st : CirStmt const?; kind : string; usable : bool) : array<bool> {
    if (usable) {
        return <- var_parameters(m, use, x, kind == "value", st, em.macro_var) $(t) => is_var_parameter(tu, t)
    }
    var none : array<bool>
    none |> resize(length(m.params))
    return <- none
}

// expansion `use` at `level` of node `x` or `st` folded as a call when its verdict and its body
// allow (`fold_macro`); false with the caller's statement state as it was
def private fold_level(var em : Emitter; tu : CirTu; x, spelled : CirExpr const?; st : CirStmt const?; use : CirMacroUse; level : int; kind : string; loc : CirLoc; var call : Em&) : bool {
    if (use.m < 0 || use.m >= length(tu.macros)) {
        return false
    }
    assume m = tu.macros[use.m]
    let site <- x != null ? fold_expr_site(m, use, x, em.fold_scope) : fold_stmt_site(m, use, st, em.fold_scope)
    if (!empty(site.reason)) {
        count_fold(em, use.site, site.reason)
        return false
    }
    let pre_at = length(em.pre)
    let temp_at = em.temp_counter
    var inscope hoisted_at := em.hoisted
    let unsafe_before = em.unsafe_used
    var inscope args <- fold_arguments(em, tu, site, use, loc)
    let name = macro_def_name(em, tu, use.m)
    var inscope params <- [for (p in m.params); reserved_rename(p)]
    var is_bool, c_function, no_op, statements : bool
    let text = spell_macro_body(em, tu, x, spelled, st, level, site, params, args, kind, loc, is_bool, c_function, no_op, statements)
    // a value returned after statements has no `[c_macro]` shape: the site stays expanded
    let returns = kind == "value" && statements
    let usable = !empty(text) && !returns
    var inscope needs <- site_var_needs(em, tu, m, use, x, st, kind, usable)
    macro_def_of(em, tu, name, m, use.m, site, needs)
    let sig = join([for (k in range(length(params))); argument_type(em, tu, site, args, k, loc)], "\n")
    var taken = false
    em.macro_defs |> get(name) $(var md) {
        taken = usable && take_variant(md, text, sig)
        md.c_function ||= taken && c_function
    }
    if (!taken) {
        em.pre |> resize(pre_at)
        em.temp_counter = temp_at
        delete em.hoisted
        em.hoisted <- hoisted_at
        em.unsafe_used = unsafe_before
        // a body that spells nothing (`lua_assert`'s `((void)0)`) is a no-op, never folded
        count_fold(em, use.site, no_op ? "never" : empty(text) ? "spelling" : returns ? "statements" : "overload")
        return false
    }
    count_fold(em, use.site, "")
    em.requires |> insert("c_runtime/c_macro")
    call = Em(text = "{name}({join([for (a in args); a.text], LIST_SEPARATOR)})", prec = PREC_PRIMARY, is_bool = is_bool)
    return true
}

// expansion node `x` (an expression read for its value or its effect, `spelled` the node read: its
// load for an lvalue) or `st` (a statement macro) as a call of its macro's `[c_macro] def`, at the
// first level of its chain that folds; false leaves it to the expanded spelling, with the caller's
// statement state as it was
[arch(at="ARCHITECTURE_EMITTER_MACROS.md#fold-emission")]
def private fold_macro(var em : Emitter; tu : CirTu; x, spelled : CirExpr const?; st : CirStmt const?; kind : string; loc : CirLoc; var call : Em&) : bool {
    if (!em.in_body || em.in_global_init) {
        return false
    }
    let node = x != null ? intptr(x) : intptr(st)
    let first = em.fold_levels?[node] ?? 0
    var inscope uses : array<CirMacroUse>
    if (x != null) {
        uses := x.fn_macro
    } else {
        uses := st.fn_macro
    }
    if (em.fold_function_off) {
        if (first < length(uses)) {
            count_fold(em, uses[first].site, "labels")
        }
        return false
    }
    let blocked = x != null && (key_exists(em.fold_blocked, node) || key_exists(em.fold_blocked, intptr(spelled)))
    for (level in range(first, length(uses))) {
        if (blocked) {
            count_fold(em, uses[level].site, "ternary")
        } elif (fold_level(em, tu, x, spelled, st, uses[level], level, kind, loc, call)) {
            return true
        }
    }
    return false
}

// the module's `[c_macro]` defs of its folded macros, in first-use order: one generic def per macro
// spelled one way, else one typed overload per signature of each text
[arch(at="ARCHITECTURE_EMITTER_MACROS.md#fold-emission")]
def private macro_def_text(em : Emitter) : string {
    var parts : array<string>
    for (name in em.macro_def_order) {
        em.macro_defs |> get(name) $(md) {
            var inscope annotations <- ["c_macro"]
            if (md.c_function) {
                annotations |> push("c_function")
            }
            if (em.prog.unchecked) {
                annotations |> push_from(UNCHECKED_ANNOTATIONS)
            }
            let head = "{md.comment}\n[{join(annotations, ", ")}]\ndef private {md.name}"
            let generic = length(md.variants) == 1
            for (v in md.variants) {
                for (sig in v.sigs) {
                    var inscope types <- split(sig, "\n")
                    var inscope typed <- [for (p, t, mode in md.params, types, md.modes); "{empty(mode) ? "" : "var "}{p}{empty(t) ? "" : generic ? (mode == "ref" ? " : auto&" : "") : " : " + t}"]
                    parts |> push("{head}({join(typed, PARAMETER_SEPARATOR)}){v.text}\n\n")
                    break if (generic)
                }
            }
        }
    }
    return join(parts, "")
}

// whether `x` is a numeric constant das can hold in a module `let`: literals, enumerators, sizeof
// and alignof under arithmetic, bitwise and numeric conversions
def private is_constant_tree(tu : CirTu; x : CirExpr const?) : bool {
    if (x == null || (kind_of(tu, x.t) != "int" && kind_of(tu, x.t) != "float") || is_c_bool(tu, x.t)) {
        return false
    }
    if (x.e == "int_lit" || x.e == "float_lit" || x.e == "enum_ref" || x.e == "sizeof_v" || x.e == "alignof_v") {
        return true
    }
    if (x.e == "cast") {
        return key_exists(CONSTANT_CASTS, x.cast_kind) && is_constant_tree(tu, x.a)
    }
    if (x.e == "un") {
        return (x.op == "neg" || x.op == "plus" || x.op == "bnot") && is_constant_tree(tu, x.a)
    }
    return x.e == "bin" && key_exists(CONSTANT_OPS, x.op) && is_constant_tree(tu, x.a) && is_constant_tree(tu, x.b)
}

let private CONSTANT_CASTS <- {"IntegralCast", "NoOp", "IntegralToFloating", "FloatingCast", "FloatingToIntegral"}
let private CONSTANT_OPS <- {"add", "sub", "mul", "div", "rem", "shl", "shr", "band", "bor", "bxor"}

// the `#define` constant `macro` in place of its value `e`: the module's `let` of that name holds
// the value spelled at the first use; a use spelling another value (the macro redefined, or its
// type another) keeps the value
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#constant-names")]
def private named_constant(var em : Emitter; macro : string; e : Em) : Em {
    let name = reserved_rename(macro)
    if (builtin_global(em, name)) {
        return e
    }
    let have = em.constants?[name] ?? ""
    if (empty(have)) {
        em.constants[name] = e.text
        em.constant_order |> push(name)
    } elif (have != e.text) {
        return e
    }
    return Em(text = name, prec = PREC_PRIMARY, is_bool = e.is_bool)
}

// whether a builtin module holds a global named `name` (`math`'s `PI`, `$`'s `INT_MAX`), which a
// module `let` of the name would make ambiguous
def private builtin_global(var em : Emitter; name : string) : bool {
    if (!key_exists(em.builtin_globals, name)) {
        var found = false
        program_for_each_registered_module() $(mod) {
            found = found || find_variable(mod, name) != null
        }
        em.builtin_globals[name] = found
    }
    return em.builtin_globals?[name] ?? false
}

// the module's `let` of each `#define` constant its functions name, in first-use order
def private constant_lets(em : Emitter) : string {
    let lets = join([for (idx in range(length(em.constant_order))); "let private {em.constant_order[idx]} = {em.constants?[em.constant_order[idx]] ?? ""}\n"], "")
    return empty(lets) ? "" : lets + "\n"
}

// a cast: the read of a volatile object, C's wrapping signed sum, or the cast table
def private emit_cast_node(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    if (x.cast_kind == "LValueToRValue" && volatile_kept(em, tu, x.a)) {
        return volatile_load(em, tu, x.a, loc)
    }
    let offset = null_offset_cast(em, tu, *x, loc)
    if (!empty(offset.text)) {
        return offset
    }
    let wrapped = wrap_pair(tu, x)
    return wrapped != null ? emit_wrap_pair(em, tu, *wrapped, x.t, loc) : emit_cast(em, tu, *x, loc)
}

def private emit_node(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    if (x == null) {
        fail(em, "missing expression", loc)
        return value("", PREC_PRIMARY)
    }
    if (x.e == "int_lit" || x.e == "float_lit") {
        return literal(em, tu, *x, loc)
    }
    if (x.e == "str_lit") {
        fail(em, "a string literal outside a pointer context is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    if ((x.e == "member" || x.e == "index" || (x.e == "un" && x.op == "addr")) && null_rooted(x)) {
        // `null_offset_cast` folds the one shape C defines by practice, the offset as an integer
        fail(em, "a member of a null pointer constant (`((T *)0)->f`) is lowered only as the offset idiom, its address cast to an integer", loc)
        return value("", PREC_PRIMARY)
    }
    if (x.e == "ref") {
        return emit_ref(em, tu, *x, loc)
    }
    if (x.e == "enum_ref") {
        // an enumerator is an integer in C (`unsigned int` when one of its enum exceeds
        // INT_MAX); `emit_enum_cast` and `enum_equality` keep it symbolic
        let as_type = das_type(em, tu, x.t, loc)
        return value(enum_to_integer(tu, x.enum_t, enum_item(em, tu, x.enum_t, x.item), as_type), PREC_PRIMARY)
    }
    if (x.e == "cast" && x.cast_kind == "ArrayToPointerDecay" && unchecked_access(em, tu, x.a) == "flexible") {
        return flexible_pointer(em, tu, x.a, loc)
    }
    if (x.e == "cast") {
        return emit_cast_node(em, tu, x, loc)
    }
    if (x.e == "un") {
        return emit_unary(em, tu, *x, loc)
    }
    if (x.e == "bin") {
        return emit_binary(em, tu, *x, loc)
    }
    if (x.e == "assign") {
        // the store and the read of the stored value go through one pinned target
        var keys : array<uint64>
        pin_lvalue(em, tu, x.a, loc, keys)
        em.pre |> push(assignment_line(em, tu, *x, loc))
        let stored_value = lvalue_read(em, tu, x.a, loc)
        unpin(em, keys)
        return stored_value
    }
    if (x.e == "cond") {
        return emit_cond(em, tu, *x, loc)
    }
    if (x.e == "comma") {
        emit_effect(em, tu, x.a, loc)
        return emit_expr(em, tu, x.b, loc)
    }
    if (x.e == "call") {
        return call_value(em, tu, *x, loc)
    }
    if (x.e == "member") {
        return emit_member(em, tu, *x, loc)
    }
    if (x.e == "init_list") {
        return emit_init_list(em, tu, *x, loc)
    }
    if (x.e == "compound_lit") {
        return emit_compound_literal(em, tu, *x, loc)
    }
    if (x.e == "index") {
        return emit_index(em, tu, *x, loc)
    }
    if (key_exists(TYPE_OPERATORS, x.e)) {
        return emit_type_operator(em, tu, x, loc)
    }
    fail(em, "expression `{x.e}` is not lowered yet", loc)
    return value("", PREC_PRIMARY)
}

let TYPE_OPERATORS <- {"sizeof_v", "alignof_v", "offsetof", "va_arg"}

// the expressions C spells as operators over a type: `sizeof`, `_Alignof`, `offsetof`, `va_arg`
def private emit_type_operator(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    if (x.e == "alignof_v") {
        if (is_marshal(em, tu, x.of_t) || is_va_list(tu, x.of_t) || natural_align(tu, em.prog.layout, x.of_t) != int(x.trait_v)) {
            // das aligns the type below clang (a record's bitfield units, F5), or never lays it out
            return value("{das_type(em, tu, x.t, loc)}({int64(x.trait_v)})", PREC_PRIMARY)
        }
        return value("{das_type(em, tu, x.t, loc)}(typeinfo alignof(type<{das_type(em, tu, x.of_t, loc)}>))", PREC_PRIMARY)
    }
    if (x.e == "sizeof_v") {
        if (is_marshal(em, tu, element_under(tu, x.of_t)) || is_va_list(tu, x.of_t)) {
            // the record's bytes, an array of them included, are laid out by clang, not by das; a
            // `va_list` is never laid out
            return value("{das_type(em, tu, x.t, loc)}({type_size(tu, x.of_t)})", PREC_PRIMARY)
        }
        return value("{das_type(em, tu, x.t, loc)}(typeinfo sizeof(type<{das_type(em, tu, x.of_t, loc)}>))", PREC_PRIMARY)
    }
    if (x.e == "offsetof") {
        if (kind_of(tu, x.of_t) == "union") {
            // a union's members are operators over one storage at 0
            return value("{das_type(em, tu, x.t, loc)}(0)", PREC_PRIMARY)
        }
        if (is_marshal(em, tu, x.of_t)) {
            // the record's bytes are laid out by clang, not by das
            return value("{das_type(em, tu, x.t, loc)}({tu.types[x.of_t].fields[x.field].off})", PREC_PRIMARY)
        }
        return value("{das_type(em, tu, x.t, loc)}(typeinfo offsetof<{field_name(em, tu, x.of_t, x.field)}>(type<{das_type(em, tu, x.of_t, loc)}>))", PREC_PRIMARY)
    }
    return emit_va_arg(em, tu, *x, loc)
}

// a byte offset into a record: `k` its constant part, `terms` the das ones, an `int` field
// offset or an `int64` element step
struct private NullOffset {
    k : int64
    terms : array<string>
}

// the offset as one das integer: a lone term as it is, a sum in `int64`
def private offset_text(offset : NullOffset) : string {
    if (empty(offset.terms)) {
        return "{offset.k}"
    }
    if (length(offset.terms) == 1 && offset.k == 0l) {
        return offset.terms[0]
    }
    var parts <- [for (term in offset.terms); term |> starts_with("typeinfo") ? "int64({term})" : term]
    if (offset.k != 0l) {
        parts |> push("{offset.k}l")
    }
    return join(parts, " + ")
}

// the offset of field `field` of record `rec` added to `offset`: a union's members are operators
// over one storage at 0, a marshal-only record's fields lie where clang puts them, a natural
// record's where das does, which is clang's (the layout law)
def private add_field_offset(var em : Emitter; tu : CirTu; rec, field : int; loc : CirLoc; var offset : NullOffset) {
    if (kind_of(tu, rec) == "union") {
        return
    }
    if (is_marshal(em, tu, rec)) {
        offset.k += int64(tu.types[rec].fields[field].off)
        return
    }
    offset.terms |> push("typeinfo offsetof<{field_name(em, tu, rec, field)}>(type<{das_type(em, tu, rec, loc)}>)")
}

// the byte offset C's `&((T *)0)->f...` names, `x` the `&`'s operand: a member chain (`.f`,
// `[i]` of an array) from a member of a null pointer constant cast to a record pointer; true with
// the offset in `offset` and whether a marshal-only record holds it in `marshal`, false for any
// other lvalue
def private null_offset(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc; var offset : NullOffset; var marshal : bool&) : bool {
    if (x == null) {
        return false
    }
    if (x.e == "member" && x.arrow) {
        if (!(reaches_null(x.base) && kind_of(tu, x.base.t) == "ptr")) {
            return false
        }
        let rec = tu.types[x.base.t].to
        marshal = is_marshal(em, tu, rec)
        add_field_offset(em, tu, rec, x.field, loc, offset)
        return true
    }
    if (x.e == "member") {
        if (!null_offset(em, tu, x.base, loc, offset, marshal)) {
            return false
        }
        add_field_offset(em, tu, x.base.t, x.field, loc, offset)
        return true
    }
    let decay = x.e == "index" ? x.base : null
    if (decay == null || decay.e != "cast" || decay.cast_kind != "ArrayToPointerDecay" || kind_of(tu, decay.a.t) != "array" || !null_offset(em, tu, decay.a, loc, offset, marshal)) {
        return false
    }
    // an element lies `i` elements in: C's size in marshal memory, das's (clang's) elsewhere
    let elem = tu.types[decay.a.t].elem
    let k = literal_index(x.i)
    if (marshal && k >= 0l) {
        offset.k += k * type_size(tu, elem)
        return true
    }
    let size = marshal ? "{type_size(tu, elem)}l" : "int64(typeinfo sizeof(type<{das_type(em, tu, elem, loc)}>))"
    let count = k >= 0l ? "{k}l" : "int64({index_value(em, tu, x.i, loc).text})"
    offset.terms |> push("{count} * {size}")
    return true
}

// `(integer)&((T *)0)->f...`, the offset idiom, `x` the cast: the offset as an integer of the
// cast's type, never a load through null; an empty text for any other cast
def private null_offset_cast(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    if (x.cast_kind != "PointerToIntegral" || x.a == null || x.a.e != "un" || x.a.op != "addr") {
        return Em()
    }
    var offset = NullOffset()
    var marshal = false
    if (!null_offset(em, tu, x.a.a, loc, offset, marshal)) {
        return Em()
    }
    return value("{das_type(em, tu, x.t, loc)}({offset_text(offset)})", PREC_PRIMARY)
}

// whether `x`, a member, an index or an `&`, reaches a member of a null pointer constant
// (`((T *)0)->f`) through its member chain
def private null_rooted(x : CirExpr const?) : bool {
    var at = x
    while (at != null) {
        if (at.e == "member" && at.arrow) {
            return reaches_null(at.base)
        }
        if (at.e == "member" || at.e == "index") {
            at = at.base
        } elif ((at.e == "un" && at.op == "addr") || (at.e == "cast" && (at.cast_kind == "ArrayToPointerDecay" || at.cast_kind == "LValueToRValue"))) {
            at = at.a
        } else {
            return false
        }
    }
    return false
}

// `va_arg(v, T)`: the pop of the class C's default promotions gave the argument, `va_i` for
// the integers (narrowed to `T`: a `char` or `short` read is undefined in C, since no argument
// arrives as one, and reads the promoted `int`), `va_d` for `double` (and `float`, undefined
// alike), `va_p` for a pointer; a record and a `va_list` fail closed
def private emit_va_arg(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let t = x.arg_t
    let k = kind_of(tu, t)
    if (is_va_list(tu, t)) {
        fail(em, "va_arg of a `va_list` is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    if (is_record(tu, t)) {
        fail(em, "va_arg of a record type is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    let list = emit_expr(em, tu, x.list, loc).text
    em.requires |> insert("c_runtime/variadic")
    if (k == "enum") {
        return value(int_to_enum(em, tu, t, "int({VA_INT}({list}))"), PREC_PRIMARY)
    }
    let spelled = das_type(em, tu, t, loc)
    if (k == "int") {
        if (spelled == "bool") {
            return truth("{VA_INT}({list}) != 0l", PREC_EQ)
        }
        return value(spelled == "int64" ? "{VA_INT}({list})" : "{spelled}({VA_INT}({list}))", PREC_PRIMARY)
    }
    if (k == "float") {
        return value(spelled == "float" ? "float({VA_DOUBLE}({list}))" : "{VA_DOUBLE}({list})", PREC_PRIMARY)
    }
    if (k == "ptr") {
        return unsafe_value(em, "reinterpret<{spelled}>({VA_POINTER}({list}))", PREC_PRIMARY)
    }
    fail(em, "va_arg of type kind `{k}` is not lowered yet", loc)
    return value("", PREC_PRIMARY)
}

// a record the sidecar marks marshal-only: read and written as bytes at clang's offsets
def private is_marshal(em : Emitter; tu : CirTu; t : int) : bool => kind_of(tu, t) == "struct" && key_exists(em.prog.marshal, t)

// the marshal-only record a pointer type points at, -1 for any other type
def private marshal_pointee(em : Emitter; tu : CirTu; t : int) : int =>
    kind_of(tu, t) == "ptr" && is_marshal(em, tu, tu.types[t].to) ? tu.types[t].to : -1

// whether `x` is a marshal-only record in C memory (`marshal_site`), spelled nothing
def private marshal_located(em : Emitter; tu : CirTu; x : CirExpr const?) : bool {
    if (x == null) {
        return false
    }
    if (x.e == "un" && x.op == "deref") {
        return marshal_pointee(em, tu, x.a.t) >= 0
    }
    if (x.e == "index") {
        return marshal_pointee(em, tu, x.base.t) >= 0 && !value_array_decay(em, tu, x.base)
    }
    return x.e == "member" && is_marshal(em, tu, x.t) && marshal_held(em, tu, x)
}

// whether `x` is the decay of an array held by value, a das array its index reads directly,
// not one in C memory
def private value_array_decay(em : Emitter; tu : CirTu; x : CirExpr const?) : bool =>
    x.e == "cast" && x.cast_kind == "ArrayToPointerDecay" && kind_of(tu, x.a.t) == "array" && !marshal_array_member(em, tu, x.a)

// whether member `x` is a field of a marshal-only record in C memory
def private marshal_held(em : Emitter; tu : CirTu; x : CirExpr const?) : bool =>
    x.arrow ? marshal_pointee(em, tu, x.base.t) >= 0 : marshal_located(em, tu, x.base)

// a marshal-only record located in C memory: `*p`, `p[i]` and `p->` of a byte pointer give
// the record slot and spell the bytes it starts at, a record field of one (`p->r`) the bytes
// its `ptr_T_r` gives; -1 for a value (a local, a literal)
def private marshal_site(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc; var bytes : Em&) : int {
    if (x == null) {
        return -1
    }
    if (x.e == "member" && is_marshal(em, tu, x.t) && marshal_held(em, tu, x)) {
        var outer : Em
        let holder = marshal_holder(em, tu, *x, loc, outer)
        bytes = value("{pointer_name(em, tu, holder, x.field)}({outer.text}, 0)", PREC_PRIMARY)
        return x.t
    }
    if (x.e == "un" && x.op == "deref" && marshal_pointee(em, tu, x.a.t) >= 0) {
        bytes = emit_expr(em, tu, x.a, loc)
        return marshal_pointee(em, tu, x.a.t)
    }
    if (x.e == "index" && marshal_pointee(em, tu, x.base.t) >= 0 && !value_array_decay(em, tu, x.base)) {
        let rec = marshal_pointee(em, tu, x.base.t)
        let base = emit_expr(em, tu, x.base, loc)
        let i = enum_as_int(to_int(em, emit_expr(em, tu, x.i, loc)), tu, x.i.t)
        bytes = unsafe_value(em, "{wrap(base, PREC_ADD)} + {wrap(i, PREC_MUL)} * {type_size(tu, rec)}", PREC_ADD)
        return rec
    }
    return -1
}

// a scalar field of a marshal-only record in C memory: its record and bytes when `x` is `p->f`,
// `(*p).f` or `p[i].f` of a byte pointer, -1 for a field of a value and for a record field,
// which is a `marshal_site` itself
def private marshal_field(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc; var bytes : Em&) : int {
    if (x.e != "member" || is_marshal(em, tu, x.t)) {
        return -1
    }
    return marshal_holder(em, tu, x, loc, bytes)
}

// the marshal-only record in C memory holding member `x`, with its bytes; -1 for a value's
def private marshal_holder(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc; var bytes : Em&) : int {
    if (x.arrow && marshal_pointee(em, tu, x.base.t) >= 0) {
        bytes = emit_expr(em, tu, x.base, loc)
        return marshal_pointee(em, tu, x.base.t)
    }
    return x.arrow ? -1 : marshal_site(em, tu, x.base, loc, bytes)
}

// whether `x` is an array field of a marshal-only record in C memory, `p->a`, `(*p).a` or
// `p[i].a` of a byte pointer: its elements are read and written where they lie, through
// `marshal_elements`
def private marshal_array_member(em : Emitter; tu : CirTu; x : CirExpr const?) : bool =>
    x != null && x.e == "member" && kind_of(tu, x.t) == "array" && marshal_held(em, tu, x)

// the pointer to the first element of `x`, an array field of a marshal-only record in C memory
// (`marshal_array_member`): its generated `ptr_T_f` over the record's bytes
def private marshal_elements(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    var bytes : Em
    let rec = marshal_holder(em, tu, x, loc, bytes)
    return value("{pointer_name(em, tu, rec, x.field)}({bytes.text}, 0)", PREC_PRIMARY)
}

// `&` of a marshal-only record in C memory is the bytes it starts at (`&p->r`, `&p->a[i]` of
// a record field or element, `&p[i]`); `&p->a[i]` of an array field of scalars is its first
// element's pointer plus `i`, and `&p->a` that pointer as the field's; an empty text for any
// other operand
def private marshal_element_address(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let at = x.a
    var bytes : Em
    if (marshal_site(em, tu, at, loc, bytes) >= 0) {
        return bytes
    }
    if (marshal_array_member(em, tu, at)) {
        if (is_record(tu, element_under(tu, at.t))) {
            // a pointer to the whole array would be a das array of the natural struct
            let holder = at.arrow ? tu.types[at.base.t].to : at.base.t
            fail(em, "the address of `{tag_name(em, tu, holder)}.{field_name(em, tu, holder, at.field)}`, an array of marshal-only records, is not lowered yet", loc)
            return value("", PREC_PRIMARY)
        }
        let first = marshal_elements(em, tu, *at, loc)
        return unsafe_value(em, "reinterpret<{das_type(em, tu, x.t, loc)}>({first.text})", PREC_PRIMARY)
    }
    if (at.e != "index" || at.base.e != "cast" || at.base.cast_kind != "ArrayToPointerDecay" || !marshal_array_member(em, tu, at.base.a)) {
        return Em()
    }
    let first = marshal_elements(em, tu, *at.base.a, loc)
    let i = index_value(em, tu, at.i, loc)
    return unsafe_value(em, "{first.text} + {wrap(i, PREC_ADD + 1)}", PREC_ADD)
}

def private reader_name(var em : Emitter; tu : CirTu; rec : int; field : int) : string =>
    field < 0 ? "read_{tag_name(em, tu, rec)}" : "read_{tag_name(em, tu, rec)}_{field_name(em, tu, rec, field)}"

def private writer_name(var em : Emitter; tu : CirTu; rec : int; field : int) : string =>
    field < 0 ? "write_{tag_name(em, tu, rec)}" : "write_{tag_name(em, tu, rec)}_{field_name(em, tu, rec, field)}"

def private pointer_name(var em : Emitter; tu : CirTu; rec : int; field : int) : string =>
    "ptr_{tag_name(em, tu, rec)}_{field_name(em, tu, rec, field)}"

// a subscript as das takes it: C subscripts by any integer as it is, never promoted, and das
// indexes by `int`, `int64`, `uint` or `uint64` alone (`docs/probe-findings.md` F43), so an enum
// goes through `int` and a small integer widens to `int`
def private index_value(var em : Emitter; tu : CirTu; i : CirExpr?; loc : CirLoc) : Em {
    let at = enum_as_int(to_int(em, emit_expr(em, tu, i, loc)), tu, i.t)
    return is_small_int(tu, i.t) ? value("int({at.text})", PREC_PRIMARY) : at
}

// the das type `index_value` spells subscript `i` in: `int` for an enum or a small integer
def private index_type(var em : Emitter; tu : CirTu; i : CirExpr?; loc : CirLoc) : string =>
    kind_of(tu, i.t) == "enum" || is_small_int(tu, i.t) ? "int" : das_type(em, tu, i.t, loc)

// `a[i]` of an array is the das index, range-checked; of a pointer it is das's pointer index `p[i]`,
// unchecked (`docs/probe-findings.md` F100); of a byte pointer to a marshal-only record it is the
// record read at the scaled offset
def private emit_index(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    // a flexible, an over-indexed trailing or a padded array is indexed through its decay,
    // unchecked, and so is an array field of a marshal-only record in C memory, whose elements lie
    // in its bytes
    if (x.base.e == "cast" && x.base.cast_kind == "ArrayToPointerDecay" && kind_of(tu, x.base.a.t) == "array" && x.base.a.e != "str_lit" && empty(unchecked_access(em, tu, x.base.a)) && !marshal_array_member(em, tu, x.base.a)) {
        let arr = emit_expr(em, tu, x.base.a, loc)
        let at = index_value(em, tu, x.i, loc)
        return value("{wrap(arr, PREC_PRIMARY)}[{at.text}]", PREC_PRIMARY)
    }
    var bytes : Em
    let marshal = marshal_site(em, tu, unsafe(addr(x)), loc, bytes)
    if (marshal >= 0) {
        return value("{reader_name(em, tu, marshal, -1)}({bytes.text}, 0)", PREC_PRIMARY)
    }
    let base = emit_expr(em, tu, x.base, loc)
    let i = index_value(em, tu, x.i, loc)
    if (kind_of(tu, x.base.t) == "ptr") {
        return unsafe_value(em, "{wrap(base, PREC_PRIMARY)}[{i.text}]", PREC_PRIMARY)
    }
    return value("{wrap(base, PREC_PRIMARY)}[{i.text}]", PREC_PRIMARY)
}

// `*(p + i)` and `*(i + p)` of a data pointer, the das pointer index `p[i]` as `p[i]` itself is
// (`docs/probe-findings.md` F100); an empty text for any other dereference, a marshal-only
// record's pointee included, which `pointer_arithmetic` scales
def private pointer_sum_index(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let sum = x.a
    if (x.op != "deref" || sum.e != "bin" || sum.op != "add" || marshal_pointee(em, tu, sum.t) >= 0) {
        return Em()
    }
    let pointer_lhs = kind_of(tu, sum.a.t) == "ptr"
    let base = emit_expr(em, tu, pointer_lhs ? sum.a : sum.b, loc)
    let i = index_value(em, tu, pointer_lhs ? sum.b : sum.a, loc)
    return unsafe_value(em, "{wrap(base, PREC_PRIMARY)}[{i.text}]", PREC_PRIMARY)
}

// `a.f`, and `p.f` for `p->f` and `(*p).f` alike: das reads a field through a pointer
// without a `deref`, and without unsafe; a field of a marshal-only record in C memory reads
// through its generated reader
def private emit_member(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    var bytes : Em
    let whole = marshal_site(em, tu, unsafe(addr(x)), loc, bytes)
    if (whole >= 0) {
        return value("{reader_name(em, tu, whole, -1)}({bytes.text}, 0)", PREC_PRIMARY)
    }
    let marshal = marshal_field(em, tu, x, loc, bytes)
    if (marshal >= 0) {
        return value("{reader_name(em, tu, marshal, x.field)}({bytes.text}, 0)", PREC_PRIMARY)
    }
    let rec = x.arrow ? tu.types[x.base.t].to : x.base.t
    let through_deref = !x.arrow && x.base.e == "un" && x.base.op == "deref"
    let base = emit_expr(em, tu, through_deref ? x.base.a : x.base, loc)
    return value("{wrap(base, PREC_PRIMARY)}.{field_name(em, tu, rec, x.field)}", PREC_PRIMARY)
}

// the store into a marshal-only record in C memory, `p->f = v`, `p->f op= v` (field `field`
// of record `rec`) or `*p = v` (field -1), through the generated writer over `bytes`
def private marshal_store(var em : Emitter; tu : CirTu; x : CirExpr; rec, field : int; bytes, rhs : Em; loc : CirLoc) : string {
    if (field < 0) {
        return "{writer_name(em, tu, rec, -1)}({bytes.text}, 0, {rhs.text})"
    }
    var v = rhs
    if (!empty(x.op)) {
        let spelled = BIN_SPELLING?[x.op] ?? ""
        let prec = BIN_PREC?[x.op] ?? 0
        let narrow = das_type(em, tu, x.a.t, loc)
        let wide = das_type(em, tu, x.b.t, loc)
        let current = "{reader_name(em, tu, rec, field)}({bytes.text}, 0)"
        v = value(narrow == wide ? "{current} {spelled} {wrap(rhs, prec + 1)}" : "{narrow}({wide}({current}) {spelled} {wrap(rhs, prec + 1)})", narrow == wide ? prec : PREC_PRIMARY)
    }
    return "{writer_name(em, tu, rec, field)}({bytes.text}, 0, {v.text})"
}

let SPARSE_ARRAY_LIMIT = 32

// the literal of array type `t` holding `elems`; an array of pointers names its element type,
// since `fixed_array(null, null)` is a `void?` array no other pointer array takes
// (`docs/probe-findings.md` F41)
def private array_literal(var em : Emitter; tu : CirTu; t : int; elems : array<string>; loc : CirLoc) : string {
    let elem = das_type(em, tu, tu.types[t].elem, loc)
    let elem_arg = elem |> ends_with("?") ? "<{elem}>" : ""
    return "fixed_array{elem_arg}({join(elems, LIST_SEPARATOR)})"
}

// a literal of the type's zero: what C's static zeroing and das's default agree on
def private zero_literal(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    let k = kind_of(tu, t)
    if (k == "array") {
        let one = zero_literal(em, tu, tu.types[t].elem, loc)
        return array_literal(em, tu, t, [for (_i in range(tu.types[t].count)); one], loc)
    }
    return zero_of(em, tu, t, das_type(em, tu, t, loc))
}

// whether an array initializer spells as one `fixed_array` literal: the literal must hold
// every element, so a large array the source fills sparsely is a declaration plus stores
def private literal_array(tu : CirTu; x : CirExpr) : bool =>
    kind_of(tu, x.t) != "array" || length(x.init_items) == tu.types[x.t].count || tu.types[x.t].count <= SPARSE_ARRAY_LIMIT

// `S(f = v, ...)` naming the slots the source filled, the rest the struct's zeros;
// `fixed_array(...)` with every element, the unwritten ones as zero literals; a union's list
// in either is left at its zero for the stores that follow (`union_stores`), since a struct
// literal cannot name a `[c_union]` member
def private emit_init_list(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let k = kind_of(tu, x.t)
    if (k == "union") {
        fail(em, "a union initializer list outside a declaration is not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    if (k != "struct" && k != "array") {
        fail(em, "`{k}` initializer lists are not lowered yet", loc)
        return value("", PREC_PRIMARY)
    }
    if (k == "array") {
        if (!literal_array(tu, x)) {
            fail(em, "an array of {tu.types[x.t].count} filled sparsely inside an initializer is not lowered yet", loc)
            return value("", PREC_PRIMARY)
        }
        var elems <- [for (_i in range(tu.types[x.t].count)); ""]
        for (item in x.init_items) {
            continue if (is_union_list(tu, item.v))
            elems[item.pos] = stored(em, init_value(em, tu, item.v, loc), tu, tu.types[x.t].elem).text
        }
        for (e in elems) {
            if (empty(e)) {
                e = zero_literal(em, tu, tu.types[x.t].elem, loc)
            }
        }
        return value(array_literal(em, tu, x.t, elems, loc), PREC_PRIMARY)
    }
    var units : array<BitUnit>
    if (has_bitfield(tu, x.t, true) && !bit_units(tu, em.prog.layout, x.t, units)) {
        // the dumper marks such a record packed, so only a C-IR from elsewhere reaches this
        fail(em, "record `{tag_name(em, tu, x.t)}`: no bitfield units reproduce clang's layout", loc)
        return value("", PREC_PRIMARY)
    }
    // a unit's bitfields fold into one `_bits<N>` item, at the place of the first one written
    var unit_parts : array<array<tuple<field : int; v : Em; spelled : string>>>
    unit_parts |> resize(length(units))
    var items : array<string>
    var item_units : array<int>
    items |> reserve(length(x.init_items))
    for (item in x.init_items) {
        continue if (is_union_list(tu, item.v))
        if (is_flexible(tu, x.t, item.pos)) {
            fail(em, "an initializer of flexible array member `{tag_name(em, tu, x.t)}.{tu.types[x.t].fields[item.pos].name}` (a GNU extension) is not lowered yet", loc)
            return value("", PREC_PRIMARY)
        }
        let v = stored(em, init_value(em, tu, item.v, loc), tu, tu.types[x.t].fields[item.pos].t)
        let n = tu.types[x.t].fields[item.pos].is_bitfield ? unit_of(units, item.pos) : -1
        if (n < 0) {
            items |> push("{field_name(em, tu, x.t, item.pos)} = {v.text}")
            item_units |> push(-1)
        } else {
            if (empty(unit_parts[n])) {
                items |> push("_bits{n} = ")
                item_units |> push(n)
            }
            unit_parts[n] |> push((field = item.pos, v = v, spelled = das_type(em, tu, tu.types[x.t].fields[item.pos].t, loc)))
        }
    }
    for (idx, n in range(length(items)), item_units) {
        if (n >= 0) {
            items[idx] += unit_init(tu, x.t, units[n], unit_parts[n])
        }
    }
    return value("{tag_name(em, tu, x.t)}({join(items, LIST_SEPARATOR)})", PREC_PRIMARY)
}

// the stores of a sparsely filled large array: `name[pos] = value` per written element
def private sparse_stores(var em : Emitter; tu : CirTu; name : string; x : CirExpr; loc : CirLoc; var out : array<string>) {
    out |> reserve(length(out) + length(x.init_items))
    for (item in x.init_items) {
        init_stores(em, tu, "{name}[{item.pos}]", item.v, loc, out)
    }
}

// whether `x` is the integer literal 0, through C's implicit conversions
def private is_zero_literal(x : CirExpr const?) : bool {
    var v = x
    while (v != null && v.e == "cast") {
        v = v.a
    }
    return v != null && v.e == "int_lit" && v.v == "0"
}

// whether initializer `x` holds a union's list, itself or in an item at any depth
def private holds_union_list(tu : CirTu; x : CirExpr const?) : bool {
    if (is_union_list(tu, x)) {
        return true
    }
    if (x != null && x.e == "init_list") {
        for (item in x.init_items) {
            if (holds_union_list(tu, item.v)) {
                return true
            }
        }
    }
    return false
}

// whether evaluating `x` has an effect: a call, an assignment, a step or a comma anywhere in it
def private has_effects(x : CirExpr const?) : bool {
    var found = false
    each_subexpr(x) $(sub) {
        found = found || sub.e == "call" || sub.e == "va_arg" || sub.e == "assign" || sub.e == "comma" || (sub.e == "un" && is_step(sub.op))
    }
    return found
}

// whether evaluating `x` reads a volatile object: a load of an lvalue the dumper marked, an
// access C counts as an effect
def private reads_volatile(x : CirExpr const?) : bool {
    var found = false
    each_subexpr(x) $(sub) {
        found = found || (sub.e == "cast" && sub.cast_kind == "LValueToRValue" && sub.a != null && sub.a.vol)
    }
    return found
}

// lvalue `x` with each effect in it evaluated once, ahead: the pointer it goes through, an
// index, a record value, whichever has an effect (`*next()`, `a[i++]`, `p[g()].bf`), lands in a
// temporary every later spelling of `x` reads through `em.hoisted`, so a step, a compound store
// or an assignment read as a value spells its target as often as it needs and evaluates it
// once; `keys` collects what `unpin` drops when the target's statement is spelled
def private pin_lvalue(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc; var keys : array<uint64>) {
    if (!has_effects(x) && !reads_volatile(x)) {
        return
    }
    if (x.e == "un" && x.op == "deref") {
        pin_value(em, tu, x.a, loc, keys)
    } elif (x.e == "index") {
        if (x.base.e == "cast" && x.base.cast_kind == "ArrayToPointerDecay" && kind_of(tu, x.base.a.t) == "array") {
            pin_lvalue(em, tu, x.base.a, loc, keys)
        } else {
            pin_value(em, tu, x.base, loc, keys)
        }
        pin_value(em, tu, x.i, loc, keys)
    } elif (x.e == "member") {
        if (x.arrow) {
            pin_value(em, tu, x.base, loc, keys)
        } else {
            pin_lvalue(em, tu, x.base, loc, keys)
        }
    } else {
        // no other lvalue the dumper takes holds an effect (it refuses `f().a[0]`)
        fail(em, "a step or a store through a `{x.e}` target with an effect is not lowered yet", loc)
    }
}

// value `x` evaluated once, when it has an effect: its text when that is a temporary the emitter
// hoisted (a postfix step's old value), else a temporary holding it; a variable's own name (`i`
// of `++i`, `p` of `p = q`) is not kept, since a call later in the statement can change it
def private pin_value(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc; var keys : array<uint64>) {
    if ((!has_effects(x) && !reads_volatile(x)) || key_exists(em.hoisted, intptr(x))) {
        return
    }
    var e = emit_expr(em, tu, x, loc)
    if (!is_temp_name(em, e.text)) {
        let name = temp_name(em)
        // a `let` copy of a value holding a pointer takes a const pointee (F3)
        em.pre |> push("{holds_data_pointer(tu, x.t) ? "var" : "let"} {name} = {e.text}")
        e.text = name
        e.prec = PREC_PRIMARY
        e.inverse = ""
    }
    em.hoisted[intptr(x)] = e
    keys |> push(intptr(x))
}

def private unpin(var em : Emitter; keys : array<uint64>) {
    for (key in keys) {
        em.hoisted |> erase(key)
    }
}

// whether `text` is a temporary the emitter hoisted (`_tN`), which holds one value
def private is_temp_name(em : Emitter; text : string) : bool => numbered_after(text, "_t") >= 0 && !key_exists(em.spelled, text)

// every value of initializer `x` evaluated into a temporary, in source order, before the
// declaration: the literal and the union stores after it then read the temporaries, so C's
// left-to-right order of the items holds
def private hoist_items(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) {
    for (item in x.init_items) {
        if (item.v.e == "init_list") {
            hoist_items(em, tu, item.v, loc)
        } else {
            let e = init_value(em, tu, item.v, loc)
            let name = temp_name(em)
            // a `let` copy of a value holding a pointer takes a const pointee, which no `var` slot
            // takes (F3)
            em.pre |> push("{holds_data_pointer(tu, item.v.t) ? "var" : "let"} {name} = {e.text}")
            em.hoisted[intptr(item.v)] = Em(text = name, prec = PREC_PRIMARY, is_bool = e.is_bool)
        }
    }
}

def private is_union_list(tu : CirTu; x : CirExpr const?) : bool => x != null && x.e == "init_list" && kind_of(tu, x.t) == "union"

// the stores that make lvalue `path` hold initializer `v`: `path = v`, a union's list left out
// of it, then the stores of every union's list `v` holds
def private init_stores(var em : Emitter; tu : CirTu; path : string; v : CirExpr const?; loc : CirLoc; var out : array<string>) {
    if (!is_union_list(tu, v)) {
        out |> push("{path} = {stored(em, init_value(em, tu, v, loc), tu, v.t).text}")
    }
    union_stores(em, tu, path, v, loc, out)
}

// the stores of the union lists inside initializer `x` of lvalue `path`: a union's list stores
// the one member it names (`{}` stores nothing, the union is zero), a record's or an array's
// list the union lists of its items
def private union_stores(var em : Emitter; tu : CirTu; path : string; x : CirExpr const?; loc : CirLoc; var out : array<string>) {
    if (x == null || x.e != "init_list") {
        return
    }
    if (kind_of(tu, x.t) == "union") {
        for (item in x.init_items) {
            // the storage starts at zero, so `{0}` stores nothing
            if (!is_zero_literal(item.v)) {
                init_stores(em, tu, "{path}.{field_name(em, tu, x.t, item.pos)}", item.v, loc, out)
            }
        }
        return
    }
    for (item in x.init_items) {
        let at = kind_of(tu, x.t) == "array" ? "{path}[{item.pos}]" : "{path}.{field_name(em, tu, x.t, item.pos)}"
        union_stores(em, tu, at, item.v, loc, out)
    }
}

// a value of an initializer: a `char[N]` from a string literal, a whole declaration's or a row
// or field of one, is `cstr_array("...", N)` (the bytes, a NUL where it fits, zeros to `N`); a
// literal longer than `N` keeps its first `N` bytes, as clang initializes the array; one
// `hoist_items` evaluated ahead is its temporary
def private init_value(var em : Emitter; tu : CirTu; v : CirExpr const?; loc : CirLoc) : Em {
    if (v != null && v.e == "str_lit" && kind_of(tu, v.t) == "array" && !key_exists(em.hoisted, intptr(v))) {
        em.requires |> insert("c_runtime/cstr_array")
        let count = tu.types[v.t].count
        if (interior_nul(*v, count)) {
            // `cstr_array` reads its literal as a das string, which ends at the first NUL: the row
            // is the bytes
            let row <- [for (idx in range(count)); "uint8({idx < length(v.bytes) ? int(v.bytes[idx]) : 0})"]
            return value("fixed_array({join(row, LIST_SEPARATOR)})", PREC_PRIMARY)
        }
        return value("{CSTR_ARRAY}({quoted_literal(em, tu, *v, loc, count)}, {count})", PREC_PRIMARY)
    }
    return emit_expr(em, tu, v, loc)
}

// why initializer `x` of type `t` cannot fill its arrays from a string literal it holds at any
// depth, "" when it can: a literal filling an array of signed bytes (`cstr_array` gives `uint8`
// ones; a `signed char` row or field), or a literal in braces (`char s[3] = {
// "ab" }`), which the list spells as the array's first element
def private string_init_refusal(tu : CirTu; t : int; x : CirExpr const?) : string {
    if (x == null || t < 0) {
        return ""
    }
    if (x.e == "str_lit" && kind_of(tu, t) != "array") {
        return "a string literal in braces initializing a `{tu.types[t].spell}` array is not lowered yet"
    }
    if (x.e == "str_lit") {
        let elem = tu.types[t].elem
        // a wide literal's elements are refused by the literal itself (`quoted_literal`)
        let signed_bytes = kind_of(tu, elem) == "int" && tu.types[elem].w == 8 && tu.types[elem].is_signed
        return signed_bytes ? "a string literal initializing a `{tu.types[elem].spell}` array is not lowered yet" : ""
    }
    if (x.e != "init_list") {
        return ""
    }
    for (item in x.init_items) {
        let item_t = kind_of(tu, t) == "array" ? tu.types[t].elem : is_record(tu, t) ? tu.types[t].fields[item.pos].t : -1
        let refusal = string_init_refusal(tu, item_t, item.v)
        if (!empty(refusal)) {
            return refusal
        }
    }
    return ""
}

// a compound literal (`(T){...}`) where C reads its value: a struct's is the literal `S(f = v,
// ...)` and a scalar's the value it holds; an array, a union and a record holding a union's list
// are objects (`literal_object`), since only a declaration spells them
def private emit_compound_literal(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let refusal = string_init_refusal(tu, x.t, x.init)
    if (!empty(refusal)) {
        fail(em, "a compound literal: {refusal}", loc)
        return value("", PREC_PRIMARY)
    }
    let k = kind_of(tu, x.t)
    if (k == "struct" && !holds_union_list(tu, x.init)) {
        return emit_init_list(em, tu, *x.init, loc)
    }
    if (k == "struct" || k == "union" || k == "array") {
        return literal_object(em, tu, x, loc)
    }
    if (empty(x.init.init_items)) {
        return value(zero_literal(em, tu, x.t, loc), PREC_PRIMARY)
    }
    return stored(em, emit_expr(em, tu, x.init.init_items[0].v, loc), tu, x.t)
}

// the object of compound literal `x`, `_cl<N>` (C11 6.5.2.5): inside a function a local declared
// before the statement, in the enclosing block, initialized there, or, under a conditional arm,
// declared there and initialized in the arm; at file scope a module global, declared before the
// global whose initializer reads it, since its storage is static
[arch(at="ARCHITECTURE_EMITTER_AGGREGATES.md#compound-literals")]
def private literal_object(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let spelled = das_type(em, tu, x.t, loc)
    let name = literal_name(em)
    let scalar = !is_record(tu, x.t) && kind_of(tu, x.t) != "array"
    let init = scalar ? (empty(x.init.init_items) ? null : x.init.init_items[0].v) : x.init
    var stores : array<string>
    var text = ""
    if (init != null) {
        text = decl_init_text(em, tu, name, x.t, init, loc, stores)
        unhoist_items(em, init)
    }
    if (em.in_global_init) {
        let head = "var private {name} : {spelled}"
        if (empty(text)) {
            em.global_literals |> push(head)
        } elif (inline_legal(em, tu, init)) {
            em.global_literals |> push("{head} = {text}")
        } else {
            em.global_literals |> push(head)
            em.global_stores |> push("{name} = {text}")
        }
        em.global_stores |> push_from(stores)
    } elif (em.narrow > 0 || at_case_level(em)) {
        // the statements land in a narrower block than C's: a conditional arm's `if`, or the `if`
        // of a matched-flag switch's group, which a later group reached by fallthrough is outside of
        if (at_case_level(em)) {
            em.case_literal_decls |> push("var {name} : {spelled}")
        } else {
            em.literal_decls |> push("var {name} : {spelled}")
        }
        let zero = kind_of(tu, x.t) == "array" ? "default<{spelled}>" : zero_literal(em, tu, x.t, loc)
        em.pre |> push("{name} = {empty(text) ? zero : text}")
        em.pre |> push_from(stores)
    } else {
        em.pre |> push(empty(text) ? "var {name} : {spelled}" : "var {name} : {spelled} = {text}")
        em.pre |> push_from(stores)
    }
    return value(name, PREC_PRIMARY)
}

// whether the statement being spelled is a group-level statement of a matched-flag switch
def private at_case_level(em : Emitter) : bool => em.case_depth > 0 && em.case_depth == em.stmt_depth

// `_cl<N>`: the next number no name of the function, no global and no function spells; a
// file-scope literal's global joins the names every later one skips
def private literal_name(var em : Emitter) : string {
    var name = "_cl{em.literal_counter}"
    em.literal_counter++
    while (key_exists(em.spelled, name) || key_exists(em.prog.defined_globals, name) || key_exists(em.prog.functions, name) || key_exists(em.literal_globals, name)) {
        name = "_cl{em.literal_counter}"
        em.literal_counter++
    }
    if (em.in_global_init) {
        em.literal_globals |> insert(name)
    }
    return name
}

// the temporaries `hoist_items` recorded for initializer `x` dropped, once its declaration is
// spelled
def private unhoist_items(var em : Emitter; x : CirExpr const?) {
    if (x == null || x.e != "init_list") {
        return
    }
    for (item in x.init_items) {
        em.hoisted |> erase(intptr(item.v))
        unhoist_items(em, item.v)
    }
}

// the initializer of a declared variable: a `char[N]` from a string literal is
// `cstr_array`, an array filled sparsely is the bare declaration (stores follow), anything
// else the expression; "" with `stores` set means the declaration carries no `=`
def private decl_init(var em : Emitter; tu : CirTu; name : string; t : int; init : CirExpr?; loc : CirLoc; var stores : array<string>) : string {
    let refusal = string_init_refusal(tu, t, init)
    if (!empty(refusal)) {
        fail(em, "`{name}`: {refusal}", loc)
        return ""
    }
    let text = decl_init_text(em, tu, name, t, init, loc, stores)
    // a folded macro's def body keeps its parameters' spellings (`spell_macro_body`)
    var kept <- {for (key in keys(em.fold_seeds)); key => em.hoisted?[key] ?? Em()}
    em.hoisted <- kept
    return text
}

// the text of `decl_init`, which may read temporaries `hoist_items` made
def private decl_init_text(var em : Emitter; tu : CirTu; name : string; t : int; init : CirExpr?; loc : CirLoc; var stores : array<string>) : string {
    if (init.e == "init_list" && !is_union_list(tu, init) && holds_union_list(tu, init) && has_effects(init)) {
        // the union stores follow the literal, so every item is evaluated first, in order
        hoist_items(em, tu, init, loc)
    }
    if (is_union_list(tu, init)) {
        union_stores(em, tu, name, init, loc, stores)
        return ""
    }
    if (init.e == "init_list" && !literal_array(tu, *init)) {
        sparse_stores(em, tu, name, *init, loc, stores)
        return ""
    }
    let text = stored(em, init_value(em, tu, init, loc), tu, t).text
    union_stores(em, tu, name, init, loc, stores)
    return text
}

// an expression evaluated for its effect alone: the statement forms of assignment, the
// steps and calls, everything else through its pre-statements
def private emit_effect(var em : Emitter; tu : CirTu; x : CirExpr?; loc : CirLoc) {
    // a value evaluated ahead (a general setjmp site's) has no effect left
    if (x == null || key_exists(em.hoisted, intptr(x))) {
        return
    }
    var folded : Em
    if (!empty(x.fn_macro) && !is_lvalue(x) && fold_macro(em, tu, x, x, null, "effect", loc, folded)) {
        em.pre |> push(folded.text)
    } elif (x.e == "assign") {
        em.pre |> push(assignment_line(em, tu, *x, loc))
    } elif (x.e == "un" && is_step(x.op)) {
        em.pre |> push(step_line(em, tu, *x, loc))
    } elif (x.e == "call" && is_va_builtin(*x)) {
        // `va_end` dissolves into no statement
        let text = emit_va_builtin(em, tu, *x, loc).text
        if (!empty(text)) {
            em.pre |> push(text)
        }
    } elif (x.e == "call") {
        em.pre |> push(emit_call(em, tu, *x, loc).text)
    } elif (x.e == "comma") {
        emit_effect(em, tu, x.a, loc)
        emit_effect(em, tu, x.b, loc)
    } elif (x.e == "cond" && kind_of(tu, x.t) == "void") {
        void_conditional(em, tu, *x, loc)
    } elif (x.e == "cast" && x.cast_kind == "LValueToRValue" && volatile_kept(em, tu, x.a)) {
        // a volatile read is an access C keeps though its value is discarded
        em.pre |> push("let {temp_name(em)} = {volatile_load(em, tu, x.a, loc).text}")
    } elif (x.e == "cast" && (x.cast_kind == "ToVoid" || x.cast_kind == "LValueToRValue" || x.cast_kind == "NoOp")) {
        emit_effect(em, tu, x.a, loc)
    } else {
        let e = emit_expr(em, tu, x, loc)
        if (x.e != "ref" && x.e != "int_lit" && x.e != "float_lit") {
            // a discard takes a fresh name, since das refuses a `_` that shadows an outer one
            em.pre |> push("let {temp_name(em)} = {e.text}")
        }
    }
}

// a conditional of `void` type, which C evaluates for its arms' effects alone: an `if`/`else`
// statement, each arm's effects spelled in place, never a temporary, since das has no `void`
// variable; an arm with no effect drops out (`if (!(c))` when it is the first)
def private void_conditional(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) {
    let c = truth_of(em, tu, x.c, loc)
    let mark = length(em.pre)
    em.narrow++
    emit_effect(em, tu, x.a, loc)
    let a_end = length(em.pre)
    emit_effect(em, tu, x.b, loc)
    em.narrow--
    let a_pre <- [for (idx in range(mark, a_end)); "    {em.pre[idx]}"]
    let b_pre <- [for (idx in range(a_end, length(em.pre))); "    {em.pre[idx]}"]
    em.pre |> resize(mark)
    if (empty(a_pre) && empty(b_pre)) {
        return
    }
    if (empty(a_pre)) {
        hoist(em, ["if ({negation(c)}) \{"])
        hoist(em, b_pre)
    } else {
        hoist(em, ["if ({c.text}) \{"])
        hoist(em, a_pre)
        if (!empty(b_pre)) {
            hoist(em, ["\} else \{"])
            hoist(em, b_pre)
        }
    }
    hoist(em, ["\}"])
}

def private emit_body(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (st == null) {
        return
    }
    if (st.s == "compound") {
        emit_statements(em, tu, st, 0)
    } else {
        emit_stmt(em, tu, st)
    }
}

// the statements of a block from `first` on; a single-branch setjmp `if` takes the rest of
// the block as its tail, the trampoline of docs/lowering-examples.md "setjmp / longjmp", unless
// the site is flat
def private emit_statements(var em : Emitter; tu : CirTu; owner : CirStmt const?; first : int) {
    for (idx in range(first, length(owner.body))) {
        let child = owner.body[idx]
        var first_in_then = false
        if (flat_setjmp(owner, idx)) {
            if (tail_leaves_loop(em, owner, idx)) {
                return
            }
            emit_setjmp_site(em, tu, *child, setjmp_site(child.cond, first_in_then), true)
            continue
        }
        if (child.s == "if" && child.else_s == null && setjmp_site(child.cond, first_in_then) != null) {
            emit_trampoline(em, tu, owner, idx, first_in_then, null)
            return
        }
        let call = general_setjmp(child)
        if (call != null) {
            emit_trampoline(em, tu, owner, idx, false, call)
            return
        }
        emit_stmt(em, tu, child)
    }
}

// a single-branch setjmp `if` whose branch is the first run (`== 0`, `!`) and whose block tail
// calls nothing, so no longjmp from the tail reaches the buffer: the contained site with an
// empty `recover` arm, the tail after it run once
[arch(at="ARCHITECTURE_EMITTER.md#setjmp-general")]
def private flat_setjmp(owner : CirStmt const?; site : int) : bool {
    let st = owner.body[site]
    var first_in_then = false
    if (st.s != "if" || st.else_s != null || setjmp_site(st.cond, first_in_then) == null || !first_in_then) {
        return false
    }
    for (idx in range(site + 1, length(owner.body))) {
        var calls = false
        each_expr(owner.body[idx]) $(x) {
            calls = calls || x.e == "call"
        }
        if (calls) {
            return false
        }
    }
    return true
}

// the setjmp call of a statement that re-enters through the general trampoline, null for any
// other statement: the forms ISO C 7.13.1.1 gives setjmp, where the statement reads nothing
// before the call that a rerun would read again - `setjmp(buf);` (`(void)` included), `r =
// setjmp(buf);` (a plain store into a target with no effect), `int r = setjmp(buf);`, `return
// setjmp(buf);`, and an `if` or a `switch` controlled by the value, by `!setjmp(buf)` or by
// setjmp compared with an integer constant (`setjmp(buf) == 2`), beside the `if` forms tested
// against zero; implicit conversions of the value pass, since they read nothing
[arch(at="ARCHITECTURE_EMITTER.md#setjmp-general")]
def private general_setjmp(st : CirStmt const?) : CirExpr const? {
    if (st.s == "decl") {
        return setjmp_call(st.init)
    } elif (st.s == "return") {
        return setjmp_call(st.e)
    } elif (st.s == "expr") {
        let whole = setjmp_call(st.e)
        if (whole != null) {
            return whole
        }
        let x = below_casts(st.e)
        if (x != null && x.e == "assign" && empty(x.op) && !has_effects(x.a)) {
            return setjmp_call(x.b)
        }
    } elif (st.s == "switch") {
        return controlling_setjmp(st.cond)
    } elif (st.s == "if") {
        var first_in_then = false
        if (setjmp_site(st.cond, first_in_then) == null) {
            return controlling_setjmp(st.cond)
        }
    }
    return null
}

// the setjmp call `x` is below its casts, with a buffer that has no effect; null for any other
def private setjmp_call(x : CirExpr const?) : CirExpr const? {
    let at = below_casts(x)
    if (at == null || at.e != "call" || !key_exists(SETJMP_NAMES, called_name(*at)) || length(at.args) != 1 || has_effects(at.args[0])) {
        return null
    }
    return at
}

// the setjmp call of a controlling expression ISO C gives it: the value, `!` of it, or the value
// compared with an integer constant on either side
def private controlling_setjmp(x : CirExpr const?) : CirExpr const? {
    let at = below_casts(x)
    if (at == null) {
        return null
    }
    if (at.e == "un" && at.op == "not") {
        return setjmp_call(at.a)
    }
    if (at.e == "bin" && (at.op == "eq" || at.op == "ne" || at.op == "lt" || at.op == "gt" || at.op == "le" || at.op == "ge")) {
        if (integer_constant(at.b)) {
            return setjmp_call(at.a)
        }
        if (integer_constant(at.a)) {
            return setjmp_call(at.b)
        }
        return null
    }
    return setjmp_call(at)
}

// whether `x` is an integer constant: a literal, an enumerator, `sizeof` or `_Alignof`, through
// casts and the unary arithmetic operators
def private integer_constant(x : CirExpr const?) : bool {
    let at = below_casts(x)
    if (at == null) {
        return false
    }
    if (at.e == "un" && (at.op == "neg" || at.op == "plus" || at.op == "bnot")) {
        return integer_constant(at.a)
    }
    return at.e == "int_lit" || at.e == "enum_ref" || at.e == "sizeof_v" || at.e == "alignof_v"
}

// whether the setjmp site at `site` or the rest of its block leaves an enclosing loop, which
// fails closed: the branch sits in a `try` arm, and the trampoline's tail in its loop
def private tail_leaves_loop(var em : Emitter; owner : CirStmt const?; site : int) : bool {
    for (idx in range(site, length(owner.body))) {
        if (breaks_switch(owner.body[idx]) || continues_out(owner.body[idx])) {
            fail(em, "a setjmp site whose tail leaves an enclosing loop is not lowered yet", owner.body[site].loc)
            return true
        }
    }
    return false
}

// `if (setjmp(buf)) { B } tail`: C re-enters at the setjmp with longjmp's value and runs on,
// so the branch and the tail live in a loop that reruns once per longjmp caught; a branch or a
// tail that leaves an outer loop would leave this one instead and fails closed. The general form (`call`,
// `general_setjmp`) puts the site's statement itself first in the tail, the setjmp read as
// `_sj_val`, which is 0 on the first run and longjmp's value on every rerun
def private emit_trampoline(var em : Emitter; tu : CirTu; owner : CirStmt const?; site : int; first_in_then : bool; call : CirExpr const?) {
    let st = owner.body[site]
    if (tail_leaves_loop(em, owner, site)) {
        return
    }
    var first_in_then_again = false
    var buf : CirExpr const? = setjmp_site(st.cond, first_in_then_again)
    if (call != null) {
        buf = call.args[0]
    }
    let arm <- [for (idx in range(site, length(owner.body))); owner.body[idx]]
    var returns = false
    if (!arm_returns(em, arm, st.loc, returns)) {
        return
    }
    em.requires |> insert("c_runtime/setjmp")
    em.setjmp_counter++
    let run = numbered("_sj_run", em.setjmp_counter)
    let val = numbered("_sj_val", em.setjmp_counter)
    let target = emit_expr(em, tu, buf, st.loc)
    flush_pre(em)
    let declared = open_sj_result(em, returns)
    line(em, "var {run} = true")
    line(em, "var {val} = 0")
    open_block(em, "while ({run})")
    line(em, "{run} = false")
    open_block(em, "try")
    open_sj_arm(em, returns)
    if (call != null) {
        em.hoisted[intptr(call)] = value(val, PREC_PRIMARY)
        emit_stmt(em, tu, st)
        em.hoisted |> erase(intptr(call))
    } else {
        open_block(em, "if ({val} {first_in_then ? "==" : "!="} 0)")
        emit_body(em, tu, st.then_s)
        close_block(em)
    }
    em.cont_flags |> push("")
    emit_statements(em, tu, owner, site + 1)
    em.cont_flags |> pop()
    close_sj_arm(em, returns, site + 1 < length(owner.body) ? statements_end_in_return(tu, owner, site + 1) : call != null && ends_in_return(tu, st))
    em.depth--
    open_block(em, "\} recover")
    open_block(em, "if ({JMP_TARGET} != {target.text})")
    line(em, "panic(\"longjmp\")")
    close_block(em)
    line(em, "{JMP_TARGET} = null")
    // the value through the buffer the site named: `buf.val` for a buffer in reach, which
    // arrives as the decay of the `jmp_buf`, `(*p).val` for one behind a pointer
    let direct = buf.e == "cast" && buf.cast_kind == "ArrayToPointerDecay" && !(buf.a.e == "un" && buf.a.op == "deref")
    let held = direct ? emit_expr(em, tu, buf.a, st.loc).text : "(*{wrap(target, PREC_UNARY)})"
    line(em, "{val} = {held}.val")
    line(em, "{run} = true")
    close_block(em)
    close_block(em)
    close_sj_result(em, returns, declared)
}

// whether the statements `arm`, which go into a `try` or `recover` arm, hold a `return`, in
// `returns`; false when they do and a `goto` crosses the arm's edge, which the arm's block
// cannot carry (`ARCHITECTURE_EMITTER.md`, setjmp / longjmp)
[arch(at="ARCHITECTURE_EMITTER.md#setjmp-general")]
def private arm_returns(var em : Emitter; arm : array<CirStmt const?>; loc : CirLoc; var returns : bool&) : bool {
    var labels : table<string>
    var gotos : table<uint64>
    returns = false
    for (top in arm) {
        each_stmt(top) $(s) {
            returns = returns || s.s == "return"
            if (s.s == "label") {
                labels |> insert(s.label_name)
            } elif (s.s == "goto") {
                gotos |> insert(intptr(s))
            }
        }
    }
    if (!returns) {
        return true
    }
    var crosses = false
    each_stmt(em.fn_body) $(s) {
        crosses = crosses || (s.s == "goto" && key_exists(gotos, intptr(s)) != key_exists(labels, s.label_name))
    }
    if (crosses) {
        fail(em, "a setjmp arm that returns and a goto across its edge is not lowered yet", loc)
        return false
    }
    return true
}

// the result the outermost setjmp site whose arms return declares before its `try`: the value
// `_sj_ret` (none in a void function) and the flag `_sj_returned`; true when this site declared them
def private open_sj_result(var em : Emitter; returns : bool) : bool {
    if (!returns || !empty(em.sj_returned)) {
        return false
    }
    em.sj_result_counter++
    em.sj_returned = numbered("_sj_returned", em.sj_result_counter)
    em.sj_ret = em.fn_ret == "void" ? "" : numbered("_sj_ret", em.sj_result_counter)
    if (!empty(em.sj_ret)) {
        line(em, "var {em.sj_ret} : {em.fn_ret}")
    }
    line(em, "var {em.sj_returned} = false")
    return true
}

// an arm that returns opens as the block whose answer is whether it returned
def private open_sj_arm(var em : Emitter; returns : bool) {
    if (returns) {
        open_block(em, "{em.sj_returned} = invoke($() : bool")
        em.sj_arms++
    }
}

// the arm's block closes, answering false when its statements fall off its end (`ended` false)
def private close_sj_arm(var em : Emitter; returns, ended : bool) {
    if (returns) {
        if (!ended) {
            line(em, "return false")
        }
        em.sj_arms--
        em.depth--
        line(em, "\})")
    }
}

// after the site's `try` and `recover`: a return an arm took leaves the function, or the arm of
// an enclosing site, which then answers true; the outermost site's declaration ends with it
def private close_sj_result(var em : Emitter; returns, declared : bool) {
    if (!returns) {
        return
    }
    open_block(em, "if ({em.sj_returned})")
    line(em, em.sj_arms > 0 ? "return true" : empty(em.sj_ret) ? "return" : "return {em.sj_ret}")
    close_block(em)
    if (declared) {
        em.sj_ret = ""
        em.sj_returned = ""
    }
}

// a C `return`; inside a setjmp arm's block the value goes into `_sj_ret` and the block answers true
def private emit_return(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    let in_arm = em.sj_arms > 0
    if (st.e != null) {
        let e = stored(em, emit_expr(em, tu, st.e, st.loc), tu, st.e.t)
        flush_pre(em)
        line(em, !in_arm ? "return {e.text}" : empty(em.sj_ret) ? e.text : "{em.sj_ret} = {e.text}")
    } elif (!in_arm) {
        line(em, "return")
    }
    if (in_arm) {
        line(em, "return true")
    }
}

def private open_block(var em : Emitter; head : string) {
    line(em, empty(head) ? "\{" : head + " \{")
    em.depth++
}

def private close_block(var em : Emitter) {
    em.depth--
    line(em, "\}")
}

// `setjmp(buf)` tested against zero as an `if` condition: the call below the casts, `!` and
// `== 0` / `!= 0`, and whether the then-branch is the first run (zero) or the longjmp return
def private setjmp_site(x : CirExpr const?; var first_in_then : bool&) : CirExpr const? {
    var at = x
    first_in_then = false
    while (at != null) {
        if (at.e == "cast" && (at.cast_kind == "IntegralToBoolean" || at.cast_kind == "LValueToRValue" || at.cast_kind == "NoOp" || at.cast_kind == "IntegralCast")) {
            at = at.a
        } elif (at.e == "un" && at.op == "not") {
            first_in_then = !first_in_then
            at = at.a
        } elif (at.e == "bin" && (at.op == "eq" || at.op == "ne") && at.b.e == "int_lit" && at.b.v == "0") {
            first_in_then = at.op == "eq" ? !first_in_then : first_in_then
            at = at.a
        } else {
            break
        }
    }
    if (at == null || at.e != "call" || at.fn == null || length(at.args) != 1) {
        return null
    }
    var callee = at.fn
    if (callee.e == "cast" && callee.cast_kind == "FunctionToPointerDecay") {
        callee = callee.a
    }
    return callee.e == "ref" && key_exists(SETJMP_NAMES, callee.name) ? at.args[0] : null
}

// the contained setjmp site of docs/lowering-examples.md: the first run is the `try`, the
// longjmp return the `recover`, which rethrows a longjmp to another buffer or a genuine
// panic (a null target) and clears its own
def private emit_setjmp_site(var em : Emitter; tu : CirTu; st : CirStmt; buf : CirExpr const?; first_in_then : bool) {
    let first = first_in_then ? st.then_s : st.else_s
    let again = first_in_then ? st.else_s : st.then_s
    var first_returns, again_returns : bool
    if (!arm_returns(em, array<CirStmt const?>(first), st.loc, first_returns) || !arm_returns(em, array<CirStmt const?>(again), st.loc, again_returns)) {
        return
    }
    // the JIT takes a `break` or `continue` out of a `try` whose `recover` can rethrow as leaving
    // the `try` alone (docs/probe-findings.md F97), and a block carries neither
    if (leaves_arm(first) || leaves_arm(again)) {
        fail(em, "a setjmp arm that leaves an enclosing loop is not lowered yet", st.loc)
        return
    }
    em.requires |> insert("c_runtime/setjmp")
    let target = emit_expr(em, tu, buf, st.loc)
    flush_pre(em)
    let declared = open_sj_result(em, first_returns || again_returns)
    open_block(em, "try")
    open_sj_arm(em, first_returns)
    emit_body(em, tu, first)
    close_sj_arm(em, first_returns, ends_in_return(tu, first))
    em.depth--
    open_block(em, "\} recover")
    open_block(em, "if ({JMP_TARGET} != {target.text})")
    line(em, "panic(\"longjmp\")")
    close_block(em)
    line(em, "{JMP_TARGET} = null")
    open_sj_arm(em, again_returns)
    emit_body(em, tu, again)
    close_sj_arm(em, again_returns, ends_in_return(tu, again))
    close_block(em)
    close_sj_result(em, first_returns || again_returns, declared)
}

// whether an arm leaves an enclosing loop or switch
def private leaves_arm(arm : CirStmt const?) : bool => breaks_switch(arm) || continues_out(arm)

def private emit_if(var em : Emitter; tu : CirTu; st : CirStmt; head : string) {
    var first_in_then = false
    let buf = setjmp_site(st.cond, first_in_then)
    if (buf != null) {
        if (head == "if" && st.else_s != null) {
            emit_setjmp_site(em, tu, st, buf, first_in_then)
        } else {
            fail(em, "a setjmp site must be an `if` at a block's statement level, with both branches or the block's tail as its continuation", st.loc)
        }
        return
    }
    let c = truth_of(em, tu, st.cond, st.loc)
    flush_pre(em)
    open_block(em, "{head} ({c.text})")
    emit_body(em, tu, st.then_s)
    if (st.else_s != null) {
        if (st.else_s.s == "if") {
            let mark = length(em.pre)
            let decls_mark = length(em.literal_decls)
            let case_mark = length(em.case_literal_decls)
            let probe = truth_of(em, tu, st.else_s.cond, st.else_s.loc)
            let pure = length(em.pre) == mark
            em.pre |> resize(mark)
            em.literal_decls |> resize(decls_mark)
            em.case_literal_decls |> resize(case_mark)
            if (pure) {
                em.depth--
                emit_if(em, tu, *st.else_s, "\} elif")
                return
            }
        }
        em.depth--
        open_block(em, "\} else")
        emit_body(em, tu, st.else_s)
        close_block(em)
        return
    }
    close_block(em)
}

// C `continue`: das's inside a loop body; inside a matched-flag switch loop it sets the
// switch's `_cont` flag and leaves that loop, whose epilogue continues the real one
def private emit_continue(var em : Emitter) {
    let flag = empty(em.cont_flags) ? "" : em.cont_flags[length(em.cont_flags) - 1]
    if (empty(flag)) {
        line(em, "continue")
    } elif (flag |> starts_with("goto ")) {
        line(em, flag)
    } else {
        line(em, "{flag} = true")
        line(em, "break")
    }
}

// a loop's body: C `continue` and `break` inside it are das's
def private emit_loop_body(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    em.cont_flags |> push("")
    em.break_gotos |> push("")
    emit_body(em, tu, st)
    em.break_gotos |> pop()
    em.cont_flags |> pop()
}

// C `break`: das's, or the `goto` to the end of the open loop or switch it leaves
def private emit_break(var em : Emitter) {
    let jump = empty(em.break_gotos) ? "" : em.break_gotos[length(em.break_gotos) - 1]
    line(em, empty(jump) ? "break" : jump)
}

def private emit_while(var em : Emitter; tu : CirTu; st : CirStmt) {
    let mark = length(em.pre)
    let c = truth_of(em, tu, st.cond, st.loc)
    if (length(em.pre) == mark) {
        open_block(em, "while ({c.text})")
        emit_loop_body(em, tu, st.body_s)
        close_block(em)
        return
    }
    let cond_pre <- [for (idx in range(mark, length(em.pre))); em.pre[idx]]
    em.pre |> resize(mark)
    flush_literal_decls(em)
    open_block(em, "while (true)")
    for (stmt in cond_pre) {
        line(em, stmt)
    }
    open_block(em, "if ({negation(c)})")
    line(em, "break")
    close_block(em)
    emit_loop_body(em, tu, st.body_s)
    close_block(em)
}

def private numbered(base : string; count : int) : string => count == 1 ? base : "{base}{count}"

// `do { body } while (c)`: under the default `loops` option the count-down range (`count_down`),
// a block for `do { body } while (0)` whose body leaves by no `break`, `return`, `goto` or
// `continue` in a function with no `goto`, which plans its labels on the C loop, `while (true)`
// with no test for a body with no `continue` of the loop that always leaves or a `while (0)`,
// `c_do_while (c) { body }` for a test that hoists no statement, else, with no `continue` of the
// loop in the body, the body and then the hoisted test at the bottom of `while (true)`; otherwise
// the `_first` flag, which lets a `continue` reach the test
def private emit_do(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (em.prog.range_loops && count_down(em, tu, st)) {
        return
    }
    let never = below_casts(st.cond)
    let once = never != null && never.e == "int_lit" && never.v == "0"
    if (em.prog.range_loops && once && !em.has_goto && !leaves_loop(st.body_s, false) && !continues_loop(st.body_s, false)) {
        open_block(em, "")
        emit_body(em, tu, st.body_s)
        close_block(em)
        return
    }
    let no_continue = !continues_loop(st.body_s, false)
    // a body that always leaves never reaches the test, and `while (0)` is no test
    if (em.prog.range_loops && no_continue && (once || leaves_at_end(st.body_s))) {
        open_block(em, "while (true)")
        emit_loop_body(em, tu, st.body_s)
        if (once) {
            line(em, "break")
        }
        close_block(em)
        return
    }
    let mark = length(em.pre)
    let c = truth_of(em, tu, st.cond, st.loc)
    if (em.prog.range_loops && length(em.pre) == mark) {
        flush_literal_decls(em)
        em.requires |> insert("c_runtime/{DO_WHILE}")
        open_block(em, "{DO_WHILE} ({once ? "false" : c.text})")
        emit_loop_body(em, tu, st.body_s)
        close_block(em)
        return
    }
    if (em.prog.range_loops && no_continue) {
        let cond_pre <- [for (idx in range(mark, length(em.pre))); em.pre[idx]]
        em.pre |> resize(mark)
        flush_literal_decls(em)
        open_block(em, "while (true)")
        emit_loop_body(em, tu, st.body_s)
        for (stmt in cond_pre) {
            line(em, stmt)
        }
        open_block(em, "if ({negation(c)})")
        line(em, "break")
        close_block(em)
        close_block(em)
        return
    }
    em.first_counter++
    let flag = numbered("_first", em.first_counter)
    if (length(em.pre) == mark) {
        line(em, "var {flag} = true")
        open_block(em, "while ({flag} || {wrap(c, PREC_LOR + 1)})")
        line(em, "{flag} = false")
        emit_loop_body(em, tu, st.body_s)
        close_block(em)
        return
    }
    // a condition with effects (`while (--n > 0)`) runs its statements at the top of every pass
    // but the first, where C evaluates it after the body; a `continue` reaches it there too
    let cond_pre <- [for (idx in range(mark, length(em.pre))); em.pre[idx]]
    em.pre |> resize(mark)
    flush_literal_decls(em)
    line(em, "var {flag} = true")
    open_block(em, "while (true)")
    open_block(em, "if (!{flag})")
    for (stmt in cond_pre) {
        line(em, stmt)
    }
    open_block(em, "if ({negation(c)})")
    line(em, "break")
    close_block(em)
    close_block(em)
    line(em, "{flag} = false")
    emit_loop_body(em, tu, st.body_s)
    close_block(em)
}

// `do { body } while (count--)`, the test uncast, with `count` an `int` or `unsigned` parameter
// or local the function declares once, never takes the address of and holds no `goto`, that the
// body never names and that is dead after the loop (`dead_after`), is
// `for (_t0 in urange64(uint64(uint(count)) + 1ul))`: the body runs `count + 1` times from a
// start at or above 0 and, by the wrap C's decrement takes, `2^32 + count + 1` times from a
// negative one, which that sum is in both cases. False, with nothing spelled, for any other loop
def private count_down(var em : Emitter; tu : CirTu; st : CirStmt const?) : bool {
    // a cast on the test (`(unsigned char) n--`) tests fewer bits than the count holds
    let step = st.cond
    let root = step != null && step.e == "un" && step.op == "postdec" ? below_casts(step.a) : null
    if (root == null || root.e != "ref" || root.vol || em.has_goto || key_exists(em.addressed, root.name)) {
        return false
    }
    let t = em.local_types?[root.name] ?? -1
    let kind = t >= 0 ? range_kind(em, tu, t, st.loc) : ""
    if ((kind != "range" && kind != "urange") || name_count(st.body_s, root.name) > 0 || !dead_after(em, st, root.name)) {
        return false
    }
    let count = das_name(em, root.name)
    let passes = kind == "range" ? "uint64(uint({count})) + 1ul" : "uint64({count}) + 1ul"
    open_block(em, "for ({temp_name(em)} in urange64({passes}))")
    emit_loop_body(em, tu, st.body_s)
    close_block(em)
    return true
}

// true when the body can leave the loop in a way C's increment must not follow: a `break` at
// this loop's level, a `return` or a `goto` anywhere inside
def private leaves_loop(st : CirStmt?; nested : bool) : bool {
    if (st == null) {
        return false
    }
    if (st.s == "return" || st.s == "goto") {
        return true
    }
    if (st.s == "break") {
        return !nested
    }
    let inner = nested || st.s == "while" || st.s == "do" || st.s == "for" || st.s == "switch"
    for (child in st.body) {
        if (leaves_loop(child, inner)) {
            return true
        }
    }
    return leaves_loop(st.then_s, inner) || leaves_loop(st.else_s, inner) || leaves_loop(st.body_s, inner)
}

def private emit_for_flag(var em : Emitter; tu : CirTu; st : CirStmt; inc_lines : array<string>) {
    em.for_counter++
    let flag = numbered("_f", em.for_counter)
    line(em, "var {flag} = false")
    open_block(em, "while (true)")
    open_block(em, "if ({flag})")
    write_increment(em, tu, st, inc_lines)
    close_block(em)
    line(em, "{flag} = true")
    if (st.cond != null) {
        let c = truth_of(em, tu, st.cond, st.loc)
        flush_pre(em)
        open_block(em, "if ({negation(c)})")
        line(em, "break")
        close_block(em)
    }
    emit_loop_body(em, tu, st.body_s)
    close_block(em)
}

// the loop head: `while (cond)`, or `while (true)` plus the test when the condition
// carries hoisted statements or is absent
def private open_for_head(var em : Emitter; tu : CirTu; st : CirStmt) {
    if (st.cond == null) {
        open_block(em, "while (true)")
        return
    }
    let mark = length(em.pre)
    let c = truth_of(em, tu, st.cond, st.loc)
    if (length(em.pre) == mark) {
        open_block(em, "while ({c.text})")
        return
    }
    let cond_pre <- [for (idx in range(mark, length(em.pre))); em.pre[idx]]
    em.pre |> resize(mark)
    flush_literal_decls(em)
    open_block(em, "while (true)")
    for (stmt in cond_pre) {
        line(em, stmt)
    }
    open_block(em, "if ({negation(c)})")
    line(em, "break")
    close_block(em)
}

// the statements of C's increment `st.inc`, each evaluation's: a compound literal object in it is
// assigned there and declared in `em.literal_decls`
def private increment_lines(var em : Emitter; tu : CirTu; st : CirStmt) : array<string> {
    let mark = length(em.pre)
    em.narrow++
    emit_effect(em, tu, st.inc, st.loc)
    em.narrow--
    var lines <- [for (idx in range(mark, length(em.pre))); em.pre[idx]]
    em.pre |> resize(mark)
    return <- lines
}

// the increment's statements where the loop runs them: `ahead`, the ones `emit_for` spelled before
// the loop, when it holds a compound literal, else spelled here
def private write_increment(var em : Emitter; tu : CirTu; st : CirStmt; ahead : array<string>) {
    if (!holds_compound_literal(st.inc)) {
        let lines <- increment_lines(em, tu, st)
        for (stmt in lines) {
            line(em, stmt)
        }
        return
    }
    for (stmt in ahead) {
        line(em, stmt)
    }
}

// whether `x` holds a compound literal
def private holds_compound_literal(x : CirExpr const?) : bool {
    var found = false
    each_subexpr(x) $(sub) {
        found = found || sub.e == "compound_lit"
    }
    return found
}

// a compound literal in the increment lives as long as the `for` (C11 6.8.5p5), past the block
// the increment's statements land in: its object is declared ahead, in the `for`'s own block. A
// canonical counting loop is a das range loop (`for_range`); the increment of any other is the
// body's last statement when the body holds no `continue` of the loop, else the `finally` block
// when the body never leaves the loop, else the increment-first flag
def private emit_for(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (for_range(em, tu, st)) {
        return
    }
    let opened = length(em.out)
    open_block(em, "")
    if (st.init_s != null) {
        emit_body(em, tu, st.init_s)
    }
    let ahead = st.inc != null && holds_compound_literal(st.inc)
    let inc_lines <- ahead ? increment_lines(em, tu, *st) : array<string>()
    if (ahead) {
        flush_literal_decls(em)
    }
    if (st.inc != null && continues_loop(st.body_s, false) && leaves_loop(st.body_s, false)) {
        emit_for_flag(em, tu, *st, inc_lines)
    } else {
        open_for_head(em, tu, *st)
        if (st.inc == null) {
            emit_loop_body(em, tu, st.body_s)
        } elif (!continues_loop(st.body_s, false)) {
            emit_loop_body(em, tu, st.body_s)
            // a body ending in a `break`, a `return` or a `goto` never reaches the increment
            if (!leaves_at_end(st.body_s)) {
                write_increment(em, tu, *st, inc_lines)
            }
        } else {
            open_block(em, "")
            emit_loop_body(em, tu, st.body_s)
            em.depth--
            open_block(em, "\} finally")
            write_increment(em, tu, *st, inc_lines)
            close_block(em)
        }
        close_block(em)
    }
    close_block(em)
    unbrace_plain(em, opened)
}

// true when the body holds a C `continue` of this loop: one outside every nested loop, a switch's
// included
def private continues_loop(st : CirStmt?; nested : bool) : bool {
    if (st == null) {
        return false
    }
    if (st.s == "continue") {
        return !nested
    }
    let inner = nested || st.s == "while" || st.s == "do" || st.s == "for"
    for (child in st.body) {
        if (continues_loop(child, inner)) {
            return true
        }
    }
    return continues_loop(st.then_s, inner) || continues_loop(st.else_s, inner) || continues_loop(st.body_s, inner)
}

// the das range of a counting variable of C type `t`: `range`, `range64`, `urange`, `urange64`;
// "" for a type no range counts
def private range_kind(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    if (kind_of(tu, t) != "int" || is_c_bool(tu, t)) {
        return ""
    }
    let spelled = das_type(em, tu, t, loc)
    return spelled == "int" ? "range" : spelled == "int64" ? "range64" : spelled == "uint" ? "urange" : spelled == "uint64" ? "urange64" : ""
}

// the one declaration a `for`'s initializer holds, null for any other initializer
def private counter_decl(st : CirStmt const?) : CirStmt const? {
    if (st == null) {
        return null
    }
    if (st.s == "decl") {
        return st.init != null ? st : null
    }
    if (st.s == "compound" && length(st.body) == 1) {
        return counter_decl(st.body[0])
    }
    return null
}

// `x` is a read of variable `name`: the reference under its load
def private reads_variable(x : CirExpr const?; name : string) : bool {
    let root = below_casts(x)
    return root != null && root.e == "ref" && root.name == name && x.e == "cast" && x.cast_kind == "LValueToRValue" && !root.vol
}

// `inc` adds one to `name`: `++i`, `i++`, `i += 1`
def private steps_by_one(inc : CirExpr const?; name : string) : bool {
    if (inc == null) {
        return false
    }
    let target = inc.e == "un" || inc.e == "assign" ? below_casts(inc.a) : null
    if (target == null || target.e != "ref" || target.name != name || target.vol) {
        return false
    }
    if (inc.e == "un") {
        return inc.op == "preinc" || inc.op == "postinc"
    }
    let one = below_casts(inc.b)
    return inc.op == "add" && one != null && one.e == "int_lit" && one.v == "1"
}

// the names statement tree `st` assigns, steps or takes the address of, below casts
def private written_names(st : CirStmt const?) : table<string> {
    var names : table<string>
    each_expr(st) $(x) {
        if (x.e == "assign" || (x.e == "un" && (is_step(x.op) || x.op == "addr"))) {
            let root = below_casts(x.a)
            if (root != null && root.e == "ref") {
                names |> insert(root.name)
            }
        }
    }
    return <- names
}

// adds to `names` the variable of every address statement tree `st` forms: the storage root
// (`storage_root`) of each `&` operand and of each array that decays other than to be indexed
def private addressed_roots(st : CirStmt const?; var names : table<string>) {
    var indexed : table<uint64>
    each_expr(st) $(x) {
        if (x.e == "index") {
            indexed |> insert(intptr(x.base))
        }
        let formed = (x.e == "un" && x.op == "addr") || (x.e == "cast" && x.cast_kind == "ArrayToPointerDecay" && !key_exists(indexed, intptr(x)))
        if (formed) {
            let root = storage_root(below_casts(x.a))
            if (!empty(root)) {
                names |> insert(root)
            }
        }
    }
}

// a loop bound C reads before every pass that reads the same value each time (`for_range`):
// literals, constants, locals, parameters and globals that `body` never names in a store or an
// `&`, and members by `.` and `->`, under casts and `+`, `-`, `*`, never a call, a volatile object,
// a local something points at or a load the body's stores may change (`store_misses`); a body
// with a call keeps a bound that reads a global or through a pointer, which the callee may write
def private invariant_bound(em : Emitter; tu : CirTu; x : CirExpr const?; written : table<string>; body : CirStmt const?) : bool {
    var ok = x != null
    var memory = false
    var loads : array<Access>
    each_subexpr(x) $(sub) {
        if (sub.e == "ref") {
            let global = key_exists(em.prog.global_names, sub.name)
            ok = ok && !sub.vol && !key_exists(written, sub.name) && (global || !key_exists(em.escaped, sub.name))
            memory ||= global
        } elif (sub.e == "member") {
            ok = ok && !sub.vol
            memory ||= sub.arrow
        } elif (sub.e == "bin") {
            ok = ok && (sub.op == "add" || sub.op == "sub" || sub.op == "mul")
        } elif (sub.e == "cast") {
            ok = ok && (sub.cast_kind == "LValueToRValue" || sub.cast_kind == "IntegralCast" || sub.cast_kind == "NoOp")
            if (sub.cast_kind == "LValueToRValue") {
                loads |> push(Access(t = access_type(tu, sub.a), root = storage_root(sub.a)))
            }
        } else {
            ok = ok && (sub.e == "int_lit" || sub.e == "enum_ref" || sub.e == "sizeof_v" || sub.e == "alignof_v")
        }
    }
    if (!ok || (memory && !calls_miss(em, tu, body, loads))) {
        return false
    }
    var misses = true
    each_expr(body) $(store) {
        if (store.e == "assign" || (store.e == "un" && is_step(store.op))) {
            let target = below_casts(store.a)
            let access = Access(t = access_type(tu, target), root = storage_root(target))
            for (load in loads) {
                misses = misses && store_misses(em, tu, access, load)
            }
        }
    }
    return misses
}

// an lvalue a loop bound loads or a loop body stores: its C type, and the variable whose own
// storage holds it (`storage_root`), "" for one reached through a pointer
struct Access {
    t : int
    root : string
}

// the variables expression `x` (not its operands) points at: the storage root of an `&` operand
// or of an array that decays, the only ways C forms a pointer to a variable
def private mark_pointed(x : CirExpr const?; var names : table<string>) {
    if ((x.e == "un" && x.op == "addr") || (x.e == "cast" && x.cast_kind == "ArrayToPointerDecay")) {
        let root = storage_root(below_casts(x.a))
        if (!empty(root)) {
            names |> insert(root)
        }
    }
}

// whether no call in statement tree `body` may store to a load of the bound (`loads`), by the
// callees' summaries (`summarize`)
def private calls_miss(em : Emitter; tu : CirTu; body : CirStmt const?; loads : array<Access>) : bool {
    var misses = true
    each_expr(body) $(x) {
        if (misses && x.e == "call") {
            let effects = callee_effects(em.prog.summaries, x)
            for (load in loads) {
                misses = misses && !call_stores(em, tu, em.prog.summaries.effects[effects], load)
            }
        }
    }
    return misses
}

// whether a call of `effects` may store to the object `load` reads: one it stores to by name, a
// variable a pointer reaches or an access through a pointer when it stores through one (apart
// by type only under the sidecar's `strict_aliasing: true`, `alias_class`), an access through a
// pointer when it stores by name to a global a pointer reaches; every object for an unknown callee
def private call_stores(em : Emitter; tu : CirTu; effects : CallEffects; load : Access) : bool {
    if (effects.all) {
        return true
    }
    var through = effects.through && !em.prog.strict_aliasing
    if (effects.through && em.prog.strict_aliasing) {
        for (t in keys(effects.through_types)) {
            // -1, every type, has the class "", which aliases every class
            through ||= classes_alias(alias_class(tu, t), alias_class(tu, load.t))
        }
    }
    if (empty(load.root)) {
        return through || effects.pointed_global
    }
    let by_name = key_exists(em.prog.global_names, load.root) && stores_global(em.prog.summaries, effects, load.root)
    return by_name || (through && pointed_at(em, load.root))
}

// whether every call in statement tree `body` surely returns and does no input or output, so the
// body cannot end the run early or keep a loop of its own running forever (`summarize`)
def private calls_return(em : Emitter; body : CirStmt const?) : bool {
    var quiet = true
    each_expr(body) $(x) {
        if (quiet && x.e == "call") {
            let effects = callee_effects(em.prog.summaries, x)
            quiet = em.prog.summaries.effects[effects].returns && !em.prog.summaries.effects[effects].io
        }
    }
    return quiet
}

// whether a pointer may reach variable `name`: a local or parameter whose address escapes
// (`em.escaped`), a global the program points at or does not define
def private pointed_at(em : Emitter; name : string) : bool {
    if (key_exists(em.prog.global_names, name)) {
        return key_exists(em.prog.pointed, name) || !key_exists(em.prog.defined_globals, name)
    }
    return key_exists(em.escaped, name)
}

// whether `store` provably leaves the value `load` reads alone. Two variables' storage is apart;
// a variable no pointer reaches (`pointed_at`) is apart from every access through a pointer. Two
// accesses through pointers, or one through a pointer and a variable a pointer reaches, are apart
// only by C's type-based aliasing (C11 6.5p7), which a program converted under the sidecar's
// `strict_aliasing: true` keeps: types of different alias classes (`alias_class`)
def private store_misses(em : Emitter; tu : CirTu; store, load : Access) : bool {
    if (!empty(store.root) && !empty(load.root)) {
        return store.root != load.root
    }
    let named = empty(store.root) ? load.root : store.root
    if (!empty(named) && !pointed_at(em, named)) {
        return true
    }
    return em.prog.strict_aliasing && !classes_alias(alias_class(tu, store.t), alias_class(tu, load.t))
}

// the class of C type `t` under C's type-based aliasing: an integer by its width (a signed type
// and its unsigned twin alias), `_Bool`, an enum, a floating type by its width, every pointer
// one class; "" for a character type, which accesses any object, and a record, an array or any
// other type, whose store may change every member
def private alias_class(tu : CirTu; t : int) : string {
    let k = kind_of(tu, t)
    if (k == "int") {
        return is_c_bool(tu, t) ? "bool" : tu.types[t].w <= 8 ? "" : "i{tu.types[t].w}"
    }
    return k == "enum" ? "enum" : k == "float" ? "f{tu.types[t].w}" : k == "ptr" ? "ptr" : ""
}

// whether two alias classes (`alias_class`) may name one object: equal, either "", or an enum and
// an integer, whose compatible type the implementation picks
def private classes_alias(a, b : string) : bool =>
    empty(a) || empty(b) || a == b || (a == "enum" && starts_with(b, "i")) || (b == "enum" && starts_with(a, "i"))

// a counted `for` loop `for_range` takes: the counter's C name and C type, its start and the
// das range that counts it; `kind` is "" for any other loop
struct CountedFor {
    name : string
    t : int
    start : CirExpr const?
    kind : string
    // the initializer declares the counter (C99), else it assigns a local declared before (C89)
    declared : bool
    // the test is `i <= n`, which counts to `n + 1` (`inclusive_end`)
    inclusive : bool
}

// the plain store `i = a` a `for`'s initializer is, into a variable that `a` does not read;
// null for any other initializer
def private counter_store(st : CirStmt const?) : CirExpr const? {
    if (st != null && st.s == "compound" && length(st.body) == 1) {
        return counter_store(st.body[0])
    }
    if (st == null || st.s != "expr" || st.e.e != "assign" || st.e.op != "") {
        return null
    }
    let root = below_casts(st.e.a)
    return root != null && root.e == "ref" && !root.vol && !reads_name(st.e.b, root.name) ? st.e : null
}

// whether expression `x` names variable `name`
def private reads_name(x : CirExpr const?; name : string) : bool {
    var found = false
    each_subexpr(x) $(sub) {
        found ||= sub.e == "ref" && sub.name == name
    }
    return found
}

// how many times statement tree `st` names variable `name`
def private name_count(st : CirStmt const?; name : string) : int {
    var n = 0
    each_expr(st) $(x) {
        if (x.e == "ref" && x.name == name) {
            n++
        }
    }
    return n
}

// O1 of the plan, the "General for" of docs/lowering-examples.md: `for (T i = a; i < n; ++i)`
// with `i` an integer of 32 or 64 bits that the body never writes or takes the address of and
// `n` an invariant bound (`invariant_bound`) of `i`'s type; `for (i = a; i < n; ++i)` too when
// `i` is a parameter or a local the function declares once, holds no `goto` and reads no more after the loop
// (`dead_after`); `i <= n` too where `n + 1` cannot wrap (`inclusive_counts`). Under `loops`
// `while` no loop is one
def private counted_for(var em : Emitter; tu : CirTu; st : CirStmt const?) : CountedFor {
    var loop : CountedFor
    if (!em.prog.range_loops || st.cond == null || st.cond.e != "bin" || (st.cond.op != "lt" && st.cond.op != "le")) {
        return loop
    }
    let decl = counter_decl(st.init_s)
    let store = decl == null ? counter_store(st.init_s) : null
    if (decl != null) {
        loop = CountedFor(name = decl.name, t = decl.t, start = decl.init, declared = true)
    } elif (store != null && !em.has_goto) {
        let name = below_casts(store.a).name
        loop = CountedFor(name = name, t = em.local_types?[name] ?? -1, start = store.b)
        if (loop.t < 0) {
            return CountedFor()
        }
    } else {
        return loop
    }
    if (!steps_by_one(st.inc, loop.name) || !reads_variable(st.cond.a, loop.name) || st.cond.a.t != loop.t || st.cond.b.t != loop.t) {
        return CountedFor()
    }
    var written <- written_names(st.body_s)
    // a variable whose address the body forms (`&b.n`, a member array passed on) may change
    // through it, by a call or a store, whatever the summaries say of the callee
    addressed_roots(st.body_s, written)
    if (key_exists(written, loop.name) || key_exists(em.addressed, loop.name)) {
        return CountedFor()
    }
    // the increment writes the counter, so a bound that reads it is no invariant
    written |> insert(loop.name)
    if (!invariant_bound(em, tu, st.cond.b, written, st.body_s) || (!loop.declared && !dead_after(em, st, loop.name))) {
        return CountedFor()
    }
    loop.inclusive = st.cond.op == "le"
    if (loop.inclusive && !inclusive_counts(em, tu, st, loop.t)) {
        return CountedFor()
    }
    loop.kind = range_kind(em, tu, loop.t, st.loc)
    return loop
}

// whether `for (i = a; i <= n; ++i)` counts the passes `range(a, n + 1)` does, which wraps to an
// empty range where `n` is its type's maximum: a constant `n` below the maximum (a constant at it
// stays `while`), or, for a signed `i`, a body that cannot end the run before `i` steps past the
// maximum, which C leaves undefined, so a defined run never meets `n + 1` wrapped. Such a body
// holds no `break` of the loop, `return` or `goto` (`leaves_loop`), no call, which may `exit` or
// `longjmp`, no volatile access, and no loop of its own whose test reads no object (`reads_object`):
// that is a constant test (`while (!0)`, an enumerator, `sizeof`) or none, a loop C lets run
// forever; a loop testing an object, with no call or volatile access, C11 6.8.5p6 lets the
// implementation assume ends
def private inclusive_counts(em : Emitter; tu : CirTu; st : CirStmt const?; t : int) : bool {
    if (inclusive_constant(tu, st.cond.b, t) >= 0l) {
        return true
    }
    if (constant_index(tu, st.cond.b) >= 0l || is_unsigned(tu, t) || leaves_loop(st.body_s, false) || !calls_return(em, st.body_s)) {
        return false
    }
    var endless = false
    each_stmt(st.body_s) $(s) {
        endless ||= (s.s == "while" || s.s == "do" || s.s == "for") && may_run_forever(em.prog.summaries, s)
    }
    each_expr(st.body_s) $(x) {
        endless ||= (x.e == "ref" || x.e == "member" || x.e == "index" || (x.e == "un" && x.op == "deref")) && x.vol
    }
    return !endless
}

// the value of constant loop bound `x` (`constant_index`) where its successor fits counter type
// `t`, else -1
def private inclusive_constant(tu : CirTu; x : CirExpr const?; t : int) : int64 {
    let n = constant_index(tu, x)
    return n >= 0l && n < LONG_MAX && holds_value(tu, t, n + 1l) ? n : -1l
}

// the end of the range `i <= n` counts to: `n + 1` in the range's type, the successor itself for a
// literal `n` (`last`, the constant's value, -1 for any other bound)
def private inclusive_end(bound : Em; last : int64; kind : string) : string {
    let suffix = kind == "range64" ? "l" : kind == "urange" ? "u" : kind == "urange64" ? "ul" : ""
    return last >= 0l && bound.text == "{last}{suffix}" ? "{last + 1l}{suffix}" : "{wrap(bound, PREC_ADD)} + 1{suffix}"
}

// a counted loop (`counted_for`) is `for (i in range(a, n))`; das evaluates `a` then `n` once,
// C's order, and `i` dies with the loop as C99's does and as C89's is dead after it. das refuses
// a loop variable that shadows a local, so a C89 counter whose declaration stays counts in a
// free name. False, with nothing spelled, for any other loop
def private for_range(var em : Emitter; tu : CirTu; st : CirStmt const?) : bool {
    let loop = counted_for(em, tu, st)
    if (empty(loop.kind)) {
        return false
    }
    let mark = length(em.pre)
    let first = emit_expr(em, tu, loop.start, st.loc)
    let bound = emit_expr(em, tu, st.cond.b, st.loc)
    // the start's statements go before the loop, in a block of its own as C scopes them
    let scoped = length(em.pre) != mark
    if (scoped) {
        open_block(em, "")
        flush_pre(em)
    }
    let zero = below_casts(loop.start)
    let start = zero.e == "int_lit" && zero.v == "0" ? "" : "{first.text}, "
    let fresh = !loop.declared && !key_exists(em.range_counters, loop.name)
    if (fresh) {
        em.renames[loop.name] = fresh_counter(em, loop.name)
    }
    let end = loop.inclusive ? inclusive_end(bound, inclusive_constant(tu, st.cond.b, loop.t), loop.kind) : bound.text
    open_block(em, "for ({das_name(em, loop.name)} in {loop.kind}({start}{end}))")
    emit_loop_body(em, tu, st.body_s)
    close_block(em)
    if (fresh) {
        em.renames |> erase(loop.name)
    }
    if (scoped) {
        close_block(em)
    }
    return true
}

// the name C89 counter `name` counts in where its declaration stays: its das name (`_c_block`
// for a das keyword) with the first number neither the function nor a global spells, the same
// for every loop of the counter
def private fresh_counter(var em : Emitter; name : string) : string {
    if (!key_exists(em.range_fresh, name)) {
        let base = das_name(em, name)
        var fresh = free_name(em.spelled, base)
        while (key_exists(em.prog.global_names, fresh)) {
            fresh = free_name(em.spelled, base)
        }
        em.range_fresh[name] = fresh
    }
    return em.range_fresh[name]
}

// the per-function facts the counted loops read (the `Emitter` fields above `fn_body`): a C89
// counter whose every reference sits in counted loops that assign it, whose declaration holds no
// initializer or a literal one and is no switch's carried one, loses its declaration and counts
// in its own name
def private plan_counted_loops(var em : Emitter; tu : CirTu; d : CirDecl) {
    let body = d.body
    em.fn_body = body
    em.has_goto = false
    em.local_types |> clear()
    em.range_counters |> clear()
    em.range_fresh |> clear()
    for (p in d.params) {
        em.local_types[p.name] = p.t
    }
    var counts : table<string; int>
    count_decls(body, counts)
    var decls : table<string; CirStmt const?>
    each_stmt(body) $(s) {
        em.has_goto ||= s.s == "goto"
        if (s.s == "decl" && (counts?[s.name] ?? 0) == 1) {
            em.local_types[s.name] = s.t
            decls[s.name] = s
        }
    }
    var in_loops : table<string; int>
    each_stmt(body) $(s) {
        // a loop a case label below its switch's level enters is spelled open, never a range
        if (s.s == "for" && !key_exists(em.opened, intptr(s))) {
            let loop = counted_for(em, tu, s)
            if (!empty(loop.kind) && !loop.declared) {
                in_loops[loop.name] = (in_loops?[loop.name] ?? 0) + name_count(s, loop.name)
            }
        }
    }
    for (name, n in keys(in_loops), values(in_loops)) {
        let decl = decls?[name] ?? null
        let init = decl != null ? below_casts(decl.init) : null
        if (decl != null && n == name_count(body, name) && !key_exists(em.prog.carried, intptr(decl)) && (init == null || init.e == "int_lit")) {
            em.range_counters |> insert(name)
        }
    }
}

// what the statements a path runs after a loop do with a variable: `not_found` when the loop is
// not among them, `fell_off` when the path reaches their end without naming it, `dead` when it
// assigns the variable or returns before any read, `live` when it may read it first
enum LoopFlow {
    not_found
    fell_off
    dead
    live
}

// whether local `name` is dead once loop `target` of the function being emitted exits: on every
// path from the loop's end it is assigned, or the function returns, before any read. The walk
// follows the statements after the loop in order, around every enclosing loop (its test, then
// its body from the top) and out of it; a `break` or `continue` on the way counts as a read.
// The function holds no `goto` and takes no address of `name`, which the caller checks
def private dead_after(em : Emitter; target : CirStmt const?; name : string) : bool {
    let flow = flow_around(em.fn_body, target, name)
    return flow == LoopFlow.dead || flow == LoopFlow.fell_off
}

// statement `st` holds loop `target`: what the path from the loop's end does with `name` until
// it leaves `st`
def private flow_around(st : CirStmt const?; target : CirStmt const?; name : string) : LoopFlow {
    if (st == null) {
        return LoopFlow.not_found
    }
    if (st == target) {
        return LoopFlow.fell_off
    }
    if (st.s == "compound") {
        for (idx, child in range(length(st.body)), st.body) {
            let flow = flow_around(child, target, name)
            if (flow == LoopFlow.fell_off) {
                return flow_list(st.body, idx + 1, name, false)
            } elif (flow != LoopFlow.not_found) {
                return flow
            }
        }
        return LoopFlow.not_found
    }
    if (st.s == "if") {
        let flow = flow_around(st.then_s, target, name)
        return flow != LoopFlow.not_found ? flow : flow_around(st.else_s, target, name)
    }
    if (st.s == "switch") {
        return flow_around(st.body_s, target, name)
    }
    if (st.s == "while" || st.s == "do" || st.s == "for") {
        let flow = flow_around(st.body_s, target, name)
        if (flow != LoopFlow.fell_off) {
            return flow
        }
        if (reads_name(st.cond, name) || reads_name(st.inc, name)) {
            return LoopFlow.live
        }
        // the next pass from the top: with no read before an assignment, the path leaves the loop
        return flow_through(st.body_s, name) == LoopFlow.live ? LoopFlow.live : LoopFlow.fell_off
    }
    return LoopFlow.not_found
}

// the statements of `list` from `first` on, run in order, inside a loop of the walked statements
// when `nested`
def private flow_list(list : array<CirStmt?>; first : int; name : string; nested : bool) : LoopFlow {
    for (idx in range(first, length(list))) {
        let flow = flow_through(list[idx], name, nested)
        if (flow != LoopFlow.fell_off) {
            return flow
        }
    }
    return LoopFlow.fell_off
}

// statement `st`, run from its start: `dead`, `live` or `fell_off`. A plain store into `name`
// that reads nothing of it, its declaration and a `for` whose initializer is one assign it; an
// `if` takes the worse of its arms; a `break` or `continue` is a read unless it binds to a loop
// inside the walked statements (`nested`), where it ends the pass, and so is a statement that
// does not name `name` but holds one that leaves it (`escapes`); a loop or switch that names
// `name` is `flow_loop`'s
def private flow_through(st : CirStmt const?; name : string; nested : bool = false) : LoopFlow {
    if (st == null) {
        return LoopFlow.fell_off
    }
    if (st.s == "compound") {
        return flow_list(st.body, 0, name, nested)
    }
    if (st.s == "decl" && st.name == name) {
        return LoopFlow.dead
    }
    if (st.s == "expr" || st.s == "for") {
        let store = st.s == "expr" ? counter_store(st) : counter_store(st.init_s)
        if (store != null && below_casts(store.a).name == name) {
            return LoopFlow.dead
        }
    }
    if (st.s == "return") {
        return reads_name(st.e, name) ? LoopFlow.live : LoopFlow.dead
    }
    if (st.s == "break" || st.s == "continue") {
        return nested ? LoopFlow.fell_off : LoopFlow.live
    }
    if (name_count(st, name) == 0) {
        return !nested && escapes(st) ? LoopFlow.live : LoopFlow.fell_off
    }
    if (st.s == "if" && !reads_name(st.cond, name)) {
        let a = flow_through(st.then_s, name, nested)
        let b = flow_through(st.else_s, name, nested)
        return a == LoopFlow.live || b == LoopFlow.live ? LoopFlow.live : a == LoopFlow.dead && b == LoopFlow.dead ? LoopFlow.dead : LoopFlow.fell_off
    }
    return flow_loop(st, name)
}

// whether statement `st` holds a `break` or a `continue` that leaves it: one outside every loop
// and switch inside it, a `continue` inside a switch included
def private escapes(st : CirStmt const?) : bool {
    var found = false
    walk_escapes(st, false, false, found)
    return found
}

def private walk_escapes(st : CirStmt const?; in_loop, in_switch : bool; var found : bool&) {
    if (st == null || found) {
        return
    }
    if (st.s == "break") {
        found = !in_loop && !in_switch
        return
    }
    if (st.s == "continue") {
        found = !in_loop
        return
    }
    let loop = in_loop || st.s == "while" || st.s == "do" || st.s == "for"
    let switch_ = in_switch || st.s == "switch"
    for (child in st.body) {
        walk_escapes(child, loop, switch_, found)
    }
    walk_escapes(st.then_s, loop, switch_, found)
    walk_escapes(st.else_s, loop, switch_, found)
    walk_escapes(st.body_s, loop, switch_, found)
}

// loop or switch `st` that names `name`, run from its start: a `while` or `for` whose head reads
// nothing of it takes its body's first pass, which it may skip, a `do` its body's, which a
// `break` or a `continue` may leave early; any other is a read
def private flow_loop(st : CirStmt const?; name : string) : LoopFlow {
    if ((st.s == "while" || st.s == "for") && name_count(st.init_s, name) == 0 && !reads_name(st.cond, name) && !reads_name(st.inc, name)) {
        return flow_through(st.body_s, name, true) == LoopFlow.live ? LoopFlow.live : LoopFlow.fell_off
    }
    if (st.s == "do") {
        let flow = flow_through(st.body_s, name, true)
        if (flow == LoopFlow.dead) {
            return leaves_loop(st.body_s, false) || continues_loop(st.body_s, false) ? LoopFlow.fell_off : LoopFlow.dead
        }
        return flow == LoopFlow.fell_off && !reads_name(st.cond, name) ? LoopFlow.fell_off : LoopFlow.live
    }
    return LoopFlow.live
}

// where a label or a goto sits: the compound blocks above it, outermost first, and whether
// each is a bare block (one that is its parent's statement, not an `if`, loop or switch body);
// an arm or body that is no block stands in the path too, and `owners` holds the `if`, loop or
// switch whose arm or body each entry is, null for a bare block
struct LabelSite {
    path : array<uint64>
    bare : array<bool>
    owners : array<CirStmt const?>
    // the switches around the site, outermost first, and the case group of each the site is in
    switches : array<uint64>
    groups : array<int>
}

struct LabelPlan {
    labels : table<string; LabelSite>
    gotos : array<CirStmt const?>
    goto_sites : array<LabelSite>
    // the case labels, each with its site
    cases : array<CirStmt const?>
    case_sites : array<LabelSite>
    // the switch bodies, each once its own walk ends: an inner switch before the one around it,
    // and the switch of each
    switch_order : array<uint64>
    switch_stmts : table<uint64; CirStmt const?>
}

// das resolves a label lexically upward, so a goto reaches a label in its own block or an
// enclosing one; the C labels are numbered in order of appearance, every bare block between a
// goto and a deeper label is flattened, and every `if`, loop or switch on that way is spelled
// open, as is every one between a case label and its switch's level
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-into-body")]
def private plan_labels(var em : Emitter; tu : CirTu; body : CirStmt const?) {
    var plan : LabelPlan
    var site : LabelSite
    em.label_count = 0
    walk_labels(em, body, true, null, site, plan)
    for (idx, g in range(length(plan.gotos)), plan.gotos) {
        if (!key_exists(plan.labels, g.label_name)) {
            fail(em, "goto to a label the function does not declare", g.loc)
            return
        }
        var target : LabelSite
        target := plan.labels[g.label_name]
        var common = 0
        while (common < length(target.path) && common < length(plan.goto_sites[idx].path) && target.path[common] == plan.goto_sites[idx].path[common]) {
            common++
        }
        open_path(em, target, common, length(target.path))
        plan_cross_group(em, g, target, plan.goto_sites[idx])
    }
    for (at in plan.case_sites) {
        let level = find_index(at.path, at.switches |> back())
        if (level + 1 < length(at.path)) {
            open_path(em, at, level, length(at.path))
        }
    }
    if (em.prog.goto_dispatch) {
        open_redispatched(em, tu, plan)
    }
    for (c, at in plan.cases, plan.case_sites) {
        if (key_exists(em.flag_switches, at.switches |> back()) && key_exists(em.flatten, at.switches |> back())) {
            fail(em, "a switch spelled open, for a goto into its body or a case label below its level, that a goto from another case re-dispatches is not lowered", c.loc)
            return
        }
    }
    number_restarts(em, tu, plan)
    for (n in values(em.labels)) {
        em.label_count = max(em.label_count, n)
    }
}

// under `switch_dispatch` `goto`, a switch that a goto from another case group re-dispatches and
// the jump table refuses is spelled open in place of the matched-flag loop: each label such a goto
// reaches is then a das label at the switch's level, which the goto jumps to
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#flat-cases")]
def private open_redispatched(var em : Emitter; tu : CirTu; plan : LabelPlan) {
    let switches <- [for (sw in keys(em.flag_switches)); sw]
    for (sw in switches) {
        let st = plan.switch_stmts?[sw] ?? null
        continue if (st == null || dispatch_plan(em, tu, st).span > 0)
        em.opened |> insert(intptr(st))
        enter_arm(em, st.body_s, true)
        em.flag_switches |> erase(sw)
        var inscope names <- [for (name in keys(em.group_labels)); name; where(em.group_labels?[name] ?? 0ul) == sw]
        for (name in names) {
            em.group_labels |> erase(name)
        }
    }
}

// every block on `site`'s path from `from` on loses its braces, and every `if`, loop or switch
// whose arm or body is one is spelled open; an `if` arm no goto enters keeps its braces
// (ARCHITECTURE_EMITTER_CONTROL.md, A goto into a body)
def private open_path(var em : Emitter; site : LabelSite; from, to : int) {
    for (depth in range(from, to)) {
        let owner = site.owners[depth]
        if (owner == null) {
            em.flatten |> insert(site.path[depth])
            continue
        }
        if (owner.s == "if") {
            var first_in_then = false
            if (setjmp_site(owner.cond, first_in_then) != null) {
                fail(em, "a goto into an arm of a setjmp `if` is not lowered", owner.loc)
                return
            }
            enter_arm(em, owner.then_s, site.path[depth] == intptr(owner.then_s))
            enter_arm(em, owner.else_s, site.path[depth] == intptr(owner.else_s))
        } else {
            enter_arm(em, owner.body_s, true)
        }
        em.opened |> insert(intptr(owner))
    }
}

// arm or body `st` of an open statement, when `flat`, spelled at the statement's level
def private enter_arm(var em : Emitter; st : CirStmt const?; flat : bool) {
    if (st != null && flat) {
        em.entered |> insert(intptr(st))
        if (st.s == "compound") {
            em.flatten |> insert(intptr(st))
        }
    }
}

// the das label that restarts each switch a cross-group goto re-dispatches, and each jump table's
// labels: numbered after the C labels, an inner switch's before the one around it
def private number_restarts(var em : Emitter; tu : CirTu; plan : LabelPlan) {
    var count = length(em.labels)
    for (sw in plan.switch_order) {
        var dispatch = dispatch_plan(em, tu, plan.switch_stmts?[sw] ?? null)
        if (dispatch.span > 0) {
            // the case values, the out-of-range target, then one per label a goto re-dispatches to
            dispatch.base = count + 1
            count += dispatch.span + 1 + length([for (name in keys(em.group_labels)); name; where(em.group_labels?[name] ?? 0ul) == sw])
            em.goto_switches[sw] = dispatch
            if (key_exists(em.flag_switches, sw)) {
                em.flag_switches[sw] = dispatch.base
            }
        } elif (key_exists(em.flag_switches, sw)) {
            count++
            em.flag_switches[sw] = count
        }
    }
    // the open lowering's labels number after these too
    em.label_count = max(em.label_count, count)
}

// a goto into another case group of a switch around both (`goto dflt` from `case '$'`): the
// lowering puts each group in its own branch, so the switch takes the matched-flag loop and the
// label becomes a case only the switch's goto variable selects, which every goto to the label
// sets before it restarts the loop
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-labels")]
def private plan_cross_group(var em : Emitter; g : CirStmt const?; target, from : LabelSite) {
    for (depth in range(length(target.switches))) {
        if (depth >= length(from.switches) || target.switches[depth] != from.switches[depth]) {
            return
        }
        if (target.groups[depth] != from.groups[depth]) {
            let sw = target.switches[depth]
            em.group_labels[g.label_name] = sw
            em.flag_switches[sw] = 0
            return
        }
    }
}

def private walk_labels(var em : Emitter; st : CirStmt const?; bare : bool; owner : CirStmt const?; var site : LabelSite; var plan : LabelPlan) {
    if (st == null) {
        return
    }
    if (!bare && st.s != "compound") {
        // an arm or body that is no block: its own entry in the path
        site.path |> push(intptr(st))
        site.bare |> push(false)
        site.owners |> push(owner)
        walk_labels(em, st, true, null, site, plan)
        site.path |> pop()
        site.bare |> pop()
        site.owners |> pop()
        return
    }
    if (st.s == "label") {
        if (!key_exists(em.labels, st.label_name)) {
            em.labels[st.label_name] = length(em.labels) + 1
        }
        plan.labels[st.label_name] := site
    } elif (st.s == "goto") {
        plan.gotos |> push(st)
        var copy : LabelSite
        copy := site
        plan.goto_sites |> emplace(copy)
    } elif ((st.s == "case" || st.s == "default") && !empty(site.switches)) {
        plan.cases |> push(st)
        var copy : LabelSite
        copy := site
        plan.case_sites |> emplace(copy)
    } elif (st.s == "compound") {
        site.path |> push(intptr(st))
        site.bare |> push(bare)
        site.owners |> push(bare ? null : owner)
        for (child in st.body) {
            walk_labels(em, child, true, null, site, plan)
        }
        site.path |> pop()
        site.bare |> pop()
        site.owners |> pop()
    } elif (st.s == "switch" && st.body_s != null && st.body_s.s == "compound") {
        // the case group of every statement at the body's own level: a run of case labels opens one
        site.path |> push(intptr(st.body_s))
        site.bare |> push(false)
        site.owners |> push(st)
        site.switches |> push(intptr(st.body_s))
        site.groups |> push(-1)
        var marker = false
        for (child in st.body_s.body) {
            let is_marker = child.s == "case" || child.s == "default"
            if (is_marker && !marker) {
                site.groups[length(site.groups) - 1]++
            }
            marker = is_marker
            walk_labels(em, child, true, null, site, plan)
        }
        site.path |> pop()
        site.bare |> pop()
        site.owners |> pop()
        site.switches |> pop()
        site.groups |> pop()
        plan.switch_order |> push(intptr(st.body_s))
        plan.switch_stmts[intptr(st.body_s)] = st
    } else {
        walk_labels(em, st.then_s, false, st, site, plan)
        walk_labels(em, st.else_s, false, st, site, plan)
        walk_labels(em, st.body_s, false, st, site, plan)
        walk_labels(em, st.init_s, false, st, site, plan)
    }
}

// one run of labels and the statements under them, up to the next label
struct CaseGroup {
    values : array<int64>
    is_default : bool
    stmts : array<CirStmt const?>
}

// the jump table of a dense switch: das label `base + v - lo` before the group of case value `v`,
// `base + span` the target of every value outside [lo, hi]; `span` 0 for a switch without one
struct GotoDispatch {
    base : int
    lo : int64
    span : int
}

// whether switch `st` takes the jump table under `switch_dispatch` `goto`: 8 or more case values
// in `int`'s range filling at least half of [lo, hi], no group falling into the next, the switch not
// spelled open; its range, else a zero `span`
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-dispatch")]
def private dispatch_plan(var em : Emitter; tu : CirTu; st : CirStmt const?) : GotoDispatch {
    var groups : array<CaseGroup>
    if (!em.prog.goto_dispatch || st == null || key_exists(em.opened, intptr(st)) || !case_groups(em, st.body_s, st.loc, groups)) {
        return GotoDispatch()
    }
    var lo = LONG_MAX
    var hi = LONG_MIN
    var n = 0
    for (idx, g in range(length(groups)), groups) {
        if (idx < length(groups) - 1 && (empty(g.stmts) || !leaves_at_end(g.stmts |> back()))) {
            return GotoDispatch()
        }
        for (v in g.values) {
            var held : int64
            if (!held_value(em, tu, switch_cond_type(tu, *st), v, held)) {
                return GotoDispatch()
            }
            n++
            lo = min(lo, held)
            hi = max(hi, held)
        }
    }
    if (n < 8 || lo < int64(INT_MIN) || hi > int64(INT_MAX) || hi - lo + 1l > 2l * int64(n)) {
        return GotoDispatch()
    }
    return GotoDispatch(lo = lo, span = int(hi - lo + 1l))
}

// case value `v` as a condition of type `cond_t` holds it, for a jump table's range: the C-IR keeps
// `case -1` of an unsigned subject as -1, which the subject holds as its type's largest value;
// false when that value is past `int64`
def private held_value(var em : Emitter; tu : CirTu; cond_t : int; v : int64; var held : int64&) : bool {
    let spelled = kind_of(tu, cond_t) == "enum" ? "int" : das_type(em, tu, cond_t, CirLoc())
    held = spelled == "uint" ? v & int64(UINT_MAX) : v
    return spelled != "uint64" || v >= 0l
}

// a `break` that leaves the switch: one at this level, or inside an `if` or a block here,
// not one inside a nested loop or switch, which is that construct's own
def private breaks_switch(st : CirStmt const?) : bool {
    if (st == null || st.s == "while" || st.s == "do" || st.s == "for" || st.s == "switch") {
        return false
    }
    if (st.s == "break") {
        return true
    }
    for (child in st.body) {
        if (breaks_switch(child)) {
            return true
        }
    }
    return breaks_switch(st.then_s) || breaks_switch(st.else_s) || breaks_switch(st.body_s)
}

// a `continue` that reaches the loop around the switch: anywhere below but inside a loop
def private continues_out(st : CirStmt const?) : bool {
    if (st == null || st.s == "while" || st.s == "do" || st.s == "for") {
        return false
    }
    if (st.s == "continue") {
        return true
    }
    for (child in st.body) {
        if (continues_out(child)) {
            return true
        }
    }
    return continues_out(st.then_s) || continues_out(st.else_s) || continues_out(st.body_s)
}

// a statement after which control cannot fall into the next case: a leaving statement, or a
// block whose last statement is one
def private ends_group(st : CirStmt const?) : bool {
    if (st == null) {
        return false
    }
    if (st.s == "compound") {
        return !empty(st.body) && ends_group(st.body[length(st.body) - 1])
    }
    return st.s == "break" || st.s == "return" || st.s == "goto" || st.s == "continue"
}

// whether control cannot run past the end of loop body `st`: it ends in a leaving statement, or
// in an `if` whose both arms do
def private leaves_at_end(st : CirStmt const?) : bool {
    if (st != null && st.s == "compound") {
        return !empty(st.body) && leaves_at_end(st.body[length(st.body) - 1])
    }
    if (st != null && st.s == "if") {
        return st.else_s != null && leaves_at_end(st.then_s) && leaves_at_end(st.else_s)
    }
    return ends_group(st)
}

// whether the group's last statement leaves the switch only in tail position: the `break`
// itself, or a block ending in one, with no other switch-leaving `break` inside
def private tail_breaks_only(st : CirStmt const?) : bool {
    if (st == null || st.s == "break") {
        return true
    }
    if (st.s == "compound") {
        let n = length(st.body)
        for (idx in range(n - 1)) {
            if (breaks_switch(st.body[idx])) {
                return false
            }
        }
        return n == 0 || tail_breaks_only(st.body[n - 1])
    }
    return !breaks_switch(st)
}

// one statement of a switch body into the groups: a label opens or extends the last group,
// anything else joins it; a statement before the first label fails closed
def private group_statement(var em : Emitter; st : CirStmt const?; loc : CirLoc; var groups : array<CaseGroup>) : bool {
    if (st.s == "case" || st.s == "default") {
        if (empty(groups) || !empty(groups[length(groups) - 1].stmts)) {
            groups |> emplace(CaseGroup())
        }
        if (st.s == "case") {
            groups[length(groups) - 1].values |> push(st.v)
        } else {
            groups[length(groups) - 1].is_default = true
        }
        return true
    }
    if (empty(groups)) {
        if (st.s == "null") {
            return true
        }
        fail(em, "a statement before the first case label is unreachable; not lowered", loc)
        return false
    }
    groups[length(groups) - 1].stmts |> push(st)
    return true
}

// the groups of a switch body, in order
def private case_groups(var em : Emitter; body : CirStmt const?; loc : CirLoc; var groups : array<CaseGroup>) : bool {
    if (body.s != "compound") {
        return group_statement(em, body, loc, groups)
    }
    for (child in body.body) {
        if (!group_statement(em, child, loc, groups)) {
            return false
        }
    }
    join_inert_groups(groups)
    return true
}

// a group whose statements do nothing falls into the next with no effect on the way: it joins the
// next group's labels, so the fall-through is gone; neither group may hold `default`
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#inert-cases")]
def private join_inert_groups(var groups : array<CaseGroup>) {
    var idx = length(groups) - 2
    while (idx >= 0) {
        if (!groups[idx].is_default && !groups[idx + 1].is_default && !has_value([for (st in groups[idx].stmts); is_inert(st)], false)) {
            groups[idx].values |> push_from(groups[idx + 1].values)
            groups[idx + 1].values <- groups[idx].values
            groups |> erase(idx)
        }
        idx--
    }
}

// whether statement `st` does nothing: a `;`, an expression statement with no effect and no
// volatile read (an `assert` emptied by NDEBUG is `(void)0`), a block of such statements
def private is_inert(st : CirStmt const?) : bool {
    if (st == null || st.s == "null") {
        return true
    }
    if (st.s == "expr") {
        return !has_effects(st.e) && !reads_volatile(st.e)
    }
    if (st.s == "compound") {
        for (child in st.body) {
            if (!is_inert(child)) {
                return false
            }
        }
        return true
    }
    return false
}

// the readable if-chain holds when no group falls into the next and every `break` that
// leaves the switch is the last statement of its group
def private is_if_chain(groups : array<CaseGroup>) : bool {
    for (idx, g in range(length(groups)), groups) {
        let n = length(g.stmts)
        for (sidx in range(n - 1)) {
            if (breaks_switch(g.stmts[sidx])) {
                return false
            }
        }
        if ((n > 0 && !tail_breaks_only(g.stmts[n - 1])) || (idx < length(groups) - 1 && !(n > 0 && ends_group(g.stmts[n - 1])))) {
            return false
        }
    }
    return true
}

// a case value against the condition: an enumerator of the condition's enum, else a literal
// of the condition's integer type
def private case_compare(var em : Emitter; tu : CirTu; cond : string; cond_t : int; v : int64) : string {
    if (kind_of(tu, cond_t) == "enum") {
        let named = enumerator_of(tu, cond_t, "{v}")
        return empty(named) ? "int({cond}) == {v}" : "{cond} == {enum_item(em, tu, cond_t, named)}"
    }
    return "{cond} == {case_literal(em, tu, cond_t, v)}"
}

// value `v` as a literal of the condition's integer type, a character literal where the switch
// labels it with one
def private case_literal(var em : Emitter; tu : CirTu; cond_t : int; v : int64) : string {
    let spelled = das_type(em, tu, cond_t, CirLoc())
    let spelling = spelled == "int" && key_exists(em.char_cases, v) ? char_literal(int(v)) : ""
    if (!empty(spelling)) {
        return spelling
    }
    let suffixed = int_literal(spelled, "{v}")
    return v == int64(INT_MIN) && spelled == "int" ? "-2147483647 - 1" : (!empty(suffixed) ? suffixed : "{spelled}({v})")
}

// the value a re-dispatch stores into the condition so that no case test matches it: one below
// the smallest case value, else one above the largest, in the condition's type (an enum's is
// `int`, out-of-range values surviving `enum_from_int`); "" when both fall outside the type
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-labels")]
def private restart_sentinel(var em : Emitter; tu : CirTu; cond_t : int; groups : array<CaseGroup>) : string {
    var lo = LONG_MAX
    var hi = LONG_MIN
    for (g in groups) {
        for (v in g.values) {
            lo = min(lo, v)
            hi = max(hi, v)
        }
    }
    let on_enum = kind_of(tu, cond_t) == "enum"
    let spelled = on_enum ? "int" : das_type(em, tu, cond_t, CirLoc())
    let type_lo = spelled == "int" ? int64(INT_MIN) : (spelled == "int64" ? LONG_MIN : 0l)
    let type_hi = spelled == "int" ? int64(INT_MAX) : (spelled == "uint" ? int64(UINT_MAX) : LONG_MAX)
    if (lo <= type_lo && hi >= type_hi) {
        return ""
    }
    let sentinel = lo > type_lo ? lo - 1l : hi + 1l
    // daslang reads `-2147483648` as a negated constant out of `int`'s range
    return on_enum ? int_to_enum(em, tu, cond_t, sentinel == int64(INT_MIN) ? "-2147483647 - 1" : "{sentinel}") : case_literal(em, tu, cond_t, sentinel)
}

// the switch's condition, evaluated once: the enum below C's promotion when there is one,
// so cases compare symbolically; returns the name of the local and its type
def private switch_condition(var em : Emitter; tu : CirTu; st : CirStmt; var cond_t : int&) : string =>
    switch_condition(em, tu, st, cond_t, false)

// the enum operand below C's promotion of switch `st`'s condition, null when there is none
def private switch_enum_operand(tu : CirTu; st : CirStmt) : CirExpr const? {
    var operand = st.cond
    while (operand != null && operand.e == "cast" && (operand.cast_kind == "IntegralCast" || operand.cast_kind == "LValueToRValue" || operand.cast_kind == "NoOp") && kind_of(tu, operand.a.t) == "enum") {
        operand = operand.a
    }
    return operand != null && kind_of(tu, operand.t) == "enum" ? operand : null
}

// the type the condition of switch `st` is compared in: its enum when it has one
def private switch_cond_type(tu : CirTu; st : CirStmt) : int {
    let operand = switch_enum_operand(tu, st)
    return operand != null ? operand.t : st.cond.t
}

// the same, the local a `var` when `mutable`: a re-dispatch stores its sentinel into it
def private switch_condition(var em : Emitter; tu : CirTu; st : CirStmt; var cond_t : int&; mutable : bool) : string {
    let operand = switch_enum_operand(tu, st)
    let on_enum = operand != null
    cond_t = switch_cond_type(tu, st)
    var c : Em
    if (on_enum) {
        c = emit_expr(em, tu, operand, st.loc)
    } else {
        c = to_int(em, emit_expr(em, tu, st.cond, st.loc))
    }
    flush_pre(em)
    let name = numbered("_cond", em.switch_counter)
    line(em, "{mutable ? "var" : "let"} {name} = {c.text}")
    return name
}

// the three-tier ladder of docs/lowering-examples.md "switch": the if-chain where no case
// falls through and breaks are tail-only, else the matched-flag loop; computed goto (O6)
// is the optimization tier's
def private emit_switch(var em : Emitter; tu : CirTu; st : CirStmt) {
    var groups : array<CaseGroup>
    if (!case_groups(em, st.body_s, st.loc, groups)) {
        return
    }
    em.switch_counter++
    var outer_chars <- em.char_cases
    em.char_cases <- char_cases(st.body_s)
    var cond_t = st.cond.t
    let restart = em.flag_switches?[intptr(st.body_s)] ?? 0
    var dispatch : GotoDispatch
    get(em.goto_switches, intptr(st.body_s)) $(d) {
        dispatch = d
    }
    // a re-dispatch stores a value no case holds into the condition, so the case tests need not
    // test the pending goto; under the jump table it jumps to its label and tests no case
    let sentinel = restart > 0 && dispatch.span == 0 ? restart_sentinel(em, tu, switch_cond_type(tu, st), groups) : ""
    if (restart == 0 && dispatch.span == 0 && switch_macro_fits(em, tu, st, groups)) {
        emit_switch_macro(em, tu, st, groups)
        em.char_cases <- outer_chars
        return
    }
    let cond = switch_condition(em, tu, st, cond_t, !empty(sentinel))
    if (restart > 0) {
        label_cases(em, st, empty(sentinel) ? "" : "{cond} = {sentinel}", dispatch)
    }
    // C scopes a declaration at the body's own level to the whole body, the lowering a group
    // to its own branch: a declaration a later group reaches is declared here
    for (g in groups) {
        for (child in g.stmts) {
            if (child.s == "decl" && key_exists(em.prog.carried, intptr(child))) {
                line(em, "var {das_name(em, child.name)} : {das_type_dims(em, tu, child.t, child.loc, child.dims)}")
            }
        }
    }
    if (is_if_chain(groups) && restart == 0 && dispatch.span == 0) {
        emit_if_chain(em, tu, groups, cond, cond_t)
    } else {
        emit_flag_loop(em, tu, groups, cond, cond_t, st.body_s, restart, !empty(sentinel), dispatch)
    }
    em.char_cases <- outer_chars
}

// whether switch `st` prints as c_runtime's `c_switch` shape macro: every case value of an enum
// condition has its enumerator, and a `continue` that reaches the loop around it is that loop's
// own (the macro rewrites it), not an outer matched-flag switch's or a goto's
def private switch_macro_fits(em : Emitter; tu : CirTu; st : CirStmt; groups : array<CaseGroup>) : bool {
    let cond_t = switch_cond_type(tu, st)
    if (empty(groups) || (continues_out(st.body_s) && !empty(em.cont_flags) && !empty(em.cont_flags |> back()))) {
        return false
    }
    if (kind_of(tu, cond_t) == "enum") {
        for (g in groups) {
            for (v in g.values) {
                if (empty(enumerator_of(tu, cond_t, "{v}"))) {
                    return false
                }
            }
        }
    }
    return true
}

// `c_switch (c) { case (A, B) { ... } ... case (_) { ... } }`: each group an arm in C's order, as
// C wrote it, its breaks and falling into the next arm included; the macro
// (`c_runtime/c_switch.das`) expands to the if-chain or the matched-flag loop, as `is_if_chain`
// tells, its group-level compound literals declared before it in the loop's case
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#switch-macro")]
def private emit_switch_macro(var em : Emitter; tu : CirTu; st : CirStmt; groups : array<CaseGroup>) {
    let cond_t = switch_cond_type(tu, st)
    let operand = switch_enum_operand(tu, st)
    let c = operand != null ? emit_expr(em, tu, operand, st.loc) : to_int(em, emit_expr(em, tu, st.cond, st.loc))
    flush_pre(em)
    for (g in groups) {
        for (child in g.stmts) {
            if (child.s == "decl" && key_exists(em.prog.carried, intptr(child))) {
                line(em, "var {das_name(em, child.name)} : {das_type_dims(em, tu, child.t, child.loc, child.dims)}")
            }
        }
    }
    em.requires |> insert("c_runtime/{C_SWITCH}")
    let looped = !is_if_chain(groups)
    let decls_at = length(em.out)
    let decls_depth = em.depth
    let outer_case_depth = em.case_depth
    var outer_decls <- em.case_literal_decls
    if (looped) {
        em.case_depth = em.stmt_depth + 1
    }
    open_block(em, "{C_SWITCH} ({c.text})")
    em.cont_flags |> push("")
    em.break_gotos |> push("")
    let on_enum = kind_of(tu, cond_t) == "enum"
    for (g in groups) {
        var inscope values <- [for (v in g.values); on_enum ? enum_item(em, tu, cond_t, enumerator_of(tu, cond_t, "{v}")) : case_literal(em, tu, cond_t, v)]
        if (g.is_default) {
            values |> push("_")
        }
        open_block(em, "case ({join(values, ", ")})")
        emit_group(em, tu, g, false)
        close_block(em)
    }
    em.break_gotos |> pop()
    em.cont_flags |> pop()
    close_block(em)
    if (!empty(em.case_literal_decls)) {
        em.out |> push(join([for (decl in em.case_literal_decls); repeat("    ", decls_depth) + decl + "\n"], ""), decls_at)
    }
    em.case_depth = outer_case_depth
    em.case_literal_decls <- outer_decls
}

// the case values switch body `body` labels with a character literal
def private char_cases(body : CirStmt const?) : table<int64> {
    var found : table<int64>
    if (body.s == "case" && body.is_char) {
        found |> insert(body.v)
    }
    if (body.s == "compound") {
        for (st in body.body) {
            if (st.s == "case" && st.is_char) {
                found |> insert(st.v)
            }
        }
    }
    return <- found
}

// each label of switch `st` a goto into its group reaches, as a case of its own number (1 up, in
// the order the labels appear) in the switch's goto variable, which is 0 while no goto is pending:
// no value of the condition stands in for a label, since the condition can hold any of them
def private label_cases(var em : Emitter; st : CirStmt; reset : string; dispatch : GotoDispatch) {
    var names <- [for (name in keys(em.group_labels)); name; where(em.group_labels?[name] ?? 0ul) == intptr(st.body_s)]
    sort(names) <| cmp_by(em.labels?[_] ?? 0)
    for (idx, name in range(length(names)), names) {
        em.label_index[name] = idx + 1
        em.label_flags[name] = numbered("_flag", em.switch_counter)
        em.label_gotos[name] = numbered("_goto", em.switch_counter)
        em.label_conds[name] = reset
        if (dispatch.span > 0) {
            em.label_jumps[name] = dispatch.base + dispatch.span + idx + 1
        }
    }
}

def private emit_if_chain(var em : Emitter; tu : CirTu; groups : array<CaseGroup>; cond : string; cond_t : int) {
    var first = true
    var default_at = -1
    for (idx, g in range(length(groups)), groups) {
        if (g.is_default && empty(g.values)) {
            default_at = idx
            continue
        }
        let tests = join([for (v in g.values); case_compare(em, tu, cond, cond_t, v)], " || ")
        // a default label shared with a case covers every other value: the else branch
        if (g.is_default) {
            default_at = idx
            continue
        }
        if (first) {
            open_block(em, "if ({tests})")
        } else {
            em.depth--
            open_block(em, "\} elif ({tests})")
        }
        first = false
        emit_group(em, tu, g, true)
    }
    if (default_at >= 0) {
        if (first) {
            open_block(em, "")
        } else {
            em.depth--
            open_block(em, "\} else")
        }
        emit_group(em, tu, groups[default_at], true)
        first = false
    }
    if (!first) {
        close_block(em)
    }
}

// a group's statements; the trailing `break` of an if-chain group is the branch's end
def private emit_group(var em : Emitter; tu : CirTu; g : CaseGroup; drop_tail_break : bool) {
    let n = length(g.stmts)
    for (idx in range(n)) {
        if (drop_tail_break && idx == n - 1) {
            emit_without_tail_break(em, tu, g.stmts[idx])
        } else {
            emit_stmt(em, tu, g.stmts[idx])
        }
    }
}

// a statement with its tail `break` dropped, through a trailing block
def private emit_without_tail_break(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (st.s == "break") {
        return
    }
    if (st.s != "compound") {
        emit_stmt(em, tu, st)
        return
    }
    let opened = length(em.out)
    open_block(em, "")
    let n = length(st.body)
    for (idx in range(n)) {
        if (idx == n - 1) {
            emit_without_tail_break(em, tu, st.body[idx])
        } else {
            emit_stmt(em, tu, st.body[idx])
        }
    }
    close_block(em)
    unbrace_plain(em, opened)
}

def private emit_flag_loop(var em : Emitter; tu : CirTu; groups : array<CaseGroup>; cond : string; cond_t : int; body : CirStmt const?; restart : int; sentinel : bool; dispatch : GotoDispatch) {
    let flag = numbered("_flag", em.switch_counter)
    let cont = continues_out(body) ? numbered("_cont", em.switch_counter) : ""
    // every case value of the switch, for `default`'s match-none test
    let all_values <- [for (g in groups); join([for (v in g.values); case_compare(em, tu, cond, cond_t, v)], " || "); where !empty(g.values)]
    // a switch a goto re-dispatches matches a case or `default` only while no goto is pending
    let goto_var = restart > 0 ? numbered("_goto", em.switch_counter) : ""
    // a compound literal of a group-level statement lives as long as the switch body (C11
    // 6.5.2.5p5), which a later group reached by fallthrough reads: declared before the loop
    let decls_at = length(em.out)
    let decls_depth = em.depth
    let outer_case_depth = em.case_depth
    var outer_decls <- em.case_literal_decls
    em.case_depth = em.stmt_depth + 1
    if (!empty(cont)) {
        line(em, "var {cont} = false")
    }
    if (restart > 0) {
        line(em, "var {goto_var} = 0")
    }
    open_block(em, "while (true)")
    if (restart > 0 && dispatch.span == 0) {
        line(em, "label {restart}:  // re-dispatch")
    }
    let plain <- [for (idx in range(length(groups))); plain_case(em, groups, idx, !empty(all_values))]
    var needs_flag = false
    for (idx, g in range(length(groups)), groups) {
        needs_flag ||= !plain[idx] && !empty(g.stmts)
    }
    if (needs_flag) {
        line(em, "var {flag} = false")
    }
    em.cont_flags |> push(cont)
    em.break_gotos |> push("")
    emit_loop_groups(em, tu, groups, plain, cond, cond_t, all_values, flag, goto_var, sentinel, dispatch)
    em.break_gotos |> pop()
    em.cont_flags |> pop()
    line(em, "break")
    close_block(em)
    if (!empty(em.case_literal_decls)) {
        em.out |> push(join([for (decl in em.case_literal_decls); repeat("    ", decls_depth) + decl + "\n"], ""), decls_at)
    }
    em.case_depth = outer_case_depth
    em.case_literal_decls <- outer_decls
    if (!empty(cont)) {
        open_block(em, "if ({cont})")
        emit_continue(em)
        close_block(em)
    }
}

// the groups of the matched-flag loop, under a jump table (`dispatch`'s `span` above 0) behind its
// entry and each after its labels
def private emit_loop_groups(var em : Emitter; tu : CirTu; groups : array<CaseGroup>; plain : array<bool>; cond : string; cond_t : int; all_values : array<string>; flag, goto_var : string; sentinel : bool; dispatch : GotoDispatch) {
    let jumped = dispatch.span > 0
    var cases : table<int64>
    if (jumped) {
        for (g in groups) {
            for (v in g.values) {
                cases |> insert(v)
            }
        }
        dispatch_jump(em, tu, dispatch, cond, cond_t)
    }
    for (idx, g in range(length(groups)), groups) {
        if (jumped) {
            dispatch_labels(em, dispatch, g.values, g.is_default, cases, "default")
        }
        if (!empty(g.stmts)) {
            emit_loop_group(em, tu, g, plain[idx], cond, cond_t, all_values, flag, goto_var, sentinel, jumped)
        }
    }
    if (jumped && !has_value([for (g in groups); g.is_default], true)) {
        dispatch_labels(em, dispatch, array<int64>(), true, cases, "no case: switch end")
    }
}

// one group of the matched-flag loop: a plain case (`plain_case`) as its own `if` on its tests, any
// other under the flag its labels set; `goto_var` is "" unless a goto re-dispatches the switch, and
// under a re-dispatch that stores a `sentinel` into the condition only `default` tests the goto
def private emit_loop_group(var em : Emitter; tu : CirTu; g : CaseGroup; plain : bool; cond : string; cond_t : int; all_values : array<string>; flag, goto_var : string; sentinel, jumped : bool) {
    let pending = empty(goto_var) || jumped || (sentinel && !g.is_default) ? "" : "{goto_var} == 0 && "
    let value_pending = sentinel ? "" : pending
    if (plain) {
        var inscope tests <- [for (v in g.values); case_compare(em, tu, cond, cond_t, v)]
        if (g.is_default) {
            tests |> push("!({join(all_values, " || ")})")
        }
        let test = join(tests, " || ")
        open_block(em, empty(pending) || length(tests) == 1 ? "if ({pending}{test})" : "if ({pending}({test}))")
        emit_group(em, tu, g, false)
        close_block(em)
        return
    }
    for (v in g.values) {
        line(em, "{flag} ||= {value_pending}{case_compare(em, tu, cond, cond_t, v)}")
    }
    if (g.is_default) {
        if (empty(all_values)) {
            line(em, empty(goto_var) ? "{flag} = true" : "{flag} ||= {goto_var} == 0")
        } else {
            line(em, "{flag} ||= {pending}!({join(all_values, " || ")})")
        }
    }
    if (check_group_split(em, g)) {
        open_block(em, "if ({flag})")
        emit_group(em, tu, g, false)
        close_block(em)
    }
}

// the jump table's entry: a value outside [lo, hi] to the out-of-range label, any other to its case's
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-dispatch")]
def private dispatch_jump(var em : Emitter; tu : CirTu; d : GotoDispatch; cond : string; cond_t : int) {
    let on_enum = kind_of(tu, cond_t) == "enum"
    let hi = d.lo + int64(d.span - 1)
    let value = on_enum ? "int({cond})" : cond
    let lo_text = on_enum ? int_text(d.lo) : case_literal(em, tu, cond_t, d.lo)
    let hi_text = on_enum ? int_text(hi) : case_literal(em, tu, cond_t, hi)
    open_block(em, "if ({value} < {lo_text} || {value} > {hi_text})")
    line(em, "goto label {d.base + d.span}")
    close_block(em)
    let offset = int64(d.base) - d.lo
    let target = das_type(em, tu, cond_t, CirLoc()) == "int" && !on_enum ? cond : "int({cond})"
    if (offset > int64(INT_MAX)) {
        // `base - lo` past `int`: the value's distance from `lo` first, which [lo, hi] keeps small
        line(em, "goto ({target} - ({int_text(d.lo)})) + {d.base}")
    } else {
        line(em, offset == 0l ? "goto {target}" : (offset > 0l ? "goto {target} + {offset}" : "goto {target} - {-offset}"))
    }
}

// an `int` value as das reads it: `-2147483648` is a negated constant out of `int`'s range
def private int_text(v : int64) : string => v == int64(INT_MIN) ? "-2147483647 - 1" : "{v}"

// the jump table's labels before a group: one per case value of `values`, and at `default`, or the
// loop's end when the switch has none, one per value of [lo, hi] no case holds, then the
// out-of-range target
def private dispatch_labels(var em : Emitter; d : GotoDispatch; values : array<int64>; at_default : bool; cases : table<int64>; target : string) {
    for (v in values) {
        line(em, "label {d.base + int(v - d.lo)}:  // case {v}")
    }
    if (at_default) {
        for (off in range(d.span)) {
            if (!key_exists(cases, d.lo + int64(off))) {
                line(em, "label {d.base + off}:  // no case {d.lo + int64(off)}")
            }
        }
        line(em, "label {d.base + d.span}:  // {target}")
    }
}

// whether group `idx` of a matched-flag loop is entered by its own labels alone: the group before
// it cannot fall into it, no goto re-dispatches into it and it cannot fall into the next, so its
// branch tests its labels directly and the flag stays unset; `default` needs a case value to
// negate (`has_values`)
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#plain-cases")]
def private plain_case(em : Emitter; groups : array<CaseGroup>; idx : int; has_values : bool) : bool {
    let n = length(groups[idx].stmts)
    if (n == 0 || (groups[idx].is_default && !has_values) || (idx > 0 && !ends_group(groups[idx - 1].stmts |> back())) || (idx < length(groups) - 1 && !ends_group(groups[idx].stmts[n - 1]))) {
        return false
    }
    var entered = false
    for (st in groups[idx].stmts) {
        each_stmt(st) $(s) {
            entered ||= s.s == "label" && key_exists(em.group_labels, s.label_name)
        }
    }
    return !entered
}

// a statement of a group as the lowering spells it at the group's level: a block a goto
// enters loses its braces, so its statements are the group's
def private group_level(em : Emitter; st : CirStmt const?; var out : array<CirStmt const?>) {
    if (st.s == "compound" && key_exists(em.flatten, intptr(st))) {
        for (child in st.body) {
            group_level(em, child, out)
        }
    } else {
        out |> push(st)
    }
}

// false with the error set when a label another group's goto reaches follows a declaration of
// its own group: the label splits the group's `if (_flag)` branch in two, and the declaration
// would end with the first
def private check_group_split(var em : Emitter; g : CaseGroup) : bool {
    var level : array<CirStmt const?>
    for (st in g.stmts) {
        group_level(em, st, level)
    }
    var declared = ""
    for (st in level) {
        if (st.s == "decl" && !key_exists(em.prog.carried, intptr(st)) && empty(declared)) {
            declared = st.name
        } elif (st.s == "label" && key_exists(em.group_labels, st.label_name) && !empty(declared)) {
            fail(em, "label `{st.label_name}`, which a goto from another case reaches, follows the declaration of `{declared}` in its case; not lowered yet", st.loc)
            return false
        }
    }
    return true
}

// a block a goto enters from outside loses its braces (docs/lowering-examples.md "goto /
// labels"), so the label sits in the scope the goto sees
def private emit_compound(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    let flat = key_exists(em.flatten, intptr(st))
    let opened = length(em.out)
    if (!flat) {
        open_block(em, "")
    }
    emit_statements(em, tu, st, 0)
    if (!flat) {
        close_block(em)
        unbrace_plain(em, opened)
    }
}

// the braces of the block whose `{` line is `em.out[opened]` go when its own level declares
// nothing and holds no label: its statements stand in the enclosing block, one level out
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#plain-blocks")]
def private unbrace_plain(var em : Emitter; opened : int) {
    let inner = repeat("    ", em.depth + 1)
    let last = length(em.out) - 1
    for (k in range(opened + 1, last)) {
        let text = em.out[k]
        if (find(text, "\n") != length(text) - 1 || starts_with(text, inner + "var ") || starts_with(text, inner + "let ") || starts_with(text, inner + "label ")) {
            return
        }
    }
    em.out |> erase(last)
    em.out |> erase(opened)
    for (k in range(opened, last - 1)) {
        em.out[k] = outdented(em.out[k])
    }
}

// a one-line entry of `em.out` one level out: four spaces fewer, a blank line kept
def private outdented(text : string) : string {
    let rest = strip_left(text)
    let indent = length(text) - length(rest)
    return empty(rest) ? "\n" : repeat(" ", max(indent - 4, 0)) + rest
}

// the initializer of declaration `st` of `name`: the line `head` spells from the initializer's
// text ("" when stores fill the value), then the stores; nothing when `head` gives ""
def private emit_initialized(var em : Emitter; tu : CirTu; st : CirStmt; name : string; head : block<(init : string) : string>) {
    var stores : array<string>
    let init = decl_init(em, tu, name, st.t, st.init, st.loc, stores)
    let first = invoke(head, init)
    if (empty(first)) {
        return
    }
    flush_pre(em)
    line(em, first)
    for (store in stores) {
        line(em, store)
    }
}

// a local nothing in its scope assigns, steps or takes the address of (`unwritten`), whose das
// type takes `let` as it is: an integer, a floating value or an enum. A `let` pointer reads its
// pointee as const and passes to no `var` parameter (F3), and a record or an array is written
// through its members
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#let-locals")]
def private let_local(tu : CirTu; st : CirStmt; unwritten : bool) : bool {
    let k = kind_of(tu, st.t)
    return unwritten && (k == "int" || k == "float" || k == "enum") && empty(st.dims)
}

// the declarations of every block of `body` that no statement after them in the block writes: a
// declaration's scope is the rest of its block, and a nested block's own `x` is renamed apart
// (`unshadow_locals`), so a write after it names it alone. A `for`'s first clause is a block
// whose scope is the whole loop
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#let-locals")]
def private plan_let_locals(var em : Emitter; body : CirStmt const?) {
    em.unwritten_decls |> clear()
    var loop_heads : table<uint64>
    each_stmt(body) $(st) {
        if (st.s == "for" && st.init_s != null) {
            loop_heads |> insert(intptr(st.init_s))
            let whole <- written_names(st)
            for (child in st.init_s.body) {
                if (child.s == "decl" && !key_exists(whole, child.name)) {
                    em.unwritten_decls |> insert(intptr(child))
                }
            }
        }
    }
    each_stmt(body) $(st) {
        if (key_exists(loop_heads, intptr(st))) {
            return
        }
        var later : table<string>
        for (idx in range(length(st.body))) {
            let child = st.body[length(st.body) - 1 - idx]
            if (child.s == "decl" && !key_exists(later, child.name)) {
                em.unwritten_decls |> insert(intptr(child))
            }
            // bound first: a `for` over the keys of a returned table reads freed memory (daScript#55)
            var inscope written <- written_names(child)
            for (name in keys(written)) {
                later |> insert(name)
            }
        }
    }
}

def private emit_decl(var em : Emitter; tu : CirTu; st : CirStmt; unwritten : bool) {
    let spelled = das_type_dims(em, tu, st.t, st.loc, st.dims)
    let name = das_name(em, st.name)
    if (st.init == null) {
        line(em, "var {name} : {spelled}")
        return
    }
    let fixed = let_local(tu, st, unwritten)
    emit_initialized(em, tu, st, name) $(init) {
        return empty(init) ? "var {name} : {spelled}" : "{fixed ? "let" : "var"} {name} : {spelled} = {init}"
    }
}

// a declaration the lowered switch carries: declared before the switch (`emit_switch`), its
// initializer is the assignment that stands where C declares it
def private emit_carried_init(var em : Emitter; tu : CirTu; st : CirStmt; name : string) {
    if (st.init == null) {
        return
    }
    emit_initialized(em, tu, st, name) $(init) {
        if (empty(init)) {
            // the stores rely on the declaration's zero, which a second pass through the case
            // would not give again
            fail(em, "a declaration under a case label filled by stores (a union or a sparse array) and used under a later label is not lowered yet", st.loc)
            return ""
        }
        return "{name} = {init}"
    }
}

def emit_stmt(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (st == null) {
        return
    }
    if (st.s != "compound" && st.s != "label") {
        carry_comments(em, st.loc)
    }
    em.stmt_depth++
    emit_stmt_kind(em, tu, st)
    em.stmt_depth--
}

// a C label; one another case group's goto reaches is a case of its own number in the switch's
// goto variable: it splits its group's branch, control falling into it keeps the flag, and the
// branch consumes the pending goto
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-labels")]
def private emit_label(var em : Emitter; st : CirStmt const?) {
    if (!key_exists(em.group_labels, st.label_name)) {
        jump_label(em, em.labels?[st.label_name] ?? 0, st.label_name)
        return
    }
    let flag = em.label_flags?[st.label_name] ?? ""
    let opened = repeat("    ", em.depth - 1) + "if ({flag}) \{\n"
    let jump = em.label_jumps?[st.label_name] ?? 0
    if (!empty(em.out) && em.out[length(em.out) - 1] == opened) {
        // the label heads its group: no empty branch before it
        em.out |> pop()
        em.depth--
    } else {
        close_block(em)
    }
    if (jump > 0) {
        line(em, "label {jump}:  // {st.label_name}")
    }
    let goto_var = em.label_gotos?[st.label_name] ?? ""
    line(em, "{flag} ||= {goto_var} == {em.label_index?[st.label_name] ?? 0}  // {st.label_name}")
    open_block(em, "if ({flag})")
    line(em, "{goto_var} = 0")
}

// das label `n` with `comment` after it
def private jump_label(var em : Emitter; n : int; comment : string) {
    line(em, "label {n}:  // {comment}")
}

// a C goto; one to a label a goto from another case group reaches re-dispatches, from that label's
// own group too: the label's number into the switch's goto variable, then the switch from the top
def private emit_goto(var em : Emitter; st : CirStmt const?) {
    let sw = em.group_labels?[st.label_name] ?? 0ul
    if (sw != 0ul) {
        line(em, "{em.label_gotos?[st.label_name] ?? ""} = {em.label_index?[st.label_name] ?? 0}")
        let reset = em.label_conds?[st.label_name] ?? ""
        if (!empty(reset)) {
            line(em, reset)
        }
        // under the jump table straight to the label's own das label
        let jump = em.label_jumps?[st.label_name] ?? 0
        line(em, "goto label {jump > 0 ? jump : (em.flag_switches?[sw] ?? 0)}")
    } else {
        line(em, "goto label {em.labels?[st.label_name] ?? 0}")
    }
}

// a new das label for the open lowering, numbered after every label the function had
def private new_label(var em : Emitter) : int {
    em.label_count++
    return em.label_count
}

// a case label of an open switch, its das label; the label of a switch whose body is no block
// cannot sit below the switch's level
def private emit_case_label(var em : Emitter; st : CirStmt const?) {
    if (key_exists(em.case_labels, intptr(st))) {
        if (st.s == "default") {
            emit_holes(em, intptr(st))
        }
        jump_label(em, em.case_labels?[intptr(st)] ?? 0, st.s == "case" ? "case {st.v}" : "default")
    } else {
        fail(em, "a case label of a switch whose body is no block, below that switch's level; not lowered", st.loc)
    }
}

// an `if`, loop or switch a goto enters from outside, or a switch with a case label below its
// level (Duff's device), spelled open at its parent's level: its entered arms and its body flat,
// its control flow as das labels and gotos, so every label in it lands in a scope a goto sees
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#goto-into-body")]
def private emit_open(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (st.s == "if") {
        emit_open_if(em, tu, st)
    } elif (st.s == "switch") {
        emit_open_switch(em, tu, st)
    } else {
        emit_open_loop(em, tu, st)
    }
}

def private emit_open_if(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    let then_flat = key_exists(em.entered, intptr(st.then_s))
    let else_flat = st.else_s != null && key_exists(em.entered, intptr(st.else_s))
    let c = truth_of(em, tu, st.cond, st.loc)
    flush_pre(em)
    let end_at = new_label(em)
    if (then_flat && else_flat) {
        let else_at = new_label(em)
        open_block(em, "if ({negation(c)})")
        line(em, "goto label {else_at}")
        close_block(em)
        emit_body(em, tu, st.then_s)
        let falls = !ends_group(st.then_s)
        if (falls) {
            line(em, "goto label {end_at}")
        }
        jump_label(em, else_at, "else")
        emit_body(em, tu, st.else_s)
        if (falls) {
            jump_label(em, end_at, "end if")
        }
        return
    }
    // the arm no goto enters stays a branch, which jumps past the entered one unless it leaves
    let braced = then_flat ? st.else_s : st.then_s
    let falls = !ends_group(braced)
    open_block(em, then_flat ? "if ({negation(c)})" : "if ({c.text})")
    emit_body(em, tu, braced)
    if (falls) {
        line(em, "goto label {end_at}")
    }
    close_block(em)
    emit_body(em, tu, then_flat ? st.then_s : st.else_s)
    if (falls) {
        jump_label(em, end_at, "end if")
    }
}

// a loop spelled open: the test at its top label, the body flat, C `continue` a goto to the
// increment or the test and `break` one to its end
def private emit_open_loop(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    if (st.s == "for" && st.init_s != null) {
        emit_body(em, tu, st.init_s)
    }
    let top = new_label(em)
    let next = st.s == "while" || !continues_loop(st.body_s, false) ? top : new_label(em)
    let end_at = new_label(em)
    jump_label(em, top, st.s)
    let tested = st.s != "do" && st.cond != null
    if (tested) {
        let c = truth_of(em, tu, st.cond, st.loc)
        flush_pre(em)
        open_block(em, "if ({negation(c)})")
        line(em, "goto label {end_at}")
        close_block(em)
    }
    em.cont_flags |> push("goto label {next}")
    em.break_gotos |> push("goto label {end_at}")
    emit_body(em, tu, st.body_s)
    em.break_gotos |> pop()
    em.cont_flags |> pop()
    if (next != top) {
        jump_label(em, next, "{st.s} next")
    }
    if (st.s == "do") {
        let c = truth_of(em, tu, st.cond, st.loc)
        flush_pre(em)
        open_block(em, "if ({c.text})")
        line(em, "goto label {top}")
        close_block(em)
    } else {
        if (st.s == "for" && st.inc != null) {
            let lines <- increment_lines(em, tu, *st)
            flush_literal_decls(em)
            for (stmt in lines) {
                line(em, stmt)
            }
        }
        line(em, "goto label {top}")
    }
    if (tested || breaks_switch(st.body_s)) {
        jump_label(em, end_at, "{st.s} end")
    }
}

// the case labels of a switch body `st`, in order, a nested switch's left to it
def private case_markers(st : CirStmt const?; var out : array<CirStmt const?>) {
    if (st == null || st.s == "switch") {
        return
    }
    if (st.s == "case" || st.s == "default") {
        out |> push(st)
    }
    for (child in st.body) {
        case_markers(child, out)
    }
    case_markers(st.then_s, out)
    case_markers(st.else_s, out)
    case_markers(st.body_s, out)
}

// a switch spelled open: the condition once, a chain of gotos to its case labels or, under
// `switch_dispatch` `goto`, a jump table (`open_table`), the body flat with every case label a das
// label, C `break` a goto to its end
def private emit_open_switch(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    em.switch_counter++
    var outer_chars <- em.char_cases
    em.char_cases <- char_cases(st.body_s)
    var cond_t = st.cond.t
    let cond = switch_condition(em, tu, *st, cond_t)
    var markers : array<CirStmt const?>
    case_markers(st.body_s, markers)
    // a declaration a later case reads, as `emit_switch` declares it
    for (child in st.body_s.body) {
        if (child.s == "decl" && key_exists(em.prog.carried, intptr(child))) {
            line(em, "var {das_name(em, child.name)} : {das_type_dims(em, tu, child.t, child.loc, child.dims)}")
        }
    }
    var jumps = open_table(em, tu, cond_t, markers)
    if (jumps.span > 0) {
        emit_open_table(em, tu, st, markers, cond, cond_t, jumps)
        em.char_cases <- outer_chars
        return
    }
    let end_at = new_label(em)
    var default_at = end_at
    var first = true
    for (m in markers) {
        let n = new_label(em)
        em.case_labels[intptr(m)] = n
        if (m.s == "default") {
            default_at = n
            continue
        }
        let test = case_compare(em, tu, cond, cond_t, m.v)
        open_block(em, first ? "if ({test})" : "\} elif ({test})")
        first = false
        line(em, "goto label {n}")
        em.depth--
    }
    if (first) {
        line(em, "goto label {default_at}")
    } else {
        open_block(em, "\} else")
        line(em, "goto label {default_at}")
        close_block(em)
    }
    em.break_gotos |> push("goto label {end_at}")
    emit_body(em, tu, st.body_s)
    em.break_gotos |> pop()
    if (default_at == end_at || breaks_switch(st.body_s)) {
        jump_label(em, end_at, "switch end")
    }
    em.char_cases <- outer_chars
}

// the jump table of an open switch under `switch_dispatch` `goto`: two or more case values in
// `int`'s range filling at least half of [lo, hi]; else a zero `span`
[arch(at="ARCHITECTURE_EMITTER_CONTROL.md#flat-cases")]
def private open_table(var em : Emitter; tu : CirTu; cond_t : int; markers : array<CirStmt const?>) : GotoDispatch {
    if (!em.prog.goto_dispatch) {
        return GotoDispatch()
    }
    var lo = LONG_MAX
    var hi = LONG_MIN
    var n = 0
    for (m in markers) {
        if (m.s == "case") {
            var held : int64
            if (!held_value(em, tu, cond_t, m.v, held)) {
                return GotoDispatch()
            }
            n++
            lo = min(lo, held)
            hi = max(hi, held)
        }
    }
    if (n < 2 || lo < int64(INT_MIN) || hi > int64(INT_MAX) || hi - lo + 1l > 2l * int64(n)) {
        return GotoDispatch()
    }
    return GotoDispatch(lo = lo, span = int(hi - lo + 1l))
}

// an open switch through its jump table: das label `base + v - lo` at case value `v`, `base + span`
// at `default`, or at the end when the switch has none, with the labels of the values no case holds
// before it
def private emit_open_table(var em : Emitter; tu : CirTu; st : CirStmt const?; markers : array<CirStmt const?>; cond : string; cond_t : int; var jumps : GotoDispatch) {
    var cases : table<int64>
    var default_key = 0ul
    let holes_key = intptr(st.body_s)
    for (m in markers) {
        if (m.s == "case") {
            cases |> insert(m.v)
        } else {
            default_key = intptr(m)
        }
    }
    let end_at = default_key != 0ul ? new_label(em) : 0
    jumps.base = em.label_count + 1
    em.label_count += jumps.span + 1
    for (m in markers) {
        em.case_labels[intptr(m)] = m.s == "case" ? jumps.base + int(m.v - jumps.lo) : jumps.base + jumps.span
    }
    var holes <- [for (off in range(jumps.span)); "label {jumps.base + off}:  // no case {jumps.lo + int64(off)}"; where !key_exists(cases, jumps.lo + int64(off))]
    em.case_holes[default_key != 0ul ? default_key : holes_key] <- holes
    dispatch_jump(em, tu, jumps, cond, cond_t)
    let finish = default_key != 0ul ? end_at : jumps.base + jumps.span
    em.break_gotos |> push("goto label {finish}")
    emit_body(em, tu, st.body_s)
    em.break_gotos |> pop()
    if (default_key == 0ul) {
        emit_holes(em, holes_key)
        jump_label(em, finish, "no case: switch end")
    } elif (breaks_switch(st.body_s)) {
        jump_label(em, finish, "switch end")
    }
}

// the labels of the values no case of an open switch's jump table holds, before its `default`, by
// its key, or before its end, by its body's
def private emit_holes(var em : Emitter; key : uint64) {
    get(em.case_holes, key) $(holes) {
        for (hole in holes) {
            line(em, hole)
        }
    }
    em.case_holes |> erase(key)
}

def private emit_stmt_kind(var em : Emitter; tu : CirTu; st : CirStmt const?) {
    var folded : Em
    if (key_exists(em.opened, intptr(st))) {
        emit_open(em, tu, st)
    } elif ((st.s == "do" || st.s == "compound") && !empty(st.fn_macro) && fold_macro(em, tu, null, null, st, "stmt", st.loc, folded)) {
        flush_pre(em)
        line(em, folded.text)
    } elif (st.s == "compound") {
        emit_compound(em, tu, st)
    } elif (st.s == "label") {
        emit_label(em, st)
    } elif (st.s == "goto") {
        emit_goto(em, st)
    } elif (st.s == "decl" && key_exists(em.prog.carried, intptr(st))) {
        emit_carried_init(em, tu, *st, das_name(em, st.name))
    } elif (st.s == "decl" && key_exists(em.range_counters, st.name)) {
        pass
    } elif (st.s == "decl") {
        emit_decl(em, tu, *st, key_exists(em.unwritten_decls, intptr(st)))
    } elif (st.s == "expr") {
        emit_effect(em, tu, st.e, st.loc)
        flush_pre(em)
    } elif (st.s == "return") {
        emit_return(em, tu, st)
    } elif (st.s == "if") {
        emit_if(em, tu, *st, "if")
    } elif (st.s == "while") {
        emit_while(em, tu, *st)
    } elif (st.s == "do") {
        emit_do(em, tu, st)
    } elif (st.s == "for") {
        emit_for(em, tu, st)
    } elif (st.s == "break") {
        emit_break(em)
    } elif (st.s == "continue") {
        emit_continue(em)
    } elif (st.s == "switch") {
        emit_switch(em, tu, *st)
    } elif (st.s == "case" || st.s == "default") {
        emit_case_label(em, st)
    } elif (st.s == "null") {
        return
    } else {
        fail(em, "statement `{st.s}` is not lowered yet", st.loc)
    }
}

// the variable a store into `x` writes, below casts; none when the store goes through a pointer
// or into a field or element, which writes no parameter the copy rule spells in place
def private mark_store_root(var em : Emitter; x : CirExpr const?) {
    var target = x
    while (target != null && target.e == "cast") {
        target = target.a
    }
    if (target != null && target.e == "ref") {
        em.written |> insert(target.name)
    }
}

// `each_expr` over a tree the block may change
def private each_expr_mut(var st : CirStmt?; blk : block<(var x : CirExpr?) : void>) {
    walk_stmts(st) $(var s : CirStmt?) {
        for (x in fixed_array(s.init, s.e, s.cond, s.inc)) {
            each_subexpr_mut(x, blk)
        }
    }
}

// `each_subexpr` over a tree the block may change
def private each_subexpr_mut(var x : CirExpr?; blk : block<(var x : CirExpr?) : void>) {
    walk_subexprs(x, blk)
}

// whether a statement tree calls alloca anywhere
def private calls_alloca(st : CirStmt const?) : bool {
    var found = false
    each_expr(st) $(x) {
        found = found || (x.e == "call" && key_exists(ALLOCA_NAMES, called_name(*x)))
    }
    return found
}

// the names a function's parameters, locals and references take
def private body_names(em : Emitter; d : CirDecl) : table<string> {
    var spelled : table<string>
    collect_spelled_names(d.body, spelled)
    var names : table<string>
    for (p in d.params) {
        names |> insert(das_name(em, p.name))
    }
    for (name in keys(spelled)) {
        names |> insert(das_name(em, name))
    }
    return <- names
}

// C lets a block's local hide a local or parameter of an enclosing scope, and das refuses a local
// that shadows another (`docs/probe-findings.md` F42): a hiding local takes a free name, and so
// does every reference C resolves to it. `scopes` maps each C name to its das name, innermost
// scope last; `taken` holds every name the function spells.
struct ScopeWalk {
    scopes : array<table<string; string>>
    taken : table<string>
    // the locals the lowering declares outside their C block (`moved_decls`), the unit's global
    // names and how many locals of the function each C name declares
    moved : table<uint64>
    globals : table<string>
    decl_count : table<string; int>
    // the references named like a libc object (`stderr`) that a parameter or local binds
    bound_objects : table<uint64>
}

def private scoped_name(w : ScopeWalk; name : string) : string {
    for (idx in range(length(w.scopes))) {
        let found = w.scopes[length(w.scopes) - 1 - idx]?[name] ?? ""
        if (!empty(found)) {
            return found
        }
    }
    return ""
}

def private unshadow_expr(var w : ScopeWalk; var x : CirExpr?) {
    each_subexpr_mut(x) $(var sub) {
        if (sub.e == "ref") {
            let renamed = scoped_name(w, sub.name)
            if (!empty(renamed)) {
                if (key_exists(CRT_OBJECTS, sub.name)) {
                    w.bound_objects |> insert(intptr(sub))
                }
                sub.name = renamed
            }
        }
    }
}

def private unshadow_stmt(var w : ScopeWalk; var st : CirStmt?) {
    if (st == null) {
        return
    }
    // a block and every `for` open a scope
    let opens = st.s == "compound" || st.s == "for"
    if (opens) {
        w.scopes |> emplace(table<string; string>())
    }
    if (st.s == "decl") {
        // C's scope of a local starts at its declarator, so its own initializer sees it; a local
        // the lowering moves out of its block also hides a global and another local of its name
        let moved = key_exists(w.moved, intptr(st)) && (key_exists(w.globals, st.name) || (w.decl_count?[st.name] ?? 0) > 1)
        let hides = moved || !empty(scoped_name(w, st.name))
        let name = hides ? free_name(w.taken, st.name) : st.name
        w.scopes[length(w.scopes) - 1][st.name] = name
        st.name = name
    }
    if (st.init_s != null && st.init_s.s == "compound") {
        for (child in st.init_s.body) {
            unshadow_stmt(w, child)
        }
    } else {
        unshadow_stmt(w, st.init_s)
    }
    for (x in fixed_array(st.init, st.e, st.cond, st.inc)) {
        unshadow_expr(w, x)
    }
    for (child in st.body) {
        unshadow_stmt(w, child)
    }
    for (child in fixed_array(st.then_s, st.else_s, st.body_s)) {
        unshadow_stmt(w, child)
    }
    if (opens) {
        delete w.scopes[length(w.scopes) - 1]
        w.scopes |> pop()
    }
}

// every function body of the unit with its hiding locals renamed, before anything reads a name;
// `carried` gets the declarations a lowered switch declares before itself, `bound_objects` the
// references named like a libc object that a parameter or local binds
def private unshadow_locals(var tu : CirTu; var carried : table<uint64>; var bound_objects : table<uint64>; goto_dispatch : bool) {
    var globals : table<string>
    for (d in tu.decls) {
        if (d.k == "global") {
            globals |> insert(d.name)
        }
    }
    for (d in tu.decls) {
        continue if (d.k != "func" || d.body == null)
        var inscope w : ScopeWalk
        collect_spelled_names(d.body, w.taken)
        w.globals := globals
        count_decls(d.body, w.decl_count)
        // the blocks a goto enters lose their braces, which `plan_labels` decides at emission
        var inscope plan : Emitter
        // under `switch_dispatch` `goto` a re-dispatched switch's body is flat too (`open_redispatched`)
        plan.prog.goto_dispatch = goto_dispatch
        plan_labels(plan, tu, d.body)
        moved_decls(d.body, plan, w.moved, carried)
        w.scopes |> resize(1)
        for (p in d.params) {
            w.scopes[0][p.name] = p.name
            w.taken |> insert(p.name)
        }
        unshadow_stmt(w, d.body)
        for (x in keys(w.bound_objects)) {
            bound_objects |> insert(x)
        }
    }
}

// how many locals of statement tree `st` each C name declares
def private count_decls(st : CirStmt const?; var counts : table<string; int>) {
    each_stmt(st) $(s) {
        if (s.s == "decl") {
            counts[s.name] = (counts?[s.name] ?? 0) + 1
        }
    }
}

// the locals the lowering declares outside their C block: one of a block a goto enters, which
// loses its braces (`flatten`), one of an open `for`'s initializer or a flat arm that is a
// declaration, and one a lowered switch carries (`carried_decls`), which also lands in `carried`
def private moved_decls(st : CirStmt const?; plan : Emitter; var moved : table<uint64>; var carried : table<uint64>) {
    each_stmt(st) $(s) {
        if (s.s == "compound" && key_exists(plan.flatten, intptr(s))) {
            for (child in s.body) {
                if (child.s == "decl") {
                    moved |> insert(intptr(child))
                }
            }
        }
        if (s.s == "for" && key_exists(plan.opened, intptr(s))) {
            each_stmt(s.init_s) $(init) {
                if (init.s == "decl") {
                    moved |> insert(intptr(init))
                }
            }
        }
        if (s.s == "switch") {
            var found : table<uint64>
            carried_decls(s.body_s, found)
            for (decl in keys(found)) {
                moved |> insert(decl)
                carried |> insert(decl)
            }
        }
    }
}

// the declarations at switch body `body`'s own level that a statement under a later label
// names: C scopes them to the whole body, while the lowering puts each group in its own branch
def private carried_decls(body : CirStmt const?; var out : table<uint64>) {
    if (body == null || body.s != "compound") {
        return
    }
    let n = length(body.body)
    for (idx in range(n)) {
        let decl = body.body[idx]
        continue if (decl.s != "decl")
        var past_label = false
        for (later in range(idx + 1, n)) {
            let st = body.body[later]
            past_label = past_label || st.s == "case" || st.s == "default"
            if (past_label && names_local(st, decl.name)) {
                out |> insert(intptr(decl))
                break
            }
        }
    }
}

// whether statement tree `st` references C name `name` where no declaration of `st` binds it: a
// declaration of `name` in `st` takes every later reference of its block or its `for`, its own
// initializer included (C's scope of a local starts at its declarator)
def private names_local(st : CirStmt const?; name : string) : bool {
    if (st == null || (st.s == "decl" && st.name == name)) {
        return false
    }
    for (child in st.body) {
        if (names_local(child, name)) {
            return true
        }
        if (child.s == "decl" && child.name == name) {
            return false
        }
    }
    if (names_local(st.init_s, name)) {
        return true
    }
    if (declares(st.init_s, name)) {
        return false
    }
    for (x in fixed_array<CirExpr const?>(st.init, st.e, st.cond, st.inc)) {
        if (refs_name(x, name)) {
            return true
        }
    }
    for (child in fixed_array<CirStmt const?>(st.then_s, st.else_s, st.body_s)) {
        if (names_local(child, name)) {
            return true
        }
    }
    return false
}

// whether a `for`'s first clause `st`, the block of declarations the dumper wraps it in,
// declares `name`
def private declares(st : CirStmt const?; name : string) : bool {
    if (st == null) {
        return false
    }
    for (child in st.body) {
        if (child.s == "decl" && child.name == name) {
            return true
        }
    }
    return false
}

// whether expression `x` references C name `name`
def private refs_name(x : CirExpr const?; name : string) : bool {
    var found = false
    each_subexpr(x) $(sub) {
        found = found || (sub.e == "ref" && sub.name == name)
    }
    return found
}

// every C name a statement tree declares or references
def private collect_spelled_names(st : CirStmt const?; var names : table<string>) {
    each_stmt(st) $(s) {
        if (s.s == "decl") {
            names |> insert(s.name)
        }
    }
    each_expr(st) $(x) {
        if (x.e == "ref") {
            names |> insert(x.name)
        }
    }
}

def private is_step(op : string) : bool => op == "preinc" || op == "predec" || op == "postinc" || op == "postdec"


// C lets a non-void function fall off its end (the value is then unspecified, and main's is
// 0); das wants every path to return, so the body gets a trailing zero
// whether block `owner`'s statements from `first` on end in a return das reads: a single-branch
// setjmp site turns the rest of the block into a loop, whose end das does not read as one
def private statements_end_in_return(tu : CirTu; owner : CirStmt const?; first : int) : bool {
    for (idx in range(first, length(owner.body))) {
        let child = owner.body[idx]
        var first_in_then = false
        if (flat_setjmp(owner, idx)) {
            continue
        }
        if ((child.s == "if" && child.else_s == null && setjmp_site(child.cond, first_in_then) != null) || general_setjmp(child) != null) {
            return false
        }
    }
    return length(owner.body) > first && ends_in_return(tu, owner.body[length(owner.body) - 1])
}

def private ends_in_return(tu : CirTu; st : CirStmt?) : bool {
    if (st == null) {
        return false
    }
    if (st.s == "return") {
        return true
    }
    if (st.s == "compound") {
        return statements_end_in_return(tu, st, 0)
    }
    if (st.s == "if") {
        // a setjmp site's arms return through `_sj_returned`, after which das reads no return
        var first_in_then = false
        return setjmp_site(st.cond, first_in_then) == null && ends_in_return(tu, st.then_s) && ends_in_return(tu, st.else_s)
    }
    return false
}

// whether the function body spelled in `em.out` from `body_at` on ends in a statement das itself
// reads as returning on every path, so a zero `return` after it is dead (probes/test_return_paths.das)
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#plain-blocks")]
def private text_returns(em : Emitter; body_at : int) : bool {
    let text = join([for (k in range(body_at, length(em.out))); em.out[k]], "")
    let lines <- [for (l in split(text, "\n")); Ln(ind = length(l) - length(strip_left(l)), text = strip(l)); where !empty(strip(l))]
    return block_returns(lines, 0, length(lines), em.depth * 4)
}

// a line of emitted text: its indentation in spaces and its text without it
struct private Ln {
    ind : int
    text : string
}

// the statements of `lines[from..to)` at `indent` spaces: whether the last one returns on every
// path, which das then reads as returning too: a `return`, an `if` chain with an `else` whose arms
// each return, a bare block that returns, a `while (true)` whose body returns and no `break` of its
// own leaves (das reads the loop by its body alone, a `break` included: probes/test_return_paths.das)
def private block_returns(lines : array<Ln>; from, to, indent : int) : bool {
    var last = -1
    for (k in range(from, to)) {
        if (lines[k].ind == indent && !starts_with(lines[k].text, "\}") && !starts_with(lines[k].text, "//")) {
            last = k
        }
    }
    if (last < 0) {
        return false
    }
    let head = lines[last].text
    if (head == "return" || starts_with(head, "return ")) {
        return true
    }
    if (head == "\{") {
        var close = last + 1
        while (close < to && lines[close].ind != indent) {
            close++
        }
        return close < to && block_returns(lines, last + 1, close, indent + 4)
    }
    // the closing `}` of the last statement's arms, each arm's body between two of them
    let arms <- [for (k in range(last, to)); k; where lines[k].ind == indent]
    if (lines[arms[length(arms) - 1]].text != "\}" || !ends_with(head, " \{")) {
        return false
    }
    if (head == "while (true) \{") {
        return length(arms) == 2 && block_returns(lines, arms[0] + 1, arms[1], indent + 4) && !breaks_out(lines, arms[0] + 1, arms[1], indent + 4)
    }
    if (starts_with(head, "{C_SWITCH} (")) {
        return length(arms) == 2 && switch_returns(lines, arms[0] + 1, arms[1], indent + 4)
    }
    if (!starts_with(head, "if (") || lines[arms[length(arms) - 2]].text != "\} else \{") {
        return false
    }
    for (a in range(length(arms) - 1)) {
        let arm_head = lines[arms[a]].text
        if ((a > 0 && !starts_with(arm_head, "\} elif (") && arm_head != "\} else \{") || !block_returns(lines, arms[a] + 1, arms[a + 1], indent + 4)) {
            return false
        }
    }
    return true
}

// the `case (...) { }` arms of a `c_switch` in `lines[from..to)` at `indent`: whether one is the
// default and each ends in a `return` (a bare block's last statement looked into, as the macro
// reads an arm's end), with no own `break`, so the macro expands to an if-chain with an `else`
// whose arms each return
def private switch_returns(lines : array<Ln>; from, to, indent : int) : bool {
    let heads <- [for (k in range(from, to)); k; where lines[k].ind == indent]
    var has_default = false
    for (a in range(length(heads) / 2)) {
        let open = heads[2 * a]
        let close = heads[2 * a + 1]
        has_default ||= ends_with(lines[open].text, "(_) \{") || ends_with(lines[open].text, ", _) \{")
        if (!ends_in_return_line(lines, open + 1, close, indent + 4) || breaks_out(lines, open + 1, close, indent + 4)) {
            return false
        }
    }
    return has_default && length(heads) % 2 == 0
}

// whether the last statement of `lines[from..to)` at `indent` is a `return`, a bare block's looked into
def private ends_in_return_line(lines : array<Ln>; from, to, indent : int) : bool {
    var last = -1
    for (k in range(from, to)) {
        if (lines[k].ind == indent && !starts_with(lines[k].text, "\}") && !starts_with(lines[k].text, "//")) {
            last = k
        }
    }
    if (last < 0) {
        return false
    }
    let head = lines[last].text
    if (head == "\{") {
        var close = last + 1
        while (close < to && lines[close].ind != indent) {
            close++
        }
        return close < to && ends_in_return_line(lines, last + 1, close, indent + 4)
    }
    return head == "return" || starts_with(head, "return ")
}

// whether a `break` of the loop whose body is `lines[from..to)` at `indent` can run: one at the
// body's level or inside its `if` arms, not inside a nested loop, and not right after a `return`
// or a `break` of the same level; a `goto` anywhere counts, it may leave the loop
def private breaks_out(lines : array<Ln>; from, to, indent : int) : bool {
    var dead_after = false
    var k = from
    while (k < to) {
        let head = lines[k].text
        if (lines[k].ind != indent) {
            if (find(head, "goto ") >= 0) {
                return true
            }
            k++
            continue
        }
        if (head == "break") {
            if (!dead_after) {
                return true
            }
        } elif (starts_with(head, "goto ")) {
            return true
        } elif (starts_with(head, "if (") || starts_with(head, "\} elif (") || head == "\} else \{" || head == "\{") {
            var e = k + 1
            while (e < to && lines[e].ind != indent) {
                e++
            }
            if (breaks_out(lines, k + 1, e, indent + 4)) {
                return true
            }
        } elif (starts_with(head, "while (") || starts_with(head, "for (")) {
            var e = k + 1
            while (e < to && lines[e].ind != indent) {
                if (find(lines[e].text, "goto ") >= 0) {
                    return true
                }
                e++
            }
            k = e
            dead_after = false
            continue
        }
        dead_after = head == "return" || starts_with(head, "return ") || head == "break"
        k++
    }
    return false
}

def private zero_of(var em : Emitter; tu : CirTu; t : int; spelled : string) : string {
    if (is_record(tu, t)) {
        return "{spelled}()"
    }
    if (kind_of(tu, t) == "enum") {
        // the enumerator of value zero when the enum has one; `default<E>` is rejected for an
        // enum without one (probes/test_process.das), so its zero is the conversion of 0
        let named = enumerator_of(tu, t, "0")
        return empty(named) ? int_to_enum(em, tu, t, "0") : enum_item(em, tu, t, named)
    }
    if (spelled == "bool") {
        return "false"
    }
    if (spelled == "float") {
        return "0.0f"
    }
    if (spelled == "double") {
        return "0.0lf"
    }
    if (spelled |> ends_with("?")) {
        return "null"
    }
    if (is_function_pointer(tu, t)) {
        // das takes no `null` for a function value (probes/test_globals.das)
        return "default<{spelled}>"
    }
    return spelled == "int" ? "0" : "{spelled}(0)"
}

def private das_func_name(var em : Emitter; d : CirDecl) : string {
    if (d.c_name == "main" && !d.is_static) {
        em.has_c_main = true
    }
    return function_name(em, d.name)
}

// the das name of function `name` of the unit: C `main` is `c_main`, a function named like a mapped
// libc one or one the wrapper calls takes its free name (`rename_taken_names`)
def private function_name(em : Emitter; name : string) : string {
    if (name == "main") {
        return C_MAIN
    }
    return em.prog.function_renames?[name] ?? das_name(em, name)
}

// the functions the `main` wrapper calls: C `main` itself and the `c_runtime/c_args` ones
let WRAPPER_CALLS <- {C_MAIN, RUNTIME_INIT, ARGC, ARGV}

// a function the program defines named like a libc function c_runtime maps (h264bsd's own
// `malloc`) would make its calls ambiguous with the mapped one and das's builtin of the name, and
// one of a unit that has a `main` named like one the wrapper calls would make that call ambiguous
// (or redefine `c_main`): each takes the next free numbered name (`malloc1`, `c_argc1`), and C's
// calls of the name bind to it, as the link binds them to the program's definition
def private rename_taken_names(var em : Emitter; tu : CirTu) {
    let wrapped = key_exists(em.prog.functions, "main")
    var taken : table<string>
    for (d in tu.decls) {
        taken |> insert(d.name)
    }
    for (name in keys(WRAPPER_CALLS)) {
        taken |> insert(name)
    }
    for (d in tu.decls) {
        if (d.k == "func" && d.body != null && ((wrapped && key_exists(WRAPPER_CALLS, d.name)) || !empty(libc_call(d.name)))) {
            em.prog.function_renames[d.name] = free_name(taken, d.name)
        }
    }
}

// whether C `main` takes what the wrapper passes, with the error set when not: none, or `int argc,
// char **argv` (`char *argv[]` decays alike), which the wrapper takes from `c_runtime/c_args`
def private main_parameters(var em : Emitter; tu : CirTu; d : CirDecl) : bool {
    let n = length(d.params)
    if (n == 0) {
        return true
    }
    if (n == 3) {
        fail(em, "main with an environment parameter (`char **envp`) is not lowered yet", d.loc)
        return false
    }
    let argv = n == 2 ? d.params[1].t : -1
    let argv_ok = kind_of(tu, argv) == "ptr" && kind_of(tu, tu.types[argv].to) == "ptr" && das_type(em, tu, argv, d.loc) == "uint8??"
    if (n != 2 || das_type(em, tu, d.params[0].t, d.loc) != "int" || !argv_ok) {
        fail(em, "main whose parameters are not `int argc, char **argv` is not lowered yet", d.loc)
        return false
    }
    em.main_args = true
    return true
}

// the per-function state of the emitter, set for function `d` before its body is spelled
def private reset_function_state(var em : Emitter; tu : CirTu; d : CirDecl) {
    em.written |> clear()
    em.renames |> clear()
    em.spelled |> clear()
    em.temp_counter = 0
    em.first_counter = 0
    em.for_counter = 0
    em.switch_counter = 0
    em.setjmp_counter = 0
    em.sj_ret = ""
    em.sj_returned = ""
    em.sj_arms = 0
    em.sj_result_counter = 0
    em.literal_counter = 0
    em.cont_flags |> clear()
    em.break_gotos |> clear()
    em.labels |> clear()
    em.flatten |> clear()
    em.opened |> clear()
    em.entered |> clear()
    em.case_labels |> clear()
    em.group_labels |> clear()
    em.flag_switches |> clear()
    em.label_index |> clear()
    em.label_flags |> clear()
    em.label_gotos |> clear()
    em.label_conds |> clear()
    em.goto_switches |> clear()
    em.label_jumps |> clear()
    em.case_holes |> clear()
    plan_labels(em, tu, d.body)
    plan_let_locals(em, d.body)
    em.unsafe_used = false
    em.addressed |> clear()
    em.pointed |> clear()
    each_expr(d.body) $(x) {
        if (x.e == "assign" || (x.e == "un" && (is_step(x.op) || x.op == "addr"))) {
            mark_store_root(em, x.a)
        }
        if (x.e == "un" && x.op == "addr") {
            let root = below_casts(x.a)
            if (root != null && root.e == "ref") {
                em.addressed |> insert(root.name)
            }
        }
        mark_pointed(x, em.pointed)
    }
    em.escaped |> clear()
    if (em.prog.range_loops) {
        for (name in keys(em.addressed)) {
            if (address_escapes(em.prog.summaries, d.body, name)) {
                em.escaped |> insert(name)
            }
        }
        for (name in keys(em.pointed)) {
            if (!key_exists(em.escaped, name) && address_escapes(em.prog.summaries, d.body, name)) {
                em.escaped |> insert(name)
            }
        }
    }
    delete em.fold_scope
    em.fold_scope.locals <- {for (p in d.params); p.name}
    each_stmt(d.body) $(s) {
        if (s.s == "decl") {
            em.fold_scope.locals |> insert(s.name)
        }
    }
    em.fold_scope.addressed := em.addressed
    em.fold_scope.no_fold := em.prog.no_fold
}

// the parameters of function `d` as das declares them, and the callee copies that open its body
def private function_params(var em : Emitter; tu : CirTu; d : CirDecl; var taken : table<string>; var params : array<string>; var copies : array<string>) {
    for (idx, p in range(length(d.params)), d.params) {
        let spelled = das_type(em, tu, p.t, d.loc)
        let name = das_name(em, p.name)
        let passed = idx < length(tu.types[d.t].params) ? tu.types[d.t].params[idx] : p.t
        if (passed != p.t) {
            // a K&R definition takes its arguments promoted (its type is `int (int, int)` for
            // `char b`) and converts each to the declared type on entry, as C does
            promoted_param(em, tu, d, p, passed, name, taken, params, copies)
            continue
        }
        if (is_va_list(tu, p.t)) {
            // the caller's cursor, which the body's pops advance, as linux's decayed array does
            params |> push("var {name} : {spelled}")
            continue
        }
        let mode = is_var_parameter(tu, p.t) ? "var " : ""
        // das passes a record by reference: the copy is C's by-value one; in the copy mode a
        // written scalar or pointer is copied too, since the interpreter writes a local faster
        // than an argument slot. The parameter keeps its mode under a name no parameter or
        // local of the body takes
        if (is_record(tu, p.t) || (em.prog.param_copy && key_exists(em.written, p.name))) {
            let copy = free_name(taken, "{name}_in")
            params |> push("{mode}{copy} : {spelled}")
            copies |> push("var {name} = {copy}")
        } else {
            // das passes a scalar or a pointer by value, so the body writes it in place
            params |> push("{key_exists(em.written, p.name) ? "var " : mode}{name} : {spelled}")
        }
    }
}

// a K&R parameter that arrives as its promoted type `passed`: the parameter `<name>_in` of that
// type and its conversion to the declared type, `var` when the body writes it
def private promoted_param(var em : Emitter; tu : CirTu; d : CirDecl; p : CirParam; passed : int; name : string; var taken : table<string>; var params : array<string>; var copies : array<string>) {
    let copy = free_name(taken, "{name}_in")
    let spelled = das_type(em, tu, p.t, d.loc)
    params |> push("{copy} : {das_type(em, tu, passed, d.loc)}")
    // only an integer (an enum and `_Bool` among them) or a `float` promotes
    let converted = is_c_bool(tu, p.t) ? "{copy} != 0" : kind_of(tu, p.t) == "enum" ? int_to_enum(em, tu, p.t, "int({copy})") : "{spelled}({copy})"
    copies |> push("{key_exists(em.written, p.name) ? "var" : "let"} {name} = {converted}")
}

def private emit_function(var em : Emitter; tu : CirTu; d : CirDecl) {
    if (d.body == null) {
        return
    }
    let out_at = length(em.out)
    var inscope defs := em.macro_defs
    var inscope def_order := em.macro_def_order
    var inscope names := em.macro_names
    var inscope var_modes := em.macro_var
    var inscope counts := em.fold_counts
    var inscope counted := em.fold_counted
    let c_functions = em.c_functions
    let function_count = em.function_count
    spell_function(em, tu, d)
    if (empty(em.error) && labeled_fold(em, out_at)) {
        // das inlines no call declared in a block with a label (error 30100): spelled again,
        // every expansion of the function expanded
        em.out |> resize(out_at)
        em.macro_defs <- defs
        em.macro_def_order <- def_order
        em.macro_names <- names
        em.macro_var <- var_modes
        em.fold_counts <- counts
        em.fold_counted <- counted
        em.c_functions = c_functions
        em.function_count = function_count
        em.fold_function_off = true
        spell_function(em, tu, d)
        em.fold_function_off = false
    }
}

// whether the function spelled into `em.out` from `out_at` declares a folded call (`let` or `var`)
// in a block that holds a label, which das's inliner refuses
def private labeled_fold(em : Emitter; out_at : int) : bool {
    if (empty(em.macro_defs)) {
        return false
    }
    var lines : array<string>
    for (idx in range(out_at, length(em.out))) {
        lines |> push_from(split(em.out[idx], "\n"))
    }
    for (at, head in count(), lines) {
        let indent = indentation(head)
        if (!(slice(head, indent) |> starts_with("label "))) {
            continue
        }
        // the label's block: the lines around it at its indent or deeper
        var lo = at
        while (lo > 0 && (empty(lines[lo - 1]) || indentation(lines[lo - 1]) >= indent)) {
            lo--
        }
        var hi = at
        while (hi + 1 < length(lines) && (empty(lines[hi + 1]) || indentation(lines[hi + 1]) >= indent)) {
            hi++
        }
        for (idx in range(lo, hi + 1)) {
            let text = lines[idx]
            let own = indentation(text)
            let stmt = slice(text, own)
            if (own == indent && (stmt |> starts_with("let ") || stmt |> starts_with("var "))) {
                for (name in keys(em.macro_defs)) {
                    if (find(stmt, "{name}(") >= 0) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

// function `d` spelled into `em.out`
def private spell_function(var em : Emitter; tu : CirTu; d : CirDecl) {
    let variadic = tu.types[d.t].variadic
    if (d.c_name == "main" && d.is_static) {
        fail(em, "`main` is static: no entry point is synthesized", d.loc)
        return
    }
    if (d.c_name == "main" && !main_parameters(em, tu, d)) {
        return
    }
    reset_function_state(em, tu, d)
    var params, copies : array<string>
    var taken <- body_names(em, d)
    function_params(em, tu, d, taken, params, copies)
    em.spelled := taken
    plan_counted_loops(em, tu, d)
    // the trailing arguments arrive as the list the `[variadic]` prologue binds, under a name
    // the body leaves free
    if (variadic && key_exists(taken, VA_TUPLE)) {
        fail(em, "a C name `{VA_TUPLE}` in variadic function `{d.c_name}` is the [variadic] annotation's own; not lowered yet", d.loc)
        return
    }
    em.va_name = variadic ? free_name(taken, "va") : ""
    if (variadic) {
        em.requires |> insert("c_runtime/variadic")
        params |> push("{em.va_name} : va_args")
    }
    let ret = das_type(em, tu, tu.types[d.t].ret, d.loc)
    em.fn_ret = ret
    let header = "def {d.is_static ? "private " : ""}{das_func_name(em, d)}" + (empty(params) ? "" : "({join(params, PARAMETER_SEPARATOR)})") + (ret == "void" ? "" : " : {ret}")
    carry_comments_above(em, d.loc)
    let header_at = length(em.out)
    open_block(em, header)
    for (copy in copies) {
        line(em, copy)
    }
    if (calls_alloca(d.body)) {
        // the per-function arena every alloca of the body bumps, freed with the frame
        line(em, "var _c_astack : uint8[{em.prog.alloca_limit}]")
        line(em, "var _c_aoff = 0")
    }
    em.in_body = true
    let body_at = length(em.out)
    emit_body(em, tu, d.body)
    em.in_body = false
    if (ret != "void" && !ends_in_return(tu, d.body) && !text_returns(em, body_at)) {
        line(em, "return {zero_of(em, tu, tu.types[d.t].ret, ret)}")
    }
    close_block(em)
    line(em, "")
    em.function_count++
    var annotations : array<string>
    if (em.unsafe_used) {
        em.c_functions++
        annotations |> push("c_function")
        em.requires |> insert("c_runtime/c_function")
    }
    if (em.prog.unchecked) {
        annotations |> push_from(UNCHECKED_ANNOTATIONS)
    }
    if (variadic) {
        annotations |> push("variadic")
    }
    if (!empty(annotations)) {
        em.out[header_at] = "[{join(annotations, ", ")}]\n" + em.out[header_at]
    }
}

// whether record `t` is refused, with the error set: a marshal-only record with a bitfield, named
// or not; a packed record whose alignment an attribute raises past its members', or that has
// bitfields, or that the sidecar does not list marshal-only; a field spelled like an anonymous
// member's name; a `va_list` field; a flexible array member
def private record_refusal(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : bool {
    let name = tag_name(em, tu, t)
    let marshal = is_marshal(em, tu, t)
    let any_bitfield = has_bitfield(tu, t, false)
    if (marshal && any_bitfield) {
        fail(em, "bitfields of the marshal-only record `{name}` are not lowered yet", loc)
        return true
    }
    if (tu.types[t].packed && !marshal && (any_bitfield || has_underaligned_record_field(tu, em.prog.layout, t))) {
        let members_align = members_align(tu, em.prog.layout, t)
        if (tu.types[t].align > members_align) {
            fail(em, "record `{name}` has an alignment attribute das cannot spell: clang aligns it to {tu.types[t].align}, its members to {members_align}; not lowered yet", loc)
            return true
        }
    }
    if (tu.types[t].packed && has_bitfield(tu, t, true)) {
        fail(em, "record `{name}` has bitfields and das cannot lay it out as clang does; not lowered yet", loc)
        return true
    }
    let jmp_buf_at = tu.types[t].packed ? jmp_buf_field(tu, t) : -1
    if (jmp_buf_at >= 0) {
        // das holds the protocol's `CJmpBuf`, not glibc's buffer, so the fields after it cannot
        // sit where clang puts them
        fail(em, "record `{name}` holds a `jmp_buf` (`{tu.types[t].fields[jmp_buf_at].name}`), which das spells as `CJmpBuf`, not at the C library's size; not lowered yet", loc)
        return true
    }
    if (tu.types[t].packed && !marshal) {
        fail(em, "record `{name}` is not laid out naturally: a packed record is marshal-only, listed under `marshal` in the .c2das sidecar", loc)
        return true
    }
    if (has_anonymous_member(tu, t)) {
        for (f in tu.types[t].fields) {
            if (numbered_after(das_name(em, f.name), "_anon") >= 0) {
                fail(em, "field `{name}.{f.name}` is spelled like the name of an anonymous member", loc)
                return true
            }
        }
    }
    for (f in tu.types[t].fields) {
        if (is_va_list(tu, f.t)) {
            fail(em, "a `va_list` field (`{name}.{f.name}`) is not lowered yet", loc)
            return true
        }
    }
    let n = length(tu.types[t].fields)
    if (n > 0 && is_flexible(tu, t, n - 1)) {
        assume fam = tu.types[t].fields[n - 1]
        var rest_align = 1
        for (idx in range(n - 1)) {
            let a = natural_align(tu, em.prog.layout, tu.types[t].fields[idx].t)
            if (a > rest_align) {
                rest_align = a
            }
        }
        if (marshal) {
            fail(em, "flexible array member `{name}.{fam.name}` of a marshal-only record is not lowered yet", loc)
            return true
        }
        if (fam.off != tu.types[t].size || natural_align(tu, em.prog.layout, fam.t) > rest_align) {
            // the record leaves the member out, so the member may neither pad its end nor raise its
            // alignment
            fail(em, "flexible array member `{name}.{fam.name}`, which pads the record or raises its alignment, is not lowered yet", loc)
            return true
        }
    }
    return false
}

// whether field `field` of record `rec` is a flexible array member: an array of unknown length
// that ends the record
def private is_flexible(tu : CirTu; rec, field : int) : bool {
    let n = length(tu.types[rec].fields)
    return field == n - 1 && kind_of(tu, tu.types[rec].fields[field].t) == "array" && tu.types[tu.types[rec].fields[field].t].count < 0
}

// the key of field `field` of record `rec` in `Emitter.over_indexed`
def private member_key(rec, field : int) : int64 => (int64(rec) << 32l) | int64(field)

// the record and field of member expression `x`
def private member_of(tu : CirTu; x : CirExpr const?) : tuple<rec : int; field : int> =>
    (rec = x.arrow ? tu.types[x.base.t].to : x.base.t, field = x.field)

// how an array member `x` (a member expression) is reached past its declaration: "flexible" for a
// flexible array member, which the record leaves out, "over" for a trailing array the sidecar
// lists under `over_indexed`, "padded" for an array it lists under `padded`, "" for any other
// expression
def private unchecked_access(em : Emitter; tu : CirTu; x : CirExpr const?) : string {
    if (x == null || x.e != "member") {
        return ""
    }
    let m = member_of(tu, x)
    if (m.field < 0 || m.field >= length(tu.types[m.rec].fields)) {
        return ""
    }
    if (is_flexible(tu, m.rec, m.field)) {
        return "flexible"
    }
    let key = member_key(m.rec, m.field)
    return key_exists(em.prog.over_indexed, key) ? "over" : key_exists(em.prog.padded, key) ? "padded" : ""
}

// the decay of flexible array member `x` (`p->data`, `s.data`): the record's address plus the
// member's offset as a pointer to its element, since the record declares no field for it
[arch(at="ARCHITECTURE_EMITTER_AGGREGATES.md#flexible-array-members")]
def private flexible_pointer(var em : Emitter; tu : CirTu; x : CirExpr const?; loc : CirLoc) : Em {
    let m = member_of(tu, x)
    var record : Em
    if (x.arrow) {
        record = emit_expr(em, tu, x.base, loc)
    } elif (x.base.e == "un" && x.base.op == "deref") {
        record = emit_expr(em, tu, x.base.a, loc)
    } else {
        record = unsafe_value(em, "addr({wrap(emit_expr(em, tu, x.base, loc), PREC_PRIMARY)})", PREC_PRIMARY)
    }
    let ft = tu.types[m.rec].fields[m.field].t
    let elem = das_type(em, tu, tu.types[ft].elem, loc)
    return unsafe_value(em, "reinterpret<{elem}?>(reinterpret<uint8?>({record.text}) + {tu.types[m.rec].fields[m.field].off})", PREC_PRIMARY)
}

// member expression `x` (`p->f`, `s.f`) is a field at offset 0 that the containing pointer can stand
// for: neither a field of a marshal-only record, which das reads through its readers, nor one of a
// marshal-only type, whose das value has das's layout (C takes no bitfield's address)
def private at_offset_zero(em : Emitter; tu : CirTu; x : CirExpr const?) : bool {
    if (x == null || x.e != "member") {
        return false
    }
    let m = member_of(tu, x)
    if (is_marshal(em, tu, m.rec) || m.field < 0 || m.field >= length(tu.types[m.rec].fields)) {
        return false
    }
    return tu.types[m.rec].fields[m.field].off == 0 && !is_marshal(em, tu, tu.types[m.rec].fields[m.field].t)
}

// the lvalue under the members at offset 0 that `x` chains (`p->a.b`, `(*p).a`, `p[i].a`) when it
// is reached through a pointer: the arrow member, the `*p` or the `p[i]` of a pointer; null when
// `x` is no such member, or the chain ends at a record held by value (`s.a`, `arr[i].a`)
def private first_member_root(em : Emitter; tu : CirTu; x : CirExpr const?) : CirExpr const? {
    if (!at_offset_zero(em, tu, x)) {
        return null
    }
    var at = x
    while (at_offset_zero(em, tu, at)) {
        if (at.arrow) {
            return at
        }
        at = at.base
    }
    if (at.e == "un" && at.op == "deref") {
        return at
    }
    let decay = at.e == "index" && at.base.e == "cast" && at.base.cast_kind == "ArrayToPointerDecay"
    return at.e == "index" && is_data_pointer(tu, at.base.t) && !decay ? at : null
}

// a pointer operand under its pointer `BitCast`s (`(union GCUnion *) o` is `o`), the record it
// points to being read at offset 0 alone
def private under_pointer_casts(tu : CirTu; p : CirExpr const?) : CirExpr const? {
    var at = p
    while (at.e == "cast" && at.cast_kind == "BitCast" && is_data_pointer(tu, at.t) && is_data_pointer(tu, at.a.t)) {
        at = at.a
    }
    return at
}

// under the `first_member` option `reinterpret`, `&x` (`x` the `&`) of a member at offset 0, or the
// decay of an array member at offset 0 (`x` the cast), as its record's pointer reinterpreted to the
// result's type: `reinterpret<TValue?>(base + a)` for `&(base + a)->val`, the pointer as it is when
// it already has that type; an empty text for any other operand, which keeps `addr(...)`
[arch(at="ARCHITECTURE_EMITTER_AGGREGATES.md#first-member-address")]
def private first_member_address(var em : Emitter; tu : CirTu; x : CirExpr; loc : CirLoc) : Em {
    let root = em.prog.reinterpret_members ? first_member_root(em, tu, x.a) : null
    if (root == null) {
        return Em()
    }
    let target = das_type(em, tu, x.t, loc)
    if (root.e == "index") {
        let base = emit_expr(em, tu, root.base, loc)
        let i = index_value(em, tu, root.i, loc)
        return unsafe_value(em, "reinterpret<{target}>({wrap(base, PREC_ADD)} + {wrap(i, PREC_ADD + 1)})", PREC_PRIMARY)
    }
    let pointer = under_pointer_casts(tu, root.e == "member" ? root.base : root.a)
    let text = emit_expr(em, tu, pointer, loc)
    if (das_type(em, tu, pointer.t, loc) == target) {
        return text
    }
    return unsafe_value(em, "reinterpret<{target}>({text.text})", PREC_PRIMARY)
}

// the field lines of record `t`, adjacent fields of one type on one line, a padding field
// `_pad<N> : uint8[n]` where the layout law pads; false with the error set when a C field is
// spelled like a padding field of a record that pads
def private record_lines(var em : Emitter; tu : CirTu; t : int; loc : CirLoc; var lines : array<string>) : bool {
    let n = length(tu.types[t].fields)
    var inscope pads <- layout_pads(tu, em.prog.layout, t)
    if (!empty(pads)) {
        for (f in tu.types[t].fields) {
            if (numbered_after(das_name(em, f.name), "_pad") >= 0) {
                fail(em, "field `{tag_name(em, tu, t)}.{f.name}` is spelled like a padding field", loc)
                return false
            }
        }
    }
    lines |> reserve(length(lines) + n + length(pads))
    var names : array<string>
    names |> reserve(n)
    var spelled = ""
    var next_pad = 0
    for (idx in range(n + 1)) {
        let pad_here = next_pad < length(pads) && pads[next_pad].before == idx
        var ft = ""
        if (idx < n && !is_unnamed_bitfield(tu.types[t].fields[idx]) && !is_flexible(tu, t, idx)) {
            ft = is_marshal(em, tu, t) ? marshal_field_type(em, tu, tu.types[t].fields[idx], loc) : das_type_dims(em, tu, tu.types[t].fields[idx].t, loc, tu.types[t].fields[idx].dims)
        }
        // the end, a padding field or a field of another type closes the line of names
        if (!empty(names) && (idx == n || pad_here || (!empty(ft) && ft != spelled))) {
            lines |> push("{join(names, ", ")} : {spelled}")
            names |> clear()
        }
        while (next_pad < length(pads) && pads[next_pad].before == idx) {
            lines |> push("_pad{next_pad} : uint8[{pads[next_pad].size}]")
            next_pad++
        }
        if (!empty(ft)) {
            spelled = ft
            names |> push(member_name(em, tu.types[t].fields[idx], idx))
        }
    }
    return true
}

// `struct Name { fields }` (`record_lines`), under `[c_bitfields(...)]` when it has bitfields
// and under `[c_union]` when it is a union
def private emit_record(var em : Emitter; tu : CirTu; d : CirDecl) {
    let t = d.t
    let name = tag_name(em, tu, t)
    if (kind_of(tu, t) == "union") {
        let annotation = union_annotation(em, tu, t, d.loc)
        if (empty(annotation)) {
            return
        }
        em.requires |> insert("c_runtime/c_union")
        line(em, annotation)
    }
    if (record_refusal(em, tu, t, d.loc)) {
        return
    }
    if (has_bitfield_units(tu, t)) {
        let annotation = bitfields_annotation(em, tu, t, d.loc)
        if (!empty(em.error)) {
            return
        }
        em.requires |> insert("c_runtime/c_bitfields")
        line(em, annotation)
    }
    var lines : array<string>
    if ((is_marshal(em, tu, t) && !marshal_fields_lowered(em, tu, t, d.loc)) || !record_lines(em, tu, t, d.loc, lines)) {
        return
    }
    open_block(em, "struct {name}")
    for (l in lines) {
        line(em, l)
    }
    close_block(em)
    line(em, "")
    if (is_marshal(em, tu, t)) {
        emit_marshal_readers(em, tu, t, d.loc)
    }
}

// `[c_union]` for union `t`, or `[c_union(size = N, align = A)]` when the members alone do not
// give clang's size and alignment, or when a member's type spells a dimension by an enum
// constant, which das folds only after the annotation has read the members; a bitfield member
// adds `name = width` and an unnamed one is no member; "" with the error set on a union the
// annotation does not lower
def private union_annotation(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    let name = tag_name(em, tu, t)
    var bare = true
    var widths : array<string>
    for (f in tu.types[t].fields) {
        continue if (is_unnamed_bitfield(f))
        let member = empty(f.name) ? "an anonymous member" : "`{name}.{f.name}`"
        if (f.is_bitfield) {
            if (kind_of(tu, f.t) != "int") {
                fail(em, "bitfield `{name}.{f.name}` of {kind_of(tu, f.t)} type is not lowered yet", loc)
                return ""
            }
            let spelled = das_name(em, f.name)
            if (spelled == "size" || spelled == "align") {
                fail(em, "bitfield {member} is spelled like an argument of `[c_union]`", loc)
                return ""
            }
            widths |> push("{spelled} = {f.bit_w}")
        }
        let elem = element_under(tu, f.t)
        if (is_marshal(em, tu, elem)) {
            fail(em, "union `{name}` holds the marshal-only record `{tag_name(em, tu, elem)}`; not lowered yet", loc)
            return ""
        }
        if (das_name(em, f.name) == "_storage") {
            fail(em, "member {member} is spelled like the storage field of `[c_union]`", loc)
            return ""
        }
        bare = bare && !spells_enum_dim(tu, f.t, f.dims)
    }
    let flaw = union_flaw(tu, em.prog.layout, t)
    if (!empty(flaw)) {
        fail(em, "union `{name}` {flaw}; not lowered yet", loc)
        return ""
    }
    let derived = union_member_layout(tu, em.prog.layout, t)
    if (bare && derived.size == int64(tu.types[t].size) && derived.align == tu.types[t].align) {
        return empty(widths) ? "[c_union]" : "[c_union({join(widths, ", ")})]"
    }
    widths |> push("size = {tu.types[t].size}")
    widths |> push("align = {tu.types[t].align}")
    return "[c_union({join(widths, ", ")})]"
}

// whether a declarator of type `t` with dimensions `dims` spells a dimension by an enum
// constant, in itself or in a record it holds by value
def private spells_enum_dim(tu : CirTu; t : int; dims : array<CirDim>) : bool {
    if (!empty(dims)) {
        return true
    }
    let rec = record_under(tu, t)
    if (rec >= 0) {
        for (f in tu.types[rec].fields) {
            if (spells_enum_dim(tu, f.t, f.dims)) {
                return true
            }
        }
    }
    return false
}

// whether record `t` is a struct whose bitfields `[c_bitfields]` gives storage units
def private has_bitfield_units(tu : CirTu; t : int) : bool => kind_of(tu, t) != "union" && has_bitfield(tu, t, true)

def private is_bitfield_member(tu : CirTu; x : CirExpr const?) : bool {
    if (x == null || x.e != "member") {
        return false
    }
    let rec = x.arrow ? tu.types[x.base.t].to : x.base.t
    return x.field >= 0 && x.field < length(tu.types[rec].fields) && tu.types[rec].fields[x.field].is_bitfield
}

def private unit_storage(size : int) : string => size == 1 ? "uint8" : size == 2 ? "uint16" : size == 4 ? "uint" : "uint64"

// the number in `name` after `prefix` when the rest is all digits, else -1
def private numbered_after(name, prefix : string) : int =>
    name |> starts_with(prefix) && is_digit_run(name, length(prefix)) ? to_int(slice(name, length(prefix))) : -1

// a C field `[c_bitfields]` would misread: a bitfield named like an opener (`_bits<N>`) or a
// padding argument (`_<K>`), or another field named like one of the `units` storage fields
def private clashes_with_annotation(em : Emitter; f : CirField; units : int) : bool {
    let spelled = das_name(em, f.name)
    let opener = numbered_after(spelled, "_bits")
    if (f.is_bitfield) {
        return opener >= 0 || numbered_after(spelled, "_") >= 0
    }
    return opener >= 0 && opener < units
}

// `[c_bitfields(...)]` for record `t`, one unit after another: `_bits<N> = "storage"` opens the
// unit, left out for the first unit when its storage is the one the annotation's default rule
// gives its first field and that field starts the unit; `_<K> = gap` covers the bits clang
// leaves before a field; then `name = width` per bitfield in order
def private bitfields_annotation(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : string {
    let name = tag_name(em, tu, t)
    for (f in tu.types[t].fields) {
        if (is_storage_bitfield(f) && kind_of(tu, f.t) != "int") {
            fail(em, "bitfield `{name}.{f.name}` of {kind_of(tu, f.t)} type is not lowered yet", loc)
            return ""
        }
    }
    var units : array<BitUnit>
    if (!bit_units(tu, em.prog.layout, t, units)) {
        // the dumper marks such a record packed, so only a C-IR from elsewhere reaches this
        fail(em, "record `{name}`: no bitfield units reproduce clang's layout", loc)
        return ""
    }
    for (f in tu.types[t].fields) {
        if (!empty(f.name) && clashes_with_annotation(em, f, length(units))) {
            fail(em, "field `{name}.{f.name}` is spelled like a storage or padding name of `[c_bitfields]`", loc)
            return ""
        }
    }
    var args : array<string>
    var pad_index = 0
    for (n, u in range(length(units)), units) {
        let storage = u.byte_array ? "uint8[{u.size}]" : unit_storage(u.size)
        let base = u.off * 8
        assume first = tu.types[t].fields[u.first]
        if (n != 0 || first.bit_off != base || storage != unit_storage(int(type_size(tu, first.t)))) {
            args |> push("_bits{n} = \"{storage}\"")
        }
        var cursor = 0
        for (idx in range(u.first, u.last + 1)) {
            assume f = tu.types[t].fields[idx]
            continue if (!is_storage_bitfield(f))
            if (f.bit_off - base > cursor) {
                args |> push("_{pad_index} = {f.bit_off - base - cursor}")
                pad_index++
            }
            args |> push("{das_name(em, f.name)} = {f.bit_w}")
            cursor = f.bit_off - base + f.bit_w
        }
    }
    return "[c_bitfields({join(args, ", ")})]"
}

// the unit holding bitfield `field`, -1 when none holds it
def private unit_of(units : array<BitUnit>; field : int) : int {
    for (n, u in range(length(units)), units) {
        if (field >= u.first && field <= u.last) {
            return n
        }
    }
    return -1
}

// one unit's initializer: every initialized bitfield of it as `(W(v) & mask) << bit`, or-ed in
// the unit's arithmetic type (`uint`, `uint64` for a unit past 4 bytes; das shifts no narrower
// type) and narrowed to the storage, the conversions `[c_bitfields]`'s setter makes; a byte
// unit's word goes through `c_unit_bytes` into its bytes
def private unit_init(tu : CirTu; t : int; u : BitUnit; parts : array<tuple<field : int; v : Em; spelled : string>>) : string {
    let wide = u.size > 4
    let arith_type = wide ? "uint64" : "uint"
    let suffix = wide ? "ul" : "u"
    let bits = wide ? 64 : 32
    var terms : array<string>
    terms |> reserve(length(parts))
    for (p in parts) {
        assume f = tu.types[t].fields[p.field]
        let shift = f.bit_off - u.off * 8
        var v = p.spelled == "bool" ? value("({wrap(p.v, PREC_COND + 1)} ? 1{suffix} : 0{suffix})", PREC_PRIMARY) : (p.spelled == arith_type ? p.v : value("{arith_type}({p.v.text})", PREC_PRIMARY))
        if (f.bit_w < bits) {
            v = value("{wrap(v, PREC_BAND + 1)} & {(1ul << uint64(f.bit_w)) - 1ul}{suffix}", PREC_BAND)
        }
        terms |> push(shift > 0 ? "({v.text}) << {shift}{suffix}" : v.text)
    }
    let joined = length(terms) == 1 ? terms[0] : join([for (term in terms); "({term})"], " | ")
    if (u.byte_array) {
        return "{UNIT_BYTES}({joined}, default<uint8[{u.size}]>)"
    }
    let storage = unit_storage(u.size)
    return storage == arith_type ? joined : "{storage}({joined})"
}

// whether every field of marshal-only record `t` has accessors, with the error set when not: a
// record field, or a one-dimensional array of records, is one of a marshal-only record, which
// lies at clang's offsets as the outer one does
def private marshal_fields_lowered(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) : bool {
    let name = tag_name(em, tu, t)
    for (f in tu.types[t].fields) {
        let elem = element_under(tu, f.t)
        if (kind_of(tu, elem) == "union") {
            fail(em, "field `{name}.{f.name}` of a marshal-only record holds a union; not lowered yet", loc)
            return false
        }
        if (kind_of(tu, elem) == "struct" && !is_marshal(em, tu, elem)) {
            fail(em, "field `{name}.{f.name}` of a marshal-only record holds the record `{tag_name(em, tu, elem)}`, which is not listed under `marshal`", loc)
            return false
        }
        if (elem != f.t && kind_of(tu, elem) != "int" && kind_of(tu, elem) != "float" && kind_of(tu, elem) != "struct") {
            fail(em, "field `{name}.{f.name}` of a marshal-only record is an array of `{kind_of(tu, elem)}`; not lowered yet", loc)
            return false
        }
        if (is_record(tu, elem) && elem != f.t && tu.types[f.t].elem != elem) {
            fail(em, "field `{name}.{f.name}` of a marshal-only record is an array of arrays of records; not lowered yet", loc)
            return false
        }
    }
    return true
}

// the das type of field `f` of marshal-only record `t`: an array of a marshal-only record is
// the das array of its natural struct, which no other place holds
def private marshal_field_type(var em : Emitter; tu : CirTu; f : CirField; loc : CirLoc) : string {
    let elem = element_under(tu, f.t)
    return is_record(tu, elem) && elem != f.t ? "{tag_name(em, tu, elem)}[{tu.types[f.t].count}]" : das_type_dims(em, tu, f.t, loc, f.dims)
}

// the readers and writers of a marshal-only record: the whole record and each scalar field,
// over bytes at clang's offsets through daslang's builtin `memcpy` with an `int` size, which asks
// nothing of alignment and which the JIT folds to one load or store (`crt::memcpy` is a call per
// field there; docs/probe-findings.md F81), and a typed
// pointer to each array field at its offset, an inner marshal record through its own reader and
// writer; the value side is the naturally laid out das struct (docs/lowering-examples.md
// "Packed structs")
def private emit_marshal_readers(var em : Emitter; tu : CirTu; t : int; loc : CirLoc) {
    let name = tag_name(em, tu, t)
    em.requires |> insert("c_runtime/c_function")
    line(em, "[c_function]")
    open_block(em, "def {reader_name(em, tu, t, -1)}(bytes : uint8?; ofs : int) : {name}")
    line(em, "var r : {name}")
    for (f in tu.types[t].fields) {
        let rec = element_under(tu, f.t)
        let field = "r.{das_name(em, f.name)}"
        if (rec == f.t && is_record(tu, rec)) {
            line(em, "{field} = {reader_name(em, tu, rec, -1)}(bytes, ofs + {f.off})")
        } elif (is_record(tu, rec)) {
            open_block(em, "for (k in range({tu.types[f.t].count}))")
            line(em, "{field}[k] = {reader_name(em, tu, rec, -1)}(bytes, ofs + {f.off} + k * {type_size(tu, rec)})")
            close_block(em)
        } else {
            line(em, "memcpy(reinterpret<void?>(addr({field})), reinterpret<void?>(bytes + (ofs + {f.off})), {type_size(tu, f.t)})")
        }
    }
    line(em, "return r")
    close_block(em)
    line(em, "")
    line(em, "[c_function]")
    open_block(em, "def {writer_name(em, tu, t, -1)}(bytes : uint8?; ofs : int; {is_var_parameter(tu, t) ? "var " : ""}v : {name})")
    line(em, "var copy = v")
    for (f in tu.types[t].fields) {
        let rec = element_under(tu, f.t)
        let field = "copy.{das_name(em, f.name)}"
        if (rec == f.t && is_record(tu, rec)) {
            line(em, "{writer_name(em, tu, rec, -1)}(bytes, ofs + {f.off}, {field})")
        } elif (is_record(tu, rec)) {
            open_block(em, "for (k in range({tu.types[f.t].count}))")
            line(em, "{writer_name(em, tu, rec, -1)}(bytes, ofs + {f.off} + k * {type_size(tu, rec)}, {field}[k])")
            close_block(em)
        } else {
            line(em, "memcpy(reinterpret<void?>(bytes + (ofs + {f.off})), reinterpret<void?>(addr({field})), {type_size(tu, f.t)})")
        }
    }
    close_block(em)
    line(em, "")
    for (idx, f in range(length(tu.types[t].fields)), tu.types[t].fields) {
        if (is_record(tu, element_under(tu, f.t))) {
            // a record field, or an array of records, is the inner record's bytes where they lie,
            // the first element's for an array
            line(em, "[c_function]")
            open_block(em, "def {pointer_name(em, tu, t, idx)}(bytes : uint8?; ofs : int) : uint8?")
            line(em, "return reinterpret<uint8?>(bytes + (ofs + {f.off}))")
            close_block(em)
            line(em, "")
            continue
        }
        if (kind_of(tu, f.t) == "array") {
            // C reaches an array field only through its decay, its address or `sizeof`: the
            // field's accessor is the pointer to its first element where it lies
            let elem = das_type(em, tu, tu.types[f.t].elem, loc)
            line(em, "[c_function]")
            open_block(em, "def {pointer_name(em, tu, t, idx)}(bytes : uint8?; ofs : int) : {elem}?")
            line(em, "return reinterpret<{elem}?>(bytes + (ofs + {f.off}))")
            close_block(em)
            line(em, "")
            continue
        }
        let ft = das_type_dims(em, tu, f.t, loc, f.dims)
        line(em, "[c_function]")
        open_block(em, "def {reader_name(em, tu, t, idx)}(bytes : uint8?; ofs : int) : {ft}")
        line(em, "var r : {ft}")
        line(em, "memcpy(reinterpret<void?>(addr(r)), reinterpret<void?>(bytes + (ofs + {f.off})), {type_size(tu, f.t)})")
        line(em, "return r")
        close_block(em)
        line(em, "")
        line(em, "[c_function]")
        open_block(em, "def {writer_name(em, tu, t, idx)}(bytes : uint8?; ofs : int; {is_var_parameter(tu, f.t) ? "var " : ""}v : {ft})")
        line(em, "var copy = v")
        line(em, "memcpy(reinterpret<void?>(bytes + (ofs + {f.off})), reinterpret<void?>(addr(copy)), {type_size(tu, f.t)})")
        close_block(em)
        line(em, "")
    }
}

// `enum Name { items }` with das's default int base; an item states its value only where C's
// counting from the previous one would not give it
def private emit_enum(var em : Emitter; tu : CirTu; d : CirDecl) {
    open_block(em, "enum {tag_name(em, tu, d.t)}")
    var next = 0l
    for (it in tu.types[d.t].items) {
        line(em, it.v == next ? das_name(em, it.name) : "{das_name(em, it.name)} = {enumerator_value(it.v)}")
        next = it.v + 1l
    }
    close_block(em)
    line(em, "")
}

// an enumerator's value as an `int`-based das enum holds it: a value past INT_MAX (an unsigned
// underlying type) wrapped to the negative int of the same bits, and INT_MIN as
// `-2147483647 - 1`, since das reads `-2147483648` as a negated out-of-range constant
def private enumerator_value(v : int64) : string {
    let held = v > 2147483647l ? v - 4294967296l : v
    return held == -2147483648l ? "-2147483647 - 1" : "{held}"
}

// the layout law checked where it is claimed: every emitted record's das size, alignment and
// field offsets (each bitfield unit's included) against clang's, at compile time, zero cost at
// run time
[arch(at="ARCHITECTURE_LAYOUT.md#layout-file")]
def private emit_layout_check(var em : Emitter; tu : CirTu; records : array<int>) {
    let at = length(em.out)
    line(em, "[init]")
    open_block(em, "def private {LAYOUT_CHECK}")
    for (t in records) {
        let name = tag_name(em, tu, t)
        // a record holding bitfield units can align below clang (docs/probe-findings.md F5)
        let align = natural_align(tu, em.prog.layout, t)
        let bitfields = has_bitfield_units(tu, t)
        let below = align == tu.types[t].align ? "" : (bitfields ? ", its bitfield units align {align}" : ", its das alignment is {align}")
        line(em, "static_assert(typeinfo sizeof(type<{name}>) == {tu.types[t].size} &&{LOGIC_MARK} typeinfo alignof(type<{name}>) == {align},{LIST_MARK} \"{name}: clang lays it out as size {tu.types[t].size}, align {tu.types[t].align}{below}\")")
        if (kind_of(tu, t) == "union") {
            line(em, "static_assert(typeinfo offsetof<_storage>(type<{name}>) == 0, \"{name}: every member sits at 0\")")
        }
        for (idx, f in range(length(tu.types[t].fields)), tu.types[t].fields) {
            if (!f.is_bitfield && kind_of(tu, t) != "union" && !is_flexible(tu, t, idx)) {
                let member = member_name(em, f, idx)
                line(em, "static_assert(typeinfo offsetof<{member}>(type<{name}>) == {f.off}, \"{name}.{member}: clang puts it at {f.off}\")")
            }
        }
        var inscope units : array<BitUnit>
        if (bitfields && bit_units(tu, em.prog.layout, t, units)) {
            for (n, u in range(length(units)), units) {
                line(em, "static_assert(typeinfo offsetof<_bits{n}>(type<{name}>) == {u.off}, \"{name}._bits{n}: the bitfield unit sits at {u.off}\")")
            }
        }
    }
    close_block(em)
    line(em, "")
    if (!empty(em.layout_file)) {
        em.layout_text = laid_out(join([for (idx in range(at, length(em.out))); em.out[idx]], ""))
        em.out |> resize(at)
        line(em, "include {em.layout_file}")
        line(em, "")
    }
}

def private emit_global(var em : Emitter; tu : CirTu; d : CirDecl) {
    if (d.is_extern) {
        return
    }
    if (is_va_list(tu, d.t)) {
        fail(em, "a `va_list` global (`{d.c_name}`) is not lowered yet", d.loc)
        return
    }
    let spelled = das_type_dims(em, tu, d.t, d.loc, d.dims)
    let head = "var {d.is_static ? "private " : ""}{das_name(em, d.name)} : {spelled}"
    if (d.init == null) {
        line(em, head)
        return
    }
    em.unsafe_used = false
    em.in_global_init = true
    var stores : array<string>
    let init = decl_init(em, tu, das_name(em, d.name), d.t, d.init, d.loc, stores)
    em.in_global_init = false
    if (!empty(em.pre)) {
        em.pre |> clear()
        fail(em, "a global initializer with side effects is not lowered yet", d.loc)
        return
    }
    // the objects of the initializer's compound literals precede it
    for (literal in em.global_literals) {
        line(em, literal)
    }
    em.global_literals |> clear()
    if (empty(init)) {
        // the stores run at module init, which is C's static initialization
        line(em, head)
        em.global_stores |> push_from(stores)
        return
    }
    if (!inline_legal(em, tu, d.init) || init_reaches_itself(em, tu, d)) {
        // das orders global initialization: an address of a global that is zero-initialized
        // or declared later is taken at module init (docs/lowering-examples.md "Globals"), and
        // so is an initializer das reads as reaching its own global
        line(em, head)
        em.global_stores |> push("{das_name(em, d.name)} = {init}")
    } else {
        // only a declaration that carries its initializer has its value before module init
        line(em, "{head} = {init}")
        em.global_initialized |> insert(d.name)
    }
    em.global_stores |> push_from(stores)
}

// whether das reads global `d`'s initializer as reaching `d` itself, its initialization loop
// (`probes/test_globals.das`): an initializer depends on every global and function of the module it
// names, a function on every one its body names, a global on its own initializer while that stays
// inline; C's static data has no such order. The globals are decided in order, so every walk
// sees the edges of the final module and more. A body's local named like a global counts as the
// global, which only moves an initializer that could have stayed
[arch(at="ARCHITECTURE_EMITTER_AGGREGATES.md#initialization-loops")]
def private init_reaches_itself(var em : Emitter; tu : CirTu; d : CirDecl) : bool {
    var seen : table<string>
    var pending : array<string>
    each_subexpr(d.init) $(x) {
        if (x.e == "ref") {
            pending |> push(x.name)
        }
    }
    while (!empty(pending)) {
        let name = pending |> back()
        pending |> pop()
        if (name == d.name) {
            return true
        }
        continue if (key_exists(seen, name))
        seen |> insert(name)
        let gi = em.init_globals?[name] ?? -1
        if (gi >= 0) {
            // a global spelled before `d` ends the walk: a stored one has no initializer, and an
            // inline one's own walk, over these edges and more, found no loop through it
            if (em.global_order[name] > em.globals_seen) {
                each_subexpr(tu.decls[gi].init) $(x) {
                    if (x.e == "ref") {
                        pending |> push(x.name)
                    }
                }
            }
        } elif (key_exists(em.body_functions, name)) {
            if (!key_exists(em.body_refs, name)) {
                var inscope names : table<string>
                collect_spelled_names(tu.decls[em.body_functions[name]].body, names)
                em.body_refs[name] <- [for (n in keys(names)); n]
            }
            pending |> push_from(em.body_refs[name])
        }
    }
    return false
}

// whether a global initializer may stay inline: every global whose address it takes has an
// explicit initializer and precedes it (`probes/test_globals.das`); a function's value and a
// literal's address need no order
def private inline_legal(var em : Emitter; tu : CirTu; x : CirExpr?) : bool {
    if (x == null) {
        return true
    }
    if (x.e == "compound_lit" && (kind_of(tu, x.t) == "union" || holds_union_list(tu, x.init))) {
        // its object is a global filled by stores at module init, so no initializer reads it
        return false
    }
    if ((x.e == "un" && x.op == "addr") || (x.e == "cast" && x.cast_kind == "ArrayToPointerDecay")) {
        var target = x.a
        while (target != null && target.e != "ref" && (target.e == "cast" || target.e == "member" || target.e == "index")) {
            target = target.e == "cast" ? target.a : target.base
        }
        if (target != null && target.e == "ref" && key_exists(em.global_order, target.name) && !key_exists(em.prog.functions, target.name)) {
            if (!key_exists(em.global_initialized, target.name) || em.global_order[target.name] >= em.globals_seen) {
                return false
            }
        }
    }
    if (!inline_legal(em, tu, x.a) || !inline_legal(em, tu, x.b) || !inline_legal(em, tu, x.c) || !inline_legal(em, tu, x.init)) {
        return false
    }
    for (item in x.init_items) {
        if (!inline_legal(em, tu, item.v)) {
            return false
        }
    }
    return true
}

// whether the part being emitted holds the global or function at index `di` of the unit's
// declarations, and whether it defines record or enum `t`
def private in_part(em : Emitter; di : int) : bool => em.whole || key_exists(em.part_decls, di)

def private owns_type(em : Emitter; t : int) : bool => em.whole || key_exists(em.part_types, t)

// the enums, the opaque records and the records of the part, each record the layout check reads
// pushed to `records`
def private emit_type_decls(var em : Emitter; tu : CirTu; var records : array<int>) {
    for (d in tu.decls) {
        if (d.k == "enumdef" && owns_type(em, d.t)) {
            emit_enum(em, tu, *d)
        }
    }
    // a record the unit declares and never defines (size -1) is reached only through pointers:
    // an empty struct names it, which no dereference or `sizeof` reaches, since clang refuses both
    for (t in range(length(tu.types))) {
        if (is_record(tu, t) && tu.types[t].size < 0 && owns_type(em, t)) {
            line(em, "struct {tag_name(em, tu, t)} \{\}")
            line(em, "")
        }
    }
    for (d in tu.decls) {
        if (d.k == "record" && tu.types[d.t].size >= 0 && owns_type(em, d.t)) {
            emit_record(em, tu, *d)
            // a marshal-only record's das layout is not clang's, by design
            if (!is_marshal(em, tu, d.t)) {
                records |> push(d.t)
            }
        }
        break if (!empty(em.error))
    }
}

def private emit_types(var em : Emitter; tu : CirTu) {
    var records : array<int>
    emit_type_decls(em, tu, records)
    if (!empty(records) && empty(em.error)) {
        emit_layout_check(em, tu, records)
    }
}

// the sidecar names a marshal-only record by its tag or by a typedef name
def private flag_marshal(var em : Emitter; tu : CirTu; side : Sidecar) {
    for (d in tu.decls) {
        if (d.k == "record" && key_exists(side.marshal, tu.types[d.t].name)) {
            em.prog.marshal |> insert(d.t)
        }
        if (d.k == "typedefdecl" && key_exists(side.marshal, d.name) && kind_of(tu, tu.types[d.t].to) == "struct") {
            em.prog.marshal |> insert(tu.types[d.t].to)
        }
    }
}

// the struct a sidecar entry's record name names, by tag or typedef name (the last that does);
// -1 when none does
def private record_named(tu : CirTu; name : string) : int {
    var rec = -1
    for (d in tu.decls) {
        if (d.k == "record" && kind_of(tu, d.t) == "struct" && tu.types[d.t].name == name) {
            rec = d.t
        } elif (d.k == "typedefdecl" && d.name == name && kind_of(tu, tu.types[d.t].to) == "struct") {
            rec = tu.types[d.t].to
        }
    }
    return rec
}

// the sidecar's `over_indexed` entries, each `Record.field` by tag or typedef name, as record and
// field keys; an entry naming no record's trailing fixed-length array member is an error
def private flag_over_indexed(var em : Emitter; tu : CirTu; side : Sidecar) {
    for (entry in side.over_indexed) {
        let dot = find(entry, ".")
        let rec = record_named(tu, slice(entry, 0, dot))
        let field_name = slice(entry, dot + 1)
        let n = rec >= 0 ? length(tu.types[rec].fields) : 0
        let last_t = n > 0 ? tu.types[rec].fields[n - 1].t : -1
        if (n == 0 || tu.types[rec].fields[n - 1].name != field_name || kind_of(tu, last_t) != "array" || tu.types[last_t].count <= 0) {
            // a sidecar's error has no place in the C source
            em.error = "sidecar `over_indexed`: `{entry}` names no record's trailing array member of a fixed length"
            return
        }
        em.prog.over_indexed |> insert(member_key(rec, n - 1))
    }
}

// whether field `at` of record `rec` is an integer member of `elem`'s width, no bitfield, that lies
// at byte `off`: the pad a padded array's index reaches past one of its ends
def private pads_at(tu : CirTu; rec, at, elem, off : int) : bool {
    if (at < 0 || at >= length(tu.types[rec].fields)) {
        return false
    }
    assume f = tu.types[rec].fields[at]
    return !f.is_bitfield && f.off == off && kind_of(tu, f.t) == "int" && tu.types[f.t].w == tu.types[elem].w
}

// the sidecar's `padded` entries, each `Record.field` by tag or typedef name, as record and field
// keys: an array of integers whose index the program takes one past either end, into the
// member on that side (`visplane_t.top[-1]` is `pad1`), which das reaches since a plain record
// keeps clang's offsets; an entry naming no such array, one of a marshal-only record or one with
// no integer member of its element's width right before and right after it is an error
[arch(at="ARCHITECTURE_EMITTER_AGGREGATES.md#padded-array-members")]
def private flag_padded(var em : Emitter; tu : CirTu; side : Sidecar) {
    for (entry in side.padded) {
        let dot = find(entry, ".")
        let rec = record_named(tu, slice(entry, 0, dot))
        let field_name = slice(entry, dot + 1)
        var at = -1
        if (rec >= 0) {
            for (i, f in count(), tu.types[rec].fields) {
                if (f.name == field_name) {
                    at = i
                }
            }
        }
        let ft = at >= 0 ? tu.types[rec].fields[at].t : -1
        let elem = kind_of(tu, ft) == "array" ? tu.types[ft].elem : -1
        // a sidecar's error has no place in the C source
        if (kind_of(tu, elem) != "int") {
            em.error = "sidecar `padded`: `{entry}` names no record's array member of integers"
            return
        }
        if (is_marshal(em, tu, rec)) {
            em.error = "sidecar `padded`: `{entry}` is a member of a marshal-only record, which das reads through its readers"
            return
        }
        let off = tu.types[rec].fields[at].off
        let width = tu.types[elem].w / 8
        if (!pads_at(tu, rec, at - 1, elem, off - width) || !pads_at(tu, rec, at + 1, elem, off + tu.types[ft].count * width)) {
            em.error = "sidecar `padded`: `{entry}` has no integer member of its element's width right before and right after it"
            return
        }
        em.prog.padded |> insert(member_key(rec, at))
    }
}

// the sidecar's and the options' choices the emitter reads, and the program's global names
def private take_options(var em : Emitter; tu : CirTu; side : Sidecar) {
    em.prog.alloca_limit = side.alloca_limit > 0 ? side.alloca_limit : ALLOCA_LIMIT
    em.prog.stack_option = side.stack
    em.prog.solid_context = side.solid_context
    em.prog.jit_whole_program = side.jit_whole_program
    em.prog.strict_aliasing = side.strict_aliasing
    em.prog.unchecked = side.checks == "off"
    em.prog.param_copy = side.param_writes == "copy"
    em.prog.range_loops = side.loops != "while"
    em.prog.reinterpret_members = side.first_member == "reinterpret"
    em.prog.goto_dispatch = side.switch_dispatch == "goto"
    em.prog.past_end_inline = side.past_end == "inline"
    for (name in side.no_fold) {
        if (!has_value([for (m in tu.macros); m.name == name], true)) {
            fail(em, "the sidecar's `no_fold` names `{name}`, which is no function-like macro the program expands", CirLoc(file = tu.tu))
        }
        em.prog.no_fold |> insert(name)
    }
    em.prog.global_names <- {for (d in tu.decls); d.name; where d.k == "global"}
    em.prog.defined_globals <- {for (d in tu.decls); d.name; where d.k == "global" && !d.is_extern}
}

// a reference C makes before the definition that gives its array a length (`extern int a[];`,
// the definition later in the unit or in another one) keeps clang's type of unknown length: it
// takes the type of the global the dumper's merge or the link binds its name to, so indexing and
// decay address the definition's storage; a global no unit defines fails naming it
def private complete_extern_arrays(var em : Emitter; var tu : CirTu) {
    let globals <- {for (di, d in count(), tu.decls); d.name => di; where d.k == "global"}
    for (d in tu.decls) {
        if (d.k == "func") {
            each_expr_mut(d.body) $(var x) {
                complete_array_ref(em, tu, globals, x)
            }
        } elif (d.k == "global") {
            each_subexpr_mut(d.init) $(var x) {
                complete_array_ref(em, tu, globals, x)
            }
        }
    }
}

// `complete_extern_arrays` for one expression, `globals` each global's index by name
def private complete_array_ref(var em : Emitter; tu : CirTu; globals : table<string; int>; var x : CirExpr?) {
    if (x.e != "ref" || kind_of(tu, x.t) != "array" || tu.types[x.t].count >= 0) {
        return
    }
    let di = globals?[x.name] ?? -1
    if (di < 0) {
        return
    }
    let d = tu.decls[di]
    // only a definition completes the reference: a sized `extern` declaration another unit makes
    // is no storage, whichever unit the link saw first
    if (!d.is_extern && kind_of(tu, d.t) == "array" && tu.types[d.t].count >= 0) {
        x.t = d.t
    } else {
        fail(em, "`{d.c_name}` is an array of unknown length (`extern int a[];`) that no unit of the program defines", d.loc)
    }
}

// the facts of the whole program, before any module of it is spelled: a local that hides another
// is renamed in `tu` itself first (`unshadow_locals`)
def private prepare_program(var em : Emitter; var tu : CirTu; side : Sidecar) {
    complete_extern_arrays(em, tu)
    unshadow_locals(tu, em.prog.carried, em.prog.bound_objects, side.switch_dispatch == "goto")
    check_reserved_renames(em, tu)
    for (d in tu.decls) {
        if (d.k == "func" && d.body != null) {
            em.prog.functions |> insert(d.name)
        }
    }
    rename_taken_names(em, tu)
    flag_marshal(em, tu, side)
    flag_over_indexed(em, tu, side)
    flag_padded(em, tu, side)
    take_options(em, tu, side)
    for (d in tu.decls) {
        if (d.k == "func") {
            each_expr(d.body) $(x) {
                mark_pointed(x, em.prog.pointed)
            }
        } elif (d.k == "global") {
            each_subexpr(d.init) $(x) {
                mark_pointed(x, em.prog.pointed)
            }
        }
    }
    if (em.prog.range_loops) {
        em.prog.summaries <- summarize(tu, em.prog.pointed, em.prog.defined_globals, em.prog.strict_aliasing)
    }
    if (side.inline_helpers) {
        flag_inline_helpers(em, tu)
    }
}

// the order das initializes the globals of the part in, which is the order they are spelled
def private order_globals(var em : Emitter; tu : CirTu) {
    for (di, d in count(), tu.decls) {
        if (d.k == "global" && !d.is_extern && in_part(em, di)) {
            em.global_order[d.name] = length(em.global_order)
            if (d.init != null) {
                em.init_globals[d.name] = di
            }
        } elif (d.k == "func" && d.body != null && in_part(em, di)) {
            em.body_functions[d.name] = di
        }
    }
}

// the part's globals, then a blank line when there was one
def private emit_globals(var em : Emitter; tu : CirTu) {
    var globals_done = false
    for (di, d in count(), tu.decls) {
        if (d.k == "global" && in_part(em, di)) {
            em.globals_seen = em.global_order?[d.name] ?? em.globals_seen
            emit_global(em, tu, *d)
            globals_done = true
        }
        break if (!empty(em.error))
    }
    if (globals_done) {
        line(em, "")
    }
}

// `c2das_init_globals`, the stores the module's global initializers moved to module init
def private emit_init_globals(var em : Emitter) {
    if (!empty(em.global_stores)) {
        line(em, "[init]")
        open_block(em, "def private {INIT_GLOBALS}")
        for (store in em.global_stores) {
            line(em, store)
        }
        close_block(em)
        line(em, "")
    }
}

def private emit_functions(var em : Emitter; tu : CirTu) {
    for (di, d in count(), tu.decls) {
        if (d.k == "func" && in_part(em, di)) {
            emit_function(em, tu, *d)
        }
        break if (!empty(em.error))
    }
}

// the module's first `[init]`, at line `at`, though only the functions tell whether it is needed:
// the format families read `l` at the dialect's `long`, never the host CRT's
def private emit_dialect(var em : Emitter; tu : CirTu; at : int) {
    var dialect : array<string>
    if (key_exists(em.requires, "c_runtime/printf") || key_exists(em.requires, "c_runtime/scanf")) {
        dialect |> push("    {LONG_BITS_GLOBAL} = {tu.target.long_w}\n")
    }
    // msvc's signal numbers are its own
    if (key_exists(em.requires, "c_runtime/c_signal") && tu.target.triple |> find("windows") >= 0) {
        dialect |> push("    {SIGNAL_MSVC} = true\n")
    }
    if (!empty(dialect)) {
        em.out |> push("[init]\ndef private {DIALECT_INIT} \{\n{join(dialect, "")}\}\n\n", at)
    }
}

// `[export] def main`, which calls C `main`, when the module holds it
def private emit_main_wrapper(var em : Emitter; tu : CirTu) {
    if (em.has_c_main) {
        line(em, "[export]")
        open_block(em, "def main : int")
        if (em.main_args) {
            // argv[0] is the C program's name, its source file's stem, the name a native build
            // of it carries, on every tier
            em.requires |> insert("c_runtime/c_args")
            line(em, "{RUNTIME_INIT}(\"{program_name(tu.tu)}\")")
            line(em, "return {C_MAIN}({ARGC}(), {ARGV}())")
        } else {
            line(em, "return {C_MAIN}()")
        }
        close_block(em)
    }
}

// the module of the part `em` selects as one file: the dialect's `[init]`, the types with their
// layout check, the globals and their module-init stores, the functions and the `main` wrapper
def private emit_module_body(var em : Emitter; tu : CirTu) {
    let dialect_at = length(em.out)
    emit_types(em, tu)
    order_globals(em, tu)
    emit_globals(em, tu)
    emit_init_globals(em)
    let constants_at = length(em.out)
    emit_functions(em, tu)
    let lets = constant_lets(em) + macro_def_text(em)
    if (!empty(lets)) {
        em.out |> push(lets, constants_at)
    }
    emit_late_binding(em, tu)
    emit_dialect(em, tu, dialect_at)
    emit_main_wrapper(em, tu)
}

//! The whole module: banner, options, requires, every declaration, and the `main` wrapper
//! when the C program has one. Empty with `error` set when a node is outside the subset. A
//! local that hides another is renamed in `tu` itself first (`unshadow_locals`).
def emit_tu(var tu : CirTu; side : Sidecar) : Emitter {
    var em : Emitter
    em.whole = true
    prepare_program(em, tu, side)
    emit_module_body(em, tu)
    assemble_module(em)
    return <- em
}

// the stem of source file `file`, escaped for a das string literal
def private program_name(file : string) : string {
    let dot = rfind(file, ".")
    let stem = dot > 0 ? slice(file, 0, dot) : file
    return build_string() $(var w) {
        for (ch in stem) {
            if (ch == '"' || ch == '\\' || ch == 123 || ch == 125) {
                w |> write("\\")
            }
            w |> write(to_char(ch))
        }
    }
}

// the module text: banner, options, requires, the empty literal's byte (which precedes every
// global whose initializer takes its address), then everything emitted; a cluster's fragments get
// no options, since they are text its module includes and the module's options cover them; the
// program-wide options (`jit_split_modules`, `strict_aliasing`) go to the module holding `main`,
// the root, since daslang reads them from the root alone
[arch(at="ARCHITECTURE_TIERS.md#typed-aliasing")]
def private assemble_module(var em : Emitter) {
    let jit_pin = em.prog.jit_whole_program && em.has_c_main
    if (jit_pin) {
        em.requires |> insert("c_runtime/c_jit_build")
    }
    var required <- [for (name in keys(em.requires)); name]
    required |> sort()
    let header = join([for (name in required); "require {name}\n"], "")
    let empty = em.empty_literal ? "var private {EMPTY_LITERAL} : uint8[1] = fixed_array(uint8(0))\n\n" : ""
    let stack = em.prog.stack_option > 0 ? em.prog.stack_option : MODULE_STACK
    let stack_line = "options stack = {stack}\n"
    let solid_line = em.prog.solid_context ? "options solid_context\n" : ""
    let jit_line = jit_pin ? "options jit_split_modules = 0\n" : ""
    let alias_line = em.has_c_main && !em.prog.strict_aliasing ? "options strict_aliasing = false\n" : ""
    let banner = em.prog.unchecked ? "{GENERATED_BANNER}\n{UNCHECKED_BANNER}" : GENERATED_BANNER
    em.text = banner + "\noptions gen2\noptions indenting = 4\n" + solid_line + stack_line + alias_line + jit_line + header + "\n" + empty + laid_out(join(em.out, ""))
}

//! One file of a converted program: its path under the output folder (a module's `.das`, a
//! fragment's `.das.inc`) and its text.
struct ModuleFile {
    path : string
    text : string
}

//! A program emitted module by module: its files, the path of the module holding `main` among
//! them, the port-progress counts summed over the modules, and the first error.
struct ProgramEmission {
    files : array<ModuleFile>
    entry : string
    c_functions : int
    function_count : int
    // per reason how many function-like macro expansions folded or stayed expanded (`fold_macro`)
    fold_counts : table<string; int>
    error : string
}

// `name` in folder `dir`, relative to the program's root ("" the root itself)
def private in_dir(dir, name : string) : string => empty(dir) ? name : "{dir}/{name}"

// the path of `name` in folder `to_dir` as a file in folder `from_dir` reaches it, both relative
// to the program's root
def private relative_to(from_dir, to_dir, name : string) : string {
    var inscope from <- empty(from_dir) ? array<string>() : split(from_dir, "/")
    var inscope to <- empty(to_dir) ? array<string>() : split(to_dir, "/")
    var common = 0
    while (common < length(from) && common < length(to) && from[common] == to[common]) {
        common++
    }
    var parts <- [for (_ in range(common, length(from))); ".."]
    parts |> push_from([for (idx in range(common, length(to))); to[idx]])
    parts |> push(name)
    return join(parts, "/")
}

// what module `from` requires module `to` by: its name when the two share a folder, else its
// path, which daslang takes only with `./` or `../` in front and `.das` behind
def private require_text(plan : LayoutPlan; from, to : int) : string {
    if (plan.modules[from].dir == plan.modules[to].dir) {
        return plan.modules[to].name
    }
    let rel = relative_to(plan.modules[from].dir, plan.modules[to].dir, "{plan.modules[to].name}.das")
    return rel |> starts_with("../") ? rel : "./{rel}"
}

// the part of node `node`: the globals and functions its unit owns and the records and enums it
// defines
def private select_node(var em : Emitter; tu : CirTu; plan : LayoutPlan; owners : array<int>; node : int) {
    em.whole = false
    em.part_decls |> clear()
    em.part_types |> clear()
    let unit = plan.nodes[node].unit
    for (di, d in count(), tu.decls) {
        if ((d.k == "global" || d.k == "func") && unit >= 0 && owners[di] == unit) {
            em.part_decls |> insert(di)
        }
    }
    for (t, owner in keys(plan.type_node), values(plan.type_node)) {
        if (owner == node) {
            em.part_types |> insert(t)
        }
    }
}

// a cluster module: one fragment per member, each its types, globals and functions, and the
// module's own file with the dialect's `[init]`, one `include` per fragment in include order, the
// layout check of every member's records, the module-init stores and the `main` wrapper
def private emit_cluster(var em : Emitter; tu : CirTu; plan : LayoutPlan; owners : array<int>; mi : int; var files : array<ModuleFile>) {
    assume mod = plan.modules[mi]
    for (node in mod.members) {
        select_node(em, tu, plan, owners, node)
        order_globals(em, tu)
    }
    var records : array<int>
    var includes : array<string>
    includes |> reserve(length(mod.members))
    files |> reserve(length(files) + length(mod.members) + 1)
    for (node in mod.members) {
        select_node(em, tu, plan, owners, node)
        emit_type_decls(em, tu, records)
        emit_globals(em, tu)
        emit_functions(em, tu)
        let name = "{plan.nodes[node].stem}.das.inc"
        let text = GENERATED_BANNER + "\n" + laid_out(join(em.out, ""))
        files |> push(ModuleFile(path = in_dir(plan.nodes[node].dir, name), text = text))
        includes |> push("include {relative_to(mod.dir, plan.nodes[node].dir, name)}")
        em.out |> clear()
        break if (!empty(em.error))
    }
    let lets = constant_lets(em) + macro_def_text(em)
    if (!empty(lets)) {
        em.out |> push(lets)
    }
    for (inc in includes) {
        line(em, inc)
    }
    line(em, "")
    if (!empty(records) && empty(em.error)) {
        emit_layout_check(em, tu, records)
    }
    emit_init_globals(em)
    emit_late_binding(em, tu)
    emit_dialect(em, tu, 0)
    emit_main_wrapper(em, tu)
}

// the das signature a late-bound function's slot and wrapper share, `fn` its function type: each
// parameter `a<N>`, `var` where a parameter of its type is, a variadic one's list last
def private late_params(var em : Emitter; tu : CirTu; fn : int; loc : CirLoc; variadic_tail : string) : array<string> {
    var params : array<string>
    params |> reserve(length(tu.types[fn].params) + 1)
    for (idx, p in count(), tu.types[fn].params) {
        params |> push("{is_var_parameter(tu, p) ? "var " : ""}a{idx} : {das_type(em, tu, p, loc)}")
    }
    if (tu.types[fn].variadic) {
        em.requires |> insert("c_runtime/variadic")
        params |> push(variadic_tail)
    }
    return <- params
}

// the definition of late-bound function `name`, which a cut leaves in one module of the program
def private late_decl(tu : CirTu; name : string) : CirDecl const? {
    for (d in tu.decls) {
        if (d.k == "func" && d.body != null && d.name == name) {
            return d
        }
    }
    return null
}

// the link module of a cut program: per late-bound function its slot and a wrapper of its name,
// which fails closed while no module has bound the slot
def private emit_link_module(var em : Emitter; tu : CirTu; plan : LayoutPlan) {
    var inscope names <- [for (name in keys(plan.slots)); name]
    sort(names)
    line(em, "// the late-bound functions of the program's cut cycles: each module defining one binds its slot at [init]")
    line(em, "")
    for (name in names) {
        let d = late_decl(tu, name)
        let slot = plan.slots?[name] ?? ""
        let fn = d.t
        let ret = das_type(em, tu, tu.types[fn].ret, d.loc)
        var inscope slot_params <- late_params(em, tu, fn, d.loc, "a{length(tu.types[fn].params)} : CVaList")
        var inscope wrapper_params <- late_params(em, tu, fn, d.loc, "va : va_args")
        var inscope args <- [for (idx in range(length(tu.types[fn].params))); "a{idx}"]
        if (tu.types[fn].variadic) {
            args |> push("va")
        }
        line(em, "var {slot} : function<({join(slot_params, "; ")}) : {ret}>")
        line(em, "")
        if (tu.types[fn].variadic) {
            line(em, "[variadic]")
        }
        open_block(em, "def {function_name(em, name)}({join(wrapper_params, PARAMETER_SEPARATOR)})" + (ret == "void" ? "" : " : {ret}"))
        open_block(em, "if ({slot} == null)")
        line(em, "panic(\"{name} is late-bound and no module has bound it\")")
        close_block(em)
        let call = "invoke({slot}{empty(args) ? "" : ", "}{join(args, ", ")})"
        line(em, ret == "void" ? call : "return {call}")
        close_block(em)
        line(em, "")
    }
}

// the defining module's binding of its late-bound functions to their slots at [init]: a variadic
// one through a private function taking its list, which calls it with the list as it is
def private emit_late_binding(var em : Emitter; tu : CirTu) {
    if (empty(em.late_defs)) {
        return
    }
    var inscope names <- [for (name in keys(em.late_defs)); name]
    sort(names)
    var stores : array<string>
    for (name in names) {
        let d = late_decl(tu, name)
        let slot = em.late_defs?[name] ?? ""
        let own = "{em.late_quals?[name] ?? ""}{function_name(em, name)}"
        if (!tu.types[d.t].variadic) {
            stores |> push("{slot} = @@{own}")
            continue
        }
        let fn = d.t
        let ret = das_type(em, tu, tu.types[fn].ret, d.loc)
        var inscope params <- late_params(em, tu, fn, d.loc, "a{length(tu.types[fn].params)} : CVaList")
        let args = join([for (idx in range(length(tu.types[fn].params) + 1)); "a{idx}"], ", ")
        let binder = "{slot}_bind"
        open_block(em, "def private {binder}({join(params, "; ")})" + (ret == "void" ? "" : " : {ret}"))
        line(em, ret == "void" ? "{own}`va({args})" : "return {own}`va({args})")
        close_block(em)
        line(em, "")
        stores |> push("{slot} = @@{binder}")
    }
    line(em, "[init]")
    open_block(em, "def private {LATE_BIND}")
    for (store in stores) {
        line(em, store)
    }
    close_block(em)
    line(em, "")
}

//! The program `tu` in the source layout `plan` (`converter/layout.das`), `owners` the unit of each
//! of its declarations (`link_tus`): one module per module of the plan, a single node's as
//! `emit_tu` spells a unit, a cluster's as `emit_cluster` does, each requiring the modules of the
//! plan it uses. `tu` is renamed in place as `emit_tu` renames it.
[arch(at="ARCHITECTURE_LAYOUT.md#emission")]
def emit_program(var tu : CirTu; side : Sidecar; plan : LayoutPlan; owners : array<int>) : ProgramEmission {
    var res : ProgramEmission
    var first : Emitter
    prepare_program(first, tu, side)
    if (!empty(first.error)) {
        res.error = first.error
        return <- res
    }
    var prog <- first.prog
    for (mi, mod in count(), plan.modules) {
        var em = Emitter(prog <- prog, layout_file = mod.name + LAYOUT_FILE_SUFFIX)
        for (name, definer in keys(plan.late), values(plan.late)) {
            let dm = plan.node_module[definer]
            // the defining module names its own `__::`, which holds however the module is compiled
            if (mi == dm) {
                em.late_quals[name] = "__::"
            } elif (has_value(mod.requires, dm) && has_value(mod.requires, plan.link)) {
                em.late_quals[name] = "{plan.modules[dm].name}::"
            }
            if (mi == dm) {
                em.late_defs[name] = plan.slots?[name] ?? ""
            }
        }
        if (mi == plan.link) {
            emit_link_module(em, tu, plan)
        } elif (mod.cluster) {
            emit_cluster(em, tu, plan, owners, mi, res.files)
        } else {
            select_node(em, tu, plan, owners, mod.members[0])
            emit_module_body(em, tu)
        }
        for (r in mod.requires) {
            em.requires |> insert(require_text(plan, mi, r))
        }
        assemble_module(em)
        let path = in_dir(mod.dir, "{mod.name}.das")
        res.files |> push(ModuleFile(path = path, text = em.text))
        if (!empty(em.layout_text)) {
            res.files |> push(ModuleFile(path = in_dir(mod.dir, em.layout_file), text = GENERATED_BANNER + "\n" + em.layout_text))
        }
        if (mi == plan.entry) {
            res.entry = path
        }
        res.c_functions += em.c_functions
        res.function_count += em.function_count
        for (reason, n in keys(em.fold_counts), values(em.fold_counts)) {
            res.fold_counts[reason] += n
        }
        // the program state went to the module's emitter and comes back from it
        delete prog
        prog <- em.prog
        if (!empty(em.error)) {
            res.error = em.error
            break
        }
    }
    return <- res
}
