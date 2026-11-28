/* a function-like name at the end of an expansion picks up '(' from the source after it */
#define fn(x) <x>
#define name fn
#define nest name(name)
name(1) nest(2) nest
(3)
#define rec(x) x rec
rec(1)(2)(3)
