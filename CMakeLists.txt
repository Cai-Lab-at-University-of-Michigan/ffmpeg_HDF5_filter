cmake_minimum_required(VERSION 3.16)
project(h5ffmpeg_shared VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(WIN32)
    include(cmake/windows.cmake)
elseif(APPLE)
    include(cmake/macos.cmake)
else()
    include(cmake/linux.cmake)
endif()

add_custom_target(bundle_all
    COMMENT "Creating bundled library package"
    DEPENDS h5ffmpeg_shared
)