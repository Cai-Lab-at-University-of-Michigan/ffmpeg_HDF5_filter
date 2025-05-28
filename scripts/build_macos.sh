#!/bin/bash

set -e 

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

# Verify ARM64 architecture
check_arm64() {
    if [ "$(uname -m)" != "arm64" ]; then
        print_error "This script is designed for arm64 architecture only!"
        print_error "Current architecture: $(uname -m)"
        print_warning "The build will continue but may not work correctly on non-arm64 hosts."
    else
        print_info "Confirmed arm64 architecture"
    fi
}

# Install macOS dependencies
install_dependencies() {
    print_info "Installing FFmpeg build dependencies for macOS (arm64)..."
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_info "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add brew to the path (specifically for Apple Silicon)
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    
    # Update Homebrew and install dependencies
    brew update
    
    # Install basic build tools
    brew install \
        cmake \
        automake \
        autoconf \
        libtool \
        nasm \
        yasm \
        meson
    
    # Install Python-specific dependencies
    brew install \
        python \
        swig \
        hdf5 \
        numpy
    
    # Install Rust for rav1e if not detected
    if ! command -v cargo &> /dev/null; then
        print_info "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
        # Install cargo-c for C API generation
        cargo install cargo-c
    fi
    
    print_info "macOS arm64 dependencies installed successfully."
}

# Set build directories
ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/ffmpeg_build"
SRC_DIR="${ROOT_DIR}/ffmpeg_src"
mkdir -p "${BUILD_DIR}"
mkdir -p "${SRC_DIR}"

# Force arm64 architecture
MAC_ARCH="arm64"
print_info "Building for macOS arm64 architecture (Apple Silicon)"

print_info "Building FFmpeg in ${BUILD_DIR}"
print_info "Source code will be in ${SRC_DIR}"

# Detect number of CPU cores for parallel builds
NPROC=$(sysctl -n hw.ncpu)
print_info "Using ${NPROC} CPU cores for build"

# Set up environment variables
export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export PATH="${BUILD_DIR}/bin:${PATH}"

# Set compiler flags for ARM64
export MACOSX_DEPLOYMENT_TARGET=11.0
export ARCHFLAGS="-arch arm64"
export CFLAGS="-I${BUILD_DIR}/include -O3 -arch arm64"
export CXXFLAGS="-I${BUILD_DIR}/include -O3 -arch arm64"
export LDFLAGS="-L${BUILD_DIR}/lib -Wl,-rpath,@loader_path/../lib -arch arm64"

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
    print_info "Building x264 for arm64..."
    cd "${SRC_DIR}"
    git_clone "https://code.videolan.org/videolan/x264.git" "x264"
    cd x264
    
    # Configure for shared library and Python compatibility
    ./configure \
        --prefix="${BUILD_DIR}" \
        --enable-shared \
        --enable-pic \
        --disable-cli \
        --host=aarch64-apple-darwin \
        --extra-cflags="-arch arm64" \
        --extra-ldflags="-arch arm64"
    
    make -j${NPROC}
    make install
    
    print_info "x264 build completed for arm64."
}

# Build x265
build_x265() {
    print_info "Building x265 for arm64..."
    cd "${SRC_DIR}"
    git_clone "https://bitbucket.org/multicoreware/x265_git.git" "x265"

    mkdir -p x265/build
    cd x265/build
    
    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX=${BUILD_DIR}"
        "-DENABLE_SHARED=ON"
        "-DENABLE_CLI=OFF"
        "-DEXPORT_C_API=ON"
        "-DCMAKE_OSX_ARCHITECTURES=arm64"
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
        "-DHIGH_BIT_DEPTH=ON"
        "-DENABLE_ASSEMBLY=ON"
        "-DMAIN10=ON"
        "-DMAIN12=ON"
        # Use -O3 optimization
        "-DCMAKE_C_FLAGS=-arch arm64 -O3"
        "-DCMAKE_CXX_FLAGS=-arch arm64 -O3"
    )
    
    cmake -G "Unix Makefiles" "${CMAKE_ARGS[@]}" ../source
    
    print_info "Building x265..."
    make -j${NPROC}
    make install
    
    # Update pkg-config file to include C++ standard library
    PKG_CONFIG_FILE="${BUILD_DIR}/lib/pkgconfig/x265.pc"
    if [ -f "$PKG_CONFIG_FILE" ]; then
        sed -i '' 's/Libs: \(.*\)/Libs: \1 -lm -lstdc++/' "$PKG_CONFIG_FILE"
    else
        mkdir -p "${BUILD_DIR}/lib/pkgconfig"
        cat > "$PKG_CONFIG_FILE" << EOF
Name: x265
Description: H.265/HEVC video encoder
Version: $(grep '#define X265_VERSION' "${SRC_DIR}/x265/source/x265.h" | awk '{print $3}' | tr -d '"')
Libs: -L${BUILD_DIR}/lib -lx265 -lm -lstdc++
Cflags: -I${BUILD_DIR}/include
EOF
    fi

    export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig:$PKG_CONFIG_PATH"
    
    print_info "Checking x265 library architecture..."
    lipo -info "${BUILD_DIR}/lib/libx265.dylib" || print_warning "Could not verify architecture"
    
    print_info "x265 build completed for arm64."
}

# Build dav1d (AV1 decoder)
build_dav1d() {
    print_info "Building dav1d (AV1 decoder) for arm64..."
    cd "${SRC_DIR}"
    git_clone "https://code.videolan.org/videolan/dav1d.git" "dav1d"
    
    mkdir -p dav1d/build
    cd dav1d/build
    
    # Configure with shared library for Python compatibility
    MESON_ARGS=(
        "--prefix=${BUILD_DIR}"
        "--libdir=lib"
        "--default-library=shared"
        "-Db_pgo=generate"
        "-Dc_args=-march=native"
        "-Dcpp_args=-march=native"
    )
    
    meson setup "${MESON_ARGS[@]}" ..
    ninja
    ninja install
    
    print_info "dav1d build completed for arm64."
}

# Build SVT-AV1
build_svtav1() {
    print_info "Building SVT-AV1 for arm64..."
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
        "-DCMAKE_OSX_ARCHITECTURES=arm64"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"
    )
    
    cmake "${CMAKE_ARGS[@]}" ..
    make -j${NPROC}
    make install
    print_info "SVT-AV1 build completed for arm64."
}

# Build rav1e (Rust AV1 encoder)
build_rav1e() {
    print_info "Building rav1e (Rust AV1 encoder) for arm64..."
    cd "${SRC_DIR}"
    
    # Check if Rust is installed
    if ! command -v cargo &> /dev/null; then
        print_info "Rust is required for rav1e. Installing..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Add arm64 target explicitly
    rustup target add aarch64-apple-darwin
    
    git_clone "https://github.com/xiph/rav1e.git" "rav1e"
    cd rav1e
    
    # Build with cargo-c for C API
    if ! command -v cargo-cinstall &> /dev/null; then
        print_info "Installing cargo-c..."
        cargo install cargo-c
    fi
    
    # Build and install C API with shared library
    print_info "Building rav1e C API with cargo-c for arm64..."
    cargo cinstall --target=aarch64-apple-darwin --release --prefix="${BUILD_DIR}" --libdir="${BUILD_DIR}/lib" --includedir="${BUILD_DIR}/include" --library-type=cdylib
    
    if [ $? -ne 0 ]; then
        print_warning "cargo-c installation failed, trying alternative method..."
        
        # Alternative: Build with cargo build
        print_info "Building rav1e with cargo build for arm64..."
        cargo build --target=aarch64-apple-darwin --release
        
        # Create directories for manual installation
        mkdir -p "${BUILD_DIR}/lib"
        mkdir -p "${BUILD_DIR}/include/rav1e"
        
        # Install library
        if [ -f "target/aarch64-apple-darwin/release/librav1e.dylib" ]; then
            cp target/aarch64-apple-darwin/release/librav1e.dylib "${BUILD_DIR}/lib/"
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
    
    print_info "rav1e build completed for arm64."
}

# Build libaom (AV1 reference implementation)
build_libaom() {
    print_info "Building libaom (AV1 reference implementation) for arm64..."
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
        "-DCMAKE_OSX_ARCHITECTURES=arm64"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"
        "-DAOM_TARGET_CPU=arm64"
    )
    
    cmake "${CMAKE_ARGS[@]}" ../aom
    
    make -j${NPROC}
    make install
    
    print_info "libaom build completed for arm64."
}

# Build Xvid
build_xvid() {
    print_info "Building Xvid for arm64..."
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
    
    # Configure for shared library with arm64 flags
    CFLAGS="-arch arm64" LDFLAGS="-arch arm64" ./configure \
        --prefix="${BUILD_DIR}" \
        --host=aarch64-apple-darwin
    
    make -j${NPROC}
    make install
    
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
    
    print_info "Xvid build completed for arm64."
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

# Build FFmpeg
build_ffmpeg() {
    print_info "Building FFmpeg for macOS arm64..."
    cd "${SRC_DIR}"
    git_clone "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
    
    cd ffmpeg
    
    # Basic configuration
    CONFIG_OPTIONS=(
        "--prefix=${BUILD_DIR}"
        "--extra-cflags=${CFLAGS}"
        "--extra-ldflags=${LDFLAGS}"
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
        
        # macOS hardware acceleration
        "--enable-videotoolbox"
        "--enable-audiotoolbox"
        
        # Additional options
        "--enable-avfilter"
        "--enable-runtime-cpudetect"
        "--disable-doc"
        "--disable-ffplay"
        "--disable-debug"
        "--disable-stripping"
        "--disable-xlib"
        "--disable-libxcb"
        "--disable-libxcb-shape"
        "--disable-libxcb-xfixes"
        
        # ARM64 specific options
        "--arch=arm64"
        "--enable-neon"
    )
    
    # Configure FFmpeg
    ./configure "${CONFIG_OPTIONS[@]}"
    
    # Build and install
    make -j${NPROC}
    make install
    
    print_info "FFmpeg build completed for arm64."
}

# Fix macOS library paths
fix_macos_libraries() {
    print_info "Fixing library paths for macOS arm64..."
    
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
    
    # Verify it's an arm64 binary
    arch_check=$(lipo -info "$dylib" | grep "arm64")
    if [ -z "$arch_check" ]; then
        echo "WARNING: $basename is not an arm64 binary!"
    else
        echo "Confirmed arm64 architecture for $basename"
    fi
    
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
    
    print_info "macOS arm64 library paths fixed."
}

# Verify the build
verify_build() {
    print_info "Verifying FFmpeg arm64 build..."
    
    # Set proper library paths before verification
    export DYLD_LIBRARY_PATH="${BUILD_DIR}/lib:$DYLD_LIBRARY_PATH"
    
    # Verify FFmpeg executables
    if [ ! -f "${BUILD_DIR}/bin/ffmpeg" ]; then
        print_error "FFmpeg executable not found!"
        exit 1
    fi
    
    # Check architecture
    print_info "Checking FFmpeg binary architecture:"
    lipo -info "${BUILD_DIR}/bin/ffmpeg"
    
    # Check version
    "${BUILD_DIR}/bin/ffmpeg" -version
    
    # Verify libraries - macOS uses dylib
    if [ ! -d "${BUILD_DIR}/lib" ] || [ -z "$(ls -A ${BUILD_DIR}/lib/*.dylib 2>/dev/null)" ]; then
        print_error "FFmpeg libraries not found!"
        exit 1
    fi
    print_info "Found $(ls -1 ${BUILD_DIR}/lib/*.dylib | wc -l) dylib files"
    
    # Check architecture of a sample library
    print_info "Checking library architecture:"
    sample_lib=$(ls ${BUILD_DIR}/lib/libav*.dylib | head -1)
    if [ -n "$sample_lib" ]; then
        lipo -info "$sample_lib"
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
    
    # Check hardware acceleration
    print_info "Checking for videotoolbox support:"
    "${BUILD_DIR}/bin/ffmpeg" -encoders | grep videotoolbox || print_warning "No videotoolbox encoders found"
    
    # Check for AV1 support
    print_info "Checking for AV1 support:"
    "${BUILD_DIR}/bin/ffmpeg" -encoders | grep av1 || print_warning "No AV1 encoders found"
    
    print_info "FFmpeg arm64 build verification completed successfully."
}

# Main build process
main() {
    print_info "Starting FFmpeg build process for macOS arm64..."
    
    # Verify we're running on or building for arm64
    check_arm64

    install_dependencies
    
    # Build dependencies
    build_x264
    build_x265
    build_xvid
    build_libaom
    build_dav1d
    build_svtav1
    build_rav1e
    
    # Verify pkg-config files before FFmpeg build
    verify_pkg_config "x264" "H.264/AVC video encoder" "x264" 
    verify_pkg_config "x265" "H.265/HEVC video encoder" "x265"
    verify_pkg_config "dav1d" "AV1 decoder" "dav1d"
    verify_pkg_config "rav1e" "AV1 encoder" "rav1e"
    verify_pkg_config "aom" "AV1 codec library" "aom"
    verify_pkg_config "xvid" "Xvid MPEG-4 video codec" "xvidcore"
    
    # Build FFmpeg
    build_ffmpeg
    
    # Fix macOS library paths
    fix_macos_libraries
    
    # Verify build
    verify_build
    
    print_info "======================================="
    print_info "FFmpeg arm64 build successful!"
    print_info "FFmpeg binaries: ${BUILD_DIR}/bin"
    print_info "FFmpeg libraries: ${BUILD_DIR}/lib"
    print_info "FFmpeg headers: ${BUILD_DIR}/include"
    print_info "======================================="
}

# Execute main
main "$@"