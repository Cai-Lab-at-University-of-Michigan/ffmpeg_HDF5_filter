set(DEPS_ROOT "${HOME}")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg")
set(HDF5_ROOT "${DEPS_ROOT}/miniconda")

message(STATUS "Looking for dependencies in:")
message(STATUS "  DEPS_ROOT: ${DEPS_ROOT}")
message(STATUS "  FFMPEG_ROOT: ${FFMPEG_ROOT}")  
message(STATUS "  HDF5_ROOT: ${HDF5_ROOT}")

# Debug: Show what's actually in the deps directory
if(EXISTS "${DEPS_ROOT}")
    execute_process(COMMAND find "${DEPS_ROOT}" -name "*.dylib" -type f OUTPUT_VARIABLE FOUND_DYLIBS)
    message(STATUS "Found .dylib files in deps:")
    message(STATUS "${FOUND_DYLIBS}")
else()
    message(WARNING "DEPS_ROOT directory does not exist: ${DEPS_ROOT}")
endif()

find_path(FFMPEG_INCLUDE_DIR 
    NAMES libavcodec/avcodec.h
    PATHS ${FFMPEG_ROOT}/include
    NO_DEFAULT_PATH
)

find_path(HDF5_INCLUDE_DIR 
    NAMES hdf5.h
    PATHS ${HDF5_ROOT}/include
    NO_DEFAULT_PATH
)

# Fix: Separate FFmpeg and HDF5 library searches
set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib}
        PATHS ${FFMPEG_ROOT}/lib  # Only FFmpeg path
        NO_DEFAULT_PATH
    )
    if(FFMPEG_${lib}_LIBRARY)
        list(APPEND FFMPEG_LIBRARIES ${FFMPEG_${lib}_LIBRARY})
        message(STATUS "Found FFmpeg ${lib}: ${FFMPEG_${lib}_LIBRARY}")
    else()
        message(WARNING "FFmpeg ${lib} not found!")
    endif()
endforeach()

find_library(HDF5_C_LIBRARY
    NAMES hdf5
    PATHS ${HDF5_ROOT}/lib
    NO_DEFAULT_PATH
)

if(HDF5_C_LIBRARY)
    message(STATUS "Found HDF5: ${HDF5_C_LIBRARY}")
else()
    message(WARNING "HDF5 NOT FOUND!")
endif()

if(HDF5_C_LIBRARY)
    message(STATUS "Found HDF5: ${HDF5_C_LIBRARY}")
else()
    message(WARNING "HDF5 not found!")
endif()

add_library(h5ffmpeg_shared SHARED
    src/ffmpeg_h5filter.c
    src/ffmpeg_h5plugin.c
)

target_include_directories(h5ffmpeg_shared
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${FFMPEG_INCLUDE_DIR}
        ${HDF5_INCLUDE_DIR}
)

target_compile_definitions(h5ffmpeg_shared PRIVATE
    FFMPEG_H5_FILTER_EXPORTS
)

target_link_libraries(h5ffmpeg_shared
    PRIVATE
        ${FFMPEG_LIBRARIES}
        ${HDF5_C_LIBRARY}
        "-framework CoreFoundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework VideoToolbox"
        "-framework AudioToolbox"
)

set_target_properties(h5ffmpeg_shared PROPERTIES
    INSTALL_RPATH "@loader_path"
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_NAME_DIR "@loader_path"
)

install(TARGETS h5ffmpeg_shared
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES src/ffmpeg_h5filter.h
    DESTINATION include
)

# Simpler approach: Bundle FFmpeg dependencies directly
install(FILES 
    ${FFMPEG_ROOT}/lib/libavcodec.62.dylib
    ${FFMPEG_ROOT}/lib/libavformat.62.dylib  
    ${FFMPEG_ROOT}/lib/libavutil.60.dylib
    ${FFMPEG_ROOT}/lib/libswscale.9.dylib
    ${FFMPEG_ROOT}/lib/libswresample.6.dylib
    ${FFMPEG_ROOT}/lib/libavfilter.11.dylib
    DESTINATION lib
    OPTIONAL
)

COMMAND install_name_tool -change 
            \"/Users/runner/ffmpeg/lib/libswscale.9.dylib\" 
            \"@loader_path/libswscale.9.dylib\" 
            \"\${MAIN_LIB}\" ERROR_QUIET)
            
        execute_process(COMMAND install_name_tool -change 
            \"/Users/runner/ffmpeg/lib/libswresample.6.dylib\" 
            \"@loader_path/libswresample.6.dylib\" 
            \"\${MAIN_LIB}\" ERROR_QUIET)
            
        execute_process(COMMAND install_name_tool -change 
            \"/Users/runner/ffmpeg/lib/libavfilter.11.dylib\" 
            \"@loader_path/libavfilter.11.dylib\" 
            \"\${MAIN_LIB}\" ERROR_QUIET)
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install name fixing completed\")
        
        # Verify the result
        execute_process(COMMAND otool -L \"\${MAIN_LIB}\" OUTPUT_VARIABLE OTOOL_OUTPUT)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Final dependencies:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${OTOOL_OUTPUT}\")
    else()
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"WARNING: Main library not found at \${MAIN_LIB}\")
    endif()
")