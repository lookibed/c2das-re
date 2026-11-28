options gen2
options stack = 262144
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../c_ir.das

//! The rest of Dumper A's subset in `frontend/` (`ARCHITECTURE_SUBSET.md`): the `__builtin_*`
//! functions with clang's prototypes, `va_list` and `va_arg`, glibc's `jmp_buf`, the asm barrier,
//! the `mode` attribute, GNU case ranges, a library function's K&R composite, the attribute lists,
//! `__func__`, and every refusal with its place.

// a table entry as C spells it, short: a record its kind and name, a function `fn`
def private spelled(types : array<CirType>; t : int) : string {
    return "?" if (t < 0)
    assume ty = types[t]
    if (ty.k == "int" || ty.k == "float") {
        return ty.spell
    } elif (ty.k == "ptr") {
        return "{spelled(types, ty.to)}*"
    } elif (ty.k == "array") {
        return "{spelled(types, ty.elem)}[{ty.count}]"
    } elif (ty.k == "struct" || ty.k == "union") {
        return "{ty.k} {ty.name}"
    } elif (ty.k == "func") {
        let params = join([for (q in ty.params); spelled(types, q)], ",")
        return "fn({params}{ty.variadic ? ",..." : ""})"
    }
    return ty.k
}

// expression `x` as one line: each node its kind and type, a cast its kind
def private shown(types : array<CirType>; x : CirExpr?) : string {
    return "-" if (x == null)
    let t = spelled(types, x.t)
    if (x.e == "int_lit" || x.e == "float_lit") {
        return x.v
    } elif (x.e == "str_lit") {
        return "str<{t}>"
    } elif (x.e == "ref") {
        return x.name
    } elif (x.e == "cast") {
        return "{x.cast_kind}<{t}>({shown(types, x.a)})"
    } elif (x.e == "call") {
        return "call<{t}>({shown(types, x.fn)}; " + join([for (a in x.args); shown(types, a)], ", ") + ")"
    } elif (x.e == "va_arg") {
        return "va_arg<{t}:{spelled(types, x.arg_t)}>({shown(types, x.list)})"
    } elif (x.e == "un") {
        return "{x.op}<{t}>({shown(types, x.a)})"
    }
    return "{x.e}{x.op}<{t}>({shown(types, x.a)}, {shown(types, x.b)})"
}

// the statements of `st` and under it as lines into `out`
def private statements(types : array<CirType>; st : CirStmt?; var out : array<string>) {
    return if (st == null)
    if (st.s == "decl") {
        out |> push("{st.name}:{spelled(types, st.t)}={shown(types, st.init)}")
    } elif (st.s == "expr" || st.s == "return") {
        out |> push("{st.s} {shown(types, st.e)}")
    } elif (st.s == "case") {
        out |> push(st.is_range ? "case {st.v} ... {st.hi}{st.is_char ? "c" : ""}" : "case {st.v}")
    } elif (st.s == "null" || st.s == "default") {
        out |> push(st.s)
    }
    for (kid in st.body) {
        statements(types, kid, out)
    }
    statements(types, st.body_s, out)
    statements(types, st.then_s, out)
}

// the C-IR of unit `text` (named `t.c`) joined by ` ; `: each global's `name:type`, each function's
// `name:type(params)` and statements; `error: ` and the builder's error
def private subset_of(text : string; msvc : bool = false) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", msvc)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), "")
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        for (d in r.tu.decls) {
            if (d.k == "global") {
                out |> push("{d.name}:{spelled(r.tu.types, d.t)}" + (d.init != null ? "={shown(r.tu.types, d.init)}" : ""))
            } elif (d.k == "func") {
                let params = join([for (q in d.params); "{q.name}:{spelled(r.tu.types, q.t)}"], ",")
                out |> push("{d.name}:{spelled(r.tu.types, d.t)}({params})")
                statements(r.tu.types, d.body, out)
            } else {
                out |> push("{d.k} {d.name}")
            }
        }
    } else {
        out |> push("error: {r.err}")
    }
    let listed = join(out, " ; ")
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return listed
}

[test(description = "a __builtin_* call: the callee clang's <builtin fn type> decayed to its prototype, each argument converted to the pinned clang's parameter type, the dialect's size_t, a variadic one's extra arguments promoted")]
def test_builtins(t : T?) {
    t |> equal(subset_of("char b[4]; short s; void f(void) \{ __builtin_memcpy(b, b, s); __builtin_printf(\"%d\", s); \}"),
               "b:char[4] ; s:short ; f:fn()() ; expr call<void*>(FunctionToPointerDecay<fn(void*,void*,unsigned long)*>(__builtin_memcpy); BitCast<void*>(ArrayToPointerDecay<char*>(b)), BitCast<void*>(ArrayToPointerDecay<char*>(b)), IntegralCast<unsigned long>(LValueToRValue<short>(s))) ; expr call<int>(FunctionToPointerDecay<fn(char*,...)*>(__builtin_printf); NoOp<char*>(ArrayToPointerDecay<char*>(str<char[3]>)), IntegralCast<int>(LValueToRValue<short>(s)))")
    t |> equal(subset_of("long long v; unsigned long long f(void) \{ return __builtin_bswap64(v) + __builtin_strlen(\"a\"); \}", true),
               "v:long long ; f:fn()() ; return binadd<unsigned long long>(call<unsigned long long>(FunctionToPointerDecay<fn(unsigned long long)*>(__builtin_bswap64); IntegralCast<unsigned long long>(LValueToRValue<long long>(v))), call<unsigned long long>(FunctionToPointerDecay<fn(char*)*>(__builtin_strlen); NoOp<char*>(ArrayToPointerDecay<char*>(str<char[2]>))))")
}

[test(description = "the builtins clang checks itself (__builtin_signbit, the overflow builtins) take their arguments as values with no other conversion; __builtin_choose_expr is the operand its folded condition chooses; a builtin the table lacks stays refused")]
def test_builtin_forms(t : T?) {
    t |> equal(subset_of("float x; unsigned char c; int f(void) \{ return __builtin_signbit(x) + __builtin_mul_overflow(c, 2, &c); \}"),
               "x:float ; c:unsigned char ; f:fn()() ; return binadd<int>(call<int>(FunctionToPointerDecay<fn()*>(__builtin_signbit); LValueToRValue<float>(x)), IntegralCast<int>(call<_Bool>(FunctionToPointerDecay<fn()*>(__builtin_mul_overflow); LValueToRValue<unsigned char>(c), 2, addr<unsigned char*>(c))))")
    t |> equal(subset_of("int f(void) \{ return __builtin_choose_expr(0, 1.0, 2); \}"), "f:fn()() ; return 2")
    t |> equal(subset_of("int f(void) \{ return __builtin_choose_expr(f(), 1, 2); \}"), "error: t.c:1:22: a `__builtin_choose_expr` whose condition the builder cannot fold is not typed yet")
    t |> equal(subset_of("int f(void) \{ return __builtin_ia32_pause(); \}"), "error: t.c:1:22: the identifier '__builtin_ia32_pause', which names no variable or function the builder knows, is not typed yet")
}

let VA = "typedef __builtin_va_list va_list; "

// every record of the table of unit `text` in table order: its index, name, size and fields
def private records_of(text : string; msvc : bool = false) : string {
    var p : CParser
    c_parser_open_text(p, text, "t.c", msvc)
    let u = c_unit(p)
    return "parse error: {p.err}" if (p.failed)
    var r = new CIr
    c_ir_open(*r, msvc ? target_llp64_msvc() : target_lp64_linux(), "")
    var out : array<string>
    if (c_ir_unit(*r, p, u)) {
        for (ty, idx in r.tu.types, count()) {
            if (ty.k == "struct") {
                let fields = join([for (fl in ty.fields); "{fl.name}:{fl.t}:{spelled(r.tu.types, fl.t)}"], ",")
                out |> push("{idx} {ty.name} {ty.size}/{ty.align} \{{fields}\}")
            }
        }
    } else {
        out |> push("error: {r.err}")
    }
    let listed = join(out, " ; ")
    delete_tu(r.tu)
    unsafe {
        delete r
    }
    return listed
}

[test(description = "the opaque records enter the table after their field's type, as Dumper A builds them: va_list's unsigned long long[3] under linux and [1] under msvc, jmp_buf's int")]
def test_opaque_records(t : T?) {
    t |> equal(records_of(VA + "va_list a;"), "2 va_list 24/8 \{words:1:unsigned long long[3]\}")
    t |> equal(records_of(VA + "va_list a;", true), "2 va_list 8/8 \{words:1:unsigned long long[1]\}")
    t |> equal(records_of("struct __jmp_buf_tag \{ long a; \}; typedef struct __jmp_buf_tag jmp_buf[1]; jmp_buf e;"), "1 jmp_buf 4/4 \{val:0:int\}")
}

[test(description = "va_list under linux: the opaque record of words[3], a variable of it decayed where it is used, a parameter a pointer to it, va_arg the spec's node, the va builtins taking the decayed list and va_start's parameter as written")]
def test_va_list_linux(t : T?) {
    t |> equal(subset_of(VA + "int f(int n, ...) \{ va_list ap; __builtin_va_start(ap, n); int x = __builtin_va_arg(ap, int); __builtin_va_end(ap); return x; \} int g(va_list q) \{ return __builtin_va_arg(q, int); \}"),
               "typedefdecl va_list ; f:fn(int,...)(n:int) ; ap:struct va_list=- ; expr call<void>(FunctionToPointerDecay<fn(struct va_list*,...)*>(__builtin_va_start); ArrayToPointerDecay<struct va_list*>(ap), n) ; x:int=va_arg<int:int>(ArrayToPointerDecay<struct va_list*>(ap)) ; expr call<void>(FunctionToPointerDecay<fn(struct va_list*)*>(__builtin_va_end); ArrayToPointerDecay<struct va_list*>(ap)) ; return LValueToRValue<int>(x) ; g:fn(struct va_list*)(q:struct va_list*) ; return va_arg<int:int>(LValueToRValue<struct va_list*>(q))")
}

[test(description = "va_list under msvc: the opaque record of words[1], held whole: the va builtins and va_arg take the list as written, a call reads it")]
def test_va_list_msvc(t : T?) {
    t |> equal(subset_of(VA + "int g(va_list q); int f(int n, ...) \{ va_list ap; __builtin_va_start(ap, n); __builtin_va_copy(ap, ap); return g(ap) + __builtin_va_arg(ap, int); \}", true),
               "typedefdecl va_list ; g:fn(struct va_list)(q:struct va_list) ; f:fn(int,...)(n:int) ; ap:struct va_list=- ; expr call<void>(FunctionToPointerDecay<fn(struct va_list,...)*>(__builtin_va_start); ap, n) ; expr call<void>(FunctionToPointerDecay<fn(struct va_list,struct va_list)*>(__builtin_va_copy); ap, ap) ; return binadd<int>(call<int>(FunctionToPointerDecay<fn(struct va_list)*>(g); LValueToRValue<struct va_list>(ap)), va_arg<int:int>(ap))")
    t |> equal(subset_of(VA + "int f(int n) \{ return __builtin_va_arg(n, int); \}"), "error: t.c:1:58: a `va_arg` of other than a `va_list` is not typed yet")
    t |> equal(subset_of(VA + "va_list b(void); void f(void) \{ __builtin_va_end(b()); \}", true),
               "error: t.c:1:85: a `va_list` builtin's argument of other than a `va_list` object is not typed yet")
}

[test(description = "glibc's jmp_buf: struct __jmp_buf_tag is the opaque record of one int (4 bytes), a type holding it the record or, spelled with * or (*), a pointer to it, as Dumper A reads the spellings; its definition here adds no anchor")]
def test_jmp_buf(t : T?) {
    let unit = "struct __jmp_buf_tag \{ long long a[8]; \}; typedef struct __jmp_buf_tag jmp_buf[1]; int _setjmp(jmp_buf); "
    t |> equal(subset_of(unit + "int h(int (*)(jmp_buf)); jmp_buf e;"), "typedefdecl jmp_buf ; _setjmp:struct jmp_buf(:struct jmp_buf*) ; h:struct jmp_buf*(:struct jmp_buf*) ; e:struct jmp_buf")
    t |> equal(subset_of(unit + "jmp_buf e; int (*fp)(jmp_buf) = _setjmp; int f(void) \{ return _setjmp(e) + sizeof(jmp_buf); \}"),
               "typedefdecl jmp_buf ; _setjmp:struct jmp_buf(:struct jmp_buf*) ; e:struct jmp_buf ; fp:struct jmp_buf*=FunctionToPointerDecay<struct jmp_buf*>(_setjmp) ; f:fn()() ; return IntegralCast<int>(binadd<unsigned long>(IntegralCast<unsigned long>(call<int>(FunctionToPointerDecay<struct jmp_buf*>(_setjmp); ArrayToPointerDecay<struct jmp_buf*>(e))), sizeof_v<unsigned long>(-, -)))")
}

[test(description = "an asm barrier - an empty template, no operand, at most clobbers - is the empty statement; template text and operands refused")]
def test_asm(t : T?) {
    t |> equal(subset_of("void f(void) \{ asm(\"\"); __asm__ __volatile__(\"\" \"\" : : : \"memory\"); \}"), "f:fn()() ; null ; null")
    t |> equal(subset_of("void f(void) \{ asm(\"nop\"); \}"), "error: t.c:1:16: inline asm with template text is not typed yet, which is machine code")
    t |> equal(subset_of("void f(int x) \{ asm(\"\" : \"=r\"(x)); \}"), "error: t.c:1:17: inline asm with operands is not typed yet, which bind registers")
}

[test(description = "the mode attribute: an integer or an enum becomes the integer of the mode's width and its own sign, QI and byte a signed or unsigned char, HI a short, SI an int, DI and word the dialect's 64-bit type; a mode after a declarator other than a name, another mode or another type refused")]
def test_mode(t : T?) {
    t |> equal(subset_of("typedef unsigned u8 __attribute__((mode(QI))); u8 a; int __attribute__((__mode__(__HI__))) b; int c __attribute__((mode(byte))); unsigned d __attribute__((mode(SI))); int e __attribute__((mode(word)));"),
               "typedefdecl u8 ; a:unsigned char ; b:short ; c:signed char ; d:unsigned int ; e:long")
    t |> equal(subset_of("int e __attribute__((mode(DI))); typedef enum \{ X \} E; E __attribute__((mode(byte))) f;", true), "e:long long ; enumdef E ; typedefdecl E ; f:signed char")
    t |> equal(subset_of("typedef enum \{ X \} E; E __attribute__((mode(byte))) f;"), "enumdef E ; typedefdecl E ; f:unsigned char")
    t |> equal(subset_of("enum E \{ X \} __attribute__((mode(byte))) f;"), "error: t.c:1:29: the attribute 'mode', which changes a type, is not typed yet")
    t |> equal(subset_of("int *p __attribute__((mode(DI)));"), "error: t.c:1:23: the attribute 'mode', which changes a type, is not typed yet")
    t |> equal(subset_of("int x __attribute__((mode(TI)));"), "error: t.c:1:22: the attribute 'mode(TI)' on this type is not typed yet")
    t |> equal(subset_of("double x __attribute__((mode(DI)));"), "error: t.c:1:25: the attribute 'mode(DI)' on this type is not typed yet")
}

[test(description = "a GNU case range: both ends folded and held in the promoted controlling type, a character range marked, an empty range no marker")]
def test_case_range(t : T?) {
    t |> equal(subset_of("int f(int x) \{ switch (x) \{ case 1 ... 3: return 1; case 'a' ... 'c': case 9 ... 2: return 2; \} return 0; \}"),
               "f:fn(int)(x:int) ; case 1 ... 3 ; return 1 ; case 97 ... 99c ; return 2 ; return 0")
    t |> equal(subset_of("int f(unsigned long long x) \{ switch (x) \{ case 1 ... 9999999999999999999ULL: return 1; \} return 0; \}"),
               "f:fn(unsigned long long)(x:unsigned long long) ; case 1 ... -8446744073709551617 ; return 1 ; return 0")
    t |> equal(subset_of("int f(unsigned x) \{ switch (x) \{ case -1 ... 2: return 1; \} return 0; \}"), "f:fn(unsigned int)(x:unsigned int) ; return 1 ; return 0")
}

[test(description = "a declaration with no prototype lists the composite type's parameters, unnamed: a library function clang knows takes the library's prototype, a redeclaration an earlier prototype's")]
def test_library_composite(t : T?) {
    t |> equal(subset_of("extern void exit(); void f(int i) \{ exit(i); \}"),
               "exit:fn(int)(:int) ; f:fn(int)(i:int) ; expr call<void>(FunctionToPointerDecay<fn(int)*>(exit); LValueToRValue<int>(i))")
    t |> equal(subset_of("int g(int, char *); int g();"), "g:fn(int,char*)(:int,:char*) ; g:fn(int,char*)(:int,:char*)")
    t |> equal(subset_of("static int strcmp() \{ return -1; \}"), "t__strcmp:fn()() ; return neg<int>(1)")
}

[test(description = "the attributes Dumper A drops or reads are taken; any other refused at its place, weak on a name the unit never defines too")]
def test_attributes(t : T?) {
    t |> equal(subset_of("__attribute__((weak)) int w(void); int w(void) \{ return 0; \} __attribute__((noinline, noclone, format(printf, 1, 2))) int lg(const char *f, ...);"),
               "w:fn()() ; w:fn()() ; return 0 ; lg:fn(char*,...)(f:char*)")
    t |> equal(subset_of("extern void g(void) __attribute__((stdcall)); void __attribute__((__cdecl__)) g(void) \{\}"), "g:fn()() ; g:fn()()")
    t |> equal(subset_of("__attribute__((constructor)) static void c(void) \{\}"), "error: t.c:1:16: the attribute 'constructor' is not typed yet, which Dumper A neither drops nor reads")
    t |> equal(subset_of("void f(void) \{ int x __attribute__((__cleanup__(f))); \}"), "error: t.c:1:37: the attribute 'cleanup' is not typed yet, which Dumper A neither drops nor reads")
    t |> equal(subset_of("extern int v __attribute__((weak));"), "error: t.c:1:12: `weak` on 'v', which the unit never defines, is not typed yet")
}

[test(description = "__func__ and __FUNCTION__ are the string literal of the function's name typed const char[N]; __PRETTY_FUNCTION__ and a name outside a function refused")]
def test_function_name(t : T?) {
    t |> equal(subset_of("const char *f(void) \{ return __FUNCTION__; \}"), "f:fn()() ; return ArrayToPointerDecay<char*>(str<char[2]>)")
    t |> equal(subset_of("const char *f(void) \{ return __PRETTY_FUNCTION__; \}"), "error: t.c:1:30: '__PRETTY_FUNCTION__' is not typed yet (its text is clang's spelling of the signature)")
    t |> equal(subset_of("const char *s = __func__;"), "error: t.c:1:17: '__func__' is not typed yet outside a function")
}
