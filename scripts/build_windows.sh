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

print_info "Building FFmpeg in ${BUILD_DIR}"
print_info "Source code will be in ${SRC_DIR}"

# Detect number of CPU cores for parallel builds
NPROC=$(nproc || grep -c ^processor /proc/cpuinfo || echo 4)
print_info "Using ${NPROC} CPU cores for build"

setup_vs_environment() {
    print_info "Setting up Visual Studio environment..."
    
    local vs_path=""
    local vswhere_exe="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    
    # Try vswhere first
    if [[ -f "$vswhere_exe" ]]; then
        print_info "Using vswhere to find Visual Studio..."
        
        # Try queries in order of preference
        vs_path=$("$vswhere_exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        
        [[ -z "$vs_path" ]] && vs_path=$("$vswhere_exe" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
        
        [[ -z "$vs_path" ]] && vs_path=$("$vswhere_exe" -version "[16.0,)" -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
    fi
    
    # Fallback to standard locations if vswhere failed
    if [[ -z "$vs_path" ]]; then
        print_info "Checking standard Visual Studio locations..."
        
        local standard_paths=(
            "/c/Program Files/Microsoft Visual Studio/2022/Enterprise"
            "/c/Program Files/Microsoft Visual Studio/2022/Professional" 
            "/c/Program Files/Microsoft Visual Studio/2022/Community"
            "/c/Program Files (x86)/Microsoft Visual Studio/2019/Enterprise"
        )
        
        for path in "${standard_paths[@]}"; do
            if [[ -d "$path" && -f "$path/VC/Auxiliary/Build/vcvars64.bat" ]]; then
                vs_path="$path"
                break
            fi
        done
    fi
    
    # Verify we found a valid installation
    if [[ -z "$vs_path" || ! -f "$vs_path/VC/Auxiliary/Build/vcvars64.bat" ]]; then
        print_error "Visual Studio not found or missing vcvars64.bat"
        exit 1
    fi
    
    print_info "Found Visual Studio at: $vs_path"
    
    # Create environment script
    cat > "${BUILD_DIR}/vsenv.bat" << VSENV_EOF
@echo off
call "${vs_path}\\VC\\Auxiliary\\Build\\vcvars64.bat"
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment
    exit /b 1
)
echo VS_ENV_READY
VSENV_EOF
    
    print_info "Visual Studio environment ready: ${BUILD_DIR}/vsenv.bat"
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

    if ! command -v unzip &> /dev/null; then
        print_info "Installing Unzip..."
        choco install -y unzip
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
    
    print_info "Dependencies installed successfully."
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

build_x264() {
    print_info "Building x264 from source..."
    cd "${SRC_DIR}"
    
    git_clone "https://code.videolan.org/videolan/x264.git" "x264"
    cd x264
    
    # Create simple build script for MSVC
    cat > "build_x264.bat" << 'X264_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

rem Use configure script that comes with x264
bash configure --prefix="${WIN_BUILD_DIR}" --enable-shared --enable-pic --disable-cli
make -j4
make install
X264_EOF
    
    cmd.exe /c build_x264.bat || print_error "x264 build failed, stopping."
    print_info "x264 build completed."
}

build_x265() {
    print_info "Building x265 from source..."
    cd "${SRC_DIR}"
    
    git_clone "https://bitbucket.org/multicoreware/x265_git.git" "x265"
    cd x265/build
    
    cat > "build_x265.bat" << 'X265_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="${WIN_BUILD_DIR}" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_SHARED=ON ^
    -DHIGH_BIT_DEPTH=ON ^
    -DMAIN10=ON ^
    -DMAIN12=ON ^
    ../source

cmake --build . --config Release --target install
X265_EOF
    
    cmd.exe /c build_x265.bat || print_error "x265 build failed, stopping."
   
    print_info "x265 build completed."
}

build_dav1d() {
    print_info "Building dav1d from source..."
    cd "${SRC_DIR}"
    
    git_clone "https://code.videolan.org/videolan/dav1d.git" "dav1d"
    cd dav1d
    mkdir -p build
    cd build
    
    cat > "build_dav1d.bat" << 'DAV1D_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

meson setup --prefix="${WIN_BUILD_DIR}" --libdir=lib --default-library=shared -Db_pgo=generate -Dc_args=-march=native -Dcpp_args=-march=native ..
ninja
ninja install
DAV1D_EOF
    
    cmd.exe /c build_dav1d.bat || print_error "dav1d build failed, stopping."

    print_info "dav1d build completed."
}

build_libaom() {
    print_info "Building libaom from source..."
    cd "${SRC_DIR}"
    
    git_clone "https://aomedia.googlesource.com/aom" "aom"
    cd aom
    mkdir -p build
    cd build
    
    cat > "build_aom.bat" << 'AOM_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="${WIN_BUILD_DIR}" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_TESTS=OFF ^
    -DENABLE_EXAMPLES=OFF ^
    ..

cmake --build . --config Release --target install
AOM_EOF
    
    cmd.exe /c build_aom.bat || print_error "libaom build failed, stopping."

    print_info "aom build completed."
}

build_rav1e() {
    print_info "Building rav1e from source..."
    cd "${SRC_DIR}"
    
    # Install Rust if not available
    if ! command -v cargo &> /dev/null; then
        print_info "Installing Rust for rav1e..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
    fi
    
    git_clone "https://github.com/xiph/rav1e.git" "rav1e"
    cd rav1e
    
    # Install cargo-c for C API
    cargo install cargo-c || print_warning "cargo-c installation failed"
    
    print_info "Building rav1e C API..."
    cargo cinstall --release --prefix="${BUILD_DIR}" --libdir="${BUILD_DIR}/lib" --includedir="${BUILD_DIR}/include" --library-type=cdylib || print_error "rav1e build failed, stopping."
    
    print_info "rav1e build completed."
}

build_svtav1() {
    print_info "Building SVT-AV1 from source..."
    cd "${SRC_DIR}"
    
    git_clone "https://gitlab.com/AOMediaCodec/SVT-AV1.git" "svtav1"
    cd svtav1
    mkdir -p build
    cd build
    
    cat > "build_svtav1.bat" << 'SVTAV1_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="${WIN_BUILD_DIR}" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON ^
    ..

cmake --build . --config Release --target install
SVTAV1_EOF
    
    cmd.exe /c build_svtav1.bat || print_error "SVT-AV1 build failed, stopping."
    
    print_info "SVT-AV1 build completed."
}

build_onevpl() {
    print_info "Building Intel oneVPL for QSV support..."
    
    cd "${SRC_DIR}"
    git_clone "https://github.com/intel/libvpl.git" "oneVPL"
    
    cd oneVPL
    mkdir -p build
    cd build
    
    cat > "build_onevpl.bat" << 'ONEVPL_EOF'
@echo off
call "${VS_PATH}\VC\Auxiliary\Build\vcvars64.bat"

cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="${WIN_BUILD_DIR}" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DBUILD_TOOLS=OFF ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_TESTS=OFF ^
    ..

cmake --build . --config Release --target install
ONEVPL_EOF
    
    cmd.exe /c build_onevpl.bat || print_error "oneVPL build failed, stopping."
    
    # Setup compatibility symlinks from vpl to mfx
    if [ -d "${BUILD_DIR}/include/vpl" ]; then
        mkdir -p "${BUILD_DIR}/include/mfx"
        cp -r "${BUILD_DIR}/include/vpl/"* "${BUILD_DIR}/include/mfx/"
    fi
    
    # Create pkg-config file for oneVPL
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

    print_info "Intel oneVPL build completed."
}

setup_nvenc_headers() {
    print_info "Setting up NVIDIA encoder headers and CUDA support..."
    cd "${SRC_DIR}"
    
    # Install NVIDIA codec headers
    git_clone "https://git.videolan.org/git/ffmpeg/nv-codec-headers.git" "nv-codec-headers"
    
    cd nv-codec-headers
    mkdir -p "${BUILD_DIR}/include/ffnvcodec"
    cp include/ffnvcodec/*.h "${BUILD_DIR}/include/ffnvcodec"
    
    setup_cuda_support || print_warning "CUDA setup failed, NVENC support will be limited."
    
    print_info "NVIDIA encoder headers installed successfully."
}

download_source() {
    local url=$1
    local output_file=$2
    local retries=3
    local retry_delay=2
    local attempt=0

    print_info "Downloading: $url"

    while [ $attempt -lt $retries ]; do
        if command -v curl &> /dev/null; then
            curl -L -o "$output_file" "$url"
        elif command -v wget &> /dev/null; then
            wget -O "$output_file" "$url"
        else
            print_error "Neither curl nor wget is available. Cannot download files."
            exit 1
        fi

        # Check if the download was successful
        if [ -f "$output_file" ] && [ -s "$output_file" ]; then
            print_info "Downloaded $output_file successfully."
            return 0
        fi

        attempt=$((attempt + 1))
        print_warning "Download failed for $url. Attempt $attempt/$retries..."
        sleep $retry_delay
    done
    
    print_error "Failed to download: $url after $retries attempts."
    exit 1
}

setup_cuda_support() {
    print_info "Setting up CUDA for NVENC..."

    # Check if CUDA is already installed
    if command -v nvcc &> /dev/null; then
        CUDA_PATH=$(dirname $(dirname $(which nvcc)))
        print_info "Existing CUDA installation found at: $CUDA_PATH"
    else
        # Install the CUDA Toolkit using Chocolatey if not found
        print_info "CUDA not found. Installing CUDA Toolkit using Chocolatey..."
        choco install -y cuda

        # Check installation paths again
        CUDA_PATHS=(
            "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.3"
            "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.2"
            "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.1"
            "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.8"
            "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.7"
        )

        for cuda_path in "${CUDA_PATHS[@]}"; do
            if [ -d "$cuda_path" ] && [ -f "$cuda_path/bin/nvcc.exe" ]; then
                CUDA_PATH="$cuda_path"
                print_info "CUDA installed and found at: $CUDA_PATH"
                break
            fi
        done

        if [ -z "$CUDA_PATH" ]; then
            print_error "Failed to install/find CUDA Toolkit"
            return 1
        fi
    fi

    # Set CUDA environment variables
    export CUDA_PATH="$CUDA_PATH"
    export PATH="$CUDA_PATH/bin:$PATH"

    # Verify CUDA installation
    if [ -f "$CUDA_PATH/bin/nvcc.exe" ]; then
        print_info "CUDA compiler found: $("$CUDA_PATH/bin/nvcc.exe" --version | grep "release" || echo "version check failed")"

        # Set up CUDA libraries path
        export CUDA_LIB_PATH="$CUDA_PATH/lib/x64"
        export CUDA_INCLUDE_PATH="$CUDA_PATH/include"

        print_info "CUDA NVENC support is ready"
    else
        print_warning "CUDA compiler not found, NVENC might be limited"
        return 1
    fi
}

build_xvid() {
    print_info "Building Xvid for Windows..."
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
    download_source "https://downloads.xvid.com/downloads/xvidcore-1.3.7.zip" "xvidcore-1.3.7.zip"

    # Extract the ZIP file
    unzip -q xvidcore-1.3.7.zip

    # Navigate to the build directory
    cd xvidcore/build/generic

    # Create the build batch script for MSVC
    cat > "build_xvid.bat" << XVID_EOF
@echo off
call "${VS_PATH}\\VC\\Auxiliary\\Build\\vcvars64.bat"

rem Build with MSVC
nmake /f makefile.vc CFG=Win32-General-Release

rem Install the outputs
xcopy "..\\..\\..\\bin\\release" "${BUILD_DIR}\\bin\\" /Y /E
xcopy "..\\..\\..\\lib" "${BUILD_DIR}\\lib\\" /Y /E
xcopy "..\\..\\..\\include" "${BUILD_DIR}\\include\\" /Y /E
XVID_EOF

    # Run the build script
    cmd.exe /c build_xvid.bat || print_error "Xvid build failed, stopping."

    print_info "Xvid build completed for Windows."
}

# Create pkg-config files for the built libraries
generate_pkgconfig_files() {
    print_info "Generating pkg-config files for libraries..."
    
    mkdir -p "${BUILD_DIR}/lib/pkgconfig"
    
    # x264
    cat > "${BUILD_DIR}/lib/pkgconfig/x264.pc" << EOF
prefix=${BUILD_DIR}
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
prefix=${BUILD_DIR}
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
    
    print_info "pkg-config files generated successfully."
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
rem Call Visual Studio environment setup
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1

rem Prioritize Visual Studio's MSVC toolchain
set PATH=%VS_PATH%\VC\Tools\MSVC\<version>\bin\Hostx64\x64;%PATH%
set PATH=%PATH%;%BUILD_DIR%\bin

rem Check and remove conflicting link.exe from PATH
if exist C:\msys64\usr\bin\link.exe (
    ren C:\msys64\usr\bin\link.exe link_backup.exe
    echo Renamed conflicting MSYS link.exe to link_backup.exe
)

rem Add CUDA to path if available
if exist "%WIN_CUDA_PATH%\bin\nvcc.exe" (
    echo Found CUDA, enabling CUDA support
    set PATH=%PATH%;%WIN_CUDA_PATH%\bin
    set CUDA_NVENC_EXTRA=--enable-cuda-nvcc --enable-cuvid --enable-nvdec
) else (
    echo CUDA not found, using basic NVENC support
    set CUDA_NVENC_EXTRA=
)

set PKG_CONFIG_PATH=%BUILD_DIR%\lib\pkgconfig

rem Configure FFmpeg
echo Configuring FFmpeg...
powershell -Command "& './configure' ^
  --toolchain=msvc ^
  --prefix=${BUILD_DIR} ^
  --enable-shared ^
  --disable-static ^
  --disable-debug ^
  --enable-gpl ^
  --enable-version3 ^
  --enable-nonfree ^
  --enable-asm ^
  --enable-libx264 ^
  --enable-libx265 ^
  %CUDA_NVENC_EXTRA% ^
  --extra-cflags=-I${BUILD_DIR}\include ^
  --extra-ldflags=-LIBPATH:${BUILD_DIR}\lib"

rem Build FFmpeg
echo Building FFmpeg...
nmake -j %NPROC%

rem Install FFmpeg
echo Installing FFmpeg...
nmake install
FFMPEG_EOF
    
    # Run the build script
    cmd.exe /c build_ffmpeg_msvc.bat
    
    print_info "FFmpeg build completed."
}

verify_build() {
    print_info "Verifying FFmpeg build..."

    export PATH="${BUILD_DIR}/bin:$PATH"
    
    # Check if FFmpeg executable exists
    if [ -f "${BUILD_DIR}/bin/ffmpeg.exe" ]; then
        print_info "FFmpeg executable found successfully."
    else
        print_error "FFmpeg executable not found in ${BUILD_DIR}/bin!"
        echo "Directory contents:"
        ls -la "${BUILD_DIR}/bin"
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
    print_info "Checking for x264 support..."
    "${BUILD_DIR}/bin/ffmpeg.exe" -encoders | grep x264 || print_warning "No x264 encoders found"
    
    print_info "FFmpeg build verification completed successfully."
}

main() {
    print_info "Starting FFmpeg build for Windows using Visual Studio..."
    
    # Setup environment
    setup_vs_environment
    install_dependencies
    
    # Compile everything from source
    build_x264
    build_x265
    generate_pkgconfig_files
    
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