set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/deps")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg")
set(HDF5_ROOT "${DEPS_ROOT}/miniconda")

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
    endif()
endforeach()

find_library(HDF5_C_LIBRARY
    NAMES hdf5
    PATHS ${HDF5_ROOT}/lib
    NO_DEFAULT_PATH
)

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

function(get_so_dependencies so_path output_var)
    execute_process(
        COMMAND ldd "${so_path}"
        OUTPUT_VARIABLE deps_output
        ERROR_QUIET
    )
    
    string(REGEX MATCHALL "[^\r\n\t ]+\\.so[^\r\n\t ]*" so_list "${deps_output}")
    
    set(system_paths
        "/lib/" "/lib64/" "/usr/lib/" "/usr/lib64/"
        "/lib/x86_64-linux-gnu/" "/usr/lib/x86_64-linux-gnu/"
        "linux-vdso.so" "ld-linux" "libc.so" "libm.so" "libpthread.so"
        "libdl.so" "librt.so" "libresolv.so" "libnss_" "libgcc_s.so"
        "libstdc++.so"
    )
    
    set(filtered_deps "")
    foreach(dep ${so_list})
        string(REGEX MATCH "=> ([^ ]+)" match_result "${dep}")
        if(CMAKE_MATCH_1)
            set(dep_path "${CMAKE_MATCH_1}")
        else()
            set(dep_path "${dep}")
        endif()
        
        set(is_system FALSE)
        foreach(sys_path ${system_paths})
            if("${dep_path}" MATCHES "${sys_path}")
                set(is_system TRUE)
                break()
            endif()
        endforeach()
        
        if(NOT is_system AND EXISTS "${dep_path}")
            list(APPEND filtered_deps "${dep_path}")
        endif()
    endforeach()
    
    set(${output_var} "${filtered_deps}" PARENT_SCOPE)
endfunction()

function(bundle_dependencies target_so)
    get_so_dependencies("${target_so}" deps)
    
    foreach(dep ${deps})
        get_filename_component(so_name "${dep}" NAME)
        set(found_so "")
        
        file(GLOB_RECURSE so_candidates 
            "${FFMPEG_ROOT}/lib/${so_name}*"
            "${HDF5_ROOT}/lib/${so_name}*"
        )
        
        if(so_candidates)
            list(GET so_candidates 0 found_so)
        elseif(EXISTS "${dep}")
            set(found_so "${dep}")
        endif()
        
        if(found_so AND EXISTS "${found_so}")
            install(FILES "${found_so}" DESTINATION lib)
            bundle_dependencies("${found_so}")
        endif()
    endforeach()
endfunction()

function(fix_rpath target_so)
    find_program(PATCHELF_EXECUTABLE patchelf)
    if(PATCHELF_EXECUTABLE)
        execute_process(
            COMMAND "${PATCHELF_EXECUTABLE}" --set-rpath "$ORIGIN" "${target_so}"
            ERROR_QUIET
        )
    endif()
endfunction()

install(TARGETS h5ffmpeg_shared
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES src/ffmpeg_h5filter.h
    DESTINATION include
)

install(CODE "
    set(FFMPEG_ROOT \"${FFMPEG_ROOT}\")
    set(HDF5_ROOT \"${HDF5_ROOT}\")
    
    file(GLOB installed_sos \"\${CMAKE_INSTALL_PREFIX}/lib/*.so*\")
    foreach(so \${installed_sos})
        get_filename_component(so_name \"\${so}\" NAME)
        if(\"\${so_name}\" MATCHES \"^libh5ffmpeg_shared[.]so\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundling dependencies for \${so}\")
            
            # Get dependencies using ldd
            execute_process(
                COMMAND ldd \"\${so}\"
                OUTPUT_VARIABLE deps_output
                ERROR_QUIET
            )
            
            # Extract .so paths
            string(REGEX MATCHALL \"[^\\r\\n\\t ]+[.]so[^\\r\\n\\t ]*\" so_list \"\${deps_output}\")
            
            foreach(dep_line \${so_list})
                # Extract actual path from ldd output (format: libname.so => /path/to/lib)
                string(REGEX MATCH \"=> ([^ ]+)\" match_result \"\${dep_line}\")
                if(CMAKE_MATCH_1)
                    set(dep_path \"\${CMAKE_MATCH_1}\")
                else()
                    set(dep_path \"\${dep_line}\")
                endif()
                
                # Skip system libraries
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
                    
                    if(EXISTS \"\${dep_path}\")
                        get_filename_component(dep_name \"\${dep_path}\" NAME)
                        file(COPY \"\${dep_path}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib\")
                        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundled \${dep_name}\")
                    endif()
                endif()
            endforeach()
            
            # Fix RPATH for all libraries in the bundle
            file(GLOB all_bundle_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.so*\")
            foreach(lib \${all_bundle_libs})
                if(NOT IS_SYMLINK \"\${lib}\")
                    find_program(PATCHELF_EXECUTABLE patchelf)
                    if(PATCHELF_EXECUTABLE)
                        execute_process(
                            COMMAND \"\${PATCHELF_EXECUTABLE}\" --set-rpath \"$ORIGIN\" \"\${lib}\"
                            ERROR_QUIET
                        )
                    endif()
                endif()
            endforeach()
            
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Fixed RPATH for all bundled libraries\")
        endif()
    endforeach()
")