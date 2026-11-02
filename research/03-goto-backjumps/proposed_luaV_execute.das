// research 03: the skeleton of luaV_execute (lvm.c:1154) as the proposal spells it. A sketch,
// not compiled: the frame of startfunc / returning / ret with OP_ADD, OP_CALL, OP_TAILCALL and
// OP_RETURN; the other opcodes are plain `elif` branches of the same chain (P7.0c's form).
// Today's output: lua/work/lua/lvm.das.inc:879-3568 (labels 2 and 3 at 885 and 888, the
// `_goto = 1; goto label 1` re-dispatch at 3257, 3292, 3319, the `ret` case at 3356).

def luaV_execute(var L : lua_State?; var ci : CallInfo?) {
    var cl : LClosure?
    var k : TValue?
    var base : StackValue?
    var pc : uint?
    var trap : int
    trap = c_volatile_load(L.hookmask)                       // startfunc:
    while (true) {                                           // returning: (trap already set)
        cl = addr(reinterpret<GCUnion?>(addr(ci.func.p.val).value_.gc).cl.l)
        k = cl.p.k
        pc = ci.u.l.savedpc
        if (trap != 0) {
            trap = luaG_tracecall(L)
        }
        base = ci.func.p + 1
        while (true) {                                       // for (;;) - the main loop
            var i : uint
            if (trap != 0) {
                trap = luaG_traceexec(L, pc)
                base = ci.func.p + 1
            }
            i = deref(pc)
            pc = pc + 1
            let op = enum_from_int(type<OpCode>, int(i & 0x7Fu))
            if (op == OpCode.OP_MOVE) {
                var ra : StackValue? = base + int(i >> 7u & 0xFFu)
                // ... as today, without the `break`
            } elif (op == OpCode.OP_ADD) {
                var ra : StackValue? = base + int(i >> 7u & 0xFFu)
                // ... the arithmetic as today, `pc = pc + 1` where C writes `pc++`
            } elif (op == OpCode.OP_CALL) {
                var ra : StackValue? = base + int(i >> 7u & 0xFFu)
                var newci : CallInfo?
                var b : int = int(i >> 16u & 0xFFu)
                var nresults : int = int(i >> 24u & 0xFFu) - 1
                if (b != 0) {
                    L.top.p = ra + b
                }
                ci.u.l.savedpc = pc
                newci = luaD_precall(L, ra, nresults)
                if (newci == null) {
                    trap = c_volatile_load(ci.u.l.trap)
                } else {
                    ci = newci                               // goto startfunc:
                    trap = c_volatile_load(L.hookmask)
                    break
                }
            } elif (op == OpCode.OP_TAILCALL) {
                // ... as today up to luaD_pretailcall
                n = luaD_pretailcall(L, ci, ra, b, delta)
                if (n < 0) {
                    trap = c_volatile_load(L.hookmask)       // goto startfunc
                    break
                }
                ci.func.p = ci.func.p - delta
                luaD_poscall(L, ci, n)
                trap = c_volatile_load(ci.u.l.trap)
                if ((int(ci.callstatus) & CIST_FRESH) != 0) { // goto ret: return from a Lua function
                    return
                }
                ci = ci.previous                             // goto returning
                break
            } elif (op == OpCode.OP_RETURN) {
                // ... as today up to luaD_poscall
                luaD_poscall(L, ci, n)
                trap = c_volatile_load(ci.u.l.trap)
                if ((int(ci.callstatus) & CIST_FRESH) != 0) { // ret:
                    return
                }
                ci = ci.previous
                break
            }
            // OP_RETURN0, OP_RETURN1: the same three-line `ret` tail ends each
            // OP_TFORPREP / OP_TFORCALL / OP_TFORLOOP: see the note, `l_tforcall` and
            // `l_tforloop` are the next two opcodes' bodies inlined (P7.0c keeps them as
            // `_goto = 2/3` cases)
        }
    }
}

// The same frame with a long `ret` tail, when the coder prefers one copy of it: the exit reason
// is a named bool, tested after the dispatch loop. Two lines more per return site than today's
// `_goto = 1; goto label 1`, no re-dispatch, no label.
//
//     var returned = false
//     while (true) {                                   // returning:
//         ...
//         while (true) {
//             ...
//             } elif (op == OpCode.OP_RETURN) {
//                 ...
//                 returned = true                      // goto ret
//                 break
//             }
//         }
//         if (returned) {                              // ret:
//             if ((int(ci.callstatus) & CIST_FRESH) != 0) {
//                 return
//             }
//             ci = ci.previous
//             returned = false                         // goto returning
//         }
//     }
