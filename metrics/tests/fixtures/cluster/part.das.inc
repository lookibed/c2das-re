[c_function]
def fragment_sum(p : int?) : int {
    return deref(p + 1) + deref(p + 2)
}
