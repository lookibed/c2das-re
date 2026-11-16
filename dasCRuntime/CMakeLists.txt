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

# the checkout's own header-visible ABI defines, shared by the native module and the wasm archive
set(DAS_CRT_ABI_DEFS DAS_ENABLE_DYN_INCLUDES=1 DAS_FUSION=2 SIZE_OF_VOID_P=${CMAKE_SIZEOF_VOID_P})

if(EMSCRIPTEN)
    # the wasm64 archive a cross-compiled program links (ARCHITECTURE.md section 8): the flags and
    # defines of the web runtime the checkout's `daspkg build --wasm` builds, memory64 and threaded
    set(DAS_CRT_WASM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/_wasm" CACHE PATH "where the wasm64 archive lands")
    add_library(dasModuleCRuntime STATIC src/dasCRuntime.cpp)
    target_compile_features(dasModuleCRuntime PRIVATE cxx_std_17)
    target_include_directories(dasModuleCRuntime PRIVATE "${DASLANG_ROOT}/include")
    target_compile_definitions(dasModuleCRuntime PRIVATE ${DAS_CRT_ABI_DEFS}
        DAS_NO_ASSERTIONS DAS_ENABLE_EXCEPTIONS _EMSCRIPTEN_VER)
    target_compile_options(dasModuleCRuntime PRIVATE -fno-rtti -fwrapv -fno-strict-aliasing
        -Wno-invalid-offsetof -Wall -Wextra -Wno-missing-field-initializers -Werror -msimd128 -mnontrapping-fptoint -fwasm-exceptions
        -sWASM_LEGACY_EXCEPTIONS=0 -sMEMORY64=1 -pthread)
    set_target_properties(dasModuleCRuntime PROPERTIES
        PREFIX "" OUTPUT_NAME "liblibDasModuleCRuntime" SUFFIX ".a"
        ARCHIVE_OUTPUT_DIRECTORY "${DAS_CRT_WASM_DIR}")
    return()
endif()

# a daslang host built against libc++ with C++ exceptions (daScript's web/build_wasm_host.sh, the
# host that cross-compiles to wasm) loads only a module built the same way, kept in its own folder
option(DAS_CRT_LIBCXX_HOST "build for a libc++ + C++-exceptions daslang host, into _wasmhost/" OFF)

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
target_compile_definitions(dasModuleCRuntime PRIVATE ${DAS_CRT_ABI_DEFS})
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

set(DAS_CRT_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
if(DAS_CRT_LIBCXX_HOST)
    # RTTI stays off: the module references no typeinfo, so it loads into the RTTI host as well
    target_compile_definitions(dasModuleCRuntime PRIVATE DAS_ENABLE_EXCEPTIONS=1 _LIBCPP_DISABLE_DEPRECATION_WARNINGS)
    target_compile_options(dasModuleCRuntime PRIVATE -stdlib=libc++)
    target_link_options(dasModuleCRuntime PRIVATE -stdlib=libc++)
    set(DAS_CRT_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/_wasmhost")
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/.das_module" "${DAS_CRT_OUTPUT_DIR}/.das_module" COPYONLY)
    # daspkg finds a module's package beside its .shared_module; this copy builds from the folder above
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/.das_package" DAS_CRT_PACKAGE)
    string(REPLACE "CRT_SOURCE = \".\"" "CRT_SOURCE = \"..\"" DAS_CRT_PACKAGE "${DAS_CRT_PACKAGE}")
    file(WRITE "${DAS_CRT_OUTPUT_DIR}/.das_package" "${DAS_CRT_PACKAGE}")
endif()

set_target_properties(dasModuleCRuntime PROPERTIES
    SUFFIX ".shared_module"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${DAS_CRT_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${DAS_CRT_OUTPUT_DIR}"
)
