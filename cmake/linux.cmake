message(STATUS "=== LINUX CMAKE DEBUG START ===")

execute_process(COMMAND whoami OUTPUT_VARIABLE CURRENT_USER OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
execute_process(COMMAND pwd OUTPUT_VARIABLE CURRENT_DIR OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
message(STATUS "User: ${CURRENT_USER}, Dir: ${CURRENT_DIR}")
message(STATUS "HOME: $ENV{HOME}")

set(DEPS_ROOT "$ENV{HOME}")
set(FFMPEG_ROOT "${DEPS_ROOT}/ffmpeg")
set(HDF5_ROOT "${DEPS_ROOT}/miniconda")

message(STATUS "DEPS_ROOT: ${DEPS_ROOT}")
message(STATUS "FFMPEG_ROOT: ${FFMPEG_ROOT}")
message(STATUS "HDF5_ROOT: ${HDF5_ROOT}")

if(EXISTS "${DEPS_ROOT}")
    message(STATUS "✓ DEPS_ROOT exists")
    execute_process(COMMAND ls -la "${DEPS_ROOT}" OUTPUT_VARIABLE DEPS_LISTING ERROR_QUIET)
    message(STATUS "DEPS_ROOT contents:\n${DEPS_LISTING}")
else()
    message(WARNING "✗ DEPS_ROOT missing: ${DEPS_ROOT}")
endif()

if(EXISTS "${FFMPEG_ROOT}")
    message(STATUS "✓ FFMPEG_ROOT exists")
    execute_process(COMMAND find "${FFMPEG_ROOT}" -name "*.so*" -type f OUTPUT_VARIABLE FFMPEG_SO_FILES ERROR_QUIET)
    message(STATUS "FFmpeg .so files:\n${FFMPEG_SO_FILES}")
    
    if(EXISTS "${FFMPEG_ROOT}/lib")
        execute_process(COMMAND ls -la "${FFMPEG_ROOT}/lib" OUTPUT_VARIABLE FFMPEG_LIB_LISTING ERROR_QUIET)
        message(STATUS "FFMPEG lib:\n${FFMPEG_LIB_LISTING}")
    else()
        message(WARNING "✗ FFMPEG lib missing")
    endif()
    
    if(EXISTS "${FFMPEG_ROOT}/include")
        execute_process(COMMAND find "${FFMPEG_ROOT}/include" -name "*.h" | head -5 OUTPUT_VARIABLE FFMPEG_HEADERS ERROR_QUIET)
        message(STATUS "FFMPEG headers sample:\n${FFMPEG_HEADERS}")
    else()
        message(WARNING "✗ FFMPEG include missing")
    endif()
else()
    message(WARNING "✗ FFMPEG_ROOT missing: ${FFMPEG_ROOT}")
endif()

if(EXISTS "${HDF5_ROOT}")
    message(STATUS "✓ HDF5_ROOT exists")
    execute_process(COMMAND find "${HDF5_ROOT}" -name "*hdf5*" -type f OUTPUT_VARIABLE HDF5_FILES ERROR_QUIET)
    message(STATUS "HDF5 files:\n${HDF5_FILES}")
    
    if(EXISTS "${HDF5_ROOT}/lib")
        execute_process(COMMAND ls -la "${HDF5_ROOT}/lib" OUTPUT_VARIABLE HDF5_LIB_LISTING ERROR_QUIET)
        message(STATUS "HDF5 lib:\n${HDF5_LIB_LISTING}")
    else()
        message(WARNING "✗ HDF5 lib missing")
    endif()
else()
    message(WARNING "✗ HDF5_ROOT missing: ${HDF5_ROOT}")
endif()

execute_process(COMMAND pkg-config --list-all OUTPUT_VARIABLE PKG_LIST ERROR_QUIET)
if(PKG_LIST MATCHES "libavcodec")
    message(STATUS "✓ System FFmpeg packages detected")
    execute_process(COMMAND pkg-config --cflags libavcodec OUTPUT_VARIABLE AVCODEC_CFLAGS ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
    message(STATUS "System libavcodec CFLAGS: ${AVCODEC_CFLAGS}")
endif()

if(PKG_LIST MATCHES "hdf5")
    message(STATUS "✓ System HDF5 packages detected")
    execute_process(COMMAND pkg-config --cflags hdf5 OUTPUT_VARIABLE HDF5_CFLAGS ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
    message(STATUS "System HDF5 CFLAGS: ${HDF5_CFLAGS}")
endif()

execute_process(COMMAND find "${CMAKE_SOURCE_DIR}/.." -name "*artifact*" -type d OUTPUT_VARIABLE ARTIFACT_DIRS ERROR_QUIET)
if(ARTIFACT_DIRS)
    message(STATUS "Artifacts:\n${ARTIFACT_DIRS}")
endif()

find_path(FFMPEG_INCLUDE_DIR 
    NAMES libavcodec/avcodec.h
    PATHS 
        ${FFMPEG_ROOT}/include
        /usr/include
        /usr/local/include
        /usr/include/x86_64-linux-gnu
    DOC "FFmpeg include"
)

if(FFMPEG_INCLUDE_DIR)
    message(STATUS "✓ FFMPEG headers: ${FFMPEG_INCLUDE_DIR}")
else()
    message(WARNING "✗ FFMPEG headers not found")
    execute_process(COMMAND find /usr -name "avcodec.h" 2>/dev/null OUTPUT_VARIABLE AVCODEC_SEARCH ERROR_QUIET)
    if(AVCODEC_SEARCH)
        message(STATUS "System avcodec.h:\n${AVCODEC_SEARCH}")
    endif()
endif()

find_path(HDF5_INCLUDE_DIR 
    NAMES hdf5.h
    PATHS 
        ${HDF5_ROOT}/include
        /usr/include
        /usr/local/include
        /usr/include/hdf5/serial
    DOC "HDF5 include"
)

if(HDF5_INCLUDE_DIR)
    message(STATUS "✓ HDF5 headers: ${HDF5_INCLUDE_DIR}")
else()
    message(WARNING "✗ HDF5 headers not found")
    execute_process(COMMAND find /usr -name "hdf5.h" 2>/dev/null OUTPUT_VARIABLE HDF5_SEARCH ERROR_QUIET)
    if(HDF5_SEARCH)
        message(STATUS "System hdf5.h:\n${HDF5_SEARCH}")
    endif()
endif()

set(FFMPEG_LIBRARIES "")
foreach(lib avcodec avformat avutil swscale swresample avfilter)
    message(STATUS "Searching lib${lib}...")
    
    find_library(FFMPEG_${lib}_LIBRARY
        NAMES ${lib}
        PATHS 
            ${FFMPEG_ROOT}/lib
            /usr/lib
            /usr/local/lib
            /usr/lib/x86_64-linux-gnu
        DOC "FFmpeg ${lib}"
    )
    
    if(FFMPEG_${lib}_LIBRARY)
        list(APPEND FFMPEG_LIBRARIES ${FFMPEG_${lib}_LIBRARY})
        message(STATUS "✓ ${lib}: ${FFMPEG_${lib}_LIBRARY}")
        
        execute_process(COMMAND file "${FFMPEG_${lib}_LIBRARY}" OUTPUT_VARIABLE FILE_INFO ERROR_QUIET)
        message(STATUS "    ${FILE_INFO}")
    else()
        message(WARNING "✗ ${lib} NOT FOUND")
        execute_process(COMMAND find /usr -name "*${lib}*" -type f 2>/dev/null | head -2 OUTPUT_VARIABLE LIB_SEARCH ERROR_QUIET)
        if(LIB_SEARCH)
            message(STATUS "    Found: ${LIB_SEARCH}")
        endif()
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
    DOC "HDF5 C library"
)

if(HDF5_C_LIBRARY)
    message(STATUS "✓ HDF5: ${HDF5_C_LIBRARY}")
    execute_process(COMMAND file "${HDF5_C_LIBRARY}" OUTPUT_VARIABLE HDF5_FILE_INFO ERROR_QUIET)
    message(STATUS "    ${HDF5_FILE_INFO}")
else()
    message(WARNING "✗ HDF5 NOT FOUND")
    execute_process(COMMAND find /usr -name "*hdf5*" -type f 2>/dev/null | head -2 OUTPUT_VARIABLE HDF5_LIB_SEARCH ERROR_QUIET)
    if(HDF5_LIB_SEARCH)
        message(STATUS "    Found: ${HDF5_LIB_SEARCH}")
    endif()
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
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== LINUX INSTALL DEBUG ===\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install prefix: \${CMAKE_INSTALL_PREFIX}\")
    
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.so\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✓ Main lib: \${MAIN_LIB}\")
        
        execute_process(COMMAND file \"\${MAIN_LIB}\" OUTPUT_VARIABLE LIB_INFO ERROR_QUIET)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"File: \${LIB_INFO}\")
        
        execute_process(COMMAND ls -lh \"\${MAIN_LIB}\" OUTPUT_VARIABLE LIB_SIZE ERROR_QUIET)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Size: \${LIB_SIZE}\")
        
        execute_process(COMMAND ldd \"\${MAIN_LIB}\" OUTPUT_VARIABLE current_deps ERROR_QUIET)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Dependencies:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${current_deps}\")
        
        execute_process(
            COMMAND sh -c \"ldd '\${MAIN_LIB}' | grep 'not found' | wc -l\"
            OUTPUT_VARIABLE missing_count
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        
        if(missing_count GREATER 0)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"⚠️  WARNING: \${missing_count} missing dependencies!\")
            execute_process(
                COMMAND sh -c \"ldd '\${MAIN_LIB}' | grep 'not found'\"
                OUTPUT_VARIABLE missing_deps
                ERROR_QUIET
            )
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Missing: \${missing_deps}\")
        else()
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✓ All dependencies resolved\")
        endif()
        
        execute_process(COMMAND readelf -d \"\${MAIN_LIB}\" OUTPUT_VARIABLE RPATH_INFO ERROR_QUIET)
        if(RPATH_INFO MATCHES \"RPATH\")
            execute_process(COMMAND sh -c \"readelf -d '\${MAIN_LIB}' | grep RPATH\" OUTPUT_VARIABLE RPATH_LINE ERROR_QUIET)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"RPATH: \${RPATH_LINE}\")
        endif()
        
    else()
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✗ Main lib not found: \${MAIN_LIB}\")
        
        file(GLOB actual_libs \"\${CMAKE_INSTALL_PREFIX}/lib/*\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Actually installed:\")
        foreach(lib \${actual_libs})
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${lib}\")
        endforeach()
    endif()
")

message(STATUS "=== LINUX CMAKE DEBUG END ===")