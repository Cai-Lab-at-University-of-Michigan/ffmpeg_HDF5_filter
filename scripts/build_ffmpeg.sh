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

# Detect number of CPU cores for parallel builds
if [ "$(uname)" == "Darwin" ]; then
    # macOS
    NPROC=$(sysctl -n hw.ncpu)
    OS="macos"
    # Detect Mac architecture
    if [ "$(uname -m)" == "arm64" ]; then
        MAC_ARCH="arm64"
        print_info "Detected macOS (Apple Silicon)"
    else
        MAC_ARCH="x86_64"
        print_info "Detected macOS (Intel)"
    fi
elif [ "$(uname)" == "Linux" ]; then
    # Linux
    NPROC=$(nproc)
    OS="linux"
    print_info "Detected Linux"
else
    print_error "Unsupported OS, this script is for Linux/macOS only"
    print_info "For Windows, use build_ffmpeg_win.sh"
    exit 1
fi

print_info "Building FFmpeg in ${BUILD_DIR}"
print_info "Source code will be in ${SRC_DIR}"
print_info "Using ${NPROC} CPU cores for build"

# Set up environment variables
export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export PATH="${BUILD_DIR}/bin:${PATH}"

# Set compiler flags
CFLAGS="-I${BUILD_DIR}/include -O3"
LDFLAGS="-L${BUILD_DIR}/lib"
EXTRAFLAGS="-lm -lstdc++ -lnuma"

# For macOS, ensure libraries can be found at runtime
if [ "$OS" == "macos" ]; then
    LDFLAGS+=" -Wl,-rpath,@loader_path/../lib"
fi

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
    ./configure \
        --prefix="${BUILD_DIR}" \
        --enable-shared \
        --enable-pic \
        --disable-cli
    
    make -j${NPROC}
    make install
    
    print_info "x264 build completed."
}

# Build x265
build_x265() {
    print_info "Building x265..."
    cd "${SRC_DIR}"
    git_clone "https://bitbucket.org/multicoreware/x265_git.git" "x265"

    BUILD_DIR_X265="linux"
    if [ "$OS" == "macos" ]; then
        BUILD_DIR_X265="macos"
    fi

    mkdir -p x265/build/${BUILD_DIR_X265}
    cd x265/build/${BUILD_DIR_X265}
    mkdir -p 8bit 10bit 12bit

    # Build 12-bit
    cd 12bit
    cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DHIGH_BIT_DEPTH=ON \
        -DEXPORT_C_API=ON \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
        -DMAIN12=ON \
        ../../../source
    make -j${NPROC}

    # Build 10-bit
    cd ../10bit
    cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DHIGH_BIT_DEPTH=ON \
        -DEXPORT_C_API=ON \
        -DENABLE_SHARED=OFF \
        -DENABLE_CLI=OFF \
        ../../../source
    make -j${NPROC}

    # Build 8-bit with links to 10 and 12-bit
    cd ../8bit
    ln -sf ../10bit/libx265.a libx265_main10.a
    ln -sf ../12bit/libx265.a libx265_main12.a

    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX=${BUILD_DIR}"
        "-DEXTRA_LIB=x265_main10.a;x265_main12.a"
        "-DEXTRA_LINK_FLAGS=-L."
        "-DLINKED_10BIT=ON"
        "-DLINKED_12BIT=ON"
        "-DENABLE_SHARED=OFF"
        "-DENABLE_CLI=OFF"
    )

    if [ "$OS" == "macos" ] && [ "$MAC_ARCH" == "arm64" ]; then
        CMAKE_ARGS+=("-DCMAKE_OSX_ARCHITECTURES=arm64")
    fi

    cmake "${CMAKE_ARGS[@]}" ../../../source
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

    # Create/update pkg-config file
    PKG_CONFIG_FILE="${BUILD_DIR}/lib/pkgconfig/x265.pc"
    if [ -f "$PKG_CONFIG_FILE" ]; then
        sed -i 's/Libs: \(.*\)/Libs: \1 -lm -lstdc++ -lnuma/' "$PKG_CONFIG_FILE"
    else
        mkdir -p "${BUILD_DIR}/lib/pkgconfig"
        cat > "$PKG_CONFIG_FILE" << EOF
Name: x265
Description: H.265/HEVC video encoder
Version: $(grep '#define X265_VERSION' "${SRC_DIR}/x265/source/x265.h" | awk '{print $3}' | tr -d '"')
Libs: -L${BUILD_DIR}/lib -lx265 -lm -lstdc++ -lnuma
Cflags: -I${BUILD_DIR}/include
EOF
    fi

    export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig:$PKG_CONFIG_PATH"
    
    print_info "x265 build completed."
}

# Build dav1d (AV1 decoder)
build_dav1d() {
    print_info "Building dav1d (AV1 decoder)..."
    cd "${SRC_DIR}"
    git_clone "https://code.videolan.org/videolan/dav1d.git" "dav1d"
    
    mkdir -p dav1d/build
    cd dav1d/build
    
    # Configure with shared library for Python compatibility
    MESON_ARGS=(
        "--prefix=${BUILD_DIR}"
        "--libdir=lib"
        "--buildtype=release"
        "--default-library=shared"
    )
    
    # Architecture-specific options
    if [ "$OS" == "macos" ] && [ "$MAC_ARCH" == "arm64" ]; then
        # Set cross-file for Apple Silicon
        cat > crossfile.ini << EOF
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
EOF
        MESON_ARGS+=("--cross-file" "crossfile.ini")
    fi
    
    meson setup "${MESON_ARGS[@]}" ..
    ninja
    ninja install
    
    print_info "dav1d build completed."
}

# Build SVT-AV1
build_svtav1() {
    print_info "Building SVT-AV1..."
    cd "${SRC_DIR}"
    git_clone "https://gitlab.com/AOMediaCodec/SVT-AV1.git" "SVT-AV1"
    cd SVT-AV1
    
    # Configure and build with shared libraries
    mkdir -p build
    cd build
    
    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX=${BUILD_DIR}"
        "-DBUILD_SHARED_LIBS=ON"
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    )
    
    # Architecture-specific options
    if [ "$OS" == "macos" ] && [ "$MAC_ARCH" == "arm64" ]; then
        CMAKE_ARGS+=("-DCMAKE_OSX_ARCHITECTURES=arm64")
    fi
    
    cmake "${CMAKE_ARGS[@]}" ..
    make -j${NPROC}
    make install
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
    
    # Architecture-specific configuration
    if [ "$OS" == "macos" ] && [ "$MAC_ARCH" == "arm64" ]; then
        # For Apple Silicon, add the ARM target
        rustup target add aarch64-apple-darwin
        CARGO_ARGS="--target=aarch64-apple-darwin"
    else
        CARGO_ARGS=""
    fi
    
    # Build with cargo-c for C API
    if ! command -v cargo-cinstall &> /dev/null; then
        print_info "Installing cargo-c..."
        cargo install cargo-c
    fi
    
    # Build and install C API with shared library
    print_info "Building rav1e C API with cargo-c..."
    cargo cinstall ${CARGO_ARGS} --release --prefix="${BUILD_DIR}" --libdir="${BUILD_DIR}/lib" --includedir="${BUILD_DIR}/include" --library-type=cdylib
    
    if [ $? -ne 0 ]; then
        print_warning "cargo-c installation failed, trying alternative method..."
        
        # Alternative: Build with cargo build
        print_info "Building rav1e with cargo build..."
        cargo build ${CARGO_ARGS} --release
        
        # Create directories for manual installation
        mkdir -p "${BUILD_DIR}/lib"
        mkdir -p "${BUILD_DIR}/include/rav1e"
        
        # Install library
        if [ "$OS" == "macos" ]; then
            # macOS
            if [ -f "target/release/librav1e.dylib" ]; then
                cp target/release/librav1e.dylib "${BUILD_DIR}/lib/"
            elif [ -f "target/aarch64-apple-darwin/release/librav1e.dylib" ]; then
                cp target/aarch64-apple-darwin/release/librav1e.dylib "${BUILD_DIR}/lib/"
            fi
        else
            # Linux
            if [ -f "target/release/librav1e.so" ]; then
                cp target/release/librav1e.so "${BUILD_DIR}/lib/"
            fi
        fi
        
        # Generate and install header
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
        "-DENABLE_TESTS=OFF"
        "-DENABLE_EXAMPLES=OFF"
        "-DENABLE_TOOLS=OFF"
        "-DCONFIG_AV1_ENCODER=1"
        "-DCONFIG_AV1_DECODER=1"
        "-DCONFIG_MULTITHREAD=1"
    )
    
    # Architecture-specific options
    if [ "$OS" == "macos" ] && [ "$MAC_ARCH" == "arm64" ]; then
        CMAKE_ARGS+=("-DCMAKE_OSX_ARCHITECTURES=arm64")
        CMAKE_ARGS+=("-DAOM_TARGET_CPU=arm64")
    fi
    
    cmake "${CMAKE_ARGS[@]}" ../aom
    
    make -j${NPROC}
    make install
    
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
    
    # Navigate to build/generic
    cd xvidcore/build/generic
    
    # Configure for shared library
    ./configure \
        --prefix="${BUILD_DIR}" \
        --enable-shared
    
    make -j${NPROC}
    make install
    
    # Some systems install to lib64 instead of lib
    if [ -d "${BUILD_DIR}/lib64" ]; then
        if [ ! -d "${BUILD_DIR}/lib" ]; then
            mkdir -p "${BUILD_DIR}/lib"
        fi
        cp -a "${BUILD_DIR}/lib64/"* "${BUILD_DIR}/lib/"
    fi
    
    # Create pkg-config file for Xvid
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

# Build Intel Media SDK/oneVPL for QSV support (Linux only)
build_qsv() {
    if [ "$OS" != "linux" ]; then
        print_info "Skipping Intel Media SDK build for non-Linux OS"
        return
    fi
    
    print_info "Building Intel oneVPL (Video Processing Library) for QSV support..."
    cd "${SRC_DIR}"
    
    # Clone and build oneVPL
    git_clone "https://github.com/oneapi-src/oneVPL.git" "oneVPL"
    cd oneVPL
    mkdir -p build
    cd build
    
    # Configure with shared library for Python compatibility
    cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_TOOLS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTS=OFF \
        ..
    make -j${NPROC}
    make install
    
    # Create proper symbolic links if needed
    ln -sf "${BUILD_DIR}/include/vpl" "${BUILD_DIR}/include/mfx"
    
    print_info "Intel oneVPL build completed."
    
    # Build Intel libva for Linux QSV support
    print_info "Building libva for QSV hardware access..."
    cd "${SRC_DIR}"
    git_clone "https://github.com/intel/libva.git" "libva"
    cd libva
    ./autogen.sh
    ./configure --prefix="${BUILD_DIR}" --enable-shared
    make -j${NPROC}
    make install
    
    print_info "Intel libva build completed."
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

# Build FFmpeg
build_ffmpeg() {
    print_info "Building FFmpeg..."
    cd "${SRC_DIR}"
    git_clone "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
    
    cd ffmpeg
    
    print_info "Using libvpl (Intel oneVPL) for QSV support"
    INTEL_MEDIA_OPTION="--enable-libvpl"
    
    # Add CUDA support if nvcc is available
    if command -v nvcc &> /dev/null; then
        NVIDIA_FLAGS="--enable-cuda-nvcc --enable-libnpp"
        print_info "Enabling full NVIDIA CUDA support"
    else
        print_warning "CUDA compiler not available..."
    fi
    
    # Basic configuration
    CONFIG_OPTIONS=(
        "--prefix=${BUILD_DIR}"
        "--extra-cflags=${CFLAGS}"
        "--extra-ldflags=${LDFLAGS}"
        "--extra-libs=${EXTRAFLAGS}"
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
        
        # Additional formats
        "--enable-libvorbis"
        "--enable-libopus"
        "--enable-libvpx"
        
        # Hardware acceleration
        ${NVIDIA_FLAGS}
        
        # Additional options
        "--enable-avfilter"
        "--enable-runtime-cpudetect"
        "--disable-doc"
        "--disable-ffplay"
        "--disable-debug"
        "--disable-stripping"  # Important for debugging
    )
    
    # OS-specific options
    if [ "$OS" == "linux" ]; then
        CONFIG_OPTIONS+=(
            ${INTEL_MEDIA_OPTION}
            "--enable-libdrm"
            "--enable-vaapi"
            "--enable-vdpau"
        )
    elif [ "$OS" == "macos" ]; then
        CONFIG_OPTIONS+=(
            "--enable-videotoolbox"
            "--enable-audiotoolbox"
        )
        
        # Apple Silicon-specific options
        if [ "$MAC_ARCH" == "arm64" ]; then
            CONFIG_OPTIONS+=(
                "--arch=arm64"
                "--enable-neon"
            )
        fi
    fi
    
    # Configure FFmpeg
    ./configure "${CONFIG_OPTIONS[@]}"
    
    # Build and install
    make -j${NPROC}
    make install
    
    print_info "FFmpeg build completed."
}

# Verify the build
verify_build() {
    print_info "Verifying FFmpeg build..."
    
    # Verify FFmpeg executables
    if [ ! -f "${BUILD_DIR}/bin/ffmpeg" ]; then
        print_error "FFmpeg executable not found!"
        exit 1
    fi
    
    # Check version
    "${BUILD_DIR}/bin/ffmpeg" -version
    
    # Verify libraries
    if [ "$OS" == "macos" ]; then
        # macOS uses dylib
        if [ ! -d "${BUILD_DIR}/lib" ] || [ -z "$(ls -A ${BUILD_DIR}/lib/*.dylib 2>/dev/null)" ]; then
            print_error "FFmpeg libraries not found!"
            exit 1
        fi
        print_info "Found $(ls -1 ${BUILD_DIR}/lib/*.dylib | wc -l) dylib files"
    else
        # Linux uses so
        if [ ! -d "${BUILD_DIR}/lib" ] || [ -z "$(ls -A ${BUILD_DIR}/lib/*.so* 2>/dev/null)" ]; then
            print_error "FFmpeg libraries not found!"
            exit 1
        fi
        print_info "Found $(ls -1 ${BUILD_DIR}/lib/*.so* | wc -l) shared objects"
    fi
    
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
    if [ "$OS" == "linux" ]; then
        print_info "Checking for QSV support:"
        "${BUILD_DIR}/bin/ffmpeg" -encoders | grep qsv || print_warning "No QSV encoders found"
    fi
    
    # Check for NVIDIA support
    print_info "Checking for NVIDIA support:"
    "${BUILD_DIR}/bin/ffmpeg" -encoders | grep nvenc || print_warning "No NVENC encoders found"
    
    # Check for AV1 support
    print_info "Checking for AV1 support:"
    "${BUILD_DIR}/bin/ffmpeg" -encoders | grep av1 || print_warning "No AV1 encoders found"
    
    print_info "FFmpeg build verification completed successfully."
}

# Create rpath_tool for macOS
if [ "$OS" == "macos" ]; then
    fix_macos_libraries() {
        print_info "Fixing library paths for macOS..."
        
        # Create a script to fix library paths
        cat > ${BUILD_DIR}/fix_rpath.sh << 'EOF'
#!/bin/bash
# Fix library install names and RPATHs for macOS

LIB_DIR="$1"
if [ -z "$LIB_DIR" ]; then
    echo "Usage: $0 <library_directory>"
    exit 1
fi

# Function to fix a single dylib
fix_dylib() {
    local dylib="$1"
    local basename="$(basename "$dylib")"
    
    echo "Fixing $basename..."
    
    # Change ID
    install_name_tool -id "@rpath/$basename" "$dylib"
    
    # Fix dependencies on other FFmpeg libraries
    for dep in $(otool -L "$dylib" | grep libav | awk '{print $1}'); do
        depname="$(basename "$dep")"
        if [ "$depname" != "$basename" ]; then
            install_name_tool -change "$dep" "@rpath/$depname" "$dylib"
        fi
    done
    
    # Fix dependencies on external libraries
    for dep in $(otool -L "$dylib" | grep -E '/opt/|/usr/local/' | awk '{print $1}'); do
        depname="$(basename "$dep")"
        install_name_tool -change "$dep" "@rpath/$depname" "$dylib"
    done
    
    # Add RPATH if needed
    current_rpath=$(otool -l "$dylib" | grep -A2 LC_RPATH | grep path | awk '{print $2}')
    if [ -z "$current_rpath" ]; then
        install_name_tool -add_rpath "@loader_path" "$dylib"
    fi
}

# Fix all dylibs in directory
for dylib in "$LIB_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then
        fix_dylib "$dylib"
    fi
done

echo "All libraries fixed!"
EOF
        
        chmod +x ${BUILD_DIR}/fix_rpath.sh
        ${BUILD_DIR}/fix_rpath.sh ${BUILD_DIR}/lib
        
        print_info "macOS library paths fixed."
    }
fi

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

# Main build process
main() {
    print_info "Starting FFmpeg build process for Python package..."
    
    # Build dependencies
    build_x264
    build_x265
    build_dav1d
    build_svtav1
    build_rav1e
    build_libaom
    build_xvid
    
    # OS-specific dependencies
    if [ "$OS" == "linux" ]; then
        build_qsv
    fi
    
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
    
    # Fix macOS library paths if needed
    if [ "$OS" == "macos" ]; then
        fix_macos_libraries
    fi
    
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