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

print_info "Building FFmpeg on GitHub Actions Windows-2022"
print_info "Build directory: ${BUILD_DIR}"
print_info "Source directory: ${SRC_DIR}"

# Detect number of CPU cores for parallel builds
NPROC=$(nproc || echo 4)
print_info "Using ${NPROC} CPU cores for build"

setup_vs_environment() {
    print_info "Setting up Visual Studio environment for GitHub Actions..."
    
    # GitHub Actions windows-2022 has VS 2022 pre-installed
    # Use vswhere to find the exact path
    local vswhere_exe="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    
    if [[ ! -f "$vswhere_exe" ]]; then
        print_error "vswhere.exe not found. Visual Studio may not be properly installed."
        exit 1
    fi
    
    # Find VS 2022 installation
    local vs_path=$("$vswhere_exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
    
    if [[ -z "$vs_path" ]]; then
        vs_path=$("$vswhere_exe" -latest -property installationPath 2>/dev/null | head -n1 | tr -d '\r')
    fi
    
    if [[ -z "$vs_path" || ! -f "$vs_path/VC/Auxiliary/Build/vcvars64.bat" ]]; then
        print_error "Visual Studio 2022 not found or missing vcvars64.bat"
        print_info "Available VS installations:"
        "$vswhere_exe" -all -property installationPath || true
        exit 1
    fi
    
    print_info "Found Visual Studio at: $vs_path"
    
    # Export VS_PATH for use in build scripts
    export VS_PATH="$vs_path"
    
    # Convert paths to Windows format for batch scripts
    WIN_VS_PATH=$(echo "$vs_path" | sed 's|^/c/|C:\\|' | sed 's|/|\\|g')
    WIN_BUILD_DIR=$(echo "$BUILD_DIR" | sed 's|^/c/|C:\\|' | sed 's|/|\\|g')
    WIN_SRC_DIR=$(echo "$SRC_DIR" | sed 's|^/c/|C:\\|' | sed 's|/|\\|g')
    
    export WIN_VS_PATH WIN_BUILD_DIR WIN_SRC_DIR
    
    print_info "VS Path (Windows): $WIN_VS_PATH"
    print_info "Build Dir (Windows): $WIN_BUILD_DIR"
}

install_dependencies() {
    print_info "Installing build dependencies via Chocolatey..."
    
    # GitHub Actions already has chocolatey installed
    # Install NASM for assembly optimizations
    choco install -y nasm --no-progress
    
    # Install other necessary tools
    choco install -y cmake --no-progress
    choco install -y git --no-progress
    
    # Add tools to PATH
    export PATH="/c/Program Files/NASM:/c/Program Files/CMake/bin:$PATH"
    
    # Download and setup pkg-config
    print_info "Setting up pkg-config..."
    curl -L -o "${BUILD_DIR}/pkg-config-lite.zip" "https://sourceforge.net/projects/pkgconfiglite/files/0.28-1/pkg-config-lite-0.28-1_bin-win32.zip/download"
    unzip -o "${BUILD_DIR}/pkg-config-lite.zip" -d "${BUILD_DIR}"
    export PATH="${BUILD_DIR}/pkg-config-lite-0.28-1/bin:$PATH"
    
    # Verify installations
    print_info "Verifying tool installations..."
    nasm -v || print_error "NASM not found in PATH"
    cmake --version || print_error "CMake not found in PATH"
    pkg-config --version || print_error "pkg-config not found in PATH"
    
    print_info "Dependencies installed successfully."
}

# Function to clone git repository
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
    
    # Create build script for MSVC
    cat > "build_x264.bat" << 'EOF'
@echo off
setlocal enabledelayedexpansion

call "%WIN_VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment
    exit /b 1
)

echo Building x264...

rem Configure x264 for Windows/MSVC
bash configure --prefix="%WIN_BUILD_DIR%" --enable-shared --enable-pic --disable-cli --host=x86_64-w64-mingw32

if errorlevel 1 (
    echo ERROR: x264 configure failed
    exit /b 1
)

make -j%NPROC%
if errorlevel 1 (
    echo ERROR: x264 make failed  
    exit /b 1
)

make install
if errorlevel 1 (
    echo ERROR: x264 install failed
    exit /b 1
)

echo x264 build completed successfully
EOF
    
    # Run the build
    cmd.exe //c "set WIN_VS_PATH=${WIN_VS_PATH}&& set WIN_BUILD_DIR=${WIN_BUILD_DIR}&& set NPROC=${NPROC}&& build_x264.bat"
    
    if [ $? -ne 0 ]; then
        print_error "x264 build failed"
        exit 1
    fi
    
    print_info "x264 build completed."
}

build_x265() {
    print_info "Building x265 from source..."
    cd "${SRC_DIR}"
    
    git_clone "https://bitbucket.org/multicoreware/x265_git.git" "x265"
    cd x265/build
    
    cat > "build_x265.bat" << 'EOF'
@echo off
setlocal enabledelayedexpansion

call "%WIN_VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment
    exit /b 1
)

echo Configuring x265...
cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="%WIN_BUILD_DIR%" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_SHARED=ON ^
    -DHIGH_BIT_DEPTH=ON ^
    -DMAIN10=ON ^
    -DMAIN12=ON ^
    ../source

if errorlevel 1 (
    echo ERROR: x265 cmake configure failed
    exit /b 1
)

echo Building x265...
cmake --build . --config Release --target install
if errorlevel 1 (
    echo ERROR: x265 build failed
    exit /b 1
)

echo x265 build completed successfully
EOF
    
    cmd.exe //c "set WIN_VS_PATH=${WIN_VS_PATH}&& set WIN_BUILD_DIR=${WIN_BUILD_DIR}&& build_x265.bat"
    
    if [ $? -ne 0 ]; then
        print_error "x265 build failed"
        exit 1
    fi
    
    print_info "x265 build completed."
}

# Generate pkg-config files
generate_pkgconfig_files() {
    print_info "Generating pkg-config files..."
    
    mkdir -p "${BUILD_DIR}/lib/pkgconfig"
    
    # x264 pkg-config
    cat > "${BUILD_DIR}/lib/pkgconfig/x264.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: x264
Description: x264 library
Version: 0.164.3094
Libs: -L\${libdir} -lx264
Cflags: -I\${includedir}
EOF
    
    # x265 pkg-config
    cat > "${BUILD_DIR}/lib/pkgconfig/x265.pc" << EOF
prefix=${BUILD_DIR}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: x265 library
Version: 3.5
Libs: -L\${libdir} -lx265
Cflags: -I\${includedir}
EOF
    
    print_info "pkg-config files generated."
}

build_ffmpeg() {
    print_info "Building FFmpeg..."
    cd "${SRC_DIR}"
    
    git_clone "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
    cd ffmpeg
    
    cat > "build_ffmpeg.bat" << 'EOF'
@echo off
setlocal enabledelayedexpansion

call "%WIN_VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment
    exit /b 1
)

rem Set up paths
set PATH=%PATH%;%WIN_BUILD_DIR%\bin
set PKG_CONFIG_PATH=%WIN_BUILD_DIR%\lib\pkgconfig

rem Verify NASM is available
where nasm >nul 2>&1
if errorlevel 1 (
    echo ERROR: NASM not found in PATH
    exit /b 1
)

echo Configuring FFmpeg...
bash configure ^
  --toolchain=msvc ^
  --prefix="%WIN_BUILD_DIR%" ^
  --enable-shared ^
  --disable-static ^
  --disable-debug ^
  --enable-gpl ^
  --enable-version3 ^
  --enable-asm ^
  --enable-libx264 ^
  --enable-libx265 ^
  --extra-cflags="-I%WIN_BUILD_DIR%\include" ^
  --extra-ldflags="-LIBPATH:%WIN_BUILD_DIR%\lib"

if errorlevel 1 (
    echo ERROR: FFmpeg configure failed
    echo === Showing config.log ===
    type config.log
    exit /b 1
)

echo Building FFmpeg...
make -j%NPROC%
if errorlevel 1 (
    echo ERROR: FFmpeg build failed
    exit /b 1
)

echo Installing FFmpeg...
make install
if errorlevel 1 (
    echo ERROR: FFmpeg install failed
    exit /b 1
)

echo FFmpeg build completed successfully
EOF
    
    cmd.exe //c "set WIN_VS_PATH=${WIN_VS_PATH}&& set WIN_BUILD_DIR=${WIN_BUILD_DIR}&& set NPROC=${NPROC}&& build_ffmpeg.bat" 2>&1 | tee "${BUILD_DIR}/ffmpeg_build.log"
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        print_error "FFmpeg build failed!"
        print_info "Last 50 lines of build log:"
        tail -n 50 "${BUILD_DIR}/ffmpeg_build.log"
        exit 1
    fi
    
    print_info "FFmpeg build completed."
}

verify_build() {
    print_info "Verifying FFmpeg build..."
    
    # Check if FFmpeg executable exists
    if [ ! -f "${BUILD_DIR}/bin/ffmpeg.exe" ]; then
        print_error "FFmpeg executable not found!"
        print_info "Contents of ${BUILD_DIR}/bin:"
        ls -la "${BUILD_DIR}/bin/" 2>/dev/null || echo "Directory does not exist"
        exit 1
    fi
    
    # Test FFmpeg
    print_info "Testing FFmpeg executable..."
    "${BUILD_DIR}/bin/ffmpeg.exe" -version
    
    if [ $? -ne 0 ]; then
        print_error "FFmpeg executable test failed!"
        exit 1
    fi
    
    # Check for DLLs
    dll_count=$(ls -1 "${BUILD_DIR}/bin/"*.dll 2>/dev/null | wc -l)
    print_info "Found ${dll_count} DLL files"
    
    # Check for headers
    if [ ! -d "${BUILD_DIR}/include/libavcodec" ]; then
        print_error "FFmpeg headers not found!"
        exit 1
    fi
    
    print_info "FFmpeg build verification completed successfully."
}

main() {
    print_info "Starting FFmpeg build for GitHub Actions Windows-2022..."
    
    # Setup environment
    setup_vs_environment
    install_dependencies
    
    # Build codec libraries
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
    
    # Create completion marker
    touch "${BUILD_DIR}/.build_completed"
}

# Run main function
main "$@"