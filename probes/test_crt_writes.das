options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

//! A `crt` function that writes through a pointer argument reaches the memory it writes under the
//! interpreter, the JIT, the JIT-linked executable and the AOT host of `converter/tiers.das`, since
//! its bind says `SideEffects::modifyArgumentAndExternal` (docs/probe-findings.md F85). Bound with
//! `modifyExternal` alone, two shapes lost the write: a `SideEffects::none` reader (`strlen`) on
//! both sides of the writer in one function folded into one read on every tier (the read-write-read
//! checks below), and under the JIT a helper with a non-`var` pointer parameter left its caller's
//! local as it was (`SOURCE`: `modf`'s and `sscanf`'s out-parameters, `time`, `tmpnam`, a volatile
//! store; `REPRO`: the review's `memcpy`).

// the review's repro: one memcpy in a helper on main's local array, the bytes printed right after
let REPRO = "options gen2\nrequire crt\nrequire c_runtime/c_function\n\n[c_function]\ndef cp(dst, src : uint8?) \{\n    crt::memcpy(reinterpret<void?>(dst), reinterpret<void?>(src), uint64(4))\n\}\n\n[export]\ndef main : int \{\n    var buf : uint8[8] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4), uint8(5), uint8(6), uint8(7), uint8(8))\n    unsafe \{\n        cp(addr(buf[4]), addr(buf[0]))\n    \}\n    print(\"\{buf[4]\} \{buf[7]\}\\n\")\n    return 0\n\}\n"

// one helper per writer family, its pointer parameters not `var` (the JIT's readonly path), each
// called once on a local of main; the line every tier prints
let SOURCE = "options gen2\nrequire crt\nrequire daslib/strings_boost\nrequire c_runtime/c_function\n\n[c_function]\ndef do_memcpy(d, s : uint8?) \{\n    crt::memcpy(reinterpret<void?>(d), reinterpret<void?>(s), uint64(4))\n\}\n\n[c_function]\ndef do_memmove(d, s : uint8?) \{\n    crt::memmove(reinterpret<void?>(d), reinterpret<void?>(s), uint64(4))\n\}\n\n[c_function]\ndef do_memset(d : uint8?) \{\n    crt::memset(reinterpret<void?>(d), 9, uint64(4))\n\}\n\n[c_function]\ndef do_strcpy(d, s : uint8?) \{\n    crt::strcpy(d, s)\n\}\n\n[c_function]\ndef do_strncpy(d, s : uint8?) \{\n    crt::strncpy(d, s, uint64(2))\n\}\n\n[c_function]\ndef do_strcat(d, s : uint8?) \{\n    crt::strcat(d, s)\n\}\n\n[c_function]\ndef do_strncat(d, s : uint8?) \{\n    crt::strncat(d, s, uint64(1))\n\}\n\n[c_function]\ndef do_strtol(s : uint8?; e : uint8??) : int64 \{\n    return crt::strtol(s, e, 10)\n\}\n\n[c_function]\ndef do_snprintf(d, f : uint8?) \{\n    crt::snprintf_int(d, uint64(8), f, 42)\n\}\n\n[c_function]\ndef do_frexp(e : int?) : double \{\n    return crt::frexp(12.0lf, e)\n\}\n\n[c_function]\ndef do_modf(ip : double?) : double \{\n    return crt::modf(2.5lf, ip)\n\}\n\n[c_function]\ndef do_store(p : int?) \{\n    crt::c_volatile_store_i32(p, 33)\n\}\n\n[c_function]\ndef do_fgets(d : uint8?; f : void?) \{\n    crt::fgets(d, 8, f)\n\}\n\n[c_function]\ndef do_sscanf(o : int?) \{\n    var n = 0\n    crt::sscanf_one(reinterpret<uint8?>(\"42\"), reinterpret<uint8?>(\"%d%n\"), reinterpret<void?>(o), addr(n))\n\}\n\n[c_function]\ndef do_time(t : int64?) : int64 \{\n    return crt::time(t)\n\}\n\n[c_function]\ndef do_tmpnam(d : uint8?) \{\n    crt::tmpnam(d)\n\}\n\n// the length before and after a store between two calls a pure reading could merge\n[c_function]\ndef lengths(var d : uint8?) : int \{\n    let a = int(crt::strlen(d))\n    d[1] = uint8(0)\n    let b = int(crt::strlen(d))\n    return a * 10 + b\n\}\n\n[export]\ndef main : int \{\n    var b : uint8[8] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4), uint8(5), uint8(6), uint8(7), uint8(8))\n    var t : uint8[8] = fixed_array(uint8(97), uint8(98), uint8(99), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0))\n    var u : uint8[16]\n    var num : uint8[8] = fixed_array(uint8(49), uint8(50), uint8(120), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0))\n    var fmt : uint8[4] = fixed_array(uint8(37), uint8(100), uint8(0), uint8(0))\n    var ex = 0\n    var ip = 0.0lf\n    var cell = 0\n    var endp : uint8? = null\n    var out : array<string>\n    unsafe \{\n        do_memcpy(addr(b[4]), addr(b[0]))\n        out |> push(\"memcpy \{int(b[4])\}\{int(b[7])\}\")\n        do_memmove(addr(b[1]), addr(b[0]))\n        out |> push(\"memmove \{int(b[1])\}\{int(b[4])\}\")\n        do_memset(addr(b[0]))\n        out |> push(\"memset \{int(b[0])\}\{int(b[3])\}\")\n        do_strcpy(addr(u[0]), addr(t[0]))\n        out |> push(\"strcpy \{int(u[0])\}\{int(u[2])\}\")\n        do_strncpy(addr(u[4]), addr(t[1]))\n        out |> push(\"strncpy \{int(u[4])\}\{int(u[5])\}\")\n        do_strcat(addr(u[0]), addr(t[0]))\n        out |> push(\"strcat \{int(u[3])\}\{int(u[5])\}\")\n        do_strncat(addr(u[0]), addr(t[2]))\n        out |> push(\"strncat \{int(u[6])\}\")\n        let v = do_strtol(addr(num[0]), addr(endp))\n        out |> push(\"strtol \{v\} \{endp == addr(num[2])\}\")\n        do_snprintf(addr(u[8]), addr(fmt[0]))\n        out |> push(\"snprintf \{int(u[8])\}\{int(u[9])\}\")\n        let m = do_frexp(addr(ex))\n        out |> push(\"frexp \{m\} \{ex\}\")\n        let f = do_modf(addr(ip))\n        out |> push(\"modf \{f\} \{ip\}\")\n        do_store(addr(cell))\n        out |> push(\"store \{cell\}\")\n        out |> push(\"strlen \{lengths(addr(t[0]))\}\")\n        var line : uint8[8]\n        let file = crt::tmpfile()\n        crt::fputs(reinterpret<uint8?>(\"XY\"), file)\n        crt::fseek(file, 0l, 0)\n        do_fgets(addr(line[0]), file)\n        crt::fclose(file)\n        out |> push(\"fgets \{int(line[0])\}\{int(line[1])\}\")\n        var got = 0\n        do_sscanf(addr(got))\n        out |> push(\"sscanf \{got\}\")\n        var stamp = 0l\n        let now = do_time(addr(stamp))\n        out |> push(\"time \{stamp == now\}\")\n        var name : uint8[64]\n        do_tmpnam(addr(name[0]))\n        out |> push(\"tmpnam \{name[0] != uint8(0)\}\")\n    \}\n    print(\"\{join(out, \"; \")\}\\n\")\n    return 0\n\}\n"

let EXPECTED = "memcpy 14; memmove 14; memset 99; strcpy 9799; strncpy 9899; strcat 9799; strncat 99; strtol 12 true; snprintf 5250; frexp 0.75 4; modf 0.5 2; store 33; strlen 31; fgets 8889; sscanf 42; time true; tmpnam true"

//! Each rebound bind is checked in two shapes, on a local of 1024 bytes holding 20 `k` and NULs
//! that the writer changes within its first 24 bytes:
//! - read-write-read: `strlen(d)` before and after the writer in one function; with the readers bound
//!   `none` and the writers `modifyExternal` alone, the two reads folded into one under the
//!   interpreter and the JIT alike (`rwr_source`);
//! - one shot: the local passed once to a helper whose pointer parameter is not `var` and read right
//!   after in main; bound `modifyExternal` alone, the JIT and the exe kept the local's bytes as they
//!   were (`one_source`).
//! `mktime` writes a struct tm and is checked on its own fields. `realloc` and `free` carry no check:
//! no well-defined program sees a caller's local through what they write.
struct WriteCheck {
    name : string
    setup : string
    writer : string
}

let RWR_CHECKS <- [
        WriteCheck(name = "memcpy", setup = "", writer = "crt::memcpy(reinterpret<void?>(d), reinterpret<void?>(\"XY\"), uint64(3))"),
        WriteCheck(name = "memmove", setup = "", writer = "crt::memmove(reinterpret<void?>(d), reinterpret<void?>(\"XY\"), uint64(3))"),
        WriteCheck(name = "memset", setup = "", writer = "crt::memset(reinterpret<void?>(d), 0, uint64(4))"),
        WriteCheck(name = "strcpy", setup = "", writer = "crt::strcpy(d, reinterpret<uint8?>(\"XY\"))"),
        WriteCheck(name = "strncpy", setup = "", writer = "crt::strncpy(d, reinterpret<uint8?>(\"XY\"), uint64(3))"),
        WriteCheck(name = "strcat", setup = "", writer = "crt::strcat(d, reinterpret<uint8?>(\"XY\"))"),
        WriteCheck(name = "strncat", setup = "", writer = "crt::strncat(d, reinterpret<uint8?>(\"XY\"), uint64(1))"),
        WriteCheck(name = "strtol", setup = "", writer = "crt::strtol(reinterpret<uint8?>(\"12x\"), reinterpret<uint8??>(d), 10)"),
        WriteCheck(name = "strtoul", setup = "", writer = "crt::strtoul(reinterpret<uint8?>(\"12x\"), reinterpret<uint8??>(d), 10)"),
        WriteCheck(name = "strtoll", setup = "", writer = "crt::strtoll(reinterpret<uint8?>(\"12x\"), reinterpret<uint8??>(d), 10)"),
        WriteCheck(name = "strtoull", setup = "", writer = "crt::strtoull(reinterpret<uint8?>(\"12x\"), reinterpret<uint8??>(d), 10)"),
        WriteCheck(name = "strtod", setup = "", writer = "crt::strtod(reinterpret<uint8?>(\"1.5x\"), reinterpret<uint8??>(d))"),
        WriteCheck(name = "c_strtol32", setup = "", writer = "crt::c_strtol32(reinterpret<uint8?>(\"12x\"), reinterpret<uint8??>(d), 10)"),
        WriteCheck(name = "c_strtoul32", setup = "", writer = "crt::c_strtoul32(reinterpret<uint8?>(\"12x\"), reinterpret<uint8??>(d), 10)"),
        WriteCheck(name = "fgets", setup = "let f = crt::tmpfile()\n    crt::fputs(reinterpret<uint8?>(\"XYZ\\\\n\"), f)\n    crt::fseek(f, 0l, 0)", writer = "crt::fgets(d, 16, f)"),
        WriteCheck(name = "fread", setup = "let f = crt::tmpfile()\n    crt::fwrite(reinterpret<void?>(\"XY\"), uint64(1), uint64(3), f)\n    crt::fseek(f, 0l, 0)", writer = "crt::fread(reinterpret<void?>(d), uint64(1), uint64(3), f)"),
        WriteCheck(name = "frexp", setup = "", writer = "crt::frexp(12.0lf, reinterpret<int?>(d))"),
        WriteCheck(name = "modf", setup = "", writer = "crt::modf(2.5lf, reinterpret<double?>(d))"),
        WriteCheck(name = "time", setup = "", writer = "crt::time(reinterpret<int64?>(d))"),
        WriteCheck(name = "strftime", setup = "var t0 = 0l\n    let tm = crt::gmtime(addr(t0))", writer = "crt::strftime(d, uint64(64), reinterpret<uint8?>(\"%Y\"), tm)"),
        WriteCheck(name = "clock_gettime", setup = "", writer = "crt::clock_gettime(1, reinterpret<void?>(d))"),
        WriteCheck(name = "snprintf_none", setup = "", writer = "crt::snprintf_none(d, uint64(64), reinterpret<uint8?>(\"XY\"))"),
        WriteCheck(name = "snprintf_int", setup = "", writer = "crt::snprintf_int(d, uint64(64), reinterpret<uint8?>(\"%d\"), 42)"),
        WriteCheck(name = "snprintf_uint", setup = "", writer = "crt::snprintf_uint(d, uint64(64), reinterpret<uint8?>(\"%u\"), 42u)"),
        WriteCheck(name = "snprintf_int64", setup = "", writer = "crt::snprintf_int64(d, uint64(64), reinterpret<uint8?>(\"%lld\"), 42l)"),
        WriteCheck(name = "snprintf_uint64", setup = "", writer = "crt::snprintf_uint64(d, uint64(64), reinterpret<uint8?>(\"%llu\"), 42ul)"),
        WriteCheck(name = "snprintf_double", setup = "", writer = "crt::snprintf_double(d, uint64(64), reinterpret<uint8?>(\"%g\"), 1.5lf)"),
        WriteCheck(name = "snprintf_str", setup = "", writer = "crt::snprintf_str(d, uint64(64), reinterpret<uint8?>(\"%s\"), reinterpret<uint8?>(\"XY\"))"),
        WriteCheck(name = "snprintf_ptr", setup = "", writer = "crt::snprintf_ptr(d, uint64(64), reinterpret<uint8?>(\"%p\"), null)"),
        WriteCheck(name = "sscanf_one", setup = "", writer = "crt::sscanf_one(reinterpret<uint8?>(\"42\"), reinterpret<uint8?>(\"%d%n\"), reinterpret<void?>(d), reinterpret<int?>(d + 8))"),
        WriteCheck(name = "sscanf_none", setup = "", writer = "crt::sscanf_none(reinterpret<uint8?>(\"abc\"), reinterpret<uint8?>(\"abc%n\"), reinterpret<int?>(d))"),
        WriteCheck(name = "tmpnam", setup = "", writer = "crt::tmpnam(d)"),
        WriteCheck(name = "c_volatile_store_i8", setup = "", writer = "crt::c_volatile_store_i8(reinterpret<int8?>(d), int8(0))"),
        WriteCheck(name = "c_volatile_store_u8", setup = "", writer = "crt::c_volatile_store_u8(reinterpret<uint8?>(d), uint8(0))"),
        WriteCheck(name = "c_volatile_store_i16", setup = "", writer = "crt::c_volatile_store_i16(reinterpret<int16?>(d), int16(0))"),
        WriteCheck(name = "c_volatile_store_u16", setup = "", writer = "crt::c_volatile_store_u16(reinterpret<uint16?>(d), uint16(0))"),
        WriteCheck(name = "c_volatile_store_i32", setup = "", writer = "crt::c_volatile_store_i32(reinterpret<int?>(d), int(0))"),
        WriteCheck(name = "c_volatile_store_u32", setup = "", writer = "crt::c_volatile_store_u32(reinterpret<uint?>(d), uint(0))"),
        WriteCheck(name = "c_volatile_store_i64", setup = "", writer = "crt::c_volatile_store_i64(reinterpret<int64?>(d), int64(0))"),
        WriteCheck(name = "c_volatile_store_u64", setup = "", writer = "crt::c_volatile_store_u64(reinterpret<uint64?>(d), uint64(0))"),
        WriteCheck(name = "c_volatile_store_f32", setup = "", writer = "crt::c_volatile_store_f32(reinterpret<float?>(d), float(0))"),
        WriteCheck(name = "c_volatile_store_f64", setup = "", writer = "crt::c_volatile_store_f64(reinterpret<double?>(d), double(0))"),
    WriteCheck(name = "setvbuf", setup = "let f = crt::tmpfile()", writer = "crt::setvbuf(f, d, 0, uint64(1024))\n    crt::fwrite(reinterpret<void?>(\"XY\"), uint64(1), uint64(3), f)")
]

// the head of both programs: the 1024-byte locals need more than daslang's default stack
let CHECKS_HEAD = "options gen2\noptions stack = 1048576\nrequire crt\nrequire c_runtime/c_function\n\n"

// a local `b_<name>`: 20 `k` bytes, NULs after
def private fill_local(var w : StringBuilderWriter; name : string) {
    w |> write("    var b_{name} : uint8[1024]\n    for (i in range(20)) \{\n        b_{name}[i] = uint8(107)\n    \}\n")
}

// the program of the read-write-read checks: one `[c_function]` per check, main printing the lost ones
def private rwr_source : string {
    return build_string() $(var w) {
        w |> write(CHECKS_HEAD)
        for (c in RWR_CHECKS) {
            w |> write("[c_function]\ndef k_{c.name}(var d : uint8?) : bool \{\n")
            if (!empty(c.setup)) {
                w |> write("    {c.setup}\n")
            }
            w |> write("    let a = crt::strlen(d)\n    {c.writer}\n    let b = crt::strlen(d)\n")
            if (c.setup |> contains("tmpfile")) {
                w |> write("    crt::fclose(f)\n")
            }
            w |> write("    return a == uint64(20) && b != uint64(20)\n\}\n\n")
        }
        // mktime normalizes a struct tm: tm_sec 60, byte 0 a `<`, becomes 0 and a minute
        w |> write("[c_function]\ndef k_mktime(var d : uint8?) : bool \{\n    let a = crt::strlen(d)\n    crt::mktime(reinterpret<void?>(d))\n")
        w |> write("    let b = crt::strlen(d)\n    return a == uint64(1) && b == uint64(0)\n\}\n\n")
        w |> write("[export]\ndef main : int \{\n    var lost = \"\"\n")
        for (c in RWR_CHECKS) {
            fill_local(w, c.name)
            w |> write("    unsafe \{\n        if (!k_{c.name}(addr(b_{c.name}[0]))) \{\n            lost += \" {c.name}\"\n        \}\n    \}\n")
        }
        w |> write("    var tm : int[16]\n    tm[0] = 60\n    tm[3] = 1\n    tm[5] = 100\n    unsafe \{\n")
        w |> write("        if (!k_mktime(reinterpret<uint8?>(addr(tm[0])))) \{\n            lost += \" mktime\"\n        \}\n    \}\n")
        w |> write("    print(\"lost:\{empty(lost) ? \" none\" : lost\}\\n\")\n    return 0\n\}\n")
    }
}

//! The readers (`strlen`, `memcmp`, `strchr`, `atoi` and the rest that read through a pointer) are
//! `SideEffects::accessExternal`: bound `none`, the same reading through a second pointer to the
//! memory a writer changes through the first folded into one read under the interpreter and the
//! JIT, writer binds right or not (`alias_source`; C's `p = s; n = strlen(p); strcpy(s, t);
//! m = strlen(p)`).
let ALIAS_READERS <- [
    (name = "memcmp", read = "crt::memcmp(pv, qv, uint64(2))"),
    (name = "memchr", read = "crt::memchr(pv, 49, uint64(4))"),
    (name = "strlen", read = "crt::strlen(p)"),
    (name = "strcmp", read = "crt::strcmp(p, q)"),
    (name = "strncmp", read = "crt::strncmp(p, q, uint64(2))"),
    (name = "strchr", read = "crt::strchr(p, 49)"),
    (name = "strrchr", read = "crt::strrchr(p, 49)"),
    (name = "strstr", read = "crt::strstr(p, q)"),
    (name = "strpbrk", read = "crt::strpbrk(p, q)"),
    (name = "strspn", read = "crt::strspn(p, q)"),
    (name = "atoi", read = "crt::atoi(p)"),
    (name = "atol", read = "crt::atol(p)"),
    (name = "atof", read = "crt::atof(p)")
]

// the program of the alias checks: per reader a read through `p` (`pv`) before and after `strcpy`
// writes "12" through `d`, the two the same local, `q` (`qv`) a local "12"; the reads spell no
// cast, which keeps the optimizer from matching them
def private alias_source : string {
    return build_string() $(var w) {
        w |> write(CHECKS_HEAD)
        for (r in ALIAS_READERS) {
            w |> write("[c_function]\ndef r_{r.name}(var d : uint8?; var p : uint8?; var q : uint8?; var pv : void?; var qv : void?) : bool \{\n    let a = {r.read}\n")
            w |> write("    crt::strcpy(d, reinterpret<uint8?>(\"12\"))\n    let b = {r.read}\n    return a != b\n\}\n\n")
        }
        w |> write("[export]\ndef main : int \{\n    var lost = \"\"\n")
        for (r in ALIAS_READERS) {
            fill_local(w, r.name)
            w |> write("    var q_{r.name} : uint8[4] = fixed_array(uint8(49), uint8(50), uint8(0), uint8(0))\n    unsafe \{\n")
            w |> write("        var p_{r.name} = addr(b_{r.name}[0])\n        var s_{r.name} = addr(q_{r.name}[0])\n")
            w |> write("        if (!r_{r.name}(p_{r.name}, p_{r.name}, s_{r.name}, reinterpret<void?>(p_{r.name}), reinterpret<void?>(s_{r.name}))) \{\n")
            w |> write("            lost += \" {r.name}\"\n        \}\n    \}\n")
        }
        w |> write("    print(\"lost:\{empty(lost) ? \" none\" : lost\}\\n\")\n    return 0\n\}\n")
    }
}

// the program of the one-shot checks: per check a helper with a non-`var` pointer parameter that
// returns the stream it opened, if any, and a function of its own holding the local, which it
// reads right after the call and before the stream is flushed (a main of all of them is too large
// for the JIT to forward every local's bytes, which hides the loss)
def private one_source : string {
    return build_string() $(var w) {
        w |> write(CHECKS_HEAD)
        for (c in RWR_CHECKS) {
            w |> write("[c_function]\ndef o_{c.name}(d : uint8?) : void? \{\n")
            if (!empty(c.setup)) {
                w |> write("    {c.setup}\n")
            }
            w |> write("    {c.writer}\n    return {c.setup |> contains("tmpfile") ? "f" : "null"}\n\}\n\n")
            w |> write("def written_{c.name} : bool \{\n")
            fill_local(w, c.name)
            w |> write("    var same = true\n    unsafe \{\n        let f = o_{c.name}(addr(b_{c.name}[0]))\n")
            w |> write("        same = b_{c.name}[0] == uint8(107) && b_{c.name}[20] == uint8(0)\n")
            w |> write("        if (f != null) \{\n            crt::fclose(f)\n        \}\n    \}\n    return !same\n\}\n\n")
        }
        // mktime rolls tm_mday 32 of January 2000 into February 1
        w |> write("[c_function]\ndef o_mktime(t : int?) \{\n    crt::mktime(reinterpret<void?>(t))\n\}\n\n")
        w |> write("def written_mktime : bool \{\n    var tm : int[16]\n    tm[3] = 32\n    tm[5] = 100\n    unsafe \{\n        o_mktime(addr(tm[0]))\n    \}\n")
        w |> write("    return tm[3] == 1 && tm[4] == 1\n\}\n\n")
        w |> write("[export]\ndef main : int \{\n    var lost = \"\"\n")
        for (name in [for (c in RWR_CHECKS); c.name]) {
            w |> write("    if (!written_{name}()) \{\n        lost += \" {name}\"\n    \}\n")
        }
        w |> write("    if (!written_mktime()) \{\n        lost += \" mktime\"\n    \}\n")
        w |> write("    print(\"lost:\{empty(lost) ? \" none\" : lost\}\\n\")\n    return 0\n\}\n")
    }
}

let WRITE_TIERS = fixed_array("interp", "jit", "exe", "aot")

[test]
def test_crt_writes(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "writes.das")
    fwrite(entry, SOURCE)
    let repro = path_join(work, "repro.das")
    fwrite(repro, REPRO)
    let rwr = path_join(work, "rwr.das")
    fwrite(rwr, rwr_source())
    let one = path_join(work, "one.das")
    fwrite(one, one_source())
    let alias = path_join(work, "alias.das")
    fwrite(alias, alias_source())
    for (tier in WRITE_TIERS) {
        tt |> run("under {tier} a crt function writing through a pointer argument from a helper reaches the caller's local") @(t : T?) {
            var out : string
            let rc = run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES)
            t |> equal(rc, 0, "{tier}: {out}")
            let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
            t |> success(has_value(lines, EXPECTED), "{tier}: {out}")
            var repro_out : string
            t |> equal(run_tier(repro, tier, path_join(work, "repro_{tier}"), repro_out, CONVERTED_MODULES), 0, "{tier}: {repro_out}")
            t |> success(repro_out |> contains("0x1 0x4\n"), "{tier}: {repro_out}")
            var rwr_out : string
            t |> equal(run_tier(rwr, tier, path_join(work, "rwr_{tier}"), rwr_out, CONVERTED_MODULES), 0, "{tier}: {rwr_out}")
            t |> success(rwr_out |> contains("lost: none\n"), "{tier}: {rwr_out}")
            var one_out : string
            t |> equal(run_tier(one, tier, path_join(work, "one_{tier}"), one_out, CONVERTED_MODULES), 0, "{tier}: {one_out}")
            t |> success(one_out |> contains("lost: none\n"), "{tier}: {one_out}")
            var alias_out : string
            t |> equal(run_tier(alias, tier, path_join(work, "alias_{tier}"), alias_out, CONVERTED_MODULES), 0, "{tier}: {alias_out}")
            t |> success(alias_out |> contains("lost: none\n"), "{tier}: {alias_out}")
        }
    }
}
