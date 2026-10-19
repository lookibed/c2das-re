// dasCRuntime: the C runtime library bound into daslang as module `crt`, one addExtern per
// forwarder of dasCRuntime.h and nothing else.
#include "daScript/daScript.h"
#include "daScript/ast/ast_interop.h"
#include "dasCRuntime.h"

using namespace das;


class Module_CRT : public Module {
public:
    Module_CRT() : Module("crt") {
        ModuleLibrary lib(this);
        lib.addBuiltInModule();
        using namespace crt;
        addExtern<DAS_BIND_FUN(c_malloc)>(*this, lib, "malloc", SideEffects::modifyExternal, "crt::c_malloc")->args({"size"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_calloc)>(*this, lib, "calloc", SideEffects::modifyExternal, "crt::c_calloc")->args({"count", "size"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_realloc)>(*this, lib, "realloc", SideEffects::modifyExternal, "crt::c_realloc")->args({"ptr", "size"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_free)>(*this, lib, "free", SideEffects::modifyExternal, "crt::c_free")->args({"ptr"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_memcpy)>(*this, lib, "memcpy", SideEffects::modifyExternal, "crt::c_memcpy")->args({"dst", "src", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_memmove)>(*this, lib, "memmove", SideEffects::modifyExternal, "crt::c_memmove")->args({"dst", "src", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_memset)>(*this, lib, "memset", SideEffects::modifyExternal, "crt::c_memset")->args({"dst", "value", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_memcmp)>(*this, lib, "memcmp", SideEffects::none, "crt::c_memcmp")->args({"a", "b", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_memchr)>(*this, lib, "memchr", SideEffects::none, "crt::c_memchr")->args({"s", "c", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strlen)>(*this, lib, "strlen", SideEffects::none, "crt::c_strlen")->args({"s"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strcpy)>(*this, lib, "strcpy", SideEffects::modifyExternal, "crt::c_strcpy")->args({"dst", "src"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strncpy)>(*this, lib, "strncpy", SideEffects::modifyExternal, "crt::c_strncpy")->args({"dst", "src", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strcat)>(*this, lib, "strcat", SideEffects::modifyExternal, "crt::c_strcat")->args({"dst", "src"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strncat)>(*this, lib, "strncat", SideEffects::modifyExternal, "crt::c_strncat")->args({"dst", "src", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strcmp)>(*this, lib, "strcmp", SideEffects::none, "crt::c_strcmp")->args({"a", "b"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strncmp)>(*this, lib, "strncmp", SideEffects::none, "crt::c_strncmp")->args({"a", "b", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strchr)>(*this, lib, "strchr", SideEffects::none, "crt::c_strchr")->args({"s", "c"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strrchr)>(*this, lib, "strrchr", SideEffects::none, "crt::c_strrchr")->args({"s", "c"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strstr)>(*this, lib, "strstr", SideEffects::none, "crt::c_strstr")->args({"s", "needle"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strerror)>(*this, lib, "strerror", SideEffects::modifyExternal, "crt::c_strerror")->args({"errnum"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strtol)>(*this, lib, "strtol", SideEffects::modifyExternal, "crt::c_strtol")->args({"s", "end", "base"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strtoul)>(*this, lib, "strtoul", SideEffects::modifyExternal, "crt::c_strtoul")->args({"s", "end", "base"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strtoll)>(*this, lib, "strtoll", SideEffects::modifyExternal, "crt::c_strtoll")->args({"s", "end", "base"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strtoull)>(*this, lib, "strtoull", SideEffects::modifyExternal, "crt::c_strtoull")->args({"s", "end", "base"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_strtod)>(*this, lib, "strtod", SideEffects::modifyExternal, "crt::c_strtod")->args({"s", "end"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_atoi)>(*this, lib, "atoi", SideEffects::none, "crt::c_atoi")->args({"s"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_atol)>(*this, lib, "atol", SideEffects::none, "crt::c_atol")->args({"s"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_atof)>(*this, lib, "atof", SideEffects::none, "crt::c_atof")->args({"s"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_abs)>(*this, lib, "abs", SideEffects::none, "crt::c_abs")->args({"v"});
        addExtern<DAS_BIND_FUN(c_llabs)>(*this, lib, "llabs", SideEffects::none, "crt::c_llabs")->args({"v"});
        addExtern<DAS_BIND_FUN(c_getenv)>(*this, lib, "getenv", SideEffects::modifyExternal, "crt::c_getenv")->args({"name"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_rand)>(*this, lib, "rand", SideEffects::modifyExternal, "crt::c_rand");
        addExtern<DAS_BIND_FUN(c_srand)>(*this, lib, "srand", SideEffects::modifyExternal, "crt::c_srand")->args({"seed"});
        addExtern<DAS_BIND_FUN(c_errno)>(*this, lib, "c_errno", SideEffects::modifyExternal, "crt::c_errno");
        addExtern<DAS_BIND_FUN(c_set_errno)>(*this, lib, "c_set_errno", SideEffects::modifyExternal, "crt::c_set_errno")->args({"value"});
        addExtern<DAS_BIND_FUN(c_time)>(*this, lib, "time", SideEffects::modifyExternal, "crt::c_time");
        addExtern<DAS_BIND_FUN(c_clock)>(*this, lib, "clock", SideEffects::modifyExternal, "crt::c_clock");
        addExtern<DAS_BIND_FUN(c_fwrite_stdout)>(*this, lib, "fwrite_stdout", SideEffects::modifyExternal, "crt::c_fwrite_stdout")->args({"data", "n"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_fflush_stdout)>(*this, lib, "fflush_stdout", SideEffects::modifyExternal, "crt::c_fflush_stdout");
        addConstant(*this, "LONG_BITS", int32_t(sizeof(long) * 8));
        addConstant(*this, "CLOCKS_PER_SEC", int64_t(CLOCKS_PER_SEC));
        addConstant(*this, "RAND_MAX", int32_t(RAND_MAX));
        addConstant(*this, "EDOM", int32_t(EDOM));
        addConstant(*this, "ERANGE", int32_t(ERANGE));
        addConstant(*this, "EINVAL", int32_t(EINVAL));
        addExtern<DAS_BIND_FUN(c_fmod)>(*this, lib, "fmod", SideEffects::none, "crt::c_fmod")->args({"a", "b"});
        addExtern<DAS_BIND_FUN(c_fmodf)>(*this, lib, "fmodf", SideEffects::none, "crt::c_fmodf")->args({"a", "b"});
        addExtern<DAS_BIND_FUN(c_frexp)>(*this, lib, "frexp", SideEffects::modifyExternal, "crt::c_frexp")->args({"v", "exp"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_ldexp)>(*this, lib, "ldexp", SideEffects::none, "crt::c_ldexp")->args({"v", "exp"});
        addExtern<DAS_BIND_FUN(c_modf)>(*this, lib, "modf", SideEffects::modifyExternal, "crt::c_modf")->args({"v", "ipart"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_nextafter)>(*this, lib, "nextafter", SideEffects::none, "crt::c_nextafter")->args({"from", "to"});
        addExtern<DAS_BIND_FUN(c_hypot)>(*this, lib, "hypot", SideEffects::none, "crt::c_hypot")->args({"a", "b"});
        addExtern<DAS_BIND_FUN(c_cbrt)>(*this, lib, "cbrt", SideEffects::none, "crt::c_cbrt")->args({"v"});
        addExtern<DAS_BIND_FUN(c_expm1)>(*this, lib, "expm1", SideEffects::none, "crt::c_expm1")->args({"v"});
        addExtern<DAS_BIND_FUN(c_log1p)>(*this, lib, "log1p", SideEffects::none, "crt::c_log1p")->args({"v"});
        addExtern<DAS_BIND_FUN(c_copysign)>(*this, lib, "copysign", SideEffects::none, "crt::c_copysign")->args({"v", "sign"});
        addExtern<DAS_BIND_FUN(c_remainder)>(*this, lib, "remainder", SideEffects::none, "crt::c_remainder")->args({"a", "b"});
        addExtern<DAS_BIND_FUN(c_trunc)>(*this, lib, "trunc", SideEffects::none, "crt::c_trunc")->args({"v"});
        addExtern<DAS_BIND_FUN(c_round)>(*this, lib, "round", SideEffects::none, "crt::c_round")->args({"v"});
        addExtern<DAS_BIND_FUN(c_erf)>(*this, lib, "erf", SideEffects::none, "crt::c_erf")->args({"v"});
        addExtern<DAS_BIND_FUN(c_erfc)>(*this, lib, "erfc", SideEffects::none, "crt::c_erfc")->args({"v"});
        addExtern<DAS_BIND_FUN(c_tgamma)>(*this, lib, "tgamma", SideEffects::none, "crt::c_tgamma")->args({"v"});
        addExtern<DAS_BIND_FUN(c_lgamma)>(*this, lib, "lgamma", SideEffects::none, "crt::c_lgamma")->args({"v"});
        addExtern<DAS_BIND_FUN(c_fma)>(*this, lib, "fma", SideEffects::none, "crt::c_fma")->args({"a", "b", "c"});
        addExtern<DAS_BIND_FUN(c_isalpha)>(*this, lib, "isalpha", SideEffects::none, "crt::c_isalpha")->args({"c"});
        addExtern<DAS_BIND_FUN(c_isdigit)>(*this, lib, "isdigit", SideEffects::none, "crt::c_isdigit")->args({"c"});
        addExtern<DAS_BIND_FUN(c_isalnum)>(*this, lib, "isalnum", SideEffects::none, "crt::c_isalnum")->args({"c"});
        addExtern<DAS_BIND_FUN(c_isspace)>(*this, lib, "isspace", SideEffects::none, "crt::c_isspace")->args({"c"});
        addExtern<DAS_BIND_FUN(c_isupper)>(*this, lib, "isupper", SideEffects::none, "crt::c_isupper")->args({"c"});
        addExtern<DAS_BIND_FUN(c_islower)>(*this, lib, "islower", SideEffects::none, "crt::c_islower")->args({"c"});
        addExtern<DAS_BIND_FUN(c_isxdigit)>(*this, lib, "isxdigit", SideEffects::none, "crt::c_isxdigit")->args({"c"});
        addExtern<DAS_BIND_FUN(c_ispunct)>(*this, lib, "ispunct", SideEffects::none, "crt::c_ispunct")->args({"c"});
        addExtern<DAS_BIND_FUN(c_isprint)>(*this, lib, "isprint", SideEffects::none, "crt::c_isprint")->args({"c"});
        addExtern<DAS_BIND_FUN(c_iscntrl)>(*this, lib, "iscntrl", SideEffects::none, "crt::c_iscntrl")->args({"c"});
        addExtern<DAS_BIND_FUN(c_toupper)>(*this, lib, "toupper", SideEffects::none, "crt::c_toupper")->args({"c"});
        addExtern<DAS_BIND_FUN(c_tolower)>(*this, lib, "tolower", SideEffects::none, "crt::c_tolower")->args({"c"});
        addExtern<DAS_BIND_FUN(c_snprintf_none)>(*this, lib, "snprintf_none", SideEffects::modifyExternal, "crt::c_snprintf_none")->args({"buf", "size", "fmt"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_int)>(*this, lib, "snprintf_int", SideEffects::modifyExternal, "crt::c_snprintf_int")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_uint)>(*this, lib, "snprintf_uint", SideEffects::modifyExternal, "crt::c_snprintf_uint")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_int64)>(*this, lib, "snprintf_int64", SideEffects::modifyExternal, "crt::c_snprintf_int64")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_uint64)>(*this, lib, "snprintf_uint64", SideEffects::modifyExternal, "crt::c_snprintf_uint64")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_double)>(*this, lib, "snprintf_double", SideEffects::modifyExternal, "crt::c_snprintf_double")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_str)>(*this, lib, "snprintf_str", SideEffects::modifyExternal, "crt::c_snprintf_str")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_snprintf_ptr)>(*this, lib, "snprintf_ptr", SideEffects::modifyExternal, "crt::c_snprintf_ptr")->args({"buf", "size", "fmt", "v"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_sscanf_one)>(*this, lib, "sscanf_one", SideEffects::modifyExternal, "crt::c_sscanf_one")->args({"src", "fmt", "out", "consumed"})->unsafeOperation = true;
        addExtern<DAS_BIND_FUN(c_sscanf_none)>(*this, lib, "sscanf_none", SideEffects::modifyExternal, "crt::c_sscanf_none")->args({"src", "fmt", "consumed"})->unsafeOperation = true;
    }
    virtual ModuleAotType aotRequire(TextWriter & tw) const override {
        tw << "#include \"dasCRuntime.h\"\n";
        return ModuleAotType::cpp;
    }
};

REGISTER_MODULE(Module_CRT);
REGISTER_DYN_MODULE(Module_CRT, Module_CRT);
