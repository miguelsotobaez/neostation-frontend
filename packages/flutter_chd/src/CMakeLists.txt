# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(flutter_chd_library VERSION 0.0.1 LANGUAGES C)

set(CMAKE_C_STANDARD 99)

# libchdr ships an amalgamation that pulls in its own sources and its three
# vendored dependencies (LZMA, miniz, zstd) as one translation unit. Building
# through it keeps this file, the macOS forwarder and any future platform
# identical, and makes updating libchdr a directory swap.
add_library(flutter_chd SHARED
  "${CMAKE_CURRENT_SOURCE_DIR}/libchdr/unity.c"
  "flutter_chd.c"
)

target_include_directories(flutter_chd PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/libchdr/include"
)

set_target_properties(flutter_chd PROPERTIES
  PUBLIC_HEADER flutter_chd.h
  OUTPUT_NAME "flutter_chd"
)

target_compile_definitions(flutter_chd PUBLIC DART_SHARED_LIB)

if (MSVC)
  # libchdr and its dependencies use the standard C library's older names.
  target_compile_definitions(flutter_chd PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(flutter_chd PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")
endif()

if (NOT MSVC)
  find_library(MATH_LIBRARY m)
  if (MATH_LIBRARY)
    # The FLAC decoder used by CHD's cdfl codec needs libm.
    target_link_libraries(flutter_chd PRIVATE ${MATH_LIBRARY})
  endif()
endif()
