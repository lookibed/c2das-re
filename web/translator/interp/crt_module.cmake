# c2das-re's crt (dasCRuntime/ of lookibed/c2das-re) linked into daslang_static: an in-tree wrapper for
# the translator page's Run only (web/ARCHITECTURE.md section 9). build_interp.sh copies it into a
# daScript checkout as modules/dasCRuntime/CMakeLists.txt, beside c2das-re's dasCRuntime/src; the
# flags are the ones c2das-re's standalone CMakeLists gives the wasm64 archive.
IF (NOT DAS_CRT_INCLUDED)
    SET(DAS_CRT_INCLUDED TRUE)
    MESSAGE(STATUS "dasCRuntime (c2das-re crt) module included.")
    SET(_crt_dir ${PROJECT_SOURCE_DIR}/modules/dasCRuntime)
    SET(DAS_CRT_MODULE_SRC ${_crt_dir}/src/dasCRuntime.cpp ${_crt_dir}/src/dasCRuntime.h)
    IF(EMSCRIPTEN)
        LIST(APPEND DAS_CRT_MODULE_SRC ${_crt_dir}/src/glibc_rand.cpp)
    ENDIF()
    ADD_MODULE_CPP(CRT)
    ADD_MODULE_LIB(libDasModuleCRuntime dasModuleCRuntime ${DAS_CRT_MODULE_SRC})
    SETUP_CPP11(libDasModuleCRuntime)
    target_compile_options(libDasModuleCRuntime PRIVATE -fwrapv -fno-strict-aliasing -Wno-invalid-offsetof)
ENDIF()
