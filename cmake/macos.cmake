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

target_link_libraries(h5ffmpeg_shared PRIVATE
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

install(CODE "
    if(APPLE)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== Automated recursive bundling ===\")
        
        set(linked_libs \${FFMPEG_LIBRARIES} \${HDF5_C_LIBRARY})
        list(APPEND linked_libs \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.dylib\")
        
        set(processed_libs \"\")
        set(libs_to_process \${linked_libs})
        
        while(libs_to_process)
            list(GET libs_to_process 0 current_lib)
            list(REMOVE_AT libs_to_process 0)
            
            list(FIND processed_libs \"\${current_lib}\" found_idx)
            if(NOT found_idx EQUAL -1)
                continue()
            endif()
            
            list(APPEND processed_libs \"\${current_lib}\")
            
            if(EXISTS \"\${current_lib}\")
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Processing: \${current_lib}\")
                
                execute_process(
                    COMMAND otool -L \"\${current_lib}\"
                    OUTPUT_VARIABLE deps_output
                    ERROR_QUIET
                )
                
                string(REPLACE \"\\n\" \";\" deps_list \"\${deps_output}\")
                foreach(dep_line \${deps_list})
                    string(REGEX MATCH \"^[ \\t]*([^ \\t]+)\" dep_match \"\${dep_line}\")
                    if(dep_match)
                        set(dep_path \"\${CMAKE_MATCH_1}\")
                        
                        if(\"\${dep_path}\" MATCHES \"^/usr/lib/\" OR 
                           \"\${dep_path}\" MATCHES \"^/System/Library/\" OR
                           \"\${dep_path}\" MATCHES \"^@loader_path\" OR
                           \"\${dep_path}\" MATCHES \"^@executable_path\")
                            continue()
                        endif()

                        if(EXISTS \"\${dep_path}\")
                            get_filename_component(dep_name \"\${dep_path}\" NAME)
                            set(dest_path \"\${CMAKE_INSTALL_PREFIX}/lib/\${dep_name}\")
                            
                            if(NOT EXISTS \"\${dest_path}\")
                                execute_process(
                                    COMMAND cp -R \"\${dep_path}\" \"\${dest_path}\"
                                    RESULT_VARIABLE cp_result
                                    ERROR_QUIET
                                )
                                
                                if(cp_result EQUAL 0)
                                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  Bundled: \${dep_name}\")
                                    list(APPEND libs_to_process \"\${dep_path}\")
                                endif()
                            endif()
                        endif()
                    endif()
                endforeach()
            endif()
        endwhile()
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== Fixing install names ===\")
        
        file(GLOB all_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib\")
        foreach(lib \${all_libs})
            if(NOT IS_SYMLINK \"\${lib}\")
                get_filename_component(lib_name \"\${lib}\" NAME)
                
                execute_process(
                    COMMAND install_name_tool -id \"@loader_path/\${lib_name}\" \"\${lib}\"
                    ERROR_QUIET
                )
                
                execute_process(
                    COMMAND otool -L \"\${lib}\"
                    OUTPUT_VARIABLE lib_deps
                    ERROR_QUIET
                )
                
                string(REPLACE \"\\n\" \";\" lib_deps_list \"\${lib_deps}\")
                foreach(lib_dep_line \${lib_deps_list})
                    string(REGEX MATCH \"^[ \\t]*([^ \\t]+)\" lib_dep_match \"\${lib_dep_line}\")
                    if(lib_dep_match)
                        set(lib_dep_path \"\${CMAKE_MATCH_1}\")
                        get_filename_component(lib_dep_name \"\${lib_dep_path}\" NAME)
                        
                        if(EXISTS \"\${CMAKE_INSTALL_PREFIX}/lib/\${lib_dep_name}\" AND 
                           NOT \"\${lib_dep_path}\" MATCHES \"^@loader_path\" AND
                           NOT \"\${lib_dep_path}\" MATCHES \"^/usr/lib/\" AND
                           NOT \"\${lib_dep_path}\" MATCHES \"^/System/Library/\")
                            execute_process(
                                COMMAND install_name_tool -change \"\${lib_dep_path}\" \"@loader_path/\${lib_dep_name}\" \"\${lib}\"
                                ERROR_QUIET
                            )
                        endif()
                        
                        if(\"\${lib_dep_path}\" MATCHES \"^@rpath/\" AND EXISTS \"\${CMAKE_INSTALL_PREFIX}/lib/\${lib_dep_name}\")
                            execute_process(
                                COMMAND install_name_tool -change \"\${lib_dep_path}\" \"@loader_path/\${lib_dep_name}\" \"\${lib}\"
                                ERROR_QUIET
                            )
                        endif()
                    endif()
                endforeach()
            endif()
        endforeach()
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✅ Automated bundling completed\")
        
        file(GLOB final_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib*\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== Bundled libraries ===\")
        foreach(final_lib \${final_libs})
            get_filename_component(lib_name \"\${final_lib}\" NAME)
            if(IS_SYMLINK \"\${final_lib}\")
                execute_process(
                    COMMAND readlink \"\${final_lib}\"
                    OUTPUT_VARIABLE link_target
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET
                )
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${lib_name} -> \${link_target}\")
            else()
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${lib_name}\")
            endif()
        endforeach()
    endif()
")

message(STATUS "=== MACOS CMAKE DEBUG END ===")