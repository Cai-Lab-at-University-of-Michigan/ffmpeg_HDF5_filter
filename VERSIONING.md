# Version Information

This document tracks the versions of FFmpeg and codec libraries used in the h5ffmpeg project.

## Project Version

**h5ffmpeg**: 2.4.0

## Core Dependencies

### FFmpeg
- **Version**: 8.0
- **Repository**: https://github.com/FFmpeg/FFmpeg.git
- **Build Configuration**: See platform-specific sections below
- **License**: GPL v3+ (due to enabled GPL components)

### HDF5
- **Version**: 1.14.5
- **Source**:
  - Linux: Conda-forge or system package manager
  - macOS: Conda-forge or Homebrew
  - Windows: System installation or conda
- **License**: BSD-style

## Video Codec Libraries

### H.264/AVC

#### x264
- **Version**: 0.164.3108
- **Repository**: https://code.videolan.org/videolan/x264.git
- **License**: GPL v2+
- **Build Options**:
  - Shared library enabled
  - PIC (Position Independent Code) enabled
  - CLI disabled

### H.265/HEVC

#### x265
- **Version**: 4.1
- **Repository**: https://bitbucket.org/multicoreware/x265_git.git
- **License**: GPL v2+
- **Build Configuration**: Multi-bit-depth build (8-bit, 10-bit, 12-bit)
- **Dependencies**: libnuma (Linux)
- **Build Options**:
  - Shared library enabled
  - Multi-bit-depth support (8/10/12-bit)
  - CLI disabled

### AV1 Codecs

#### dav1d (AV1 Decoder)
- **Version**: 1.5.1
- **Repository**: https://code.videolan.org/videolan/dav1d.git
- **License**: BSD 2-Clause
- **Build System**: Meson + Ninja
- **Optimizations**:
  - Profile-Guided Optimization (PGO) enabled
  - Native CPU architecture optimizations (`-march=native`)

#### libaom (AV1 Reference Encoder/Decoder)
- **Version**: 3.12.1
- **Repository**: https://aomedia.googlesource.com/aom
- **License**: BSD 2-Clause
- **Build Options**:
  - Shared library enabled
  - Multi-threading enabled
  - Tests and examples disabled

#### SVT-AV1 (Scalable Video Technology for AV1)
- **Version**: 3.1.2
- **Repository**: https://gitlab.com/AOMediaCodec/SVT-AV1.git
- **License**: BSD-2-Clause-Patent + Alliance for Open Media Patent License 1.0
- **Build Options**: Shared library with PIC enabled

#### rav1e (Rust AV1 Encoder)
- **Version**: ≥ 0.6.0
- **Repository**: https://github.com/xiph/rav1e.git
- **License**: BSD 2-Clause
- **Build System**: Cargo (Rust)
- **Build Tool**: cargo-c for C API generation

### MPEG-4 Part 2

#### Xvid
- **Version**: 1.3.7
- **Source**: https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz
- **License**: GPL v2+

#### libvpx
- **Version**: System-provided via conda-forge
- **License**: BSD 3-Clause

## Hardware Acceleration

### NVIDIA GPU Support

#### CUDA Toolkit
- **Version**: System-dependent
- **Required for**: NVENC/NVDEC hardware encoding/decoding
- **Minimum Version**: CUDA 11.x recommended
- **Linux**: nvidia-cuda-toolkit or nvidia-cuda-nvcc via pip
- **Optional Dependencies**:
  - cupy-cuda11x (Python GPU arrays)

#### NVIDIA Codec Headers (nv-codec-headers)
- **Version**: 13.0
- **Repository**: https://github.com/FFmpeg/nv-codec-headers.git
- **License**: MIT
- **Purpose**: Headers for NVENC/NVDEC APIs

### Intel QuickSync Video (QSV)

#### Intel oneVPL (Video Processing Library)
- **Version**: 2.16
- **Repository**: https://github.com/oneapi-src/oneVPL.git
- **License**: MIT
- **Platform**: Linux and Windows
- **Build Options**: Shared library enabled, tools/tests disabled

#### libva (Video Acceleration API)
- **Version**: 2.23
- **Repository**: https://github.com/intel/libva.git
- **License**: MIT
- **Platform**: Linux only
- **Purpose**: Hardware access for Intel QSV

#### libvpl
- **Version**: Conda-forge provided (Linux builds)
- **License**: MIT

#### Intel Media SDK
- **Platform**: Windows (via system libraries)
- **Note**: Superseded by oneVPL but maintained for backward compatibility

## Compression Libraries

### Core Compression

- **zlib**: System-provided or conda-forge
- **bzip2**: System-provided or conda-forge
- **xz (LZMA)**: System-provided or conda-forge
- **lz4**: Conda-forge (Linux/macOS builds)
- **zstd**: Conda-forge (Linux/macOS builds)

## Python Dependencies

### Required Packages
```
h5py >= 3.8.0
numpy >= 1.15.0
colorama >= 0.4.6
tabulate >= 0.9.0
matplotlib >= 3.10.3
scikit-image >= 0.25.2
```

### Optional Packages
```
# NVIDIA GPU support
cupy-cuda11x

# Intel optimizations
intel-openmp
```

## Build Tools

### All Platforms
- **CMake**: ≥ 3.16
- **pkg-config**: Latest stable
- **Git**: Latest stable

### Linux-Specific
- **GCC/G++**: System default (C11/C++14 standard)
- **Meson**: Latest via conda-forge
- **Ninja**: Latest via conda-forge
- **NASM/YASM**: Assembler for codec optimizations
- **Rust**: Latest stable (via rustup) - required for rav1e
- **cargo-c**: Latest - for rav1e C API

### macOS-Specific
- **Clang**: Xcode command line tools (default)
- **Meson**: Latest via conda-forge
- **Ninja**: Latest via conda-forge
- **NASM/YASM**: Via conda-forge
- **Rust**: Latest stable (via rustup) - required for rav1e
- **Deployment Target**: macOS 12.0+
- **Architecture**: ARM64 (Apple Silicon)

### Windows-Specific
- **MSVC**: Visual Studio Build Tools
- **NASM**: Latest Windows build

## Platform-Specific Build Configurations

### Linux (manylinux_2_34_x86_64)

**Container Image**: dockcross/manylinux_2_34-x64

**FFmpeg Configure Flags**:
```bash
--enable-shared --disable-static --enable-pic
--enable-gpl --enable-nonfree --enable-version3
--enable-pthreads
--enable-libxvid --enable-libx264 --enable-libx265
--enable-libaom --enable-libdav1d --enable-librav1e --enable-libsvtav1 --enable-libvpx
--enable-libvpl --enable-libdrm --enable-vaapi --enable-vdpau
--enable-cuda-nvcc --enable-libnpp --enable-nvenc --enable-nvdec (if CUDA available)
--enable-openssl --enable-lzma --enable-bzlib --enable-zlib
--enable-runtime-cpudetect --enable-hardcoded-tables --enable-optimizations
--disable-doc --disable-ffplay --disable-debug
```

### macOS (ARM64, macOS 12.0+)

**Architecture**: ARM64 (Apple Silicon)
**Deployment Target**: macOS 12.0

**FFmpeg Configure Flags**:
```bash
--enable-shared --disable-static --enable-pic
--enable-gpl --enable-nonfree --enable-version3
--enable-pthreads
--enable-libxvid --enable-libx264 --enable-libx265
--enable-libaom --enable-libdav1d --enable-librav1e --enable-libsvtav1 --enable-libvpx
--enable-openssl --enable-lzma --enable-bzlib --enable-zlib
--enable-runtime-cpudetect --enable-hardcoded-tables --enable-optimizations
--disable-doc --disable-ffplay --disable-debug
--cc=/usr/bin/clang --cxx=/usr/bin/clang++
```

**Special Configurations**:
- RPATH settings for dylib resolution
- SDK root configuration via xcrun

### Windows

**FFmpeg Build**: Custom build script (scripts/build_windows.bat)

**Build Environment**:
- MSVC compiler with C11 standard support
- Conda environment for dependencies

## Python Package Build System

**Build Backend**: setuptools.build_meta

**Wheel Building**: cibuildwheel

**Supported Python Versions**: 3.10, 3.11, 3.12, 3.13

**Platforms**:
- Linux: manylinux_2_34_x86_64
- macOS: macosx_arm64 (Apple Silicon)
- Windows: win_amd64

**Excluded Platforms**:
- musllinux (all variants)
- 32-bit architectures (win32, manylinux_i686)
- macOS x86_64 (Intel)

## Version History

### 2.4.0 (Current)
- Latest stable release
- Full multi-codec support
- Hardware acceleration for NVIDIA and Intel
- Cross-platform wheel distribution

## Checking Installed Versions

You can check the versions of installed components:

```bash
# Python package version
python -c "import h5ffmpeg; print(h5ffmpeg.__version__)"

# Check HDF5 version
python -c "import h5py; print(h5py.version.hdf5_version)"
```

## License Information

This project combines components with various licenses:
- **FFmpeg**: GPL v3+ (due to enabled GPL components like x264, x265, xvid)
- **h5ffmpeg Python package**: MIT
- **Individual codecs**: See respective sections above

**Important**: Due to GPL dependencies, the compiled binaries are distributed under GPL v3+. Users must comply with GPL terms when distributing modified versions.

## Updates and Maintenance

Codec libraries are built from latest available sources at build time. For reproducible builds, specific commit hashes can be pinned in build scripts.

To update dependencies:
1. Update git clone commands in build scripts to specific tags/commits
2. Update Python dependency versions in setup.py and pyproject.toml
3. Rebuild FFmpeg and all codec libraries
4. Test thoroughly across all platforms
5. Update this VERSIONING.md file

## References

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [HDF5 Documentation](https://portal.hdfgroup.org/documentation/)
- [x264 Documentation](https://www.videolan.org/developers/x264.html)
- [x265 Documentation](https://x265.readthedocs.io/)
- [AV1 Codec Resources](https://aomedia.org/av1/)
- [NVIDIA Video Codec SDK](https://developer.nvidia.com/nvidia-video-codec-sdk)
- [Intel oneVPL](https://www.intel.com/content/www/us/en/developer/tools/oneapi/onevpl.html)
