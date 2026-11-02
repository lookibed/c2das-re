// 02-temporaries: hand-written das for two real Lua functions, the shape the proposed rules
// emit. Not compiled; the names and the `addr(b).n` spelling are today's (critic [^7] is
// another topic). Rules: T1 sink a postfix step below its one reader, T2 a discarded `a || f()`
// is an `if`, T3 `1 != 0` is `true`, B1 a nested bare block loses its braces.

// lstrlib.c:1283-1284, `luaL_addchar(&b, *strfrmt++)` inside str_format (today lstrlib.das:1303-1309)
        if (int(deref(strfrmt)) != 37) {
            if (!(addr(b).n < addr(b).size)) {
                luaL_prepbuffsize(addr(b), uint64(1))
            }
            deref(addr(b).b + addr(b).n) = deref(strfrmt)
            addr(b).n++
            strfrmt = strfrmt + 1
        } else {

// lvm.c:123-131 luaV_flttointeger's `lua_numbertointeger(f, p)` (today lvm.das.inc:36-41)
    var _t0 = f >= double(-9223372036854775807l - 1l) && f < -double(-9223372036854775807l - 1l)
    if (_t0) {
        deref(p) = int64(f)
        _t0 = true
    }
    return _t0 ? 1 : 0

// ldo.c:91-108 luaD_seterrorobj (today ldo.das.inc:15-41): every case body was `{ { ... } }`
def luaD_seterrorobj(var L : lua_State?; errcode : int; var oldtop : StackValue?) {
    let _cond = errcode
    if (_cond == 4) {
        var io : TValue? = addr(oldtop.val)
        var x_ : TString? = L.l_G.memerrmsg
        io.value_.gc = addr(reinterpret<GCUnion?>(x_).gc)
        io.tt_ = uint8(int(x_.tt) | 1 << 6)
    } elif (_cond == 0) {
        addr(oldtop.val).tt_ = uint8(0 | 0 << 4)
    } else {
        var io1 : TValue? = addr(oldtop.val)
        var io2 : TValue? = addr((L.top.p - 1).val)
        io1.value_ = io2.value_
        io1.tt_ = io2.tt_
    }
    L.top.p = oldtop + 1
}

// lvm.c:1588 `checkGC(L, L->top.p)` in OP_CONCAT (today lvm.das.inc:2863-2870): rule S1 drops
// the identity store, B1 the two bare blocks
                        if (L.l_G.GCdebt > int64(0)) {
                            ci.u.l.savedpc = pc
                            luaC_step(L)
                            trap = c_volatile_load(ci.u.l.trap)
                        }

// lstrlib.c nospecials's `do { ... } while (upto <= l)` (today lstrlib.das:885-892): rule T4,
// no `continue` in the body, so the condition moves to the bottom and the flag goes
    while (true) {
        if (crt::strpbrk(p + upto, reinterpret<uint8?>("^$*+?.([%-")) != null) {
            return 0
        }
        upto += crt::strlen(p + upto) + uint64(1)
        if (!(upto <= l)) {
            break
        }
    }
