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

find_library(ICONV_LIBRARY
    NAMES iconv
    PATHS 
        ${HDF5_ROOT}/lib
        ${FFMPEG_ROOT}/lib
        /usr/local/lib
        /opt/homebrew/lib
)

if(ICONV_LIBRARY)
    message(STATUS "✓ libiconv: ${ICONV_LIBRARY}")
else()
    message(WARNING "libiconv not found - may cause runtime issues")
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
        ${ICONV_LIBRARY}
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
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.dylib\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        set(FFMPEG_ROOT \"${FFMPEG_ROOT}\")
        set(HDF5_ROOT \"${HDF5_ROOT}\")
        
        set(target_libs
            \"libavcodec\" \"libavformat\" \"libavutil\" \"libswscale\" \"libswresample\" \"libavfilter\"
            \"libhdf5\"
            \"libx264\" \"libx265\" \"libvpx\" \"libdav1d\" \"libaom\" \"librav1e\" \"libSvtAv1Enc\"
            \"libxvidcore\"
        )
        
        set(system_lib_mappings
            \"libiconv;/usr/lib/libiconv.2.dylib\"
            \"liblzma;/usr/lib/liblzma.5.dylib\"
            \"libc++;/usr/lib/libc++.1.dylib\"
            \"libz;/usr/lib/libz.1.dylib\"
            \"libssl;/usr/lib/libssl.dylib\"
            \"libcrypto;/usr/lib/libcrypto.dylib\"
        )
        
        file(GLOB_RECURSE candidate_files 
            \"\${FFMPEG_ROOT}/lib/*.dylib*\"
            \"\${HDF5_ROOT}/lib/*.dylib*\"
            \"/usr/local/lib/*.dylib*\"
            \"/opt/homebrew/lib/*.dylib*\"
        )
        
        set(bundled_libs_list \"\")
        
        foreach(candidate_file \${candidate_files})
            get_filename_component(candidate_name \"\${candidate_file}\" NAME)
            
            set(should_bundle FALSE)
            foreach(target_lib \${target_libs})
                if(\"\${candidate_name}\" MATCHES \"^\${target_lib}[.].*[.]dylib$\" OR 
                   \"\${candidate_name}\" MATCHES \"^\${target_lib}[.]dylib$\" OR
                   \"\${candidate_name}\" MATCHES \"^\${target_lib}[.].*$\")
                    set(should_bundle TRUE)
                    break()
                endif()
            endforeach()
            
            if(should_bundle)
                set(dest_file \"\${CMAKE_INSTALL_PREFIX}/lib/\${candidate_name}\")
                
                if(IS_SYMLINK \"\${candidate_file}\")
                    execute_process(
                        COMMAND readlink \"\${candidate_file}\" 
                        OUTPUT_VARIABLE link_target 
                        OUTPUT_STRIP_TRAILING_WHITESPACE 
                        ERROR_QUIET
                    )
                    
                    if(link_target)
                        if(NOT IS_ABSOLUTE \"\${link_target}\")
                            get_filename_component(candidate_dir \"\${candidate_file}\" DIRECTORY)
                            set(absolute_target \"\${candidate_dir}/\${link_target}\")
                        else()
                            set(absolute_target \"\${link_target}\")
                        endif()
                        
                        if(EXISTS \"\${absolute_target}\" AND NOT IS_SYMLINK \"\${absolute_target}\")
                            get_filename_component(real_name \"\${absolute_target}\" NAME)
                            set(dest_real_file \"\${CMAKE_INSTALL_PREFIX}/lib/\${real_name}\")
                            
                            if(NOT EXISTS \"\${dest_real_file}\")
                                execute_process(
                                    COMMAND cp \"\${absolute_target}\" \"\${dest_real_file}\"
                                    ERROR_QUIET
                                )
                                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundled target file: \${real_name}\")
                                list(APPEND bundled_libs_list \"\${dest_real_file}\")
                            endif()
                        endif()
                        
                        if(NOT EXISTS \"\${dest_file}\" AND NOT IS_SYMLINK \"\${dest_file}\")
                            execute_process(
                                COMMAND ln -s \"\${link_target}\" \"\${dest_file}\"
                                ERROR_QUIET
                            )
                            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Created symlink: \${candidate_name} -> \${link_target}\")
                        endif()
                    endif()
                    
                elseif(EXISTS \"\${candidate_file}\" AND NOT IS_SYMLINK \"\${candidate_file}\")
                    if(NOT EXISTS \"\${dest_file}\")
                        execute_process(
                            COMMAND cp \"\${candidate_file}\" \"\${dest_file}\"
                            ERROR_QUIET
                        )
                        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundled: \${candidate_name}\")
                        list(APPEND bundled_libs_list \"\${dest_file}\")
                    endif()
                endif()
            endif()
        endforeach()
        
        find_program(INSTALL_NAME_TOOL install_name_tool)
        if(INSTALL_NAME_TOOL)
            file(GLOB all_bundle_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib\")
            
            foreach(lib \${all_bundle_libs})
                if(NOT IS_SYMLINK \"\${lib}\")
                    get_filename_component(lib_name \"\${lib}\" NAME)
                    
                    execute_process(
                        COMMAND \"\${INSTALL_NAME_TOOL}\" -id \"@loader_path/\${lib_name}\" \"\${lib}\"
                        ERROR_QUIET
                    )
                endif()
            endforeach()
            
            foreach(lib \${all_bundle_libs})
                if(NOT IS_SYMLINK \"\${lib}\")
                    get_filename_component(lib_name \"\${lib}\" NAME)
                    
                    execute_process(
                        COMMAND otool -L \"\${lib}\"
                        OUTPUT_VARIABLE deps
                        ERROR_QUIET
                    )
                    string(REPLACE \"\\n\" \";\" deps_list \"\${deps}\")
                    foreach(dep_line \${deps_list})
                        string(REGEX MATCH \"^[ \\t]*([^ \\t]+)\" dep_match \"\${dep_line}\")
                        if(dep_match)
                            set(dep_path \"\${CMAKE_MATCH_1}\")
                            get_filename_component(dep_name \"\${dep_path}\" NAME)
                            
                            if(EXISTS \"\${CMAKE_INSTALL_PREFIX}/lib/\${dep_name}\")
                                if(NOT \"\${dep_path}\" MATCHES \"^@loader_path\")
                                    execute_process(
                                        COMMAND \"\${INSTALL_NAME_TOOL}\" -change \"\${dep_path}\" \"@loader_path/\${dep_name}\" \"\${lib}\"
                                        ERROR_QUIET
                                    )
                                endif()
                            else()
                                foreach(mapping \${system_lib_mappings})
                                    string(REPLACE \";\" \":\" mapping_parts \"\${mapping}\")
                                    list(GET mapping_parts 0 sys_lib_name)
                                    list(GET mapping_parts 1 sys_lib_path)
                                    
                                    if(\"\${dep_name}\" MATCHES \"^\${sys_lib_name}[.].*\")
                                        if(NOT \"\${dep_path}\" MATCHES \"^/usr/lib/\" AND NOT \"\${dep_path}\" MATCHES \"^/System/\")
                                            execute_process(
                                                COMMAND \"\${INSTALL_NAME_TOOL}\" -change \"\${dep_path}\" \"\${sys_lib_path}\" \"\${lib}\"
                                                ERROR_QUIET
                                            )
                                            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Fixed system lib: \${dep_name} -> \${sys_lib_path}\")
                                        endif()
                                        break()
                                    endif()
                                endforeach()
                            endif()
                        endif()
                    endforeach()
                endif()
            endforeach()
            
            execute_process(COMMAND otool -L \"\${MAIN_LIB}\" OUTPUT_VARIABLE DEPS_AFTER ERROR_QUIET)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== Main library dependencies after bundling ===\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${DEPS_AFTER}\")
            
            string(REGEX MATCHALL \"/Users/[^\\n)]*\" found_user_paths \"\${DEPS_AFTER}\")
            string(REGEX MATCHALL \"/usr/local/[^\\n)]*\" found_usr_local \"\${DEPS_AFTER}\")
            string(REGEX MATCHALL \"/opt/homebrew/[^\\n)]*\" found_homebrew \"\${DEPS_AFTER}\")
            
            set(has_issues FALSE)
            if(found_user_paths)
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"WARNING: User-specific paths still found:\")
                foreach(path \${found_user_paths})
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${path}\")
                endforeach()
                set(has_issues TRUE)
            endif()
            
            if(found_usr_local)
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"WARNING: /usr/local paths still found:\")
                foreach(path \${found_usr_local})
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${path}\")
                endforeach()
                set(has_issues TRUE)
            endif()
            
            if(found_homebrew)
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"WARNING: Homebrew paths still found:\")
                foreach(path \${found_homebrew})
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${path}\")
                endforeach()
                set(has_issues TRUE)
            endif()
            
            if(NOT has_issues)
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"SUCCESS: All non-system dependencies use @loader_path\")
            endif()

            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== Bundled libraries ===\")
            file(GLOB final_bundled_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib\")
            foreach(bundled_lib \${final_bundled_libs})
                get_filename_component(bundled_name \"\${bundled_lib}\" NAME)
                if(IS_SYMLINK \"\${bundled_lib}\")
                    execute_process(
                        COMMAND readlink \"\${bundled_lib}\"
                        OUTPUT_VARIABLE link_target
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET
                    )
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${bundled_name} -> \${link_target}\")
                else()
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${bundled_name}\")
                endif()
            endforeach()
        endif()
    endif()
")

message(STATUS "=== MACOS CMAKE DEBUG END ===")