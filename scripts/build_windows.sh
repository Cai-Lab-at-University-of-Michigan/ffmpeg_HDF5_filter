#!/bin/bash

set -e  # Exit on error

# Console output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Logging functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Initialize build directories
ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/ffmpeg_build"
SRC_DIR="${ROOT_DIR}/ffmpeg_src"
mkdir -p "${BUILD_DIR}"
mkdir -p "${SRC_DIR}"
mkdir -p "${BUILD_DIR}/bin"
mkdir -p "${BUILD_DIR}/lib"
mkdir -p "${BUILD_DIR}/include"

# Convert to Windows paths
WIN_BUILD_DIR=$(cygpath -w "${BUILD_DIR}" 2>/dev/null || echo "${BUILD_DIR}")
WIN_SRC_DIR=$(cygpath -w "${SRC_DIR}" 2>/dev/null || echo "${SRC_DIR}")
WIN_ROOT_DIR=$(cygpath -w "${ROOT_DIR}" 2>/dev/null || echo "${ROOT_DIR}")

print_info "Building FFmpeg in ${BUILD_DIR}"
print_info "Source code will be in ${SRC_DIR}"

# Detect number of CPU cores for parallel builds
NPROC=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 16)
print_info "Using ${NPROC} CPU cores for build"

setup_vs_environment() {
    print_info "Setting up Visual Studio environment..."
    
    # Try multiple paths for vswhere.exe
    VSWHERE_PATHS=(
        "/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
        "/c/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"
        "$(which vswhere.exe 2>/dev/null)"
    )
    
    VSWHERE_EXE=""
    for path in "${VSWHERE_PATHS[@]}"; do
        if [ -f "$path" ]; then
            VSWHERE_EXE="$path"
            break
        fi
    done
    
    if [ -z "$VSWHERE_EXE" ]; then
        print_warning "vswhere.exe not found, trying alternative VS detection..."
        
        # Try common VS installation paths
        VS_PATHS=(
            "/c/Program Files/Microsoft Visual Studio/2022/Enterprise"
            "/c/Program Files (x86)/Microsoft Visual Studio/2019/Enterprise"
            "/c/Program Files/Microsoft Visual Studio/2022/Professional"
            "/c/Program Files (x86)/Microsoft Visual Studio/2019/Professional"
            "/c/Program Files/Microsoft Visual Studio/2022/Community"
            "/c/Program Files (x86)/Microsoft Visual Studio/2019/Community"
        )
        
        for vs_path in "${VS_PATHS[@]}"; do
            if [ -d "$vs_path" ] && [ -f "$vs_path/VC/Auxiliary/Build/vcvars64.bat" ]; then
                VS_PATH="$vs_path"
                print_info "Found Visual Studio at: $VS_PATH"
                break
            fi
        done
        
        if [ -z "$VS_PATH" ]; then
            print_error "Visual Studio not found! Checked paths:"
            for vs_path in "${VS_PATHS[@]}"; do
                print_error "  - $vs_path"
            done
            
            # List what's actually available
            print_info "Available directories in Program Files:"
            ls -la "/c/Program Files/" 2>/dev/null || true
            ls -la "/c/Program Files (x86)/" 2>/dev/null || true
            
            exit 1
        fi
    else
        print_info "Found vswhere.exe at: $VSWHERE_EXE"
        
        # Show what vswhere finds first for debugging
        print_info "Debugging: All available Visual Studio installations:"
        "$VSWHERE_EXE" -all -property displayName,installationPath 2>/dev/null || print_warning "vswhere -all failed"
        
        # Try different vswhere queries in order of preference
        print_info "Trying to find Visual Studio with C++ tools..."
        
        # Try 1: Latest with C++ tools
        VS_PATH=$("$VSWHERE_EXE" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        
        if [ -z "$VS_PATH" ]; then
            print_info "Trying without specific C++ component requirement..."
            # Try 2: Latest with any workload
            VS_PATH=$("$VSWHERE_EXE" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        fi
        
        if [ -z "$VS_PATH" ]; then
            print_info "Trying to find any Visual Studio 2019 or later..."
            # Try 3: Any VS 2019 or later
            VS_PATH=$("$VSWHERE_EXE" -version "[16.0,)" -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        fi
        
        if [ -z "$VS_PATH" ]; then
            print_info "Trying to find latest Visual Studio installation..."
            # Try 4: Just the latest installation
            VS_PATH=$("$VSWHERE_EXE" -latest -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        fi
        
        if [ -z "$VS_PATH" ]; then
            print_info "Trying to find any Visual Studio installation..."
            # Try 5: Any VS installation
            VS_PATH=$("$VSWHERE_EXE" -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        fi
        
        if [ -z "$VS_PATH" ]; then
            print_error "Visual Studio not found via vswhere!"
            
            # Show detailed vswhere output for debugging
            print_info "Detailed vswhere output:"
            "$VSWHERE_EXE" -all 2>/dev/null || true
            
            # Fall back to manual detection
            print_info "Falling back to manual detection..."
            VS_PATHS=(
                "/c/Program Files/Microsoft Visual Studio/2022/Enterprise"
                "/c/Program Files (x86)/Microsoft Visual Studio/2019/Enterprise"
                "/c/Program Files/Microsoft Visual Studio/2022/Professional"
                "/c/Program Files (x86)/Microsoft Visual Studio/2019/Professional"
                "/c/Program Files/Microsoft Visual Studio/2022/Community"
                "/c/Program Files (x86)/Microsoft Visual Studio/2019/Community"
                "/c/Program Files/Microsoft Visual Studio/2022/BuildTools"
                "/c/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools"
            )
            
            for vs_path in "${VS_PATHS[@]}"; do
                if [ -d "$vs_path" ] && [ -f "$vs_path/VC/Auxiliary/Build/vcvars64.bat" ]; then
                    VS_PATH="$vs_path"
                    print_info "Found Visual Studio via manual detection at: $VS_PATH"
                    break
                fi
            done
        fi
        
        if [ -z "$VS_PATH" ]; then
            print_error "Visual Studio not found!"
            print_info "Checked directories:"
            for vs_path in "${VS_PATHS[@]}"; do
                if [ -d "$vs_path" ]; then
                    print_info "  Found: $vs_path"
                    ls -la "$vs_path/" 2>/dev/null || true
                else
                    print_info "  Missing: $vs_path"
                fi
            done
            exit 1
        fi
        
        print_info "Selected Visual Studio at: $VS_PATH"
    fi
    
    # Verify the VS installation has the required files
    if [ ! -f "$VS_PATH/VC/Auxiliary/Build/vcvars64.bat" ]; then
        print_error "vcvars64.bat not found at: $VS_PATH/VC/Auxiliary/Build/vcvars64.bat"
        print_info "Contents of VS directory:"
        ls -la "$VS_PATH/" 2>/dev/null || true
        ls -la "$VS_PATH/VC/" 2>/dev/null || true
        exit 1
    fi
    
    # Create a script to set environment variables
    cat > "${BUILD_DIR}/vsenv.bat" << 'VSENV_EOF'
@echo off
call "${VS_PATH}\\VC\\Auxiliary\\Build\\vcvars64.bat"
echo VS_ENV_READY
VSENV_EOF
    
    print_info "Visual Studio environment script created: ${BUILD_DIR}/vsenv.bat"
}

install_dependencies() {
    print_info "Installing build dependencies..."
    
    # Install NASM for assembly optimizations
    if ! command -v nasm &> /dev/null; then
        print_info "Installing NASM..."
        choco install -y nasm
    fi
    
    # Add NASM to PATH
    export PATH="/c/Program Files/NASM:$PATH"
    
    # Install CMake and Ninja if not already present
    if ! command -v cmake &> /dev/null; then
        print_info "Installing CMake..."
        choco install -y cmake
    fi
    
    if ! command -v ninja &> /dev/null; then
        print_info "Installing Ninja..."
        choco install -y ninja
    fi
    
    # Install 7zip for extracting archives
    if ! command -v 7z &> /dev/null; then
        print_info "Installing 7zip..."
        choco install -y 7zip
    fi
    
    # Set up pkg-config (needed for dependencies)
    if ! command -v pkg-config &> /dev/null; then
        print_info "Setting up pkg-config..."
        curl -L -o "${BUILD_DIR}/pkg-config-lite-0.28-1.zip" "https://sourceforge.net/projects/pkgconfiglite/files/0.28-1/pkg-config-lite-0.28-1_bin-win32.zip/download"
        unzip -o "${BUILD_DIR}/pkg-config-lite-0.28-1.zip" -d "${BUILD_DIR}"
        export PATH="${BUILD_DIR}/pkg-config-lite-0.28-1/bin:$PATH"
    fi
    
    # Verify tool installations
    print_info "Verifying tool installations..."
    nasm -v || print_error "NASM not properly installed!"
    cmake --version || print_error "CMake not properly installed!"
    ninja --version || print_error "Ninja not properly installed!"
    7z i || print_error "7zip not properly installed!"
    
    print_info "Dependencies installed successfully."
}

download_file() {
    local url=$1
    local output_file=$2
    
    print_info "Downloading: $url"
    
    if command -v curl &> /dev/null; then
        curl -L -o "$output_file" "$url"
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

git_clone() {
    local repo_url=$1
    local target_dir=$2
    local branch=${3:-master}
    local depth=${4:-1}
    
    if [ ! -d "$target_dir" ]; then
        print_info "Cloning repository: $repo_url"
        git clone --depth $depth --branch $branch "$repo_url" "$target_dir"
    else
        print_info "Repository already exists: $target_dir. Updating..."
        cd "$target_dir"
        git pull
        cd - > /dev/null
    fi
}

# Download and extract prebuilt dependencies
download_prebuilt_deps() {
    print_info "Downloading and setting up prebuilt dependencies..."
    cd "${SRC_DIR}"
    
    # Create a directory for prebuilt dependencies
    mkdir -p prebuilt
    cd prebuilt
    
    # x264
    print_info "Setting up prebuilt x264..."
    download_file "https://github.com/ShiftMediaProject/x264/releases/download/latest/libx264_x64.7z" "libx264.7z"
    7z x -y "libx264.7z" -o"x264"
    
    # x265
    print_info "Setting up prebuilt x265..."
    download_file "https://github.com/ShiftMediaProject/x265/releases/download/latest/libx265_x64.7z" "libx265.7z"
    7z x -y "libx265.7z" -o"x265"
    
    # libvpx
    print_info "Setting up prebuilt libvpx..."
    download_file "https://github.com/ShiftMediaProject/libvpx/releases/download/latest/libvpx_x64.7z" "libvpx.7z"
    7z x -y "libvpx.7z" -o"libvpx"
    
    # Try to download AV1 codecs if needed
    print_info "Setting up prebuilt AV1 codecs..."
    # dav1d (AV1 decoder)
    download_file "https://github.com/ShiftMediaProject/dav1d/releases/download/latest/libdav1d_x64.7z" "dav1d.7z"
    7z x -y "dav1d.7z" -o"dav1d"
    
    # libaom (AV1 encoder/decoder)
    download_file "https://github.com/ShiftMediaProject/libaom/releases/download/latest/libaom_x64.7z" "aom.7z"
    7z x -y "aom.7z" -o"aom"
    
    # Copy files to build directory
    print_info "Copying prebuilt dependencies to build directory..."
    
    # Create directory structure
    mkdir -p "${BUILD_DIR}/bin" "${BUILD_DIR}/lib" "${BUILD_DIR}/include"
    
    # Copy DLLs, libs and includes
    for dir in x264 x265 libvpx dav1d aom; do
        if [ -d "$dir/bin" ]; then
            cp -r "$dir/bin/"* "${BUILD_DIR}/bin/" 2>/dev/null || true
        fi
        if [ -d "$dir/lib" ]; then
            cp -r "$dir/lib/"* "${BUILD_DIR}/lib/" 2>/dev/null || true
        fi
        if [ -d "$dir/include" ]; then
            cp -r "$dir/include/"* "${BUILD_DIR}/include/" 2>/dev/null || true
        fi
    done
    
    # Intel oneVPL (QSV support)
    print_info "Setting up Intel oneVPL for QSV support..."
    
    # Clone the oneVPL repository
    cd "${SRC_DIR}"
    git_clone "https://github.com/oneapi-src/oneVPL.git" "oneVPL"
    
    # Create Visual Studio build script for oneVPL
    cd oneVPL
    mkdir -p build
    cd build
    
    cat > "build_onevpl.bat" << 'ONEVPL_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

rem Configure oneVPL with CMake
cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="${WIN_BUILD_DIR}" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DBUILD_TOOLS=OFF ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_TESTS=OFF ^
    ..

rem Build and install
cmake --build . --config Release --target install -j ${NPROC}

rem Copy DLLs to bin directory
copy "${WIN_BUILD_DIR}\bin\*.dll" "${WIN_BUILD_DIR}\bin\" 2>nul
ONEVPL_EOF
    
    # Build oneVPL
    cmd.exe /c build_onevpl.bat
    
    # Create compatibility links from vpl to mfx
    if [ -d "${BUILD_DIR}/include/vpl" ]; then
        mkdir -p "${BUILD_DIR}/include/mfx"
        print_info "Creating compatibility links from vpl to mfx"
        cp -r "${BUILD_DIR}/include/vpl/"* "${BUILD_DIR}/include/mfx/" 2>/dev/null || true
    fi
    
    # Create pkg-config file for oneVPL
    mkdir -p "${BUILD_DIR}/lib/pkgconfig"
    cat > "${BUILD_DIR}/lib/pkgconfig/libvpl.pc" << EOF
prefix=${WIN_BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libvpl
Description: Intel oneAPI Video Processing Library
Version: 2.8.0
Libs: -L\${libdir} -lvpl
Cflags: -I\${includedir}
EOF
    
    print_info "Intel oneVPL setup completed."
}

# Create pkg-config files for the prebuilt libraries
generate_pkgconfig_files() {
    print_info "Generating pkg-config files for prebuilt libraries..."
    
    mkdir -p "${BUILD_DIR}/lib/pkgconfig"
    
    # x264
    cat > "${BUILD_DIR}/lib/pkgconfig/x264.pc" << EOF
prefix=${WIN_BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: x264
Description: x264 library
Version: 0.164.3094
Libs: -L\${libdir} -lx264
Libs.private: 
Cflags: -I\${includedir}
EOF
    
    # x265
    cat > "${BUILD_DIR}/lib/pkgconfig/x265.pc" << EOF
prefix=${WIN_BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: x265 library
Version: 3.5
Libs: -L\${libdir} -lx265
Libs.private: 
Cflags: -I\${includedir}
EOF
    
    # libvpx
    cat > "${BUILD_DIR}/lib/pkgconfig/vpx.pc" << EOF
prefix=${WIN_BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: vpx
Description: WebM Project VPX codec
Version: 1.11.0
Libs: -L\${libdir} -lvpx
Cflags: -I\${includedir}
EOF
    
    # dav1d (AV1 decoder)
    cat > "${BUILD_DIR}/lib/pkgconfig/dav1d.pc" << EOF
prefix=${WIN_BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: dav1d
Description: AV1 decoder
Version: 1.0.0
Libs: -L\${libdir} -ldav1d
Cflags: -I\${includedir}
EOF

    # libaom (AV1 codec)
    cat > "${BUILD_DIR}/lib/pkgconfig/aom.pc" << EOF
prefix=${WIN_BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: aom
Description: AOM AV1 codec library
Version: 3.5.0
Libs: -L\${libdir} -laom
Cflags: -I\${includedir}
EOF
    
    print_info "pkg-config files generated successfully."
}

setup_nvenc_headers() {
    print_info "Setting up NVIDIA encoder headers..."
    cd "${SRC_DIR}"
    
    git_clone "https://git.videolan.org/git/ffmpeg/nv-codec-headers.git" "nv-codec-headers"
    cd nv-codec-headers
    
    # Create batch file to install headers
    cat > "install_headers.bat" << 'NVENC_EOF'
@echo off
mkdir "${WIN_BUILD_DIR}\include\ffnvcodec"
copy include\ffnvcodec\*.h "${WIN_BUILD_DIR}\include\ffnvcodec\"
NVENC_EOF
    
    cmd.exe /c install_headers.bat
    
    print_info "NVIDIA encoder headers installed successfully."
}

build_ffmpeg() {
    print_info "Building FFmpeg with Visual Studio..."
    cd "${SRC_DIR}"
    
    # Clone FFmpeg repository
    git_clone "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
    cd ffmpeg
    
    # Create build script for Visual Studio
    cat > "build_ffmpeg_msvc.bat" << 'FFMPEG_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

rem Set up environment
set PATH=%PATH%;${WIN_BUILD_DIR}\bin
set PKG_CONFIG_PATH=${WIN_BUILD_DIR}\lib\pkgconfig

rem Configure FFmpeg
echo Configuring FFmpeg...
powershell -Command "& './configure' ^
  --toolchain=msvc ^
  --prefix=${WIN_BUILD_DIR} ^
  --enable-shared ^
  --disable-static ^
  --disable-debug ^
  --enable-gpl ^
  --enable-version3 ^
  --enable-nonfree ^
  --enable-asm ^
  --enable-libx264 ^
  --enable-libx265 ^
  --enable-libvpx ^
  --enable-libaom ^
  --enable-libdav1d ^
  --enable-nvenc ^
  --enable-libvpl ^
  --extra-cflags=-I${WIN_BUILD_DIR}\include ^
  --extra-ldflags=-LIBPATH:${WIN_BUILD_DIR}\lib"

rem Build FFmpeg
echo Building FFmpeg...
nmake -j ${NPROC}

rem Install FFmpeg
echo Installing FFmpeg...
nmake install

rem Copy DLLs to bin directory for easier access
copy ${WIN_BUILD_DIR}\bin\*.dll ${WIN_BUILD_DIR}\bin\
FFMPEG_EOF
    
    # Run the build script
    cmd.exe /c build_ffmpeg_msvc.bat
    
    print_info "FFmpeg build completed."
}

verify_build() {
    print_info "Verifying FFmpeg build..."
    
    # Check if FFmpeg executable exists
    if [ ! -f "${BUILD_DIR}/bin/ffmpeg.exe" ]; then
        print_error "FFmpeg executable not found!"
        exit 1
    fi
    
    # Check FFmpeg version
    "${BUILD_DIR}/bin/ffmpeg.exe" -version || {
        print_error "Failed to run FFmpeg executable!"
        exit 1
    }
    
    # Check if FFmpeg libraries exist
    if [ -z "$(ls -A ${BUILD_DIR}/bin/av*.dll 2>/dev/null)" ]; then
        print_error "FFmpeg DLLs not found!"
        exit 1
    fi
    
    print_info "Found $(ls -1 ${BUILD_DIR}/bin/*.dll | wc -l) DLL files"
    
    # Check for headers
    if [ ! -d "${BUILD_DIR}/include/libavcodec" ] || [ ! -d "${BUILD_DIR}/include/libavutil" ]; then
        print_error "FFmpeg headers not found!"
        exit 1
    fi
    
    print_info "FFmpeg headers verified"
    
    # Check for encoders and decoders
    print_info "Checking for hardware encoding support:"
    echo "NVENC support:"
    "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep nvenc || print_warning "No NVENC encoders found"
    
    echo "QSV support:"
    "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep qsv || print_warning "No QSV encoders found"
    
    echo "AV1 support:"
    "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep av1 || print_warning "No AV1 encoders found"
    
    print_info "FFmpeg build verification completed successfully."
}

main() {
    print_info "Starting FFmpeg build for Windows using Visual Studio..."
    
    # Setup environment
    setup_vs_environment
    install_dependencies
    
    # Get prebuilt dependencies
    download_prebuilt_deps
    generate_pkgconfig_files
    
    # Setup NVIDIA encoder headers
    setup_nvenc_headers
    
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

# Run the main function
main "$@"