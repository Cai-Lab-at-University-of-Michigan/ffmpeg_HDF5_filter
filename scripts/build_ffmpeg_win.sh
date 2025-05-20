#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Set build directories
ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/ffmpeg_build"
SRC_DIR="${ROOT_DIR}/ffmpeg_src"
mkdir -p "${BUILD_DIR}"
mkdir -p "${SRC_DIR}"
mkdir -p "${BUILD_DIR}/bin"
mkdir -p "${BUILD_DIR}/lib"
mkdir -p "${BUILD_DIR}/include"

# Convert to Windows paths when needed
WIN_BUILD_DIR=$(cygpath -w "${BUILD_DIR}" 2>/dev/null || echo "${BUILD_DIR}")
WIN_SRC_DIR=$(cygpath -w "${SRC_DIR}" 2>/dev/null || echo "${SRC_DIR}")

print_info "Building FFmpeg in ${BUILD_DIR}"
print_info "Source code will be in ${SRC_DIR}"

# Detect number of CPU cores for parallel builds
NPROC=$(nproc 2>/dev/null || echo 4)
print_info "Using ${NPROC} CPU cores for build"

# Set up environment variables
export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export PATH="${BUILD_DIR}/bin:${PATH}"

# Set compiler flags - Windows-specific
CFLAGS="-I${BUILD_DIR}/include -O2"
LDFLAGS="-L${BUILD_DIR}/lib"
EXTRAFLAGS="-lm -lstdc++"

# Function to download source using git
git_clone() {
    local repo_url=$1
    local target_dir=$2
    local depth=${3:-1}
    
    if [ ! -d "$target_dir" ]; then
        print_info "Cloning repository: $repo_url"
        git clone --depth $depth "$repo_url" "$target_dir"
    else
        print_info "Repository already exists: $target_dir. Updating..."
        cd "$target_dir"
        git pull
        cd - > /dev/null
    fi
}

# Function to download source files
download_source() {
    local url=$1
    local output_file=$2
    
    print_info "Downloading: $url"
    
    if command -v curl &> /dev/null; then
        curl -L -s -o "$output_file" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$output_file" "$url"
    else
        print_error "Neither curl nor wget is available. Cannot download files."
        exit 1
    fi
    
    if [ $? -ne 0 ]; then
        print_error "Failed to download: $url"
        exit 1
    fi
}

# Build x264
build_x264() {
    print_info "Building x264..."
    cd "${SRC_DIR}"
    git_clone "https://code.videolan.org/videolan/x264.git" "x264"
    cd x264
    
    # Configure for shared library and Python compatibility
    CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" ./configure \
        --prefix="${BUILD_DIR}" \
        --enable-shared \
        --enable-pic \
        --host=x86_64-w64-mingw32 \
        --cross-prefix=x86_64-w64-mingw32- \
        --disable-cli
    
    make -j${NPROC}
# Create combined static library
    mv libx265.a libx265_main.a
    ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

    make install
    
    # Copy DLL to bin directory for runtime loading
    cp "${BUILD_DIR}/lib/libx264"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    print_info "x264 build completed."
}

# Build x265
build_x265() {
    print_info "Building x265..."
    cd "${SRC_DIR}"
    git_clone "https://bitbucket.org/multicoreware/x265_git.git" "x265"
    
    # For multi-bit depth support
    mkdir -p x265/build/windows
    cd x265/build/windows
    mkdir -p 8bit 10bit 12bit
    
    # Build 12-bit
    cd 12bit
    cmake -G "MSYS Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DHIGH_BIT_DEPTH=ON \
        -DEXPORT_C_API=OFF \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
        -DMAIN12=ON \
        ../../../source
    make -j${NPROC}
    
    # Build 10-bit
    cd ../10bit
    cmake -G "MSYS Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DHIGH_BIT_DEPTH=ON \
        -DEXPORT_C_API=OFF \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
        ../../../source
    make -j${NPROC}
    
    # Build 8-bit with links to 10 and 12-bit
    cd ../8bit
    
    # Create symbolic links to the high bit depth libraries
    ln -sf ../10bit/libx265.a libx265_main10.a
    ln -sf ../12bit/libx265.a libx265_main12.a
    
    cmake -G "MSYS Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DEXTRA_LIB="x265_main10.a;x265_main12.a" \
        -DEXTRA_LINK_FLAGS=-L. \
        -DLINKED_10BIT=ON \
        -DLINKED_12BIT=ON \
        -DENABLE_CLI=OFF \
        -DENABLE_SHARED=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        ../../../source
    make -j${NPROC}
    make install
    
    # Copy DLL to bin directory for runtime loading
    cp "${BUILD_DIR}/lib/libx265"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    # Create pkg-config file if necessary
    if [ ! -f "${BUILD_DIR}/lib/pkgconfig/x265.pc" ]; then
        mkdir -p "${BUILD_DIR}/lib/pkgconfig"
        cat > "${BUILD_DIR}/lib/pkgconfig/x265.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: 3.5
Libs: -L\${libdir} -lx265
Libs.private: -lstdc++ -lm
Cflags: -I\${includedir}
EOF
    fi
    
    print_info "x265 build with multi-bit-depth support completed."
}

# Build dav1d (AV1 decoder)
build_dav1d() {
    print_info "Building dav1d (AV1 decoder)..."
    cd "${SRC_DIR}"
    git_clone "https://code.videolan.org/videolan/dav1d.git" "dav1d"
    
    mkdir -p dav1d/build
    cd dav1d/build
    
    # Configure with Meson for Windows
    meson setup \
        --prefix="${BUILD_DIR}" \
        --libdir=lib \
        --buildtype=release \
        --default-library=shared \
        --backend=ninja \
        ..
    
    ninja
    ninja install
    
    # Copy DLL to bin directory for runtime loading
    cp "${BUILD_DIR}/lib/libdav1d"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    print_info "dav1d build completed."
}

# Build SVT-AV1
build_svtav1() {
    print_info "Building SVT-AV1..."
    cd "${SRC_DIR}"
    git_clone "https://gitlab.com/AOMediaCodec/SVT-AV1.git" "SVT-AV1"
    cd SVT-AV1
    
    mkdir -p build
    cd build
    
    # Windows-specific CMake configuration
    cmake -G "MSYS Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        ..
    
    make -j${NPROC}
    make install
    
    # Copy DLL to bin directory for runtime loading
    cp "${BUILD_DIR}/lib/libSvtAv1"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    cp "${BUILD_DIR}/bin/SvtAv1"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    print_info "SVT-AV1 build completed."
}

# Build rav1e (Rust AV1 encoder)
build_rav1e() {
    print_info "Building rav1e (Rust AV1 encoder)..."
    cd "${SRC_DIR}"
    
    # Check if Rust is installed
    if ! command -v cargo &> /dev/null; then
        print_info "Rust is required for rav1e. Installing..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    git_clone "https://github.com/xiph/rav1e.git" "rav1e"
    cd rav1e
    
    # Check if x86_64-pc-windows-msvc target is installed
    if ! rustup target list | grep -q 'x86_64-pc-windows-msvc'; then
        print_info "Adding Windows target to Rust..."
        rustup target add x86_64-pc-windows-msvc
    fi
    
    # Build with cargo-c for C API
    if ! command -v cargo-cinstall &> /dev/null; then
        print_info "Installing cargo-c..."
        cargo install cargo-c
    fi
    
    # Build and install C API with shared library
    print_info "Building rav1e C API with cargo-c..."
    cargo cinstall --release --prefix="${BUILD_DIR}" --libdir="${BUILD_DIR}/lib" --includedir="${BUILD_DIR}/include" --library-type=cdylib
    
    if [ $? -ne 0 ]; then
        print_warning "cargo-c installation failed, trying alternative method..."
        
        # Alternative: Manual install
        cargo build --release
        
        # Create directories for manual installation
        mkdir -p "${BUILD_DIR}/lib"
        mkdir -p "${BUILD_DIR}/include/rav1e"
        
        # Install library
        cp target/release/rav1e.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
        cp target/release/rav1e.lib "${BUILD_DIR}/lib/" 2>/dev/null || true
        
        # Generate header
        if ! command -v cbindgen &> /dev/null; then
            cargo install cbindgen
        fi
        
        cbindgen --crate rav1e --output "${BUILD_DIR}/include/rav1e/rav1e.h"
        
        # Create pkg-config file
        mkdir -p "${BUILD_DIR}/lib/pkgconfig"
        cat > "${BUILD_DIR}/lib/pkgconfig/rav1e.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: rav1e
Description: The fastest and safest AV1 encoder
Version: 0.6.0
Libs: -L\${libdir} -lrav1e
Cflags: -I\${includedir}
EOF
    fi
    
    print_info "rav1e build completed."
}

# Build libaom (AV1 reference implementation)
build_libaom() {
    print_info "Building libaom (AV1 reference implementation)..."
    cd "${SRC_DIR}"
    
    git_clone "https://aomedia.googlesource.com/aom" "aom"
    
    # Configure and build with shared library
    mkdir -p aom_build
    cd aom_build
    
    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX=${BUILD_DIR}"
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
        "-DBUILD_SHARED_LIBS=ON"
        "-DCMAKE_SYSTEM_NAME=Windows"
        "-DENABLE_TESTS=OFF"
        "-DENABLE_EXAMPLES=OFF"
        "-DENABLE_TOOLS=OFF"
        "-DCONFIG_AV1_ENCODER=1"
        "-DCONFIG_AV1_DECODER=1"
        "-DCONFIG_MULTITHREAD=1"
    )
    
    cmake -G "MSYS Makefiles" "${CMAKE_ARGS[@]}" ../aom
    
    make -j${NPROC}
    make install
    
    # Copy DLL to bin directory for runtime loading
    cp "${BUILD_DIR}/bin/aom"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    print_info "libaom build completed."
}

# Build Xvid
build_xvid() {
    print_info "Building Xvid..."
    cd "${SRC_DIR}"
    
    # Remove any existing directory to avoid issues
    if [ -d "xvidcore" ]; then
        rm -rf xvidcore
    fi
    
    # Create a fresh directory
    mkdir -p xvidcore
    cd xvidcore
    
    # Download the archive
    print_info "Downloading Xvid..."
    download_source "https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz" "xvidcore-1.3.7.tar.gz"
    
    # Extract the tarball
    tar -xf xvidcore-1.3.7.tar.gz
    
    # Build for Windows - use the specific Windows build directory
    cd xvidcore/build/win32
    
    # Check if Visual Studio build is available, otherwise use generic
    if [ -f "./configure.exe" ]; then
        print_info "Using Windows build method for Xvid..."
        ./configure.exe --prefix="${BUILD_DIR}" --enable-shared
        make -j${NPROC}
        make install
    else
        # Fallback to generic build
        print_info "Falling back to generic build for Xvid..."
        cd ../generic
        ./configure --prefix="${BUILD_DIR}" --enable-shared --host=x86_64-w64-mingw32
        make -j${NPROC}
        make install
    fi
    
    # Copy DLL to bin directory for runtime loading
    cp "${BUILD_DIR}/lib/xvidcore"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    # Create pkg-config file
    mkdir -p "${BUILD_DIR}/lib/pkgconfig"
    cat > "${BUILD_DIR}/lib/pkgconfig/xvid.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: xvid
Description: Xvid MPEG-4 video codec
Version: 1.3.7
Libs: -L\${libdir} -lxvidcore
Cflags: -I\${includedir}
EOF
    
    print_info "Xvid build completed."
}

# Function to build nvenc support (headers only)
build_nvenc() {
    print_info "Setting up NVIDIA encoder/decoder headers..."
    cd "${SRC_DIR}"
    
    git_clone "https://github.com/FFmpeg/nv-codec-headers.git" "nv-codec-headers"
    cd nv-codec-headers
    
    # Use PREFIX for consistent cross-platform installation
    make install PREFIX="${BUILD_DIR}"
    print_info "NVIDIA headers installed."
}

# Function to verify pkg-config files
verify_pkg_config() {
    local package=$1
    local description=$2
    local lib_name=$3
    
    print_info "Verifying pkg-config for ${package}..."
    
    # Check if pkg-config file exists
    if [ ! -f "${BUILD_DIR}/lib/pkgconfig/${package}.pc" ]; then
        print_warning "pkg-config file for ${package} not found. Creating..."
        
        mkdir -p "${BUILD_DIR}/lib/pkgconfig"
        cat > "${BUILD_DIR}/lib/pkgconfig/${package}.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ${package}
Description: ${description}
Version: 1.0
Libs: -L\${libdir} -l${lib_name}
Libs.private: -lm -pthread
Cflags: -I\${includedir}
EOF
    fi
}

# Build Intel Media SDK/oneVPL for QSV support
build_qsv() {
    print_info "Building Intel oneVPL (Video Processing Library) for QSV support on Windows..."
    cd "${SRC_DIR}"
    
    # Clone and build oneVPL
    git_clone "https://github.com/oneapi-src/oneVPL.git" "oneVPL"
    cd oneVPL
    mkdir -p build
    cd build
    
    # Configure with shared library for Python compatibility
    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX=${BUILD_DIR}"
        "-DBUILD_SHARED_LIBS=ON"
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
        "-DBUILD_TOOLS=OFF"
        "-DBUILD_EXAMPLES=OFF"
        "-DBUILD_TESTS=OFF"
        "-DCMAKE_SYSTEM_NAME=Windows"
    )
    
    cmake -G "MSYS Makefiles" "${CMAKE_ARGS[@]}" ..
    
    make -j${NPROC}
    make install
    
    # Create proper symbolic links if needed
    if [ -d "${BUILD_DIR}/include/vpl" ]; then
        # For compatibility with older code, link vpl to mfx
        mkdir -p "${BUILD_DIR}/include/mfx"
        print_info "Creating compatibility links from vpl to mfx"
        cp -r "${BUILD_DIR}/include/vpl/"* "${BUILD_DIR}/include/mfx/" 2>/dev/null || true
    fi
    
    # Copy DLLs to bin directory
    cp "${BUILD_DIR}/lib/"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    print_info "Intel oneVPL build completed."
    
    # Verify installation
    if [ -d "${BUILD_DIR}/include/vpl" ]; then
        print_info "Intel oneVPL headers found."
        # Create pkg-config file for libvpl if not present
        if [ ! -f "${BUILD_DIR}/lib/pkgconfig/libvpl.pc" ]; then
            mkdir -p "${BUILD_DIR}/lib/pkgconfig"
            cat > "${BUILD_DIR}/lib/pkgconfig/libvpl.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libvpl
Description: Intel oneAPI Video Processing Library
Version: 2.8.0
Libs: -L\${libdir} -lvpl
Cflags: -I\${includedir}
EOF
            print_info "Created pkg-config file for libvpl"
        fi
    else
        print_warning "Intel oneVPL headers not found, QSV support may be limited"
    fi
}

# Build FFmpeg
build_ffmpeg() {
    print_info "Building FFmpeg for Windows..."
    cd "${SRC_DIR}"
    git_clone "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
    
    cd ffmpeg
    
    # Check for QSV support
    if [ -d "${BUILD_DIR}/include/vpl" ]; then
        INTEL_MEDIA_OPTION="--enable-libvpl"
        print_info "Enabling Intel QSV support via oneVPL"
    else
        INTEL_MEDIA_OPTION=""
        print_warning "Intel QSV support not available"
    fi
    
    # Add CUDA support if nvcc is available
    if command -v nvcc &> /dev/null; then
        NVIDIA_FLAGS="--enable-cuda-nvcc --enable-libnpp"
        print_info "Enabling full NVIDIA CUDA support"
    else
        print_warning "CUDA compiler not available..."
        NVIDIA_FLAGS=""
    fi
    
    # Basic configuration
    CONFIG_OPTIONS=(
        "--prefix=${BUILD_DIR}"
        "--extra-cflags=${CFLAGS}"
        "--extra-ldflags=${LDFLAGS}"
        "--extra-libs=${EXTRAFLAGS}"
        "--arch=x86_64"
        "--target-os=mingw64"
        "--enable-shared"
        "--disable-static"
        "--enable-pic"
        "--enable-gpl"
        "--enable-nonfree"
        "--enable-version3"
        
        # Standard codecs
        "--enable-libxvid"
        "--enable-libx264"
        "--enable-libx265"
        
        # AV1 codecs
        "--enable-libaom"
        "--enable-librav1e"
        "--enable-libsvtav1"
        "--enable-libdav1d"
        
        # Hardware acceleration
        ${NVIDIA_FLAGS}
        ${INTEL_MEDIA_OPTION}
        
        # Additional options
        "--enable-avfilter"
        "--enable-runtime-cpudetect"
        "--disable-doc"
        "--disable-ffplay"
        "--disable-debug"
        "--disable-stripping"  # Important for debugging
    )
    
    # Configure FFmpeg
    ./configure "${CONFIG_OPTIONS[@]}"
    
    # Build and install
    make -j${NPROC}
    make install
    
    # Ensure all DLLs are in the bin directory
    print_info "Copying FFmpeg DLLs to bin directory..."
    cp "${BUILD_DIR}/bin/"*.dll "${BUILD_DIR}/bin/" 2>/dev/null || true
    
    print_info "FFmpeg build completed."
}

# Verify the build
verify_build() {
    print_info "Verifying FFmpeg build..."
    
    export PATH="${BUILD_DIR}/bin:$PATH"# Verify the build for Windows
verify_build() {
    print_info "Verifying FFmpeg build..."
    
    # Set proper PATH for Windows
    export PATH="${BUILD_DIR}/bin:$PATH"
    
    # Verify FFmpeg executables
    if [ ! -f "${BUILD_DIR}/bin/ffmpeg.exe" ]; then
        print_error "FFmpeg executable not found!"
        exit 1
    fi
    
    # Check version
    "${BUILD_DIR}/bin/ffmpeg.exe" -version
    
    # Verify libraries - Windows uses DLLs
    if [ -z "$(ls -A ${BUILD_DIR}/bin/*.dll 2>/dev/null)" ]; then
        print_error "FFmpeg DLLs not found!"
        exit 1
    fi
    print_info "Found $(ls -1 ${BUILD_DIR}/bin/*.dll | wc -l) DLL files"
    
    # Verify headers
    if [ ! -d "${BUILD_DIR}/include/libavcodec" ] || [ ! -d "${BUILD_DIR}/include/libavutil" ]; then
        print_error "FFmpeg headers not found!"
        exit 1
    fi
    print_info "FFmpeg headers verified"
    
    # Verify pkg-config files
    if [ ! -d "${BUILD_DIR}/lib/pkgconfig" ] || [ -z "$(ls -A ${BUILD_DIR}/lib/pkgconfig/lib*.pc 2>/dev/null)" ]; then
        print_error "FFmpeg pkg-config files not found!"
        exit 1
    fi
    print_info "pkg-config files verified"
    
    # Check for QSV support
    print_info "Checking for QSV support:"
    if "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep -q qsv; then
        print_info "QSV encoders found"
        "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep qsv | head -n 5
    else
        print_warning "No QSV encoders found"
    fi
    
    # Check for NVIDIA support
    print_info "Checking for NVIDIA support:"
    "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep nvenc || print_warning "No NVENC encoders found"
    
    # Check for AV1 support
    print_info "Checking for AV1 support:"
    "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep av1 || print_warning "No AV1 encoders found"
    
    print_info "FFmpeg build verification completed successfully."
}

# Main build process
main() {
    print_info "Starting FFmpeg build process for Windows..."
    
    # Build dependencies
    build_x264
    build_x265
    build_dav1d
    build_svtav1
    build_rav1e
    build_libaom
    build_xvid
    
    # Build QSV support
    build_qsv
    
    # NVIDIA headers
    build_nvenc
    
    # Verify pkg-config files before FFmpeg build
    verify_pkg_config "x264" "H.264/AVC video encoder" "x264" 
    verify_pkg_config "x265" "H.265/HEVC video encoder" "x265"
    verify_pkg_config "dav1d" "AV1 decoder" "dav1d"
    verify_pkg_config "rav1e" "AV1 encoder" "rav1e"
    verify_pkg_config "aom" "AV1 codec library" "aom"
    verify_pkg_config "xvid" "Xvid MPEG-4 video codec" "xvidcore"
    
    # Build FFmpeg
    build_ffmpeg
    
    # Verify build
    verify_build
    
    print_info "======================================="
    print_info "FFmpeg build successful!"
    print_info "FFmpeg binaries: ${BUILD_DIR}/bin"
    print_info "FFmpeg libraries: ${BUILD_DIR}/lib"
    print_info "FFmpeg headers: ${BUILD_DIR}/include"
    print_info "======================================="
    
    # Create a marker file for the build process
    touch "${BUILD_DIR}/.build_completed"
}

# Execute main
main "$@"