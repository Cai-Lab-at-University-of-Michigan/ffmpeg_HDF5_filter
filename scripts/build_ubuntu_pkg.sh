#!/bin/bash
set -e

sudo apt-get update
sudo apt-get install -y cmake build-essential patchelf nasm yasm pkg-config libssl-dev git wget autoconf automake libtool make python3-dev python3-pip

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
bash miniconda.sh -b -p $HOME/miniconda

$HOME/miniconda/bin/conda config --add channels conda-forge
$HOME/miniconda/bin/conda config --set channel_priority strict
$HOME/miniconda/bin/conda update -y conda

$HOME/miniconda/bin/conda install -y hdf5 hdf5-external-filter-plugins pkg-config cmake ninja meson nasm yasm git wget autoconf automake libtool make x264 x265 aom libvpx dav1d rav1e svt-av1 zlib bzip2 xz lz4 zstd openssl -c conda-forge
$HOME/miniconda/bin/conda install -y libva libdrm libvpl -c conda-forge || echo "Hardware acceleration libs not available"

pip install nvidia-cuda-nvcc

export PATH="$HOME/miniconda/bin:$PATH"
export PKG_CONFIG_PATH="$HOME/miniconda/lib/pkgconfig:$HOME/miniconda/share/pkgconfig"
export LD_LIBRARY_PATH="$HOME/miniconda/lib"
export CC=gcc
export CXX=g++
export CFLAGS="-I$HOME/miniconda/include -fPIC"
export CXXFLAGS="-I$HOME/miniconda/include -fPIC"
export LDFLAGS="-L$HOME/miniconda/lib"

mkdir -p /tmp/hwaccel_src $HOME/ffmpeg/include $HOME/ffmpeg/lib $HOME/ffmpeg/lib/pkgconfig
cd /tmp/hwaccel_src

git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX="$HOME/ffmpeg"
cd /tmp/hwaccel_src

export PKG_CONFIG_PATH="$HOME/ffmpeg/lib/pkgconfig:$HOME/miniconda/lib/pkgconfig:$HOME/miniconda/share/pkgconfig"

if [ ! -f "$HOME/miniconda/lib/pkgconfig/dav1d.pc" ]; then
    git clone --depth 1 https://code.videolan.org/videolan/dav1d.git
    cd dav1d
    meson setup build --prefix=$HOME/miniconda --libdir=lib
    ninja -C build
    ninja -C build install
    cd /tmp/hwaccel_src
fi

git config --global http.postBuffer 524288000
git config --global http.maxRequestBuffer 100M
git config --global core.compression 0

if ! git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg; then
    git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg
fi

cd ffmpeg

if command -v nvcc &> /dev/null; then
    CUDA_FLAGS="--enable-cuda-nvcc --enable-libnpp"
else
    CUDA_FLAGS=""
fi

./configure --prefix="$HOME/ffmpeg" --extra-cflags="-I$HOME/miniconda/include -I$HOME/ffmpeg/include -fPIC" --extra-ldflags="-L$HOME/miniconda/lib" --extra-libs="-lm -lstdc++" --enable-shared --disable-static --enable-pic --enable-gpl --enable-nonfree --enable-version3 --enable-pthreads --enable-libx264 --enable-libx265 --enable-libaom --enable-libdav1d --enable-librav1e --enable-libsvtav1 --enable-libvpx --enable-libvpl ${CUDA_FLAGS} --enable-openssl --enable-lzma --enable-bzlib --enable-zlib --enable-runtime-cpudetect --enable-hardcoded-tables --enable-optimizations --disable-doc --disable-ffplay --disable-debug

make -j$(nproc)
make install

mkdir -p deps/ffmpeg deps/miniconda
cp -r $HOME/ffmpeg/* deps/ffmpeg/
cp -r $HOME/miniconda/lib deps/miniconda/
cp -r $HOME/miniconda/include deps/miniconda/
cp -r $HOME/miniconda/share deps/miniconda/
cp -r $HOME/miniconda/bin deps/miniconda/