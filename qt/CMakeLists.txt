cmake_minimum_required(VERSION 3.21)
project(OpenFrame VERSION 0.5.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

option(OPENFRAME_BUILD_TESTS "Compila os testes" ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Concurrent)
qt_standard_project_setup(REQUIRES 6.8)

add_subdirectory(src/core)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/app/CMakeLists.txt")
    add_subdirectory(src/app)
endif()

if(OPENFRAME_BUILD_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)
    add_subdirectory(tests)
endif()
