cmake_minimum_required(VERSION 3.16)
project(dasCRuntime CXX)

# DASLANG_ROOT is the daScript checkout this repository binds to (scripts/env.sh)
if(NOT DEFINED DASLANG_ROOT)
    set(DASLANG_ROOT "$ENV{DASLANG_ROOT}")
endif()
if(NOT DASLANG_ROOT)
    message(FATAL_ERROR "DASLANG_ROOT must name the daScript checkout")
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_library(dasModuleCRuntime SHARED src/dasCRuntime.cpp)
target_compile_features(dasModuleCRuntime PRIVATE cxx_std_17)
target_compile_definitions(dasModuleCRuntime PRIVATE DAS_MOD_EXPORTS DAS_ENABLE_DLL=1
    $<$<CONFIG:Release>:DAS_NO_ASSERTIONS>
    $<$<CONFIG:MinSizeRel>:DAS_NO_ASSERTIONS>
    $<$<CONFIG:RelWithDebInfo>:DAS_NO_ASSERTIONS>
)
target_include_directories(dasModuleCRuntime PRIVATE "${DASLANG_ROOT}/include")

# the checkout's own ABI: it compiles without RTTI and with these header-visible defines, and a
# module linked against its runtime must match (a typeinfo reference is an undefined symbol)
target_compile_definitions(dasModuleCRuntime PRIVATE DAS_ENABLE_DYN_INCLUDES=1 DAS_FUSION=2 SIZE_OF_VOID_P=${CMAKE_SIZEOF_VOID_P})
if(NOT MSVC)
    target_compile_options(dasModuleCRuntime PRIVATE -fno-rtti -fwrapv -fno-strict-aliasing -Wno-invalid-offsetof -Wall -Wextra -Wno-missing-field-initializers -Werror)
    set_target_properties(dasModuleCRuntime PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON POSITION_INDEPENDENT_CODE ON)
endif()

# the checkout's own library names: liblibDaScriptDyn on Linux and macOS, libDaScriptDyn on Windows
file(GLOB DAS_DYN_LIBS
    "${DASLANG_ROOT}/lib/liblibDaScriptDyn.so" "${DASLANG_ROOT}/lib/liblibDaScriptDyn_runtime.so"
    "${DASLANG_ROOT}/lib/liblibDaScriptDyn.dylib" "${DASLANG_ROOT}/lib/liblibDaScriptDyn_runtime.dylib"
    "${DASLANG_ROOT}/lib/Release/libDaScriptDyn.lib" "${DASLANG_ROOT}/lib/Release/libDaScriptDyn_runtime.lib"
    "${DASLANG_ROOT}/lib/libDaScriptDyn.lib" "${DASLANG_ROOT}/lib/libDaScriptDyn_runtime.lib"
)
if(NOT DAS_DYN_LIBS)
    message(FATAL_ERROR "no libDaScriptDyn under ${DASLANG_ROOT}/lib: build the checkout first")
endif()
target_link_libraries(dasModuleCRuntime PRIVATE ${DAS_DYN_LIBS})

if(MSVC)
    target_compile_options(dasModuleCRuntime PRIVATE /wd4005 /EHsc)
endif()

set_target_properties(dasModuleCRuntime PROPERTIES
    SUFFIX ".shared_module"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
