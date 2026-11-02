"""research 03: the hand-written spellings of the exec_backjump kernel, generated from the
converter's output so every module shares the harness, the globals and the kernel_run loop.
  ifchain          P7.0c's form (the audit's `if_chain` rewrite): plain cases as `if`, the
                   fall-through case and the `ret` label keep the flag, re-dispatch kept
  structured       the proposal: nested while loops for startfunc/returning, if/elif dispatch,
                   `goto startfunc` and `goto ret` as `break` with a named bool, the ret tail after the loop
  structured_inline the proposal without any bool: the one-line startfunc prefix inlined at the
                   call sites, the ret tail inlined at the return sites, `break` switches frames
  structured_goto  the if/elif dispatch with das `goto label` back-jumps kept and the ret tail
                   duplicated at each site: isolates what `goto label` costs against `break`
"""
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
conv = (root / "work/exec_backjump/exec_backjump.das").read_text()
csrc = (root / "kernels/exec_backjump.c").read_text()
out = root / "hand"
out.mkdir(exist_ok=True)

# --- ifchain: the audit's if_chain rewrite, case 46 (falls into ret) and ret keep their flags
ifchain = re.sub(r"_flag \|\|= _goto == 0 && (_cond == (?!46\b)\d+)\n(\s*)if \(_flag\) \{",
                 r"if (_goto == 0 && \1) {", conv)
ifchain = re.sub(r"_flag \|\|= _goto == 0 && (!\(_cond == 0 \|\|[^\n]*\))\n(\s*)if \(_flag\) \{",
                 r"if (_goto == 0 && \1) {", ifchain)
(out / "exec_backjump_ifchain.das").write_text(ifchain)

# --- the plain cases from the C: `case N: acc OP V; break;`
cases = re.findall(r"case (\d+): acc (\S+) (\d+); break;", csrc)
head, _, tail = conv.partition("def private exec_backjump__run(var acc : int) : int {")
tail = tail[tail.index("\ndef private exec_backjump__kernel_run"):]

def chain(call, ret, indent):
    i = " " * indent
    plain = {int(k): (op, v) for k, op, v in cases}
    lines = []
    first = True
    for k in range(47):
        kw = "if" if first else "} elif"
        first = False
        if k in plain:
            op, v = plain[k]
            lines.append(f"{i}{kw} (i == {k}) {{")
            lines.append(f"{i}    acc {op} {v}")
        elif k == 40:
            lines.append(f"{i}{kw} (i == 40) {{  // OP_CALL")
            lines.append(f"{i}    if (depth < 3) {{")
            lines.append(f"{i}        frames[depth] = pc")
            lines.append(f"{i}        depth++")
            lines.append(f"{i}        frames[depth] = 0")
            lines += [f"{i}        {l}" for l in call]
            lines.append(f"{i}    }}")
            lines.append(f"{i}    acc += 41")
        elif k == 41:
            lines.append(f"{i}{kw} (i == 41) {{  // OP_RETURN")
            lines.append(f"{i}    acc -= 42")
            lines += [f"{i}    {l}" for l in ret]
        elif k == 42:
            lines.append(f"{i}{kw} (i == 42) {{  // OP_TAILCALL, a C callee")
            lines.append(f"{i}    acc ^= 43")
            lines += [f"{i}    {l}" for l in ret]
        elif k == 46:
            lines.append(f"{i}{kw} (i == 46) {{  // OP_RETURN1")
            lines.append(f"{i}    acc ^= 47")
            lines += [f"{i}    {l}" for l in ret]
    lines.append(f"{i}}} else {{")
    lines.append(f"{i}    acc += 48")
    lines.append(f"{i}}}")
    return "\n".join(lines)

structured = f"""def private exec_backjump__run(var acc : int) : int {{
    var frames : int[8]
    var depth : int = 0
    var trap : int
    var pc : int
    frames[0] = 0
    var fresh = true
    while (true) {{
        if (fresh) {{  // startfunc:
            trap = acc & 1
        }}
        // returning:
        pc = frames[depth]
        var returned = false
        while (true) {{
            let _t0 = pc
            pc++
            var i : int = int(exec_backjump__code[_t0])
            acc += trap
{chain(["fresh = true", "break  // goto startfunc"], ["returned = true", "break  // goto ret"], 12)}
        }}
        if (returned) {{  // ret: return from a Lua function
            if (depth == 0) {{
                return acc
            }}
            depth--
            fresh = false  // goto returning
        }}
    }}
    return 0
}}
"""
(out / "exec_backjump_structured.das").write_text(head + structured + tail)

ret_tail = ["if (depth == 0) {", "    return acc", "}", "depth--", "break  // goto returning"]
structured_inline = f"""def private exec_backjump__run(var acc : int) : int {{
    var frames : int[8]
    var depth : int = 0
    var trap : int
    var pc : int
    frames[0] = 0
    trap = acc & 1  // startfunc:
    while (true) {{  // returning:
        pc = frames[depth]
        while (true) {{
            let _t0 = pc
            pc++
            var i : int = int(exec_backjump__code[_t0])
            acc += trap
{chain(["trap = acc & 1  // startfunc", "break"], ret_tail, 12)}
        }}
    }}
    return 0
}}
"""
(out / "exec_backjump_structured_inline.das").write_text(head + structured_inline + tail)

ret_inline = ["if (depth == 0) {", "    return acc", "}", "depth--", "goto label 2  // returning"]
structured_goto = f"""def private exec_backjump__run(var acc : int) : int {{
    var frames : int[8]
    var depth : int = 0
    var trap : int
    var pc : int
    frames[0] = 0
    label 1:  // startfunc
    c_label_end()
    trap = acc & 1
    label 2:  // returning
    c_label_end()
    pc = frames[depth]
    while (true) {{
        let _t0 = pc
        pc++
        var i : int = int(exec_backjump__code[_t0])
        acc += trap
{chain(["goto label 1  // startfunc"], ret_inline, 8)}
    }}
    return 0
}}
"""
(out / "exec_backjump_structured_goto.das").write_text(head + structured_goto + tail)
print("written", sorted(p.name for p in out.iterdir()))
