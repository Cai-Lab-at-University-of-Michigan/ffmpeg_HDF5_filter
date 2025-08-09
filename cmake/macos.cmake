set(DEPS_ROOT "$ENV{HOME}")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg")
set(HDF5_ROOT "${DEPS_ROOT}/miniconda")

message(STATUS "FFMPEG_ROOT: ${FFMPEG_ROOT}")  
message(STATUS "HDF5_ROOT: ${HDF5_ROOT}")

find_path(FFMPEG_INCLUDE_DIR 
    NAMES libavcodec/avcodec.h
    PATHS 
        ${FFMPEG_ROOT}/include
        /usr/local/include
        /opt/homebrew/include
    DOC "FFmpeg include"
)

if(FFMPEG_INCLUDE_DIR)
    message(STATUS "✓ FFMPEG headers: ${FFMPEG_INCLUDE_DIR}")
else()
    message(WARNING "✗ FFMPEG headers not found")
    execute_process(COMMAND find /usr/local /opt/homebrew -name "avcodec.h" 2>/dev/null OUTPUT_VARIABLE AVCODEC_SEARCH ERROR_QUIET)
    if(AVCODEC_SEARCH)
        message(STATUS "System avcodec.h:\n${AVCODEC_SEARCH}")
    endif()
endif()

find_path(HDF5_INCLUDE_DIR 
    NAMES hdf5.h
    PATHS 
        ${HDF5_ROOT}/include
        /usr/local/include
        /opt/homebrew/include
    DOC "HDF5 include"
)

if(HDF5_INCLUDE_DIR)
    message(STATUS "✓ HDF5 headers: ${HDF5_INCLUDE_DIR}")
else()
    message(WARNING "✗ HDF5 headers not found")
    execute_process(COMMAND find /usr/local /opt/homebrew -name "hdf5.h" 2>/dev/null OUTPUT_VARIABLE HDF5_SEARCH ERROR_QUIET)
    if(HDF5_SEARCH)
        message(STATUS "System hdf5.h:\n${HDF5_SEARCH}")
    endif()
endif()

set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib}
        PATHS 
            ${FFMPEG_ROOT}/lib
            /usr/local/lib
            /opt/homebrew/lib
        DOC "FFmpeg ${lib}"
    )
    
    if(FFMPEG_${lib}_LIBRARY)
        list(APPEND FFMPEG_LIBRARIES ${FFMPEG_${lib}_LIBRARY})
        message(STATUS "✓ ${lib}: ${FFMPEG_${lib}_LIBRARY}")
    else()
        message(WARNING "✗ ${lib} NOT FOUND")
    endif()
endforeach()

find_library(HDF5_C_LIBRARY
    NAMES hdf5
    PATHS 
        ${HDF5_ROOT}/lib
        /usr/local/lib
        /opt/homebrew/lib
    DOC "HDF5 C library"
)

if(HDF5_C_LIBRARY)
    message(STATUS "✓ HDF5: ${HDF5_C_LIBRARY}")
else()
    message(WARNING "✗ HDF5 NOT FOUND")
endif()

message(STATUS "=== SUMMARY ===")
message(STATUS "FFMPEG_INCLUDE_DIR: ${FFMPEG_INCLUDE_DIR}")
message(STATUS "HDF5_INCLUDE_DIR: ${HDF5_INCLUDE_DIR}")
message(STATUS "FFMPEG_LIBRARIES: ${FFMPEG_LIBRARIES}")
message(STATUS "HDF5_C_LIBRARY: ${HDF5_C_LIBRARY}")

if(NOT FFMPEG_INCLUDE_DIR)
    message(FATAL_ERROR "FFMPEG headers required")
endif()

if(NOT HDF5_INCLUDE_DIR)
    message(FATAL_ERROR "HDF5 headers required")
endif()

if(NOT HDF5_C_LIBRARY)
    message(FATAL_ERROR "HDF5 library required")
endif()

if(NOT FFMPEG_LIBRARIES)
    message(FATAL_ERROR "FFmpeg libraries required")
endif()

add_library(h5ffmpeg_shared SHARED
    src/ffmpeg_h5filter.c
    src/ffmpeg_h5plugin.c
    src/ffmpeg_native.c
    src/ffmpeg_utils.c
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

install(FILES src/ffmpeg_utils.h
    DESTINATION include
)

if(EXISTS "${FFMPEG_ROOT}/lib")
    file(GLOB FFMPEG_DYLIBS "${FFMPEG_ROOT}/lib/*.dylib")
    if(FFMPEG_DYLIBS)
        install(FILES ${FFMPEG_DYLIBS}
            DESTINATION lib
            OPTIONAL
        )
        message(STATUS "Will install FFmpeg dylibs: ${FFMPEG_DYLIBS}")
    endif()
endif()

if(EXISTS "${HDF5_ROOT}/lib")
    file(GLOB HDF5_DYLIBS "${HDF5_ROOT}/lib/*.dylib")
    if(HDF5_DYLIBS)
        install(FILES ${HDF5_DYLIBS}
            DESTINATION lib
            OPTIONAL
        )
        message(STATUS "Will install HDF5/conda dylibs: ${HDF5_DYLIBS}")
    endif()
endif()

install(CODE "
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.dylib\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        find_program(INSTALL_NAME_TOOL install_name_tool)
        if(INSTALL_NAME_TOOL)
            file(GLOB ALL_DYLIBS \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib\")
            
            foreach(current_dylib \${ALL_DYLIBS})
                get_filename_component(current_name \"\${current_dylib}\" NAME)
                
                execute_process(
                    COMMAND \"\${INSTALL_NAME_TOOL}\" -id \"@loader_path/\${current_name}\" \"\${current_dylib}\"
                    ERROR_QUIET
                )
                
                execute_process(
                    COMMAND otool -L \"\${current_dylib}\"
                    OUTPUT_VARIABLE deps
                    ERROR_QUIET
                )
                
                foreach(other_dylib \${ALL_DYLIBS})
                    get_filename_component(other_name \"\${other_dylib}\" NAME)
                    
                    string(FIND \"\${deps}\" \"\${other_name}\" found_dep)
                    if(NOT found_dep EQUAL -1)
                        # Fix absolute paths to @loader_path
                        execute_process(
                            COMMAND \"\${INSTALL_NAME_TOOL}\" -change 
                                \"/Users/runner/ffmpeg/lib/\${other_name}\"
                                \"@loader_path/\${other_name}\"
                                \"\${current_dylib}\"
                            ERROR_QUIET
                        )
                        execute_process(
                            COMMAND \"\${INSTALL_NAME_TOOL}\" -change 
                                \"/Users/runner/miniconda/lib/\${other_name}\"
                                \"@loader_path/\${other_name}\"
                                \"\${current_dylib}\"
                            ERROR_QUIET
                        )
                        execute_process(
                            COMMAND \"\${INSTALL_NAME_TOOL}\" -change 
                                \"@rpath/\${other_name}\"
                                \"@loader_path/\${other_name}\"
                                \"\${current_dylib}\"
                            ERROR_QUIET
                        )
                    endif()
                endforeach()
            endforeach()
            
            execute_process(COMMAND otool -L \"\${MAIN_LIB}\" OUTPUT_VARIABLE DEPS_AFTER ERROR_QUIET)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Main library dependencies:\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${DEPS_AFTER}\")
            
            string(REGEX MATCH \"/Users/[^/]*/[^\\n]*\" found_absolute \"\${DEPS_AFTER}\")
            if(found_absolute)
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"WARNING: Absolute paths still found\")
            else()
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"SUCCESS: All non-system dependencies use @loader_path\")
            endif()
        endif()
    endif()
")

message(STATUS "=== MACOS CMAKE DEBUG END ===")