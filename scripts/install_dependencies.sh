#!/bin/bash
# Cross-platform FFmpeg dependencies installation script
# Optimized for Python package builds with comprehensive codec support
# For use with PyPI publishing workflow

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

# Detect OS and architecture
detect_system() {
    # Detect OS
    if [ -n "$WINDIR" ] || [ -n "$SYSTEMROOT" ] || [ -n "$COMSPEC" ] || [ "$(uname -s)" == "MINGW"* ]; then
        OS="windows"
        print_info "Detected OS: Windows"
        
        # Check if running in GitHub Actions
        if [ -n "$GITHUB_ACTIONS" ]; then
            print_info "Running in GitHub Actions Windows environment"
        fi
    elif [ "$(uname)" == "Darwin" ]; then
        OS="macos"
        # Detect Mac architecture
        if [ "$(uname -m)" == "arm64" ]; then
            print_info "Detected OS: macOS (Apple Silicon)"
            MAC_ARCH="arm64"
        else
            print_info "Detected OS: macOS (Intel)"
            MAC_ARCH="x86_64"
        fi
    elif [ "$(uname)" == "Linux" ]; then
        OS="linux"
        print_info "Detected OS: Linux"
        
        # Detect Linux distribution
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
            print_info "Detected distribution: $DISTRO"
        else
            print_warning "Could not determine Linux distribution. Assuming Ubuntu..."
            DISTRO="ubuntu"
        fi
    else
        print_error "Unsupported OS"
        exit 1
    fi
}

# Install Linux dependencies
install_linux_deps() {
    print_info "Installing FFmpeg build dependencies for Linux..."
    
    # Basic build tools and dependencies
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
        zlib1g-dev \
        libssl-dev \
        patchelf
    
    # Codec-specific dependencies
    sudo apt-get install -y \
        libx264-dev \
        libx265-dev \
        libnuma-dev \
        libvpx-dev \
        libopus-dev \
        libdav1d-dev \
        libaom-dev \
        libfdk-aac-dev \
        libmp3lame-dev \
        libvorbis-dev \
        libtheora-dev \
        libfreetype6-dev \
        libfontconfig1-dev
    
    # Hardware acceleration and screen capture - IMPORTANT for oneVPL/QSV
    sudo apt-get install -y \
        libva-dev \
        libdrm-dev \
        libvdpau-dev \
        libsdl2-dev \
        libxcb1-dev \
        libxcb-shm0-dev \
        libxcb-xfixes0-dev \
        libxcb-shape0-dev \
        libx11-dev \
        libx11-xcb-dev \
        libxext-dev \
        libpciaccess-dev
    
    # Python-specific dependencies
    sudo apt-get install -y \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        python3-numpy \
        libhdf5-dev
    
    sudo apt-get install -y nvidia-cuda-toolkit
    
    # Rust for rav1e
    if ! command -v cargo &> /dev/null; then
        print_info "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
        # Install cargo-c for C API generation
        cargo install cargo-c
    fi
    
    print_info "Linux dependencies installed successfully."
}

# Install macOS dependencies
install_macos_deps() {
    print_info "Installing FFmpeg build dependencies for macOS..."
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_info "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add brew to the path if it was just installed (especially for Apple Silicon)
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    
    # Update Homebrew and install dependencies
    brew update
    
    # Install basic build tools
    brew install \
        cmake \
        pkg-config \
        automake \
        autoconf \
        libtool \
        nasm \
        yasm \
        ninja \
        meson \
        git \
        wget \
        curl
    
    # Install codec-specific dependencies
    brew install \
        x264 \
        x265 \
        dav1d \
        aom \
        libvpx \
        opus \
        lame \
        theora \
        vorbis \
        fdk-aac \
        speex \
        freetype \
        fontconfig \
        frei0r \
        sdl2
    
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
    
    print_info "macOS dependencies installed successfully."
}

# Install Windows dependencies
install_windows_deps() {
    print_info "Installing FFmpeg build dependencies for Windows..."
    
    # Use chocolatey for Windows dependencies
    print_info "Using Chocolatey to install dependencies..."
    
    # Install basic build tools
    choco install -y \
        git \
        cmake \
        ninja \
        nasm \
        yasm \
        visualstudio2022buildtools \
        visualstudio2022-workload-vctools \
        wget \
        curl
    
    # Add MSYS2 for Unix-like environment
    choco install -y msys2
    
    # Update path to include MSYS2 binaries
    MSYS2_PATH="C:/tools/msys64"
    if [ -d "/c/tools/msys64" ]; then
        MSYS2_PATH="/c/tools/msys64"
    fi
    export PATH="$MSYS2_PATH/usr/bin:$PATH"
    
    # Update MSYS2 packages
    print_info "Updating MSYS2 packages..."
    pacman -Syu --noconfirm
    
    # Install build dependencies via MSYS2
    print_info "Installing MSYS2/MinGW packages..."
    pacman -S --noconfirm \
        mingw-w64-x86_64-toolchain \
        mingw-w64-x86_64-cmake \
        mingw-w64-x86_64-autotools \
        mingw-w64-x86_64-nasm \
        mingw-w64-x86_64-yasm \
        mingw-w64-x86_64-pkg-config \
        mingw-w64-x86_64-ninja \
        mingw-w64-x86_64-meson \
        mingw-w64-x86_64-dlfcn \
        mingw-w64-x86_64-x264 \
        mingw-w64-x86_64-x265 \
        mingw-w64-x86_64-dav1d \
        mingw-w64-x86_64-aom \
        mingw-w64-x86_64-libvpx \
        mingw-w64-x86_64-opus \
        mingw-w64-x86_64-libpng \
        mingw-w64-x86_64-freetype \
        mingw-w64-x86_64-fontconfig \
        mingw-w64-x86_64-SDL2 \
        mingw-w64-x86_64-fribidi
    
    # Add Python dependencies
    choco install -y \
        python3 \
        swig
    
    # Install pip packages
    print_info "Installing Python packages..."
    pip install -U setuptools wheel numpy cython

    # Install Rust for rav1e
    print_info "Installing Rust..."
    choco install -y rustup.install
    
    # Add Rust to PATH
    export PATH="/c/Users/$USER/.cargo/bin:$PATH"
    
    # Initialize Rust and install cargo-c
    print_info "Setting up Rust and cargo-c..."
    rustup default stable
    cargo install cargo-c
    
    print_info "Windows dependencies installed successfully."
}

# Main function
main() {
    detect_system
    
    print_info "Installing FFmpeg dependencies for Python package build..."
    
    # Install OS-specific dependencies
    case "$OS" in
        linux)
            install_linux_deps
            ;;
        macos)
            install_macos_deps
            ;;
        windows)
            install_windows_deps
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    # Install common Python dependencies
    if [ "$OS" != "windows" ]; then
        print_info "Installing Python build dependencies..."
        pip3 install --upgrade pip setuptools wheel cython
        pip3 install numpy
    fi
    
    print_info "All dependencies installed successfully."
    
    # Create marker file to indicate successful installation
    touch .deps_installed
}

# Run main function
main "$@"