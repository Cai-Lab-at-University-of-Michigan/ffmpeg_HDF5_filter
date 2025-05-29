set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

set(DEPS_ROOT "$ENV{HOME}")
set(FFMPEG_ROOT "${DEPS_ROOT}")
set(HDF5_ROOT "${DEPS_ROOT}")

message(STATUS "DEPS_ROOT: ${DEPS_ROOT}")
message(STATUS "FFMPEG_ROOT: ${FFMPEG_ROOT}")
message(STATUS "HDF5_ROOT: ${HDF5_ROOT}")

find_path(FFMPEG_INCLUDE_DIR 
    NAMES libavcodec/avcodec.h
    PATHS 
        ${FFMPEG_ROOT}/include
        "C:/vcpkg/installed/x64-windows/include"
)

find_path(HDF5_INCLUDE_DIR 
    NAMES hdf5.h
    PATHS 
        ${HDF5_ROOT}/include
        "C:/vcpkg/installed/x64-windows/include"
)

set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib} lib${lib}
        PATHS 
            ${FFMPEG_ROOT}/lib
            "C:/vcpkg/installed/x64-windows/lib"
    )
    
    if(FFMPEG_${lib}_LIBRARY)
        list(APPEND FFMPEG_LIBRARIES ${FFMPEG_${lib}_LIBRARY})
        message(STATUS "Found FFmpeg ${lib}: ${FFMPEG_${lib}_LIBRARY}")
    else()
        message(FATAL_ERROR "FFmpeg ${lib} required")
    endif()
endforeach()

find_library(HDF5_C_LIBRARY
    NAMES hdf5 libhdf5
    PATHS 
        ${HDF5_ROOT}/lib
        "C:/vcpkg/installed/x64-windows/lib"
)

find_library(HDF5_HL_LIBRARY
    NAMES hdf5_hl libhdf5_hl
    PATHS 
        ${HDF5_ROOT}/lib
        "C:/vcpkg/installed/x64-windows/lib"
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

install(TARGETS h5ffmpeg_shared
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES src/ffmpeg_h5filter.h
    DESTINATION include
)

install(CODE "
    set(MAIN_DLL \"\${CMAKE_INSTALL_PREFIX}/bin/h5ffmpeg_shared.dll\")
    
    if(EXISTS \"\${MAIN_DLL}\")
        file(TO_CMAKE_PATH \"\${DEPS_ROOT}\" SEARCH_ROOT)
        
        set(target_dlls
            \"avcodec\" \"avformat\" \"avutil\" \"swscale\" \"swresample\" \"avfilter\"
            \"hdf5\" \"hdf5_hl\"
            \"x264\" \"x265\" \"vpx\" \"dav1d\" \"aom\" \"rav1e\" \"SvtAv1Enc\"
        )
        
        file(GLOB_RECURSE candidate_dlls \"\${SEARCH_ROOT}/*.dll\")
        
        set(system_dlls 
            \"kernel32\" \"user32\" \"gdi32\" \"winspool\" \"comdlg32\"
            \"advapi32\" \"shell32\" \"ole32\" \"oleaut32\" \"uuid\"
            \"odbc32\" \"odbccp32\" \"msvcrt\" \"ntdll\" \"ws2_32\" 
            \"secur32\" \"bcrypt\" \"shlwapi\" \"comctl32\" \"rpcrt4\" 
            \"winmm\" \"crypt32\" \"wldap32\" \"normaliz\"
        )
        
        foreach(candidate_dll \${candidate_dlls})
            get_filename_component(dll_name \"\${candidate_dll}\" NAME_WE)
            get_filename_component(full_name \"\${candidate_dll}\" NAME)
            string(TOLOWER \"\${full_name}\" full_name_lower)
            
            set(should_bundle FALSE)
            foreach(target_dll \${target_dlls})
                if(\"\${dll_name}\" MATCHES \"^\${target_dll}\")
                    set(should_bundle TRUE)
                    break()
                endif()
            endforeach()
            
            if(should_bundle)
                set(is_system FALSE)
                foreach(sys_dll \${system_dlls})
                    if(\"\${full_name_lower}\" MATCHES \"\${sys_dll}\" OR
                       \"\${full_name_lower}\" MATCHES \"msvcp.*[.]dll\" OR
                       \"\${full_name_lower}\" MATCHES \"vcruntime.*[.]dll\" OR
                       \"\${full_name_lower}\" MATCHES \"api-ms-.*[.]dll\" OR
                       \"\${full_name_lower}\" MATCHES \"ucrtbase.*[.]dll\")
                        set(is_system TRUE)
                        break()
                    endif()
                endforeach()
                
                if(NOT is_system)
                    set(dest_dll \"\${CMAKE_INSTALL_PREFIX}/bin/\${full_name}\")
                    if(NOT EXISTS \"\${dest_dll}\")
                        file(COPY \"\${candidate_dll}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\")
                    endif()
                endif()
            endif()
        endforeach()
    endif()
")