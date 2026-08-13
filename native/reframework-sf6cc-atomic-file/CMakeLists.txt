cmake_minimum_required(VERSION 3.24)

project(reframework_sf6cc_atomic_file LANGUAGES C CXX)

include(FetchContent)

set(
    REFRAMEWORK_COMMIT
    "a0e9010fb0449dc9d824b5978ee759eeaf50f7c6"
    CACHE STRING
    "REFramework commit whose plugin API and Lua ABI are used"
)
set(REFRAMEWORK_SOURCE_DIR "" CACHE PATH "Optional existing REFramework source checkout")

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
    message(FATAL_ERROR "REFramework Lua sources are missing")
endif()

file(GLOB REF_LUA_SOURCES CONFIGURE_DEPENDS "${REF_LUA_DIR}/l*.c")
list(REMOVE_ITEM REF_LUA_SOURCES "${REF_LUA_DIR}/lua.c" "${REF_LUA_DIR}/luac.c")
add_library(ref_lua_atomic STATIC ${REF_LUA_SOURCES})
target_include_directories(ref_lua_atomic PUBLIC "${REF_LUA_DIR}")

add_library(reframework_sf6cc_atomic_file SHARED src/plugin.cpp)
target_compile_features(reframework_sf6cc_atomic_file PRIVATE cxx_std_20)
target_compile_definitions(reframework_sf6cc_atomic_file PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_include_directories(reframework_sf6cc_atomic_file PRIVATE "${REFRAMEWORK_SOURCE_DIR}/include" "${REF_LUA_DIR}")
target_link_libraries(reframework_sf6cc_atomic_file PRIVATE ref_lua_atomic bcrypt)

if(MSVC)
    set_property(TARGET ref_lua_atomic reframework_sf6cc_atomic_file PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(reframework_sf6cc_atomic_file PRIVATE /W4 /permissive- /EHsc /utf-8)
endif()

set_target_properties(reframework_sf6cc_atomic_file PROPERTIES
    OUTPUT_NAME "reframework-sf6cc-atomic-file"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
