options gen2
require dastest/testing_boost public
require cbind
require daslib/fio

let c_shapes = ("struct P \{ int x; short y; \};\n" +
    "struct M \{ char a; long long b; double c; \};\n" +
    "struct I \{ char a; long long b; \};\n" +
    "struct O \{ char c; struct I inner; short d; void (*cb)(int); char e; \};\n" +
    "struct A \{ int id; int vals[4]; struct I inner; \};\n" +
    "struct BC \{ _Bool b; char c; \};\n" +
    "struct T2 \{ char a; short b; int c; char d; \};\n" +
    "struct BF \{ unsigned a : 3; int b : 5; short e; \};\n" +
    "struct HoldBF \{ struct BF bf; short y; \};\n" +
    "struct CharBF \{ char c; struct BF bf; \};\n" +
    "struct AC \{ unsigned a : 3; char c; \};\n" +
    "struct OuterAC \{ char q; struct AC a; \};\n")

let UNNAMED_SHAPES = "struct Pad20 \{ char a; int : 20; \};\nstruct Zero0 \{ char a; int : 0; char b; \};\nstruct ZeroBits \{ char c; char x : 3; long long : 0; char d; \};\nstruct ZeroShort \{ char x : 3; short : 0; \};\nstruct ZeroTail \{ char x : 3; long long : 0; \};\nstruct ZeroPlain \{ char x : 3; char y; long long : 0; char d; \};\nstruct ZeroTwice \{ char x : 3; int : 0; long long : 0; char d; \};\nstruct ZeroNine \{ char c; unsigned a : 9; long long : 0; char d; \};\n"

struct P {
    x : int
    y : int16
}

struct M {
    a : int8
    b : int64
    c : double
}

struct I {
    a : int8
    b : int64
}

struct O {
    c : int8
    inner : I
    d : int16
    cb : function<(x : int) : void>
    e : int8
}

struct A {
    id : int
    vals : int[4]
    inner : I
}

struct BC {
    b : bool
    c : int8
}

struct T2 {
    a : int8
    b : int16
    c : int
    d : int8
}

struct BFItanium {
    _bits0 : uint8
    e : int16
}

// Itanium mirrors whose padding fields complete clang's offsets and size where das's natural
// placement falls short; each aligns at or below clang's
struct HoldBFPadded {
    bf : BFItanium
    y : int16
    _pad0 : uint8[2]
}

// `HoldBF` with no padding field
struct HoldBFBare {
    bf : BFItanium
    y : int16
}

struct CharBFPadded {
    c : int8
    _pad0 : uint8[3]
    bf : BFItanium
}

struct ACPadded {
    _bits0 : uint8
    c : int8
    _pad0 : uint8[2]
}

struct OuterACPadded {
    q : int8
    _pad0 : uint8[3]
    a : ACPadded
}

struct BFMsvc {
    _bits0 : uint
    e : int16
}

struct ClangField {
    bit_offset : int64
    bit_width : int
}

struct ClangRecord {
    size : int64
    align : int64
    fields : table<string; ClangField>
}

var records : table<string; ClangRecord>

// the layout clang gives every struct of `source` into `into`, for `triple` (the host's when empty)
def collect_layouts(source, triple : string; var into : table<string; ClangRecord>) {
    let path = "{temp_directory_result() as value}/c2das_probe_layout.c"
    fwrite(path, source)
    var args <- ["-w"]
    if (!empty(triple)) {
        args |> push("-target")
        args |> push(triple)
    }
    var idx = clang_createIndex(0, 0)
    var unit = clang_parseTranslationUnit(idx, path, unsafe(addr(args[0])), length(args), null, 0u, 0u)
    var root = clang_getTranslationUnitCursor(unit)
    clang_visitChildren(root) $(var c, _parent) {
        if (clang_getCursorKind(c) == CXCursorKind.StructDecl) {
            var ct = clang_getCursorType(c)
            var rec = ClangRecord(size = clang_Type_getSizeOf(ct), align = clang_Type_getAlignOf(ct))
            clang_visitChildren(c) $(var fc, _fp) {
                if (clang_getCursorKind(fc) == CXCursorKind.FieldDecl) {
                    rec.fields[string(clang_getCursorSpelling(fc))] = ClangField(bit_offset = clang_Cursor_getOffsetOfField(fc), bit_width = clang_getFieldDeclBitWidth(fc))
                }
                return CXChildVisitResult.Continue
            }
            into[string(clang_getCursorSpelling(c))] <- rec
        }
        return CXChildVisitResult.Continue
    }
    clang_disposeTranslationUnit(unit)
    clang_disposeIndex(idx)
    remove(path)
}

def collect_clang_records(source : string) {
    collect_layouts(source, "", records)
}

// clang's size and alignment of struct `name` among `recs`
def check_size_align(t : T?; recs : table<string; ClangRecord>; name : string; size, align : int; what : string) {
    var found = false
    recs |> get(name) $(rec) {
        found = true
        t |> equal(int(rec.size), size, "{name} size under {what}")
        t |> equal(int(rec.align), align, "{name} align under {what}")
    }
    if (!found) {
        t |> failure("clang has no record {name} under {what}")
    }
}

// clang's size and offsets of struct `name` against a das mirror's, and its alignment: equal, or
// when `below` a mirror below clang's alignment, one that divides clang's
def check_record(t : T?; name : string; das_size, das_align : int; das_offsets : table<string; int>; below : bool = false) {
    var found = false
    records |> get(name) $(rec) {
        found = true
        t |> equal(int(rec.size), das_size, "{name} size")
        if (below) {
            t |> equal(das_align <= int(rec.align) && int(rec.align) % das_align == 0, true, "{name} align {das_align} against clang's {rec.align}")
        } else {
            t |> equal(int(rec.align), das_align, "{name} align")
        }
        for (fname, ofs in keys(das_offsets), values(das_offsets)) {
            var field_found = false
            rec.fields |> get(fname) $(cf) {
                field_found = true
                t |> equal(int(cf.bit_offset), ofs * 8, "{name}.{fname} offset")
            }
            if (!field_found) {
                t |> failure("clang has no field {name}.{fname}")
            }
        }
    }
    if (!found) {
        t |> failure("clang has no record {name}")
    }
}

def check_bits(t : T?; fname : string; bit_offset : int; bit_width : int) {
    var found = false
    records |> get("BF") $(rec) {
        rec.fields |> get(fname) $(cf) {
            found = true
            t |> equal(int(cf.bit_offset), bit_offset, "BF.{fname} bit offset")
            t |> equal(cf.bit_width, bit_width, "BF.{fname} bit width")
        }
    }
    if (!found) {
        t |> failure("clang has no field BF.{fname}")
    }
}

[test]
def test_layout(t : T?) {
    collect_clang_records(c_shapes)
    t |> run("clang parses the shape battery") @(t : T?) {
        t |> equal(length(records), 12)
    }
    t |> run("small fields pack tight and tail-pad to the largest alignment") @(t : T?) {
        check_record(t, "P", typeinfo sizeof(type<P>), typeinfo alignof(type<P>), {"x" => typeinfo offsetof < x > (type<P>), "y" => typeinfo offsetof < y > (type<P>)})
        check_record(t, "T2", typeinfo sizeof(type<T2>), typeinfo alignof(type<T2>), {"a" => typeinfo offsetof < a > (type<T2>), "b" => typeinfo offsetof < b > (type<T2>), "c" => typeinfo offsetof < c > (type<T2>), "d" => typeinfo offsetof < d > (type<T2>)})
        t |> equal(typeinfo sizeof(type<T2>), 12)
    }
    t |> run("int64 and double align to 8") @(t : T?) {
        check_record(t, "M", typeinfo sizeof(type<M>), typeinfo alignof(type<M>), {"a" => typeinfo offsetof < a > (type<M>), "b" => typeinfo offsetof < b > (type<M>), "c" => typeinfo offsetof < c > (type<M>)})
        t |> equal(typeinfo sizeof(type<M>), 24)
    }
    t |> run("nested struct alignment propagates and a function pointer field is 8 bytes") @(t : T?) {
        check_record(t, "I", typeinfo sizeof(type<I>), typeinfo alignof(type<I>), {"a" => typeinfo offsetof < a > (type<I>), "b" => typeinfo offsetof < b > (type<I>)})
        check_record(t, "O", typeinfo sizeof(type<O>), typeinfo alignof(type<O>), {"c" => typeinfo offsetof < c > (type<O>), "inner" => typeinfo offsetof < inner > (type<O>), "d" => typeinfo offsetof < d > (type<O>), "cb" => typeinfo offsetof < cb > (type<O>), "e" => typeinfo offsetof < e > (type<O>)})
        t |> equal(typeinfo sizeof(type<function<(x : int) : void>>), 8)
    }
    t |> run("fixed-array member keeps its stride; bool is one byte") @(t : T?) {
        check_record(t, "A", typeinfo sizeof(type<A>), typeinfo alignof(type<A>), {"id" => typeinfo offsetof < id > (type<A>), "vals" => typeinfo offsetof < vals > (type<A>), "inner" => typeinfo offsetof < inner > (type<A>)})
        check_record(t, "BC", typeinfo sizeof(type<BC>), typeinfo alignof(type<BC>), {"b" => typeinfo offsetof < b > (type<BC>), "c" => typeinfo offsetof < c > (type<BC>)})
        t |> equal(typeinfo sizeof(type<bool>), 1)
    }
    t |> run("array element stride includes the tail padding") @(t : T?) {
        t |> equal(typeinfo sizeof(type<O[3]>), 3 * typeinfo sizeof(type<O>))
        t |> equal(typeinfo sizeof(type<T2[3]>), 3 * typeinfo sizeof(type<T2>))
    }
    t |> run("multi-dim int[2][3] is 24 bytes with a 12-byte row stride") @(t : T?) {
        var m : int[2][3]
        t |> equal(typeinfo sizeof(m), 24)
        unsafe {
            t |> equal(int(intptr(addr(m[1])) - intptr(addr(m[0]))), 12)
        }
    }
    t |> run("bitfield bit offsets and widths come from clang; the unit width follows the target ABI") @(t : T?) {
        check_bits(t, "a", 0, 3)
        check_bits(t, "b", 3, 5)
        var e_bit_offset = -1
        records |> get("BF") $(rec) {
            rec.fields |> get("e") $(cf) {
                e_bit_offset = int(cf.bit_offset)
            }
        }
        if (e_bit_offset == 16) {
            records |> get("BF") $(rec) {
                t |> equal(int(rec.size), typeinfo sizeof(type<BFItanium>), "Itanium packs the unit to the bytes used")
                t |> equal(int(rec.align), 4, "the declared unsigned unit still aligns the struct")
                t |> equal(typeinfo alignof(type<BFItanium>), 2, "das has no align knob: the mirror aligns to its widest field")
            }
            t |> equal(typeinfo offsetof < e > (type<BFItanium>), 2)
        } else {
            t |> equal(e_bit_offset, 32, "MSVC allocates the whole unsigned unit")
            check_record(t, "BF", typeinfo sizeof(type<BFMsvc>), typeinfo alignof(type<BFMsvc>), {"e" => typeinfo offsetof < e > (type<BFMsvc>)})
        }
    }
}

[test]
def test_layout_padding(t : T?) {
    collect_clang_records(c_shapes)
    t |> run("padding fields complete clang's offsets and size where an underaligned record or a narrow unit leaves das short; the stride and a nested offset follow") @(t : T?) {
        var itanium = false
        records |> get("BF") $(rec) {
            itanium = int(rec.size) == 4
        }
        if (!itanium) {
            t |> skip("the shapes pad under the Itanium ABI only")
            return
        }
        check_record(t, "HoldBF", typeinfo sizeof(type<HoldBFPadded>), typeinfo alignof(type<HoldBFPadded>), {"bf" => typeinfo offsetof < bf > (type<HoldBFPadded>), "y" => typeinfo offsetof < y > (type<HoldBFPadded>)}, true)
        check_record(t, "CharBF", typeinfo sizeof(type<CharBFPadded>), typeinfo alignof(type<CharBFPadded>), {"c" => typeinfo offsetof < c > (type<CharBFPadded>), "bf" => typeinfo offsetof < bf > (type<CharBFPadded>)}, true)
        check_record(t, "AC", typeinfo sizeof(type<ACPadded>), typeinfo alignof(type<ACPadded>), {"c" => typeinfo offsetof < c > (type<ACPadded>)}, true)
        check_record(t, "OuterAC", typeinfo sizeof(type<OuterACPadded>), typeinfo alignof(type<OuterACPadded>), {"q" => typeinfo offsetof < q > (type<OuterACPadded>), "a" => typeinfo offsetof < a > (type<OuterACPadded>)}, true)
        t |> equal(typeinfo sizeof(type<HoldBFPadded[3]>), 24)
        t |> equal(typeinfo alignof(type<ACPadded>), 1)
    }
    t |> run("without its padding field das ends HoldBF at size 6, its own alignment, short of clang's 8") @(t : T?) {
        t |> equal(typeinfo sizeof(type<HoldBFBare>), 6)
        records |> get("HoldBF") $(rec) {
            t |> equal(int(rec.size), 8)
        }
    }
    t |> run("under msvc a nonzero-width unnamed bitfield, and a zero-width one directly after a bitfield of nonzero width, align a record by their declared type; under the Itanium ABI none does") @(t : T?) {
        var linux, msvc : table<string; ClangRecord>
        collect_layouts(UNNAMED_SHAPES, "x86_64-unknown-linux-gnu", linux)
        collect_layouts(UNNAMED_SHAPES, "x86_64-pc-windows-msvc", msvc)
        check_size_align(t, linux, "Pad20", 4, 1, "linux")
        check_size_align(t, msvc, "Pad20", 8, 4, "msvc")
        check_size_align(t, linux, "Zero0", 5, 1, "linux")
        check_size_align(t, msvc, "Zero0", 2, 1, "msvc")
        check_size_align(t, linux, "ZeroBits", 9, 1, "linux")
        check_size_align(t, msvc, "ZeroBits", 16, 8, "msvc")
        check_size_align(t, linux, "ZeroShort", 2, 1, "linux")
        check_size_align(t, msvc, "ZeroShort", 2, 2, "msvc")
        check_size_align(t, linux, "ZeroTail", 8, 1, "linux")
        check_size_align(t, msvc, "ZeroTail", 8, 8, "msvc")
        check_size_align(t, linux, "ZeroPlain", 9, 1, "linux")
        check_size_align(t, msvc, "ZeroPlain", 3, 1, "msvc")
        check_size_align(t, linux, "ZeroTwice", 9, 1, "linux")
        check_size_align(t, msvc, "ZeroTwice", 8, 4, "msvc")
        check_size_align(t, linux, "ZeroNine", 12, 4, "linux")
        check_size_align(t, msvc, "ZeroNine", 16, 8, "msvc")
    }
}
