message(STATUS "=== MACOS CMAKE DEBUG START ===")

execute_process(COMMAND whoami OUTPUT_VARIABLE CURRENT_USER OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
execute_process(COMMAND pwd OUTPUT_VARIABLE CURRENT_DIR OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
execute_process(COMMAND uname -a OUTPUT_VARIABLE SYSTEM_INFO OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
message(STATUS "User: ${CURRENT_USER}, Dir: ${CURRENT_DIR}")
message(STATUS "System: ${SYSTEM_INFO}")
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
    
    execute_process(COMMAND find "${DEPS_ROOT}" -name "*.dylib" -type f OUTPUT_VARIABLE FOUND_DYLIBS ERROR_QUIET)
    if(FOUND_DYLIBS)
        message(STATUS "Found .dylib files:\n${FOUND_DYLIBS}")
    else()
        message(STATUS "No .dylib files found")
    endif()
else()
    message(WARNING "✗ DEPS_ROOT missing: ${DEPS_ROOT}")
endif()

if(EXISTS "${FFMPEG_ROOT}")
    message(STATUS "✓ FFMPEG_ROOT exists")
    execute_process(COMMAND find "${FFMPEG_ROOT}" -name "*.dylib" -type f OUTPUT_VARIABLE FFMPEG_DYLIBS ERROR_QUIET)
    message(STATUS "FFmpeg .dylib files:\n${FFMPEG_DYLIBS}")
    
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

execute_process(COMMAND which brew OUTPUT_VARIABLE BREW_PATH ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
if(BREW_PATH)
    message(STATUS "✓ Homebrew: ${BREW_PATH}")
    execute_process(COMMAND brew list | grep -E "(ffmpeg|hdf5)" OUTPUT_VARIABLE BREW_PACKAGES ERROR_QUIET)
    if(BREW_PACKAGES)
        message(STATUS "Brew packages:\n${BREW_PACKAGES}")
    endif()
endif()

execute_process(COMMAND find "${CMAKE_SOURCE_DIR}/.." -name "*artifact*" -type d OUTPUT_VARIABLE ARTIFACT_DIRS ERROR_QUIET)
if(ARTIFACT_DIRS)
    message(STATUS "Artifacts:\n${ARTIFACT_DIRS}")
endif()

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
    message(STATUS "Searching lib${lib}...")
    
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
        
        execute_process(COMMAND file "${FFMPEG_${lib}_LIBRARY}" OUTPUT_VARIABLE FILE_INFO ERROR_QUIET)
        message(STATUS "    ${FILE_INFO}")
    else()
        message(WARNING "✗ ${lib} NOT FOUND")
        execute_process(COMMAND find /usr/local /opt/homebrew -name "*${lib}*" -type f 2>/dev/null | head -2 OUTPUT_VARIABLE LIB_SEARCH ERROR_QUIET)
        if(LIB_SEARCH)
            message(STATUS "    Found: ${LIB_SEARCH}")
        endif()
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
    execute_process(COMMAND file "${HDF5_C_LIBRARY}" OUTPUT_VARIABLE HDF5_FILE_INFO ERROR_QUIET)
    message(STATUS "    ${HDF5_FILE_INFO}")
else()
    message(WARNING "✗ HDF5 NOT FOUND")
    execute_process(COMMAND find /usr/local /opt/homebrew -name "*hdf5*" -type f 2>/dev/null | head -2 OUTPUT_VARIABLE HDF5_LIB_SEARCH ERROR_QUIET)
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

install(TARGETS h5ffmpeg_shared
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES src/ffmpeg_h5filter.h
    DESTINATION include
)

if(EXISTS "${FFMPEG_ROOT}/lib")
    file(GLOB FFMPEG_DYLIBS "${FFMPEG_ROOT}/lib/*.dylib")
    if(FFMPEG_DYLIBS)
        install(FILES ${FFMPEG_DYLIBS}
            DESTINATION lib
            OPTIONAL
        )
        message(STATUS "Will install FFmpeg dylibs: ${FFMPEG_DYLIBS}")
    endif()
endif()

install(CODE "
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"=== MACOS INSTALL DEBUG ===\")
    execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Install prefix: \${CMAKE_INSTALL_PREFIX}\")
    
    set(MAIN_LIB \"\${CMAKE_INSTALL_PREFIX}/lib/libh5ffmpeg_shared.dylib\")
    
    if(EXISTS \"\${MAIN_LIB}\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"✓ Main lib: \${MAIN_LIB}\")
        
        execute_process(COMMAND file \"\${MAIN_LIB}\" OUTPUT_VARIABLE LIB_INFO ERROR_QUIET)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"File: \${LIB_INFO}\")
        
        execute_process(COMMAND ls -lh \"\${MAIN_LIB}\" OUTPUT_VARIABLE LIB_SIZE ERROR_QUIET)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Size: \${LIB_SIZE}\")
        
        execute_process(COMMAND otool -L \"\${MAIN_LIB}\" OUTPUT_VARIABLE DEPS_BEFORE ERROR_QUIET)
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Dependencies before:\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${DEPS_BEFORE}\")
        
        file(GLOB bundle_dylibs \"\${CMAKE_INSTALL_PREFIX}/lib/*.dylib\")
        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Bundled libraries:\")
        foreach(dylib \${bundle_dylibs})
            get_filename_component(dylib_name \"\${dylib}\" NAME)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"  \${dylib_name}\")
        endforeach()
        
        find_program(INSTALL_NAME_TOOL install_name_tool)
        if(INSTALL_NAME_TOOL)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Fixing install names...\")
            
            foreach(dylib \${bundle_dylibs})
                get_filename_component(dylib_name \"\${dylib}\" NAME)
                if(NOT \"\${dylib}\" STREQUAL \"\${MAIN_LIB}\")
                    execute_process(
                        COMMAND otool -L \"\${MAIN_LIB}\"
                        COMMAND grep \"\${dylib_name}\"
                        OUTPUT_VARIABLE has_dep
                        ERROR_QUIET
                    )
                    if(has_dep)
                        execute_process(
                            COMMAND \"\${INSTALL_NAME_TOOL}\" -change 
                                \"$ENV{HOME}/ffmpeg/lib/\${dylib_name}\"
                                \"@loader_path/\${dylib_name}\"
                                \"\${MAIN_LIB}\"
                            ERROR_QUIET
                        )
                        execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"    Fixed: \${dylib_name}\")
                    endif()
                endif()
            endforeach()
            
            execute_process(COMMAND otool -L \"\${MAIN_LIB}\" OUTPUT_VARIABLE DEPS_AFTER ERROR_QUIET)
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"Dependencies after:\")
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"\${DEPS_AFTER}\")
        else()
            execute_process(COMMAND \${CMAKE_COMMAND} -E echo \"install_name_tool not found\")
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

message(STATUS "=== MACOS CMAKE DEBUG END ===")