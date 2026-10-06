options gen2

module enum_from_int public

//! `enum_from_int(type<E>, i)`: the C implicit int-to-enum conversion. An out-of-range value
//! survives by value, compares by value and prints as `enum N`; the unsafe reinterpret lives
//! here so converted code carries none.
def enum_from_int(witness : auto(TT); v : int) : TT {
    return unsafe(reinterpret<TT>(v))
}
