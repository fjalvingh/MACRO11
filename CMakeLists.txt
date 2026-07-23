cmake_minimum_required(VERSION 3.10)
project(macro11 C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

set(MACRO11_SRCS
    src/macro11.c
    src/assemble.c
    src/assemble_globals.c
    src/assemble_aux.c
    src/extree.c
    src/listing.c
    src/macros.c
    src/parse.c
    src/rept_irpc.c
    src/symbols.c
    src/mlb.c
    src/object.c
    src/stream2.c
    src/util.c
    src/rad50.c
)

set(DUMPOBJ_SRCS
    src/dumpobj.c
    src/rad50.c
)

add_executable(macro11 ${MACRO11_SRCS})
target_link_libraries(macro11 m)

add_executable(dumpobj ${DUMPOBJ_SRCS})
