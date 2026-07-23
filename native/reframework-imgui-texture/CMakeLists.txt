cmake_minimum_required(VERSION 3.24)

project(reframework_imgui_texture LANGUAGES C CXX)

include(FetchContent)

set(
    REFRAMEWORK_COMMIT
    "a0e9010fb0449dc9d824b5978ee759eeaf50f7c6"
    CACHE STRING
    "REFramework commit whose plugin API and Lua ABI are used"
)
set(
    REFRAMEWORK_SOURCE_DIR
    ""
    CACHE PATH
    "Optional existing REFramework source checkout"
)

if(NOT EXISTS "${REFRAMEWORK_SOURCE_DIR}/include/reframework/API.h")
    FetchContent_Declare(
        reframework_source
        GIT_REPOSITORY https://github.com/praydog/REFramework.git
        GIT_TAG "${REFRAMEWORK_COMMIT}"
        GIT_SHALLOW TRUE
        GIT_SUBMODULES dependencies/lua
        GIT_SUBMODULES_RECURSE FALSE
    )
    FetchContent_GetProperties(reframework_source)
    if(NOT reframework_source_POPULATED)
        FetchContent_Populate(reframework_source)
    endif()
    set(REFRAMEWORK_SOURCE_DIR "${reframework_source_SOURCE_DIR}")
endif()

set(REF_LUA_DIR "${REFRAMEWORK_SOURCE_DIR}/dependencies/lua/src")
if(NOT EXISTS "${REF_LUA_DIR}/lua.h")
    message(
        FATAL_ERROR
        "REFramework Lua sources are missing. Initialize dependencies/lua or "
        "configure with -DREFRAMEWORK_SOURCE_DIR=<checkout>."
    )
endif()

set(REF_LUA_SOURCES
    "${REF_LUA_DIR}/lapi.c"
    "${REF_LUA_DIR}/lauxlib.c"
    "${REF_LUA_DIR}/lbaselib.c"
    "${REF_LUA_DIR}/lcode.c"
    "${REF_LUA_DIR}/lcorolib.c"
    "${REF_LUA_DIR}/lctype.c"
    "${REF_LUA_DIR}/ldblib.c"
    "${REF_LUA_DIR}/ldebug.c"
    "${REF_LUA_DIR}/ldo.c"
    "${REF_LUA_DIR}/ldump.c"
    "${REF_LUA_DIR}/lfunc.c"
    "${REF_LUA_DIR}/lgc.c"
    "${REF_LUA_DIR}/linit.c"
    "${REF_LUA_DIR}/liolib.c"
    "${REF_LUA_DIR}/llex.c"
    "${REF_LUA_DIR}/lmathlib.c"
    "${REF_LUA_DIR}/lmem.c"
    "${REF_LUA_DIR}/loadlib.c"
    "${REF_LUA_DIR}/lobject.c"
    "${REF_LUA_DIR}/lopcodes.c"
    "${REF_LUA_DIR}/loslib.c"
    "${REF_LUA_DIR}/lparser.c"
    "${REF_LUA_DIR}/lstate.c"
    "${REF_LUA_DIR}/lstring.c"
    "${REF_LUA_DIR}/lstrlib.c"
    "${REF_LUA_DIR}/ltable.c"
    "${REF_LUA_DIR}/ltablib.c"
    "${REF_LUA_DIR}/ltm.c"
    "${REF_LUA_DIR}/lundump.c"
    "${REF_LUA_DIR}/lutf8lib.c"
    "${REF_LUA_DIR}/lvm.c"
    "${REF_LUA_DIR}/lzio.c"
)

add_library(ref_lua STATIC ${REF_LUA_SOURCES})
target_include_directories(ref_lua PUBLIC "${REF_LUA_DIR}")

add_library(reframework_imgui_texture SHARED src/plugin.cpp)
target_compile_features(reframework_imgui_texture PRIVATE cxx_std_20)
target_compile_definitions(
    reframework_imgui_texture
    PRIVATE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
        UNICODE
        _UNICODE
)
target_include_directories(
    reframework_imgui_texture
    PRIVATE
        "${REFRAMEWORK_SOURCE_DIR}/include"
        "${REFRAMEWORK_SOURCE_DIR}/src/cimgui"
        "${REF_LUA_DIR}"
)
target_link_libraries(
    reframework_imgui_texture
    PRIVATE
        ref_lua
        windowscodecs
        ole32
)

if(MSVC)
    set_property(
        TARGET ref_lua reframework_imgui_texture
        PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
    target_compile_options(
        reframework_imgui_texture
        PRIVATE
            /W4
            /permissive-
            /EHsc
            /utf-8
    )
endif()

set_target_properties(
    reframework_imgui_texture
    PROPERTIES
        OUTPUT_NAME "reframework-imgui-texture"
        PREFIX ""
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
