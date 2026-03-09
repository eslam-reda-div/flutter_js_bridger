cmake_minimum_required(VERSION 3.10)
project(quickjs_bridger C)

# QuickJS source directory — set this to your QuickJS source checkout
# Clone from: https://github.com/nicbarker/nicbarker-quickjs or
# https://bellard.org/quickjs/
set(QUICKJS_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/quickjs-src"
    CACHE PATH "Path to QuickJS source directory")

if(NOT EXISTS "${QUICKJS_SRC_DIR}/quickjs.h")
    message(FATAL_ERROR
        "QuickJS source not found at ${QUICKJS_SRC_DIR}\n"
        "Download QuickJS source and place it there, or set QUICKJS_SRC_DIR.\n"
        "See README for instructions.")
endif()

# QuickJS core sources
set(QUICKJS_SOURCES
    ${QUICKJS_SRC_DIR}/quickjs.c
    ${QUICKJS_SRC_DIR}/libregexp.c
    ${QUICKJS_SRC_DIR}/libunicode.c
    ${QUICKJS_SRC_DIR}/cutils.c
    ${QUICKJS_SRC_DIR}/libbf.c
)

# Our shim that provides the eval_to_string helper
set(SHIM_SOURCES
    quickjs_bridger_shim.c
)

# Build as shared library
add_library(quickjs SHARED
    ${QUICKJS_SOURCES}
    ${SHIM_SOURCES}
)

target_include_directories(quickjs PRIVATE ${QUICKJS_SRC_DIR})

# QuickJS compile definitions
target_compile_definitions(quickjs PRIVATE
    _GNU_SOURCE
    CONFIG_VERSION="2024-02-14"
    CONFIG_BIGNUM
)

# Optimize for size on Android
if(ANDROID)
    target_compile_options(quickjs PRIVATE -Os -fvisibility=hidden)
    target_link_options(quickjs PRIVATE -Wl,--gc-sections)
endif()

# Export only our shim symbols + the few QuickJS symbols we need
set_target_properties(quickjs PROPERTIES
    OUTPUT_NAME "quickjs"
    C_STANDARD 11
)
