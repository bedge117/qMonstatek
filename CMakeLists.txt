cmake_minimum_required(VERSION 3.21)
project(qmonstatek VERSION 2.1.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Qt6 modules
find_package(Qt6 REQUIRED COMPONENTS
    Core Gui Quick QuickControls2 SerialPort Network Widgets
)

option(BUILD_TESTS "Build unit tests" OFF)

add_subdirectory(src)

if(BUILD_TESTS)
    enable_testing()
    find_package(Qt6 COMPONENTS Test)
    if(Qt6Test_FOUND)
        add_subdirectory(tests)
    endif()
endif()
