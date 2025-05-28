cmake_minimum_required(VERSION 3.16)
project(h5ffmpeg_shared VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

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

function(get_dylib_dependencies dylib_path output_var)
    execute_process(
        COMMAND otool -L "${dylib_path}"
        OUTPUT_VARIABLE deps_output
        ERROR_QUIET
    )
    
    string(REGEX MATCHALL "[^\r\n\t ]+\\.dylib" dylib_list "${deps_output}")
    
    set(system_paths
        "/usr/lib/" "/System/Library/" "/Library/Frameworks/"
        "@rpath/" "@loader_path/" "@executable_path/"
    )
    
    set(filtered_deps "")
    foreach(dep ${dylib_list})
        set(is_system FALSE)
        foreach(sys_path ${system_paths})
            if("${dep}" MATCHES "^${sys_path}")
                set(is_system TRUE)
                break()
            endif()
        endforeach()
        
        if(NOT is_system)
            list(APPEND filtered_deps "${dep}")
        endif()
    endforeach()
    
    set(${output_var} "${filtered_deps}" PARENT_SCOPE)
endfunction()

function(bundle_dependencies target_dylib)
    get_dylib_dependencies("${target_dylib}" deps)
    
    foreach(dep ${deps})
        get_filename_component(dylib_name "${dep}" NAME)
        set(found_dylib "")
        
        file(GLOB_RECURSE dylib_candidates 
            "${FFMPEG_ROOT}/lib/${dylib_name}"
            "${HDF5_ROOT}/lib/${dylib_name}"
        )
        
        if(dylib_candidates)
            list(GET dylib_candidates 0 found_dylib)
        endif()
        
        if(found_dylib AND EXISTS "${found_dylib}")
            install(FILES "${found_dylib}" DESTINATION lib)
            bundle_dependencies("${found_dylib}")
        endif()
    endforeach()
endfunction()

function(fix_install_names target_dylib)
    execute_process(
        COMMAND otool -L "${target_dylib}"
        OUTPUT_VARIABLE deps_output
        ERROR_QUIET
    )
    
    string(REGEX MATCHALL "[^\r\n\t ]+\\.dylib" dylib_list "${deps_output}")
    
    foreach(dep ${dylib_list})
        get_filename_component(dep_name "${dep}" NAME)
        execute_process(
            COMMAND install_name_tool -change "${dep}" "@loader_path/${dep_name}" "${target_dylib}"
            ERROR_QUIET
        )
    endforeach()
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
    file(GLOB installed_dylibs \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib\")
    foreach(dylib \${installed_dylibs})
        get_filename_component(dylib_name \"\${dylib}\" NAME)
        if(\"\${dylib_name}\" STREQUAL \"libh5ffmpeg_shared.dylib\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundling dependencies for \${dylib}\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Fixing install names for \${dylib}\")
        endif()
    endforeach()
")