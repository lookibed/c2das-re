options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

//! A `crt` function that writes through a pointer argument, called from a `[c_function]` helper on
//! a local of its caller (an array, or a scalar whose address is taken): its writes reach the
//! caller under the interpreter, the JIT, the JIT-linked executable and the AOT host of
//! `converter/tiers.das`, since its bind says `SideEffects::modifyArgumentAndExternal`. Bound with
//! `modifyExternal` alone, the JIT kept the caller's local as it was: a lost `memcpy`, `strtol`'s
//! end pointer, `frexp`'s and `modf`'s out-parameters, a volatile store (docs/probe-findings.md
//! F85). A pure reading (`strlen`) keeps `SideEffects::none` and still sees a store made between
//! two of its calls.

// the review's repro: one memcpy in a helper on main's local array, the bytes printed right after
let REPRO = "options gen2\nrequire crt\nrequire c_runtime/c_function\n\n[c_function]\ndef cp(dst, src : uint8?) \{\n    crt::memcpy(reinterpret<void?>(dst), reinterpret<void?>(src), uint64(4))\n\}\n\n[export]\ndef main : int \{\n    var buf : uint8[8] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4), uint8(5), uint8(6), uint8(7), uint8(8))\n    unsafe \{\n        cp(addr(buf[4]), addr(buf[0]))\n    \}\n    print(\"\{buf[4]\} \{buf[7]\}\\n\")\n    return 0\n\}\n"

// one helper per writing function, each called once on a local of main; the line every tier prints
let SOURCE = "options gen2\nrequire crt\nrequire daslib/strings_boost\nrequire c_runtime/c_function\n\n[c_function]\ndef do_memcpy(d, s : uint8?) \{\n    crt::memcpy(reinterpret<void?>(d), reinterpret<void?>(s), uint64(4))\n\}\n\n[c_function]\ndef do_memmove(d, s : uint8?) \{\n    crt::memmove(reinterpret<void?>(d), reinterpret<void?>(s), uint64(4))\n\}\n\n[c_function]\ndef do_memset(d : uint8?) \{\n    crt::memset(reinterpret<void?>(d), 9, uint64(4))\n\}\n\n[c_function]\ndef do_strcpy(d, s : uint8?) \{\n    crt::strcpy(d, s)\n\}\n\n[c_function]\ndef do_strncpy(d, s : uint8?) \{\n    crt::strncpy(d, s, uint64(2))\n\}\n\n[c_function]\ndef do_strcat(d, s : uint8?) \{\n    crt::strcat(d, s)\n\}\n\n[c_function]\ndef do_strncat(d, s : uint8?) \{\n    crt::strncat(d, s, uint64(1))\n\}\n\n[c_function]\ndef do_strtol(s : uint8?; e : uint8??) : int64 \{\n    return crt::strtol(s, e, 10)\n\}\n\n[c_function]\ndef do_snprintf(d, f : uint8?) \{\n    crt::snprintf_int(d, uint64(8), f, 42)\n\}\n\n[c_function]\ndef do_frexp(e : int?) : double \{\n    return crt::frexp(12.0lf, e)\n\}\n\n[c_function]\ndef do_modf(ip : double?) : double \{\n    return crt::modf(2.5lf, ip)\n\}\n\n[c_function]\ndef do_store(p : int?) \{\n    crt::c_volatile_store_i32(p, 33)\n\}\n\n// the length before and after a store between two calls a pure reading could merge\n[c_function]\ndef lengths(var d : uint8?) : int \{\n    let a = int(crt::strlen(d))\n    d[1] = uint8(0)\n    let b = int(crt::strlen(d))\n    return a * 10 + b\n\}\n\n[export]\ndef main : int \{\n    var b : uint8[8] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4), uint8(5), uint8(6), uint8(7), uint8(8))\n    var t : uint8[8] = fixed_array(uint8(97), uint8(98), uint8(99), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0))\n    var u : uint8[16]\n    var num : uint8[8] = fixed_array(uint8(49), uint8(50), uint8(120), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0))\n    var fmt : uint8[4] = fixed_array(uint8(37), uint8(100), uint8(0), uint8(0))\n    var ex = 0\n    var ip = 0.0lf\n    var cell = 0\n    var endp : uint8? = null\n    var out : array<string>\n    unsafe \{\n        do_memcpy(addr(b[4]), addr(b[0]))\n        out |> push(\"memcpy \{int(b[4])\}\{int(b[7])\}\")\n        do_memmove(addr(b[1]), addr(b[0]))\n        out |> push(\"memmove \{int(b[1])\}\{int(b[4])\}\")\n        do_memset(addr(b[0]))\n        out |> push(\"memset \{int(b[0])\}\{int(b[3])\}\")\n        do_strcpy(addr(u[0]), addr(t[0]))\n        out |> push(\"strcpy \{int(u[0])\}\{int(u[2])\}\")\n        do_strncpy(addr(u[4]), addr(t[1]))\n        out |> push(\"strncpy \{int(u[4])\}\{int(u[5])\}\")\n        do_strcat(addr(u[0]), addr(t[0]))\n        out |> push(\"strcat \{int(u[3])\}\{int(u[5])\}\")\n        do_strncat(addr(u[0]), addr(t[2]))\n        out |> push(\"strncat \{int(u[6])\}\")\n        let v = do_strtol(addr(num[0]), addr(endp))\n        out |> push(\"strtol \{v\} \{endp == addr(num[2])\}\")\n        do_snprintf(addr(u[8]), addr(fmt[0]))\n        out |> push(\"snprintf \{int(u[8])\}\{int(u[9])\}\")\n        let m = do_frexp(addr(ex))\n        out |> push(\"frexp \{m\} \{ex\}\")\n        let f = do_modf(addr(ip))\n        out |> push(\"modf \{f\} \{ip\}\")\n        do_store(addr(cell))\n        out |> push(\"store \{cell\}\")\n        out |> push(\"strlen \{lengths(addr(t[0]))\}\")\n    \}\n    print(\"\{join(out, \"; \")\}\\n\")\n    return 0\n\}\n"

let EXPECTED = "memcpy 14; memmove 14; memset 99; strcpy 9799; strncpy 9899; strcat 9799; strncat 99; strtol 12 true; snprintf 5250; frexp 0.75 4; modf 0.5 2; store 33; strlen 31"

let WRITE_TIERS = fixed_array("interp", "jit", "exe", "aot")

[test]
def test_crt_writes(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "writes.das")
    fwrite(entry, SOURCE)
    let repro = path_join(work, "repro.das")
    fwrite(repro, REPRO)
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
        }
    }
}
