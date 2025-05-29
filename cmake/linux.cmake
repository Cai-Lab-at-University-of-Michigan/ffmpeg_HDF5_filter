set(DEPS_ROOT "$ENV{HOME}")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg")
set(HDF5_ROOT "${DEPS_ROOT}/miniconda")

message(STATUS "FFMPEG_ROOT: ${FFMPEG_ROOT}")
message(STATUS "HDF5_ROOT: ${HDF5_ROOT}")

find_path(FFMPEG_INCLUDE_DIR 
    NAMES libavcodec/avcodec.h
    PATHS 
        ${FFMPEG_ROOT}/include
        /usr/include
        /usr/local/include
        /usr/include/x86_64-linux-gnu
)

find_path(HDF5_INCLUDE_DIR 
    NAMES hdf5.h
    PATHS 
        ${HDF5_ROOT}/include
        /usr/include
        /usr/local/include
        /usr/include/hdf5/serial
)

set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib}
        PATHS 
            ${FFMPEG_ROOT}/lib
            /usr/lib
            /usr/local/lib
            /usr/lib/x86_64-linux-gnu
    )
    
    if(FFMPEG_${lib}_LIBRARY)
        list(APPEND FFMPEG_LIBRARIES ${FFMPEG_${lib}_LIBRARY})
        message(STATUS "Found FFmpeg ${lib}: ${FFMPEG_${lib}_LIBRARY}")
    else()
        message(FATAL_ERROR "FFmpeg ${lib} required")
    endif()
endforeach()

find_library(HDF5_C_LIBRARY
    NAMES hdf5
    PATHS 
        ${HDF5_ROOT}/lib
        /usr/lib
        /usr/local/lib
        /usr/lib/x86_64-linux-gnu
        /usr/lib/x86_64-linux-gnu/hdf5/serial
)

if(HDF5_C_LIBRARY)
    message(STATUS "Found HDF5: ${HDF5_C_LIBRARY}")
else()
    message(FATAL_ERROR "HDF5 library required")
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
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.so\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        set(FFMPEG_ROOT \"${FFMPEG_ROOT}\")
        set(HDF5_ROOT \"${HDF5_ROOT}\")
        
        set(target_libs
            \"libavcodec\" \"libavformat\" \"libavutil\" \"libswscale\" \"libswresample\" \"libavfilter\"
            \"libhdf5\"
            \"libx264\" \"libx265\" \"libvpx\" \"libdav1d\" \"libaom\" \"librav1e\" \"libSvtAv1Enc\"
        )
        
        file(GLOB_RECURSE candidate_files 
            \"\${FFMPEG_ROOT}/lib/*.so*\"
            \"\${HDF5_ROOT}/lib/*.so*\"
        )
        
        foreach(candidate_file \${candidate_files})
            get_filename_component(candidate_name \"\${candidate_file}\" NAME)
            
            set(should_bundle FALSE)
            foreach(target_lib \${target_libs})
                if(\"\${candidate_name}\" MATCHES \"^\${target_lib}[.]so\")
                    set(should_bundle TRUE)
                    break()
                endif()
            endforeach()
            
            if(should_bundle)
                if(EXISTS \"\${candidate_file}\" AND NOT IS_SYMLINK \"\${candidate_file}\")
                    set(dest_file \"\${CMAKE_INSTALL_PREFIX}/lib/\${candidate_name}\")
                    if(NOT EXISTS \"\${dest_file}\")
                        file(COPY \"\${candidate_file}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib\")
                    endif()
                elseif(IS_SYMLINK \"\${candidate_file}\")
                    execute_process(COMMAND readlink -f \"\${candidate_file}\" OUTPUT_VARIABLE real_file OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
                    if(EXISTS \"\${real_file}\")
                        get_filename_component(real_name \"\${real_file}\" NAME)
                        set(dest_real_file \"\${CMAKE_INSTALL_PREFIX}/lib/\${real_name}\")
                        
                        if(NOT EXISTS \"\${dest_real_file}\")
                            file(COPY \"\${real_file}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/lib\")
                        endif()
                        
                        set(dest_symlink \"\${CMAKE_INSTALL_PREFIX}/lib/\${candidate_name}\")
                        if(NOT EXISTS \"\${dest_symlink}\")
                            execute_process(COMMAND ln -sf \"\${real_name}\" \"\${dest_symlink}\" ERROR_QUIET)
                        endif()
                    endif()
                endif()
            endif()
        endforeach()
        
        find_program(PATCHELF_EXECUTABLE patchelf)
        if(PATCHELF_EXECUTABLE)
            file(GLOB bundle_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*.so*\")
            foreach(lib \${bundle_libs})
                if(NOT IS_SYMLINK \"\${lib}\")
                    execute_process(
                        COMMAND \"\${PATCHELF_EXECUTABLE}\" --set-rpath \"$ORIGIN\" \"\${lib}\"
                        ERROR_QUIET
                    )
                endif()
            endforeach()
        endif()
    endif()
")