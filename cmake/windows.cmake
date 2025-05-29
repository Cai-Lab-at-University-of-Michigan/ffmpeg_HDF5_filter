set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/deps")
set(FFMPEG_ROOT "${DEPS_ROOT}")
set(HDF5_ROOT "${DEPS_ROOT}")

message(STATUS "DEPS_ROOT: ${DEPS_ROOT}")
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
    NAMES hdf5 libhdf5
    PATHS ${HDF5_ROOT}/lib
    NO_DEFAULT_PATH
)

find_library(HDF5_HL_LIBRARY
    NAMES hdf5_hl libhdf5_hl
    PATHS ${HDF5_ROOT}/lib
    NO_DEFAULT_PATH
)

if(HDF5_C_LIBRARY)
    message(STATUS "Found HDF5: ${HDF5_C_LIBRARY}")
else()
    message(WARNING "HDF5 NOT FOUND!")
endif()

if(HDF5_HL_LIBRARY)
    message(STATUS "Found HDF5 HL: ${HDF5_HL_LIBRARY}")
else()
    message(WARNING "HDF5 HL NOT FOUND!")
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
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== WINDOWS INSTALL DEBUG INFO ===\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install prefix: \${CMAKE_INSTALL_PREFIX}\")
    
    file(GLOB installed_files \"\${CMAKE_INSTALL_PREFIX}/bin/*\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Files in bin directory:\")
    foreach(file \${installed_files})
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${file}\")
    endforeach()
    
    set(MAIN_DLL \"\${CMAKE_INSTALL_PREFIX}/bin/h5ffmpeg_shared.dll\")
    set(DEPS_ROOT \"${DEPS_ROOT}\")
    
    if(EXISTS \"\${MAIN_DLL}\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFound main DLL: \${MAIN_DLL}\")
        
        # Try to get dependencies using dumpbin if available
        find_program(DUMPBIN_EXECUTABLE dumpbin)
        if(DUMPBIN_EXECUTABLE)
            execute_process(
                COMMAND \"\${DUMPBIN_EXECUTABLE}\" /dependents \"\${MAIN_DLL}\"
                OUTPUT_VARIABLE current_deps
                ERROR_QUIET
            )
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Current dependencies (dumpbin):\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${current_deps}\")
            
            # Parse dumpbin output for DLL names
            string(REGEX MATCHALL \"([^\\r\\n\\t ]+\\.dll)\" dll_matches \"\${current_deps}\")
            
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nParsed DLL dependencies:\")
            foreach(dll_match \${dll_matches})
                execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  DLL: \${dll_match}\")
            endforeach()
        else()
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"dumpbin not found, using file-based bundling approach\")
        endif()
        
        # Bundle all non-system DLLs from deps directory
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nSearching for DLLs in deps directory...\")
        file(GLOB_RECURSE all_dep_dlls \"\${DEPS_ROOT}/*.dll\")
        
        set(system_dlls 
            \"kernel32.dll\" \"user32.dll\" \"gdi32.dll\" \"winspool.dll\" \"comdlg32.dll\"
            \"advapi32.dll\" \"shell32.dll\" \"ole32.dll\" \"oleaut32.dll\" \"uuid.dll\"
            \"odbc32.dll\" \"odbccp32.dll\" \"msvcrt.dll\" \"ntdll.dll\" \"ws2_32.dll\" 
            \"secur32.dll\" \"bcrypt.dll\" \"shlwapi.dll\" \"comctl32.dll\" \"rpcrt4.dll\" 
            \"winmm.dll\" \"crypt32.dll\" \"wldap32.dll\" \"normaliz.dll\"
        )
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Found \${CMAKE_MATCH_COUNT} DLL files in deps\")
        
        foreach(dep_dll \${all_dep_dlls})
            get_filename_component(dep_name \"\${dep_dll}\" NAME)
            string(TOLOWER \"\${dep_name}\" dep_name_lower)
            
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  Checking: \${dep_name}\")
            
            # Check if it's a system DLL
            set(is_system FALSE)
            foreach(sys_dll \${system_dlls})
                string(TOLOWER \"\${sys_dll}\" sys_dll_lower)
                if(\"\${dep_name_lower}\" STREQUAL \"\${sys_dll_lower}\" OR 
                   \"\${dep_name_lower}\" MATCHES \"msvcp.*[.]dll\" OR
                   \"\${dep_name_lower}\" MATCHES \"vcruntime.*[.]dll\" OR
                   \"\${dep_name_lower}\" MATCHES \"api-ms-.*[.]dll\" OR
                   \"\${dep_name_lower}\" MATCHES \"ucrtbase.*[.]dll\")
                    set(is_system TRUE)
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Skipping system DLL: \${dep_name}\")
                    break()
                endif()
            endforeach()
            
            # Copy non-system DLLs that don't already exist
            if(NOT is_system)
                set(dest_dll \"\${CMAKE_INSTALL_PREFIX}/bin/\${dep_name}\")
                if(NOT EXISTS \"\${dest_dll}\")
                    file(COPY \"\${dep_dll}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\")
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Bundled: \${dep_name}\")
                else()
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    -> Already exists: \${dep_name}\")
                endif()
            endif()
        endforeach()
        
        # Show final bundle contents
        file(GLOB final_dlls \"\${CMAKE_INSTALL_PREFIX}/bin/*.dll\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFinal DLL bundle contents:\")
        foreach(final_dll \${final_dlls})
            get_filename_component(final_name \"\${final_dll}\" NAME)
            file(SIZE \"\${final_dll}\" dll_size)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${final_name} (\${dll_size} bytes)\")
        endforeach()
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nWindows dependency bundling completed\")
        
    else()
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"ERROR: Main DLL not found at \${MAIN_DLL}\")
    endif()
")