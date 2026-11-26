options gen2
require dastest/testing_boost public
require strings
require _probe_macros
require _daslang_child
require daslib/fio

//! The `[c_union]` mechanism by hand: one storage field, one ref-returning `operator .` per
//! member over a `var` union and one value-returning over a const one, and what a structure
//! annotation's `apply` knows about the member types before inference.

struct Point {
    x, y : int
}

struct Value {
    _storage : uint64
}

def operator . n(var s : Value) : double& {
    unsafe {
        return *addr<double?>(s._storage)
    }
}

def operator . i(var s : Value) : int64& {
    unsafe {
        return *addr<int64?>(s._storage)
    }
}

def operator . pt(var s : Value) : Point& {
    unsafe {
        return *addr<Point?>(s._storage)
    }
}

// the storage the annotation makes: an array of the unsigned type of the union's alignment
struct Mix {
    _storage : uint[3]
}

def operator . i(var s : Mix) : int& {
    unsafe {
        return *addr<int?>(s._storage)
    }
}

def operator . i(s : Mix) : int {
    unsafe {
        return *addr<int?>(s._storage)
    }
}

def operator . bytes(var s : Mix) : uint8[12]& {
    unsafe {
        return *addr<uint8[12]?>(s._storage)
    }
}

def operator . bytes(s : Mix) : uint8[12] {
    unsafe {
        return *addr<uint8[12]?>(s._storage)
    }
}

def read_let(m : Mix) : int => m.i + int(m.bytes[0])

// a union with a bitfield member, `union { signed f0 : 8; unsigned f1; }`: the plain member
// through the ref operators, the bitfield through a property pair over `_storage[0]`, the
// storage element read as the arithmetic word
struct UBits {
    _storage : uint[1]
}

def operator . f1(var s : UBits) : uint& {
    unsafe {
        return *addr<uint?>(s._storage)
    }
}

def operator . f1(s : UBits) : uint {
    unsafe {
        return *addr<uint?>(s._storage)
    }
}

def operator . f0(s : UBits) : int => int(s._storage[0] << 24u) >> 24

def operator . f0 :=(var s : UBits; v : int) {
    s._storage[0] = (s._storage[0] & 0xffffff00u) | (uint(v) & 0xffu)
}

def read_bits_let(u : UBits) : int => u.f0

struct HoldsUBits {
    k : int
    u : UBits
}

let UNION_PROPERTY = "options gen2\nstruct U \{\n    _storage : uint[1]\n\}\ndef operator . f0(s : U) : int => int(s._storage[0] << 24u) >> 24\ndef operator . f0 :=(var s : U; v : int) \{\n    s._storage[0] = (s._storage[0] & 0xffffff00u) | (uint(v) & 0xffu)\n\}\n[export]\ndef main \{\n    var u : U\n    var p = unsafe(addr(u.f0))\n    p = null\n\}\n"

let N = 3

enum Count {
    Three = 3
}

[probe_apply_types, probe_count_annotations]
struct Seen {
    pt : Point
    later : Later
    p : Later?
    n : double
    arr : int[3]
    by_const : int[N]
    by_enum : int[int(Count.Three)]
}

// a structure annotation whose `patch` reports itself as an error, so a compile shows whether
// it ran
let PATCH_MODULE = "options gen2\nmodule probe_patch_mod public\nrequire daslib/ast\nrequire daslib/ast_boost\n[structure_macro(name = \"loud_patch\")]\nclass LoudPatch : AstStructureAnnotation \{\n    def override patch(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string; var astChanged : bool&) : bool \{\n        errors := \"PATCH RAN\"\n        return false\n    \}\n\}\n"

def patch_source(body : string) : string => "options gen2\nrequire probe_patch_mod\n[loud_patch]\nstruct P \{\n    x : int\n\}\n[export]\ndef main \{\n{body}\}\n"

struct Later {
    x : int
}

let VAR_ONLY = "options gen2\nstruct U \{\n    _storage : uint\n\}\ndef operator . i(var s : U) : int& \{\n    unsafe \{\n        return *addr<int?>(s._storage)\n    \}\n\}\ndef read(u : U) : int => u.i\n[export]\ndef main \{\n\}\n"

[test]
def test_unions(t : T?) {
    t |> run("members alias one storage: writing a double reads back as its bits") @(t : T?) {
        var v : Value
        v.n = 3.5lf
        t |> equal(v.i, int64(0x400C000000000000ul))
        t |> equal(typeinfo sizeof(type<Value>), 8)
        t |> equal(typeinfo alignof(type<Value>), 8)
    }
    t |> run("one ref-returning operator covers read, write, compound, nested field and addr-of") @(t : T?) {
        var v : Value
        v.i = 0l
        v.pt.x = 7
        v.pt.y = 9
        t |> equal(v.pt.x, 7)
        t |> equal(v.i, int64(0x0000000900000007ul))
        v.pt.x += 2
        t |> equal(v.pt.x, 9)
        var pp = unsafe(addr(v.pt))
        pp.y = 100
        t |> equal(v.pt.y, 100)
    }
    t |> run("an array storage reinterprets as any member, the array member included") @(t : T?) {
        var m : Mix
        m.i = 258
        t |> equal(int(m.bytes[0]), 2)
        m.bytes[0] = 9u8
        t |> equal(m.i, 265)
        t |> equal(typeinfo sizeof(type<Mix>), 12)
        t |> equal(typeinfo alignof(type<Mix>), 4)
    }
    t |> run("a var base takes the ref operator, a const base the value one, without ambiguity") @(t : T?) {
        var m : Mix
        m.i = 7
        t |> equal(read_let(m), 14)
        let c = m
        t |> equal(c.i, 7)
        let cp : Mix const? = unsafe(addr(m))
        t |> equal(cp.i, 7)
    }
    t |> run("a const base finds no ref operator over a var parameter") @(t : T?) {
        let r = daslang_child("union_var_only", VAR_ONLY, true)
        t |> equal(r.rc != 0, true, r.out)
        t |> equal(r.out |> find("field 'i' not found in U const") >= 0, true, r.out)
    }
    t |> run("++ and -- apply to a ref-returning operator, unlike a property pair") @(t : T?) {
        var m : Mix
        m.i = 5
        m.i++
        ++m.i
        m.i--
        t |> equal(m.i, 6)
        var p = unsafe(addr(m))
        p.i++
        t |> equal(m.i, 7)
    }
    t |> run("apply sees a struct declared earlier resolved and sized, a later one as an alias, a pointer to it sized yet isAutoOrAlias, a constant dimension unfolded") @(t : T?) {
        t |> equal(apply_types_Seen(), "pt:tStructure:8 later:alias:-:alias p:tPointer:8:alias n:tDouble:8 arr:tFixedArray:12:dim3 by_const:tFixedArray:-:dim-2 by_enum:tFixedArray:-:dim-2")
    }
    t |> run("apply sees no annotation list: the parser attaches it after every apply ran") @(t : T?) {
        t |> equal(annotations_Seen(), 0)
    }
    t |> run("patch runs only once the whole program infers without error") @(t : T?) {
        let dir = test_temp_dir()
        let module_path = "{dir}/probe_patch_mod.das"
        fwrite(module_path, PATCH_MODULE)
        let clean = daslang_child("patch_clean", patch_source("    var p : P\n    p.x = 1\n"), true)
        t |> equal(clean.out |> find("PATCH RAN") >= 0, true, clean.out)
        let broken = daslang_child("patch_broken", patch_source("    var p : P\n    p.y = 1\n"), true)
        t |> equal(broken.rc != 0, true, broken.out)
        t |> equal(broken.out |> find("field 'y' not found") >= 0, true, broken.out)
        t |> equal(broken.out |> find("PATCH RAN") < 0, true, broken.out)
        remove(module_path)
    }
}

[test]
def test_union_bitfields(t : T?) {
    t |> run("a bitfield member is a property pair over _storage[0] beside the ref operators: it truncates and sign-extends at bit 0 and puns with the plain member") @(t : T?) {
        var u : UBits
        u.f1 = 0x12345678u
        t |> equal(u.f0, 120)
        // decimal: a hex literal is `uint`, so `u.f0 = 0x1ff` finds no `int` setter, falls back
        // to the getter and fails with "can only copy to a reference"
        u.f0 = 511
        t |> equal(u.f0, -1)
        t |> equal(u.f1, 0x123456ffu)
        u.f0 = -128
        t |> equal(u.f1, 0x12345680u)
        t |> equal(typeinfo sizeof(type<UBits>), 4)
    }
    t |> run("a union bitfield member steps through += 1 and reads through a const base, a nested union, an array element and a pointer") @(t : T?) {
        var u : UBits
        u.f0 = 126
        u.f0 += 1
        u.f0 += 1
        t |> equal(u.f0, -128)
        t |> equal(read_bits_let(u), -128)
        let c = u
        t |> equal(c.f0, -128)
        var h : HoldsUBits
        h.u.f0 = -5
        h.u.f0 -= 1
        t |> equal(h.u.f0, -6)
        t |> equal(h.u.f1, 0xfau)
        var arr : UBits[3]
        arr[1].f0 = 7
        arr[1].f0 *= 3
        t |> equal(arr[1].f0, 21)
        t |> equal(arr[0].f1, 0u)
        var p = unsafe(addr(h.u))
        p.f0 = 100
        t |> equal(h.u.f0, 100)
        let cp : UBits const? = unsafe(addr(u))
        t |> equal(cp.f0, -128)
    }
    t |> run("a union bitfield member is no reference: addr of it is refused, as C refuses &u.f0") @(t : T?) {
        let r = daslang_child("union_property_addr", UNION_PROPERTY, true)
        t |> equal(r.rc != 0, true, r.out)
        t |> equal(r.out |> find("can only make a pointer of a reference") >= 0, true, r.out)
    }
}
