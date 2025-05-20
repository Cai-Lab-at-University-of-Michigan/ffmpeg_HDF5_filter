#!/bin/bash
# Script to prepare native library structure for Java wrapper

set -e

# Create directory structure
mkdir -p imagej-hdf5-wrapper/lib/native/linux
mkdir -p imagej-hdf5-wrapper/lib/native/windows
mkdir -p imagej-hdf5-wrapper/lib/native/macos

echo "Creating directory structure for native libraries..."

# Define the target file names for each platform
LINUX_TARGET="libffmpegh5filter.so"
WINDOWS_TARGET="ffmpegh5filter.dll"
MACOS_TARGET="libffmpegh5filter.dylib"

# First, try to use libraries extracted from Python wheels (preferred)
WHEEL_LINUX_PATTERN="native_libs/linux/*.so"
WHEEL_WINDOWS_PATTERN="native_libs/windows/*.dll"
WHEEL_MACOS_PATTERN="native_libs/macos/*.dylib"

# Fallback patterns from FFmpeg artifacts
FFMPEG_LINUX_PATTERN="downloads/ffmpeg-Linux/lib/*ffmpeg*"
FFMPEG_WINDOWS_PATTERN="downloads/ffmpeg-Windows/bin/*ffmpeg*"
FFMPEG_MACOS_PATTERN="downloads/ffmpeg-macOS/lib/*ffmpeg*"

# Function to find and copy libraries with priority for wheel-extracted ones
find_and_copy_library() {
    local platform=$1
    local primary_pattern=$2
    local fallback_pattern=$3
    local target_file=$4
    local found=false
    
    echo "Processing $platform libraries..."
    
    # First try primary pattern (wheel libraries)
    echo "Searching for libraries from Python wheels: $primary_pattern"
    for file in $primary_pattern; do
        if [ -f "$file" ]; then
            echo "Found $platform library from Python wheel: $file"
            cp "$file" "imagej-hdf5-wrapper/lib/native/$platform/$target_file"
            echo "Copied and renamed to: imagej-hdf5-wrapper/lib/native/$platform/$target_file"
            found=true
            break
        fi
    done
    
    # If not found, try fallback pattern (FFmpeg artifacts)
    if [ "$found" = false ]; then
        echo "No libraries found from Python wheels, falling back to FFmpeg artifacts: $fallback_pattern"
        for file in $fallback_pattern; do
            if [ -f "$file" ]; then
                echo "Found $platform library from FFmpeg artifacts: $file"
                cp "$file" "imagej-hdf5-wrapper/lib/native/$platform/$target_file"
                echo "Copied and renamed to: imagej-hdf5-wrapper/lib/native/$platform/$target_file"
                found=true
                break
            fi
        done
    fi
    
    # Report if still not found
    if [ "$found" = false ]; then
        echo "Warning: No $platform libraries found from either Python wheels or FFmpeg artifacts"
    fi
}

# Process libraries for each platform
find_and_copy_library "linux" "$WHEEL_LINUX_PATTERN" "$FFMPEG_LINUX_PATTERN" "$LINUX_TARGET"
find_and_copy_library "windows" "$WHEEL_WINDOWS_PATTERN" "$FFMPEG_WINDOWS_PATTERN" "$WINDOWS_TARGET"
find_and_copy_library "macos" "$WHEEL_MACOS_PATTERN" "$FFMPEG_MACOS_PATTERN" "$MACOS_TARGET"

# List all copied libraries
echo "Native libraries prepared:"
find imagej-hdf5-wrapper/lib/native -type f | sort

# Check if any libraries were found and copied
if [ "$(find imagej-hdf5-wrapper/lib/native -type f | wc -l)" -eq 0 ]; then
    echo "ERROR: No libraries were found and copied for any platform!"
    exit 1
else
    echo "Native library preparation complete successfully"
fi