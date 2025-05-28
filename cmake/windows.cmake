cmake_minimum_required(VERSION 3.16)
project(h5ffmpeg_shared VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/deps")
set(FFMPEG_ROOT "${DEPS_ROOT}")
set(HDF5_ROOT "${DEPS_ROOT}")

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
    endif()
endforeach()

find_library(HDF5_C_LIBRARY
    NAMES hdf5 libhdf5
    PATHS ${HDF5_ROOT}/lib
    NO_DEFAULT_PATH
)

find_library(HDF5_HL_LIBRARY
    NAMES hdf5_hl libhdf5_hl
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
    _CRT_SECURE_NO_WARNINGS
    H5_BUILT_AS_DYNAMIC_LIB
    _HDF5USEDLL_
)

target_link_libraries(h5ffmpeg_shared
    PRIVATE
        ${FFMPEG_LIBRARIES}
        ${HDF5_C_LIBRARY}
        ${HDF5_HL_LIBRARY}
        ws2_32
        secur32
        bcrypt
        shlwapi
)

function(get_dll_dependencies dll_path output_var)
    execute_process(
        COMMAND dumpbin /dependents "${dll_path}"
        OUTPUT_VARIABLE deps_output
        ERROR_QUIET
    )
    
    string(REGEX MATCHALL "[^\r\n]+\\.dll" dll_list "${deps_output}")
    
    set(system_dlls 
        "kernel32.dll" "user32.dll" "gdi32.dll" "winspool.dll" "comdlg32.dll"
        "advapi32.dll" "shell32.dll" "ole32.dll" "oleaut32.dll" "uuid.dll"
        "odbc32.dll" "odbccp32.dll" "msvcrt.dll" "msvcp*.dll" "vcruntime*.dll"
        "api-ms-*.dll" "ntdll.dll" "ws2_32.dll" "secur32.dll" "bcrypt.dll"
        "shlwapi.dll" "comctl32.dll" "rpcrt4.dll" "winmm.dll"
    )
    
    set(filtered_deps "")
    foreach(dep ${dll_list})
        string(TOLOWER "${dep}" dep_lower)
        set(is_system FALSE)
        foreach(sys_dll ${system_dlls})
            string(TOLOWER "${sys_dll}" sys_dll_lower)
            if("${dep_lower}" MATCHES "${sys_dll_lower}")
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

function(bundle_dependencies target_dll)
    get_dll_dependencies("${target_dll}" deps)
    
    foreach(dep ${deps})
        set(found_dll "")
        file(GLOB_RECURSE dll_candidates "${DEPS_ROOT}/*/${dep}")
        if(dll_candidates)
            list(GET dll_candidates 0 found_dll)
        endif()
        
        if(found_dll AND EXISTS "${found_dll}")
            get_filename_component(dll_name "${found_dll}" NAME)
            install(FILES "${found_dll}" DESTINATION bin)
            bundle_dependencies("${found_dll}")
        endif()
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
    file(GLOB installed_dlls \"\${CMAKE_INSTALL_PREFIX}/bin/*.dll\")
    foreach(dll \${installed_dlls})
        get_filename_component(dll_name \"\${dll}\" NAME)
        if(\"\${dll_name}\" STREQUAL \"h5ffmpeg_shared.dll\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundling dependencies for \${dll}\")
        endif()
    endforeach()
")