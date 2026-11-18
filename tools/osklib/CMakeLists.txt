# SPDX-License-Identifier: GPL-2.0-only
# osklib (KR-2 display layer, KR-3 input + uinput keyboard) for the Redux global OSK. C99, no libraries beyond libc
# and the Linux uapi headers. Host build: cmake -S tools/osklib -B build && cmake --build build && ctest --test-dir build
cmake_minimum_required(VERSION 3.16)
project(osklib C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra -Werror -pedantic)
endif()

# Redux's layout (frontend/term/osk.c + osk.h). Tests use the copy in tests/redux (Redux dd65506, unchanged);
# Redux builds against its own split copy instead: set OSK_LAYOUT_DIR.
set(OSK_LAYOUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests/redux" CACHE PATH "directory with osk.c and osk.h")

add_library(osklib STATIC
  src/osk_sys.c src/osk_disp.c src/osk_in.c src/osk_kbd.c ${OSK_LAYOUT_DIR}/osk.c)
target_include_directories(osklib PUBLIC src ${OSK_LAYOUT_DIR})

enable_testing()
foreach(t test_disp test_in test_kbd)
  add_executable(${t} tests/${t}.c tests/fake_sys.c)
  target_link_libraries(${t} osklib)
  add_test(NAME ${t} COMMAND ${t})
endforeach()
