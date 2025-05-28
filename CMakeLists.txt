cmake_minimum_required(VERSION 3.16)

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