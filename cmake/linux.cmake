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
        PATHS ${FFMPEG_ROOT}/lib
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
    _POSIX_C_SOURCE=200809L
)

target_compile_options(h5ffmpeg_shared PRIVATE
    -fPIC
)

target_link_libraries(h5ffmpeg_shared
    PRIVATE
        ${FFMPEG_LIBRARIES}
        ${HDF5_C_LIBRARY}
        m
        pthread
        dl
)

set_target_properties(h5ffmpeg_shared PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH TRUE
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
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== LINUX INSTALL DEBUG INFO ===\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install prefix: \${CMAKE_INSTALL_PREFIX}\")
    
    file(GLOB installed_files \"\${CMAKE_INSTALL_PREFIX}/lib/*\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Files in lib directory:\")
    foreach(file \${installed_files})
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${file}\")
    endforeach()
    
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.so\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFound main library: \${MAIN_LIB}\")
        
        execute_process(
            COMMAND ldd \"\${MAIN_LIB}\"
            OUTPUT_VARIABLE current_deps
            ERROR_QUIET
        )
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Current dependencies:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${current_deps}\")
        
        string(REGEX MATCHALL \"([^\\r\\n\\t ]+\\.so[^\\r\\n\\t ]*)\" matches \"\${current_deps}\")
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nParsed dependencies:\")
        foreach(match \${matches})
            set(dep_path \"\")
            
            string(REGEX MATCH \"=> ([^ ]+)\" arrow_match \"\${match}\")
            if(CMAKE_MATCH_1 AND NOT CMAKE_MATCH_1 STREQUAL \"(0x\")
                set(dep_path \"\${CMAKE_MATCH_1}\")
            else()
                string(REGEX MATCH \"(/[^ ]+\\.so[^ ]*)\" abs_match \"\${match}\")
                if(CMAKE_MATCH_1)
                    set(dep_path \"\${CMAKE_MATCH_1}\")
                endif()
            endif()
            
            if(dep_path)
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  Dependency: \${dep_path}\")
                
                if(NOT \"\${dep_path}\" MATCHES \"^/lib/\" AND 
                   NOT \"\${dep_path}\" MATCHES \"^/lib64/\" AND
                   NOT \"\${dep_path}\" MATCHES \"^/usr/lib/\" AND
                   NOT \"\${dep_path}\" MATCHES \"^/usr/lib64/\" AND
                   NOT \"\${dep_path}\" MATCHES \"linux-vdso\" AND
                   NOT \"\${dep_path}\" MATCHES \"ld-linux\" AND
                   NOT \"\${dep_path}\" MATCHES \"libc[.]so\" AND
                   NOT \"\${dep_path}\" MATCHES \"libm[.]so\" AND
                   NOT \"\${dep_path}\" MATCHES \"libpthread[.]so\" AND
                   NOT \"\${dep_path}\" MATCHES \"libdl[.]so\" AND
                   NOT \"\${dep_path}\" MATCHES \"libgcc_s[.]so\" AND
                   NOT \"\${dep_path}\" MATCHES \"libstdc\\\\+\\\\+[.]so\")
                    
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Needs bundling: \${dep_path}\")
                    
                    if(EXISTS \"\${dep_path}\")
                        get_filename_component(dep_name \"\${dep_path}\" NAME)
                        file(COPY \"\${dep_path}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib\")
                        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Copied \${dep_name}\")
                    else()
                        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> ERROR: File does not exist: \${dep_path}\")
                    endif()
                else()
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Skipping system library: \${dep_path}\")
                endif()
            endif()
        endforeach()
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFixing RPATH for all bundled libraries...\")
        file(GLOB all_bundle_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.so*\")
        foreach(lib \${all_bundle_libs})
            if(NOT IS_SYMLINK \"\${lib}\")
                find_program(PATCHELF_EXECUTABLE patchelf)
                if(PATCHELF_EXECUTABLE)
                    execute_process(
                        COMMAND \"\${PATCHELF_EXECUTABLE}\" --set-rpath \"$ORIGIN\" \"\${lib}\"
                        ERROR_QUIET
                    )
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Fixed RPATH for \${lib}\")
                else()
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> WARNING: patchelf not found, cannot fix RPATH\")
                endif()
            endif()
        endforeach()
        
        execute_process(
            COMMAND ldd \"\${MAIN_LIB}\"
            OUTPUT_VARIABLE final_deps
            ERROR_QUIET
        )
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFinal dependencies:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${final_deps}\")
        
    else()
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"ERROR: Main library not found at \${MAIN_LIB}\")
    endif()
")