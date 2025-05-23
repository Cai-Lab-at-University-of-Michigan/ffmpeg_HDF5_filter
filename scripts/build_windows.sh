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

# Cross-compilation settings
TARGET_ARCH="x86_64"
TARGET_OS="mingw32"
CROSS_PREFIX="x86_64-w64-mingw32-"

# Set build directories
ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/ffmpeg_build_windows"
SRC_DIR="${ROOT_DIR}/ffmpeg_src_windows"

mkdir -p "${BUILD_DIR}"
mkdir -p "${SRC_DIR}"

print_info "Building FFmpeg for Windows (cross-compilation from Ubuntu)"
print_info "Target: ${TARGET_ARCH}-${TARGET_OS}"
print_info "Build directory: ${BUILD_DIR}"
print_info "Source directory: ${SRC_DIR}"

# Detect CI environment and adjust parallelism
if [ "${CI_BUILD:-}" = "1" ] || [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    NPROC="2"  # Limit parallel jobs in CI to avoid memory issues
    print_info "CI environment detected - limiting parallel jobs to ${NPROC}"
else
    NPROC=$(nproc)
    print_info "Using ${NPROC} CPU cores for build"
fi

# Set up environment variables for cross-compilation
export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export PATH="${BUILD_DIR}/bin:${PATH}"

# Cross-compilation flags
CFLAGS="-I${BUILD_DIR}/include -O3"
LDFLAGS="-L${BUILD_DIR}/lib"
EXTRAFLAGS="-lm -lstdc++"

# Install cross-compilation dependencies
install_dependencies() {
    print_info "Installing cross-compilation dependencies for Windows target..."
    
    # Basic build tools and cross-compilation toolchain
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        cmake \
        pkg-config \
        autoconf \
        automake \
        libtool \
        nasm \
        yasm \
        ninja-build \
        meson \
        git \
        wget \
        curl \
        texinfo \
        patchelf \
        mingw-w64 \
        gcc-mingw-w64 \
        g++-mingw-w64 \
        zstd
    
    # Install CUDA if not already installed
    if ! command -v nvcc &> /dev/null; then
        print_info "Installing NVIDIA CUDA toolkit..."
        sudo apt-get install -y nvidia-cuda-toolkit
    fi
    
    print_info "Cross-compilation dependencies installed successfully."
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

# Function to download and extract MSYS2 package
download_and_extract_package() {
    local package_name=$1
    local package_url=$2
    local package_file=$(basename "$package_url")
    
    print_info "Installing ${package_name} from MSYS2 package..."
    
    cd "${SRC_DIR}"
    
    # Create temporary directory for this package
    if [ -d "${package_name}-temp" ]; then
        rm -rf "${package_name}-temp"
    fi
    mkdir -p "${package_name}-temp"
    cd "${package_name}-temp"
    
    # Download the package
    download_source "$package_url" "$package_file"
    
    # Extract the package
    tar --use-compress-program=zstd -xf "$package_file"
    
    # Copy files to build directory
    mkdir -p "${BUILD_DIR}/include" "${BUILD_DIR}/lib" "${BUILD_DIR}/bin"
    
    # Copy headers, libraries, and binaries
    if [ -d "mingw64/include" ]; then
        cp -r mingw64/include/* "${BUILD_DIR}/include/" 2>/dev/null || true
    fi
    
    if [ -d "mingw64/lib" ]; then
        cp -r mingw64/lib/* "${BUILD_DIR}/lib/" 2>/dev/null || true
    fi
    
    if [ -d "mingw64/bin" ]; then
        cp -r mingw64/bin/* "${BUILD_DIR}/bin/" 2>/dev/null || true
    fi
    
    # Handle pkg-config files
    if [ -d "mingw64/lib/pkgconfig" ]; then
        mkdir -p "${BUILD_DIR}/lib/pkgconfig"
        cp mingw64/lib/pkgconfig/*.pc "${BUILD_DIR}/lib/pkgconfig/" 2>/dev/null || true
        
        # Fix paths in pkg-config files
        for pc_file in "${BUILD_DIR}/lib/pkgconfig"/*.pc; do
            if [ -f "$pc_file" ]; then
                sed -i "s|/mingw64|${BUILD_DIR}|g" "$pc_file"
            fi
        done
    fi
    
    print_info "${package_name} installation completed."
    
    # Clean up
    cd "${SRC_DIR}"
    rm -rf "${package_name}-temp"
}

# Install all codec packages
install_codec_packages() {
    print_info "Installing codec packages from MSYS2 repository..."
    
    # Package URLs - update these periodically or add version checking
    declare -A packages=(
        ["x264"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libx264-0.164.r3161.a354f11-3-any.pkg.tar.zst"
        ["x265"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-x265-4.1-2-any.pkg.tar.zst"
        ["xvidcore"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-xvidcore-1.3.7-4-any.pkg.tar.zst"
        ["aom"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-aom-3.12.1-1-any.pkg.tar.zst"
        ["dav1d"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-dav1d-1.5.0-1-any.pkg.tar.zst"
        ["svt-av1"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-svt-av1-3.0.2-2-any.pkg.tar.zst"
        ["rav1e"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-rav1e-0.7.1-7-any.pkg.tar.zst"
        ["libvpl"]="https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libvpl-2.15.0-1-any.pkg.tar.zst"
    )
    
    # Download and install each package
    for package_name in "${!packages[@]}"; do
        download_and_extract_package "$package_name" "${packages[$package_name]}"
    done
    
    print_info "All codec packages installed successfully."
}

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

# Build NVIDIA headers for Windows
build_nvenc() {
    print_info "Setting up NVIDIA encoder/decoder headers for Windows..."
    cd "${SRC_DIR}"
    
    git_clone "https://github.com/FFmpeg/nv-codec-headers.git" "nv-codec-headers"
    cd nv-codec-headers
    
    make install PREFIX="${BUILD_DIR}"
    print_info "NVIDIA headers installed."
}

# Function to show FFmpeg configure errors
show_ffmpeg_config_errors() {
    local config_log="ffbuild/config.log"
    
    if [ -f "$config_log" ]; then
        print_error "FFmpeg configure failed. Last 100 lines of config.log:"
        echo "=========================================="
        tail -n 100 "$config_log"
        echo "=========================================="
    else
        print_error "FFmpeg configure failed and config.log not found"
    fi
}

# Build FFmpeg for Windows
build_ffmpeg() {
    print_info "Building FFmpeg for Windows..."
    cd "${SRC_DIR}"
    git_clone "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
    
    cd ffmpeg
    
    # Check for CUDA support
    if command -v nvcc &> /dev/null; then
        NVIDIA_FLAGS="--enable-nvenc --enable-nvdec"
        print_info "Enabling NVIDIA NVENC/NVDEC support"
    else
        NVIDIA_FLAGS=""
        print_warning "CUDA compiler not available, skipping NVIDIA support"
    fi
    
    # Configuration options for Windows cross-compilation
    CONFIG_OPTIONS=(
        "--prefix=${BUILD_DIR}"
        "--target-os=${TARGET_OS}"
        "--arch=${TARGET_ARCH}"
        "--cross-prefix=${CROSS_PREFIX}"
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
        
        # Hardware acceleration
        ${NVIDIA_FLAGS}
        "--enable-libvpl"
        
        # Additional options
        "--enable-avfilter"
        "--enable-runtime-cpudetect"
        "--disable-doc"
        "--disable-ffplay"
        "--disable-debug"
        "--disable-stripping"
    )
    
    # Configure FFmpeg
    export PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig"
    if ! ./configure "${CONFIG_OPTIONS[@]}"; then
        print_error "FFmpeg configure failed"
        show_ffmpeg_config_errors
        exit 1
    fi

    # Build and install
    make -j${NPROC}
    make install
    
    print_info "FFmpeg build completed."
}

# Verify the build
verify_build() {
    print_info "Verifying FFmpeg build for Windows..."
    
    # Verify FFmpeg executables (.exe for Windows)
    if [ ! -f "${BUILD_DIR}/bin/ffmpeg.exe" ]; then
        print_error "FFmpeg executable not found!"
        exit 1
    fi
    
    # Check version using wine if available
    if command -v wine &> /dev/null; then
        print_info "Testing with Wine..."
        wine "${BUILD_DIR}/bin/ffmpeg.exe" -version || print_warning "Wine test failed"
    else
        print_info "Wine not available for testing. FFmpeg.exe created successfully."
    fi
    
    # Verify libraries - Windows uses .dll
    DLL_COUNT=$(find "${BUILD_DIR}/lib" -name "*.dll*" 2>/dev/null | wc -l)
    if [ "$DLL_COUNT" -eq 0 ]; then
        print_warning "No DLL files found in lib directory"
    else
        print_info "Found ${DLL_COUNT} DLL files"
    fi
    
    # Verify headers
    if [ ! -d "${BUILD_DIR}/include/libavcodec" ] || [ ! -d "${BUILD_DIR}/include/libavutil" ]; then
        print_error "FFmpeg headers not found!"
        exit 1
    fi
    print_info "FFmpeg headers verified"
    
    # List some key files for debugging
    print_info "Key build artifacts:"
    find "${BUILD_DIR}/bin" -name "*.exe" | head -5
    find "${BUILD_DIR}/lib" -name "*.dll" | head -10
    find "${BUILD_DIR}/include" -name "*.h" | head -10
    
    print_info "FFmpeg Windows build verification completed successfully."
}

# Create build logs directory for CI
setup_logging() {
    if [ "${CI_BUILD:-}" = "1" ] || [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
        mkdir -p "${ROOT_DIR}/build_logs"
        exec > >(tee -a "${ROOT_DIR}/build_logs/build_windows.log")
        exec 2>&1
        print_info "CI logging enabled - logs will be saved to build_logs/"
    fi
}

# Function to verify or create pkg-config file
verify_pkg_config() {
    local package=$1
    local description=$2
    local lib_name=$3

    print_info "Verifying pkg-config for ${package}..."

    local pc_file="${BUILD_DIR}/lib/pkgconfig/${package}.pc"

    if [ ! -f "$pc_file" ]; then
        print_warning "pkg-config file for ${package} not found. Creating..."

        mkdir -p "$(dirname "$pc_file")"

        cat > "$pc_file" <<EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: ${package}
Description: ${description}
Version: 1.0
Libs: -L\${libdir} -l${lib_name}
Libs.private: -lm -lpthread -lstdc++
Cflags: -I\${includedir}
EOF

        print_info "Created fallback ${package}.pc"
    else
        print_info "Found existing pkg-config for ${package}"
    fi

    # Optionally test with pkg-config
    if ! PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig" pkg-config --exists "$package"; then
        print_warning "pkg-config still does not recognize ${package}"
    else
        print_info "pkg-config recognizes ${package}: version $(PKG_CONFIG_PATH="${BUILD_DIR}/lib/pkgconfig" pkg-config --modversion $package)"
    fi
}


# Main build process
main() {
    setup_logging
    
    print_info "Starting FFmpeg cross-compilation for Windows..."
    print_info "Build configuration:"
    print_info "  - Target: ${TARGET_ARCH}-${TARGET_OS}"
    print_info "  - Parallel jobs: ${NPROC}"
    print_info "  - CI mode: ${CI_BUILD:-false}"

    install_dependencies
    install_codec_packages
    
    # Build additional components
    build_nvenc

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
    print_info "FFmpeg Windows cross-compilation successful!"
    print_info "FFmpeg binaries: ${BUILD_DIR}/bin (*.exe files)"
    print_info "FFmpeg libraries: ${BUILD_DIR}/lib (*.dll files)"
    print_info "FFmpeg headers: ${BUILD_DIR}/include"
    print_info "======================================="
    
    if [ "${CI_BUILD:-}" != "1" ]; then
        print_info "Copy the entire ${BUILD_DIR} directory to your Windows system"
    fi
    
    # Create a marker file for the build process
    touch "${BUILD_DIR}/.build_completed_windows"
}

# Execute main
main "$@"