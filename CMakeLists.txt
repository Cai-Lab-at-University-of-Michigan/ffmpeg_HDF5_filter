cmake_minimum_required(VERSION 2.10)
project(ffmpeg_hdf5)
set(CMAKE_BUILD_TYPE "Debug")

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
if (USE_VPL_ENCODER)
  list(APPEND CMAKE_PREFIX_PATH ${VPL_ROOT_DIR}/lib/cmake/vpl)
endif()

# Set where to find ffmpeg related packages
#set(FFMPEG_BUILD_PATH $ENV{HOME}/ffmpeg_build)

set(FFMPEG_INCLUDE_PATH "${FFMPEG_BUILD_PATH}/include")
set(FFMPEG_LIB_PATH "${FFMPEG_BUILD_PATH}/lib")

# We have to manually set paths since ffmpeg doesn't support find_package in CMake
# But don't worry, these following code will do it for you. :)
# Please just set FFMPEG_BUILD_PATH variable
find_path(
    AVCODEC_INCLUDE_DIR
    NAMES "libavcodec/avcodec.h"
    PATHS ${FFMPEG_INCLUDE_PATH}
    NO_DEFAULT_PATH)
find_library(
    AVCODEC_LIBRARY
    NAMES libavcodec.so
    PATHS ${FFMPEG_LIB_PATH}
    NO_DEFAULT_PATH)

find_path(
    AVDEVICE_INCLUDE_DIR
    NAMES "libavdevice/avdevice.h"
    PATHS ${FFMPEG_INCLUDE_PATH}
    NO_DEFAULT_PATH)
find_library(
    AVDEVICE_LIBRARY
    NAMES libavdevice.so
    PATHS ${FFMPEG_LIB_PATH}
    NO_DEFAULT_PATH)

find_path(
    SWSCALE_INCLUDE_DIR
    NAMES "libswscale/swscale.h"
    PATHS ${FFMPEG_INCLUDE_PATH}
    NO_DEFAULT_PATH)

find_library(
    SWSCALE_LIBRARY
    NAMES libswscale.so
    PATHS ${FFMPEG_LIB_PATH}
    NO_DEFAULT_PATH)

find_path(
    AVFORMAT_INCLUDE_DIR
    NAMES "libavformat/avformat.h"
    PATHS ${FFMPEG_INCLUDE_PATH}
    NO_DEFAULT_PATH)
find_library(
    AVFORMAT_LIBRARY
    NAMES libavformat.so
    PATHS ${FFMPEG_LIB_PATH}
    NO_DEFAULT_PATH)

find_path(
    AVUTIL_INCLUDE_DIR
    NAMES "libavutil/opt.h"
    PATHS ${FFMPEG_INCLUDE_PATH}
    NO_DEFAULT_PATH)
find_library(
    AVUTIL_LIBRARY
    NAMES libavutil.so
    PATHS ${FFMPEG_LIB_PATH}
    NO_DEFAULT_PATH)

# Want to see more output from make
set(CMAKE_VERBOSE_MAKEFILE ON)

# options
option(BUILD_TESTS "Build test programs from the ffmpeg filter" ON)

option(BUILD_PLUGIN "Build dynamically loadable plugin for HDF5 version >= 1.12.1" ON)

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
include_directories(${AVDEVICE_INCLUDE_DIR})
include_directories(${SWSCALE_INCLUDE_DIR})
include_directories(${AVFORMAT_INCLUDE_DIR})
include_directories(${AVUTIL_INCLUDE_DIR})

set(TARGET ffmpeg_filter_shared)

add_library(${TARGET} SHARED ${SOURCES})
set_target_properties(${TARGET} PROPERTIES OUTPUT_NAME ffmpeg_h5filter)

if (USE_VPL_ENCODER)
    find_package(VPL REQUIRED)
    target_link_libraries(${TARGET} VPL::dispatcher)
    target_compile_definitions(${TARGET} PUBLIC -DUSE_VPL2X_INIT)

    find_package(PkgConfig REQUIRED)
    # note: pkg-config version for libva is *API* version

    pkg_check_modules(PKG_LIBVA libva>=1.2)
    if(PKG_LIBVA_FOUND)
        target_compile_definitions(${TARGET} PUBLIC -DLIBVA_SUPPORT)
        target_link_libraries(${TARGET} ${PKG_LIBVA_LIBRARIES})
        target_include_directories(${TARGET} PUBLIC ${PKG_LIBVA_INCLUDEDIR})
    else()
        message(FATAL_ERROR "libva not found")
    endif()

    pkg_check_modules(PKG_LIBVADRM libva-drm>=1.2)
    if(PKG_LIBVADRM_FOUND)
        target_compile_definitions(${TARGET} PUBLIC -DLIBVA_SUPPORT)
        target_link_libraries(${TARGET} ${PKG_LIBVADRM_LIBRARIES})
        target_include_directories(${TARGET} PUBLIC ${PKG_LIBVADRM_INCLUDEDIR})
    else()
        message(FATAL_ERROR "libva-drm not found")
    endif()
    pkg_check_modules(PKG_LIBDRM libdrm>=2.4)
    if(PKG_LIBDRM_FOUND)
        target_compile_definitions(${TARGET} PUBLIC -DLIBDRM_SUPPORT)
        target_link_libraries(${TARGET} ${PKG_LIBDRM_LIBRARIES})
        target_include_directories(${TARGET} PUBLIC ${PKG_LIBDRM_INCLUDEDIR})
    else()
        message(FATAL_ERROR "libdrm not found")
    endif()
endif(USE_VPL_ENCODER)

target_link_libraries(${TARGET} ${AVCODEC_LIBRARY} ${AVDEVICE_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})

if(BUILD_PLUGIN)
    add_library(ffmpeg_plugin_shared SHARED ${PLUGIN_SOURCES})
    set_target_properties(
            ffmpeg_plugin_shared PROPERTIES OUTPUT_NAME ffmpeg_h5plugin)
    target_link_libraries(ffmpeg_plugin_shared ${TARGET} ${AVCODEC_LIBRARY} ${AVDEVICE_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})

    install(TARGETS ffmpeg_plugin_shared DESTINATION ${PLUGIN_INSTALL_PATH} COMPONENT HDF5_FILTER_DEV)
endif(BUILD_PLUGIN)

# install
install(FILES src/ffmpeg_h5filter.h DESTINATION include COMPONENT HDF5_FILTER_DEV)
install(TARGETS ${TARGET} DESTINATION lib COMPONENT HDF5_FILTER_DEV)

# test
message("LINK LIBRARIES='${TARGET} ${AVCODEC_LIBRARY} ${AVDEVICE_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES}'")
if(BUILD_TESTS)
    enable_testing()
    add_executable(example src/example.c)
    target_compile_definitions(example PUBLIC -DLIBVA_SUPPORT -DLIBDRM_SUPPORT -DUSE_VPL2X_INIT)
    target_link_libraries(example ${PKG_LIBDRM_LIBRARIES})
    target_include_directories(example PUBLIC ${PKG_LIBDRM_INCLUDEDIR})
    target_link_libraries(example ${PKG_LIBVA_LIBRARIES})
    target_link_libraries(example ${PKG_LIBVADRM_LIBRARIES})
    target_link_libraries(example VPL::dispatcher)
    target_link_libraries(example ${TARGET} ${AVCODEC_LIBRARY} ${AVDEVICE_LIBRARY} ${SWSCALE_LIBRARY} ${AVFORMAT_LIBRARY} ${AVUTIL_LIBRARY} ${HDF5_LIBRARIES})
    target_include_directories(example PUBLIC ${PKG_LIBVADRM_INCLUDEDIR})
    target_include_directories(example PUBLIC ${PKG_LIBVA_INCLUDEDIR})

    add_test(test_hdf5_filter example)
endif(BUILD_TESTS)