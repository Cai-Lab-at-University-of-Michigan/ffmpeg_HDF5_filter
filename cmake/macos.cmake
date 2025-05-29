set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/deps")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg")
set(HDF5_ROOT "${DEPS_ROOT}/miniconda")

message(STATUS "FFMPEG_ROOT: ${FFMPEG_ROOT}")
message(STATUS "HDF5_ROOT: ${HDF5_ROOT}")

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

set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib}
        PATHS ${FFMPEG_ROOT}/lib ${HDF5_ROOT}/lib
        NO_DEFAULT_PATH
    )
    if(FFMPEG_${lib}_LIBRARY)
        list(APPEND FFMPEG_LIBRARIES ${FFMPEG_${lib}_LIBRARY})
        message(STATUS "Found FFmpeg ${lib}: ${FFMPEG_${lib}_LIBRARY}")
    else()
        message(WARNING "FFmpeg ${lib} NOT FOUND!")
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

install(CODE "
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== INSTALL DEBUG INFO ===\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install prefix: \${CMAKE_INSTALL_PREFIX}\")
    
    file(GLOB installed_files \"\${CMAKE_INSTALL_PREFIX}/lib/*\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Files in lib directory:\")
    foreach(file \${installed_files})
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${file}\")
    endforeach()
    
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.dylib\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFound main library: \${MAIN_LIB}\")
        
        execute_process(
            COMMAND otool -L \"\${MAIN_LIB}\"
            OUTPUT_VARIABLE current_deps
            ERROR_QUIET
        )
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Current dependencies:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${current_deps}\")
        
        string(REGEX MATCHALL \"\\t([^\\t\\r\\n]+\\.dylib)\" matches \"\${current_deps}\")
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nParsed dependencies:\")
        foreach(match \${matches})
            string(REGEX REPLACE \"\\t([^\\t\\r\\n]+\\.dylib).*\" \"\\\\1\" dep_path \"\${match}\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  Dependency: \${dep_path}\")
            
            if(NOT \"\${dep_path}\" MATCHES \"^/System/\" AND 
               NOT \"\${dep_path}\" MATCHES \"^/usr/lib/\" AND
               NOT \"\${dep_path}\" MATCHES \"^@loader_path\" AND
               NOT \"\${dep_path}\" MATCHES \"^@rpath\" AND
               NOT \"\${dep_path}\" MATCHES \"^@executable_path\")
                
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Needs bundling: \${dep_path}\")
                
                if(EXISTS \"\${dep_path}\")
                    get_filename_component(dep_name \"\${dep_path}\" NAME)
                    file(COPY \"\${dep_path}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib\")
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Copied \${dep_name}\")
                    
                    execute_process(
                        COMMAND install_name_tool -change \"\${dep_path}\" \"@loader_path/\${dep_name}\" \"\${MAIN_LIB}\"
                        ERROR_QUIET
                    )
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Fixed reference to \${dep_name}\")
                else()
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> ERROR: File does not exist: \${dep_path}\")
                endif()
            else()
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Skipping system library: \${dep_path}\")
            endif()
        endforeach()
        
        execute_process(
            COMMAND otool -L \"\${MAIN_LIB}\"
            OUTPUT_VARIABLE final_deps
            ERROR_QUIET
        )
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFinal dependencies:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${final_deps}\")
        
    else()
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"ERROR: Main library not found at \${MAIN_LIB}\")
    endif()
")