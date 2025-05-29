message(STATUS "=== WINDOWS CMAKE DEBUG START ===")

set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

execute_process(COMMAND whoami OUTPUT_VARIABLE CURRENT_USER OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
execute_process(COMMAND cd OUTPUT_VARIABLE CURRENT_DIR OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
message(STATUS "User: ${CURRENT_USER}, Dir: ${CURRENT_DIR}")

set(DEPS_ROOT "$ENV{HOME}")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg_build")
set(HDF5_ROOT "${DEPS_ROOT}/ffmpeg_build")

message(STATUS "DEPS_ROOT: ${DEPS_ROOT}")
message(STATUS "FFMPEG_ROOT: ${FFMPEG_ROOT}")
message(STATUS "HDF5_ROOT: ${HDF5_ROOT}")

if(EXISTS "${DEPS_ROOT}")
    message(STATUS "✓ DEPS_ROOT exists")
    execute_process(COMMAND dir "${DEPS_ROOT}" OUTPUT_VARIABLE DEPS_LISTING ERROR_QUIET)
    message(STATUS "DEPS_ROOT contents:\n${DEPS_LISTING}")
    
    execute_process(COMMAND dir "${DEPS_ROOT}\\*.dll" /s OUTPUT_VARIABLE FOUND_DLLS ERROR_QUIET)
    if(FOUND_DLLS)
        message(STATUS "Found DLLs:\n${FOUND_DLLS}")
    else()
        message(STATUS "No DLLs found")
    endif()
else()
    message(WARNING "✗ DEPS_ROOT missing: ${DEPS_ROOT}")
endif()

if(EXISTS "${FFMPEG_ROOT}/lib")
    execute_process(COMMAND dir "${FFMPEG_ROOT}\\lib" OUTPUT_VARIABLE FFMPEG_LIB_LISTING ERROR_QUIET)
    message(STATUS "FFMPEG lib:\n${FFMPEG_LIB_LISTING}")
else()
    message(WARNING "✗ FFMPEG lib missing")
endif()

if(EXISTS "${FFMPEG_ROOT}/include")
    execute_process(COMMAND dir "${FFMPEG_ROOT}\\include" OUTPUT_VARIABLE FFMPEG_INC_LISTING ERROR_QUIET)
    message(STATUS "FFMPEG include:\n${FFMPEG_INC_LISTING}")
else()
    message(WARNING "✗ FFMPEG include missing")
endif()

if(EXISTS "${HDF5_ROOT}/lib")
    execute_process(COMMAND dir "${HDF5_ROOT}\\lib" OUTPUT_VARIABLE HDF5_LIB_LISTING ERROR_QUIET)
    message(STATUS "HDF5 lib:\n${HDF5_LIB_LISTING}")
else()
    message(WARNING "✗ HDF5 lib missing")
endif()

if(EXISTS "${HDF5_ROOT}/include")
    execute_process(COMMAND dir "${HDF5_ROOT}\\include" OUTPUT_VARIABLE HDF5_INC_LISTING ERROR_QUIET)
    message(STATUS "HDF5 include:\n${HDF5_INC_LISTING}")
else()
    message(WARNING "✗ HDF5 include missing")
endif()

find_path(FFMPEG_INCLUDE_DIR 
    NAMES libavcodec/avcodec.h
    PATHS 
        ${FFMPEG_ROOT}/include
        "C:/vcpkg/installed/x64-windows/include"
    DOC "FFmpeg include"
)

if(FFMPEG_INCLUDE_DIR)
    message(STATUS "✓ FFMPEG headers: ${FFMPEG_INCLUDE_DIR}")
else()
    message(WARNING "✗ FFMPEG headers not found")
endif()

find_path(HDF5_INCLUDE_DIR 
    NAMES hdf5.h
    PATHS 
        ${HDF5_ROOT}/include
        "C:/vcpkg/installed/x64-windows/include"
    DOC "HDF5 include"
)

if(HDF5_INCLUDE_DIR)
    message(STATUS "✓ HDF5 headers: ${HDF5_INCLUDE_DIR}")
else()
    message(WARNING "✗ HDF5 headers not found")
endif()

set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    message(STATUS "Searching ${lib}...")
    
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib} lib${lib}
        PATHS 
            ${FFMPEG_ROOT}/lib
            "C:/vcpkg/installed/x64-windows/lib"
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
    NAMES hdf5 libhdf5
    PATHS 
        ${HDF5_ROOT}/lib
        "C:/vcpkg/installed/x64-windows/lib"
    DOC "HDF5 C library"
)

find_library(HDF5_HL_LIBRARY
    NAMES hdf5_hl libhdf5_hl
    PATHS 
        ${HDF5_ROOT}/lib
        "C:/vcpkg/installed/x64-windows/lib"
    DOC "HDF5 HL library"
)

if(HDF5_C_LIBRARY)
    message(STATUS "✓ HDF5: ${HDF5_C_LIBRARY}")
else()
    message(WARNING "✗ HDF5 NOT FOUND")
endif()

if(HDF5_HL_LIBRARY)
    message(STATUS "✓ HDF5 HL: ${HDF5_HL_LIBRARY}")
else()
    message(WARNING "✗ HDF5 HL NOT FOUND")
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
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== WINDOWS INSTALL DEBUG ===\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install prefix: \${CMAKE_INSTALL_PREFIX}\")
    
    set(MAIN_DLL \"\${CMAKE_INSTALL_PREFIX}/bin/h5ffmpeg_shared.dll\")
    set(DEPS_ROOT \"${DEPS_ROOT}\")
    
    if(EXISTS \"\${MAIN_DLL}\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✓ Main DLL: \${MAIN_DLL}\")
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Searching for DLLs in: \${DEPS_ROOT}\")
        file(GLOB_RECURSE all_dep_dlls \"\${DEPS_ROOT}/*.dll\")
        
        set(system_dlls 
            \"kernel32.dll\" \"user32.dll\" \"gdi32.dll\" \"winspool.dll\" \"comdlg32.dll\"
            \"advapi32.dll\" \"shell32.dll\" \"ole32.dll\" \"oleaut32.dll\" \"uuid.dll\"
            \"odbc32.dll\" \"odbccp32.dll\" \"msvcrt.dll\" \"ntdll.dll\" \"ws2_32.dll\" 
            \"secur32.dll\" \"bcrypt.dll\" \"shlwapi.dll\" \"comctl32.dll\" \"rpcrt4.dll\" 
            \"winmm.dll\" \"crypt32.dll\" \"wldap32.dll\" \"normaliz.dll\"
        )
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Found DLLs to process:\")
        
        set(bundled_count 0)
        foreach(dep_dll \${all_dep_dlls})
            get_filename_component(dep_name \"\${dep_dll}\" NAME)
            string(TOLOWER \"\${dep_name}\" dep_name_lower)
            
            set(is_system FALSE)
            foreach(sys_dll \${system_dlls})
                string(TOLOWER \"\${sys_dll}\" sys_dll_lower)
                if(\"\${dep_name_lower}\" STREQUAL \"\${sys_dll_lower}\" OR 
                   \"\${dep_name_lower}\" MATCHES \"msvcp.*[.]dll\" OR
                   \"\${dep_name_lower}\" MATCHES \"vcruntime.*[.]dll\" OR
                   \"\${dep_name_lower}\" MATCHES \"api-ms-.*[.]dll\" OR
                   \"\${dep_name_lower}\" MATCHES \"ucrtbase.*[.]dll\")
                    set(is_system TRUE)
                    break()
                endif()
            endforeach()
            
            if(NOT is_system)
                set(dest_dll \"\${CMAKE_INSTALL_PREFIX}/bin/\${dep_name}\")
                if(NOT EXISTS \"\${dest_dll}\")
                    file(COPY \"\${dep_dll}\" DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\")
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  ✓ Bundled: \${dep_name}\")
                    math(EXPR bundled_count \"\${bundled_count} + 1\")
                else()
                    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  - Exists: \${dep_name}\")
                endif()
            endif()
        endforeach()
        
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nBundled \${bundled_count} DLLs\")
        
        file(GLOB final_dlls \"\${CMAKE_INSTALL_PREFIX}/bin/*.dll\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\\nFinal bundle contents:\")
        foreach(final_dll \${final_dlls})
            get_filename_component(final_name \"\${final_dll}\" NAME)
            file(SIZE \"\${final_dll}\" dll_size)
            math(EXPR dll_size_kb \"\${dll_size} / 1024\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${final_name} (\${dll_size_kb} KB)\")
        endforeach()
        
    else()
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✗ Main DLL not found: \${MAIN_DLL}\")
        
        file(GLOB actual_files \"\${CMAKE_INSTALL_PREFIX}/bin/*\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Actually installed:\")
        foreach(file \${actual_files})
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${file}\")
        endforeach()
    endif()
")

message(STATUS "=== WINDOWS CMAKE DEBUG END ===")