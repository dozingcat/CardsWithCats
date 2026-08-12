# Builds the dds double-dummy solver (vendored in third_party/dds, plus
# our isolate-safety shim in cpp/) as libdds.so for each Android ABI.
# Invoked by Gradle via externalNativeBuild; the library loads by name
# from lib/bridge/dds_ffi.dart.
cmake_minimum_required(VERSION 3.10)
project(dds CXX)

set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

file(GLOB DDS_SOURCES "${REPO_ROOT}/third_party/dds/src/*.cpp")

add_library(dds SHARED ${DDS_SOURCES} "${REPO_ROOT}/cpp/dds_shim.cpp")

target_include_directories(dds PRIVATE
    "${REPO_ROOT}/third_party/dds/include"
    "${REPO_ROOT}/third_party/dds/src")

target_compile_definitions(dds PRIVATE DDS_THREADS_STL)
target_compile_options(dds PRIVATE -O2)
