/* The library sampler_stand_in.c's DLOPEN case loads: lib_run, the one exported function, calls
   spin, a static function placed after it, so in the library built stripped (-s) the nearest
   symbol before spin's code is lib_run, whose size ends before it. */
static unsigned spin(unsigned n);

unsigned lib_run(unsigned n)
{
    return spin(n) + 1u;
}

__attribute__((noinline)) static unsigned spin(unsigned n)
{
    unsigned x = 3;
    for (unsigned i = 0; i < n; i++)
        x = x * 22695477u + 1u;
    return x;
}
