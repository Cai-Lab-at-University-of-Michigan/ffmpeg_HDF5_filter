cmake_minimum_required(VERSION 2.10)
project(ffmpeg_hdf5)

# Set where to find ffmpeg related packages
#set(FFMPEG_BUILD_PATH ~/ffmpeg_build)

# We have to manually set paths since ffmpeg doesn't support find_package in CMake
find_path(
    AVCODEC_INCLUDE_DIR
    NAMES "libavcodec/avcodec.h"
    PATHS "${FFMPEG_BUILD_PATH}/include"
    NO_DEFAULT_PATH)
find_library(
    AVCODEC_LIBRARY
    NAMES libavcodec.so
    PATHS "${FFMPEG_BUILD_PATH}/lib"
    NO_DEFAULT_PATH)

find_path(
    SWSCALE_INCLUDE_DIR
    NAMES "libswscale/swscale.h"
    PATHS "${FFMPEG_BUILD_PATH}/include"
    NO_DEFAULT_PATH)

find_library(
    SWSCALE_LIBRARY
    NAMES libswscale.so
    PATHS "${FFMPEG_BUILD_PATH}/lib"
    NO_DEFAULT_PATH)

find_path(
    AVFORMAT_INCLUDE_DIR
    NAMES "libavformat/avformat.h"
    PATHS "${FFMPEG_BUILD_PATH}/include"
    NO_DEFAULT_PATH)
find_library(
    AVFORMAT_LIBRARY
    NAMES libavformat.so
    PATHS "${FFMPEG_BUILD_PATH}/lib"
    NO_DEFAULT_PATH)

find_path(
        AVUTIL_INCLUDE_DIR
        NAMES "libavutil/opt.h"
        PATHS "${FFMPEG_BUILD_PATH}/include"
        NO_DEFAULT_PATH)
find_library(
        AVUTIL_LIBRARY
        NAMES libavutil.so
        PATHS "${FFMPEG_BUILD_PATH}/lib"
        NO_DEFAULT_PATH)

# Want to see more output from make
set(CMAKE_VERBOSE_MAKEFILE ON)

# options
option(BUILD_TESTS "Build test programs form the ffmpeg filter" ON)

option(BUILD_PLUGIN "Build dynamically loadable plugin for HDF5 version > 1.12.9" ON)

if(BUILD_PLUGIN)
    set(PLUGIN_INSTALL_PATH "~/hdf5_plugin"
            CACHE PATH "Where to install the dynamic HDF5-plugin")
endif(BUILD_PLUGIN)

# sources
set(SOURCES src/ffmpeg_h5filter.c)
set(PLUGIN_SOURCES src/ffmpeg_h5filter.c src/ffmpeg_h5plugin.c )

# dependencies
if(MSVC)
    # FindHDF5.cmake does not find Windows installations. Try to
    # use an environment variable instead until the official "find"
    # file can be updated for Windows.
    #
    # Note that you have to set this environment variable by hand.
    file(TO_CMAKE_PATH "$ENV{HDF5_DIR}" HDF5_HINT)
    set(HDF5_DIR ${HDF5_HINT} CACHE STRING "Path to HDF5 CMake config directory.")
    find_package(HDF5 REQUIRED HINTS ${HDF5_DIR})
else(MSVC)
    find_package(HDF5 REQUIRED)
endif(MSVC)
include_directories(${HDF5_INCLUDE_DIRS})
include_directories(${AVCODEC_INCLUDE_DIR})
include_directories(${SWSCALE_INCLUDE_DIR})
include_directories(${AVFORMAT_INCLUDE_DIR})
include_directories(${AVUTIL_INCLUDE_DIR})

add_library(ffmpeg_filter_shared SHARED ${SOURCES})
set_target_properties(ffmpeg_filter_shared PROPERTIES OUTPUT_NAME ffmpeg_h5filter)
target_link_libraries(ffmpeg_filter_shared ${AVCODEC_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})

if(BUILD_PLUGIN)
    add_library(ffmpeg_plugin_shared SHARED ${PLUGIN_SOURCES})
    set_target_properties(
            ffmpeg_plugin_shared PROPERTIES OUTPUT_NAME ffmpeg_h5plugin)
    target_link_libraries(ffmpeg_plugin_shared ffmpeg_filter_shared ${AVCODEC_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})

    install(TARGETS ffmpeg_plugin_shared DESTINATION ${PLUGIN_INSTALL_PATH} COMPONENT HDF5_FILTER_DEV)
endif(BUILD_PLUGIN)

# install
install(FILES src/ffmpeg_h5filter.h DESTINATION include COMPONENT HDF5_FILTER_DEV)
install(TARGETS ffmpeg_filter_shared DESTINATION lib COMPONENT HDF5_FILTER_DEV)

# test
message("LINK LIBRARIES='ffmpeg_filter_shared ${HDF5_LIBRARIES}'")
if(BUILD_TESTS)
    enable_testing()
    add_executable(example src/example.c)
    target_link_libraries(example ffmpeg_filter_shared ${AVCODEC_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})
    add_test(test_hdf5_filter example)
endif(BUILD_TESTS)
if(BUILD_TESTS)
    enable_testing()
    add_executable(encode src/encode_video.c)
    target_link_libraries(encode ffmpeg_filter_shared ${AVCODEC_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})
    add_test(test_hdf5_filter encode)
endif(BUILD_TESTS)
if(BUILD_TESTS)
    enable_testing()
    add_executable(decode src/decode_video.c)
    target_link_libraries(decode ffmpeg_filter_shared ${AVCODEC_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})
    add_test(test_hdf5_filter decode)
endif(BUILD_TESTS)