options gen2
require dastest/testing_boost public
require _daslang_child
require daslib/fio
require strings
require daslib/strings_boost
require daslib/ast
require daslib/ast_boost

// das's `*p` beside `deref(p)` (docs/probe-findings.md F102): two functions whose bodies differ only
// in that spelling, a read, a store, a compound store, a field through `(*q)` and a double one
let private STAR_SOURCE = "options gen2\n\nstruct V \{\n    x : int\n\}\n\ndef by_star(var p : int?; var q : V?; var pp : int??) : int \{\n    unsafe \{\n        *p = 5\n        *p += 2\n        (*q).x = *p\n        **pp = 1\n        return *p + (*q).x\n    \}\n\}\n\ndef by_deref(var p : int?; var q : V?; var pp : int??) : int \{\n    unsafe \{\n        deref(p) = 5\n        deref(p) += 2\n        deref(q).x = deref(p)\n        deref(deref(pp)) = 1\n        return deref(p) + deref(q).x\n    \}\n\}\n"

// the node kinds of each function's body in visit order, and the calls the bodies make
class private Shapes : AstVisitor {
    current : string
    kinds : table<string; array<string>>
    calls : int
    def override preVisitFunction(fun : FunctionPtr) {
        current = string(fun.name)
    }
    def override preVisitExpression(expr : ExpressionPtr) {
        kinds[current] |> push(expr.__rtti)
    }
    def override preVisitExprCall(expr : ExprCall?) {
        calls++
    }
}

// a pointer step on every lvalue kind C gives one: a variable, a field, a field through a
// pointer, an array element, a pointee, a `[c_union]` member; an `int`, `uint`, `int64` or `uint64`
// count, a literal, a sum and a negated one; each prints its offset in elements from `g[0]`
let private STEPS_SOURCE = "options gen2\nrequire c_runtime/c_union\n\nstruct S \{\n    p : int?\n\}\n\n[c_union]\nstruct U \{\n    p : int?\n    n : int64\n\}\n\nvar g : int[32]\n\ndef off(p : int?) : int64 \{\n    unsafe \{\n        return int64(intptr(p) - intptr(addr(g[0]))) / 4l\n    \}\n\}\n\n[export]\ndef main \{\n    unsafe \{\n        var p : int? = addr(g[8])\n        let n = 3\n        let k = 2ul\n        let m = 5u\n        let l = -2l\n        p += n\n        p += k\n        p += m\n        p += l\n        p -= n + 1\n        p -= 2\n        p -= k\n        p += -n\n        p++\n        p--\n        var s = S(p = addr(g[0]))\n        s.p += 4\n        s.p++\n        s.p -= 1ul\n        var sp : S? = addr(s)\n        sp.p += 2\n        sp.p--\n        var arr : int? [2]\n        arr[1] = addr(g[0])\n        arr[1] += 6\n        arr[1]--\n        var held : int? = addr(g[0])\n        var pp : int?? = addr(held)\n        *pp += 3\n        (*pp)++\n        var u : U\n        u.p = addr(g[0])\n        u.p += 7\n        u.p++\n        u.p -= 2\n        print(\"\{off(p)\} \{off(s.p)\} \{off(arr[1])\} \{off(held)\} \{off(u.p)\}\\n\")\n        g[9] = 40\n        g[5] = 55\n        var q = addr(g[9])\n        print(\"\{80 / *q\} \{3 * *q\} \{-*q\} \{*s.p\} \{*sp.p\} \{*arr[1]\}\\n\")\n        *q++\n        print(\"\{off(q)\} \{g[9]\}\\n\")\n    \}\n\}\n"

[test]
def test_star_is_deref(t : T?) {
    t |> run("`*p` and `deref(p)` compile to the same nodes in the same order, no call among them (F102)") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_star", dir_error)
        t |> equal(dir_error, "")
        let path = path_join(dir, "star.das")
        fwrite(path, STAR_SOURCE)
        var inscope access <- make_file_access("")
        using() $(var mg : ModuleGroup) {
            using() $(var cop : CodeOfPolicies) {
                cop.no_optimizations = true
                cop.export_all = true
                compile_file(path, access, unsafe(addr(mg)), cop) $(ok, program, output) {
                    t |> success(ok, string(output))
                    var shapes = new Shapes()
                    make_visitor(*shapes) $(adapter) {
                        visit(program, adapter)
                    }
                    let star <- shapes.kinds?["by_star"] ?? default<array<string>>
                    let der <- shapes.kinds?["by_deref"] ?? default<array<string>>
                    t |> success(!empty(star))
                    t |> equal(join(star, " "), join(der, " "))
                    t |> equal(length([for (k in star); k; where k == "ExprPtr2Ref"]), 8)
                    t |> equal(shapes.calls, 0)
                    unsafe {
                        delete shapes
                    }
                }
            }
        }
        rmdir_rec(dir)
    }
}

[test]
def test_pointer_steps(t : T?) {
    t |> run("`+=`, `-=`, `++` and `--` step a pointer on every lvalue kind by any integer count, under the interpreter and the JIT; `*s.p` and `*a[i]` are `*(s.p)` and `*(a[i])` as in C, but `*q++` is `(*q)++` (F102)") @(t : T?) {
        let expected = "5 5 5 4 6\n2 120 -40 55 55 55\n9 41\n"
        let interp = runtime_child("steps_interp", STEPS_SOURCE, false)
        t |> equal(interp.rc, 0, interp.out)
        t |> equal(program_output(interp.out), expected, interp.out)
        let jit = runtime_child_flags("steps_jit", STEPS_SOURCE, jit_flags())
        t |> success(jit_ran(jit.out), jit.out)
        t |> equal(program_output(jit.out), expected, jit.out)
    }
}
