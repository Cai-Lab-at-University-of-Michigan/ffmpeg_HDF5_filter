#!/bin/bash

# CONDA ENV
ENVNAME="ffmpeg"
ENVS=$(conda env list | awk '$ENVNAME' )

setupCondaEnv(){
echo "Creating conda enviroment if not exist"
if [[ $ENVS != *"$ENVNAME"* ]]; then
  conda env create -f env.yml
fi
# echo "Activating conda enviroment" && \
# source $HOME/anaconda3/bin/activate ffmpeg && \
# which python
}

# NASM
installNasm(){
echo "Installing nasm"
cd $HOME/ffmpeg_sources && \
wget https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.bz2 && \
tar xjvf nasm-2.15.05.tar.bz2 && \
cd nasm-2.15.05 && \
./autogen.sh && \
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin" && \
make -j$(nproc) && \
make install
}

# yasm (for libvpx. if not installed already)
installYasm(){
echo "Installing yasm"
cd $HOME/ffmpeg_sources && \
wget http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz && \
tar xzf yasm-1.3.0.tar.gz && \
cd yasm-1.3.0 && \
./configure --prefix="$HOME/ffmpeg_build" && \
make -j$(nproc) && make install
}

# cmake (for libx265, libaom, libsvtav1. if not installed already.)
# Strongly suggest using sudo apt-get install cmake
installCmake(){
echo "Installing Cmake"
cd $HOME/ffmpeg_sources && \
wget https://github.com/Kitware/CMake/releases/download/v3.21.2/cmake-3.21.2-linux-x86_64.tar.gz && \
tar xzf cmake-3.21.2-linux-x86_64.tar.gz --strip-components=1 -C "$HOME/ffmpeg_build" && \
export PATH="$HOME/ffmpeg_build/bin:$PATH"
}

# libx264
compileLibX264(){
echo "Compiling libx264"
cd $HOME/ffmpeg_sources && \
git -C x264 pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/x264.git && \
cd x264 && \
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin" --enable-static --enable-pic && \
PATH="$HOME/bin:$PATH" make -j$(nproc) && \
make install
}

# libx265
compileLibX265(){
echo "Compling libx265"
cd $HOME/ffmpeg_sources && \
wget -O x265.tar.bz2 https://bitbucket.org/multicoreware/x265_git/get/master.tar.bz2 && \
tar xjvf x265.tar.bz2 && \
cd multicoreware*/build/linux && \
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED=off ../../source && \
PATH="$HOME/bin:$PATH" make -j$(nproc) && \
make install
}

# libvpx
compileLibVpx(){
echo "Compiling libvpx"
cd $HOME/ffmpeg_sources && \
git -C libvpx pull 2> /dev/null || git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git && \
cd libvpx && \
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm && \
PATH="$HOME/bin:$PATH" make -j$(nproc) && \
make install
}

# libaom-av1 (av1 video)
compileLibaom(){
echo "Compiling libaom"
cd $HOME/ffmpeg_sources && \
git -C aom pull 2> /dev/null || git clone --depth 1 https://aomedia.googlesource.com/aom && \
mkdir -p aom_build && \
cd aom_build && \
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_TESTS=OFF -DENABLE_NASM=on ../aom && \
PATH="$HOME/bin:$PATH" make -j$(nproc) && \
make install
}

# libsvtav1 (av1 video)
compileLibsvtav1(){
echo "Compiling libsvtav1"
cd $HOME/ffmpeg_sources && \
git -C SVT-AV1 pull 2> /dev/null || git clone https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
mkdir -p SVT-AV1/build && \
cd SVT-AV1/build && \
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DCMAKE_BUILD_TYPE=Release -DBUILD_DEC=OFF -DBUILD_SHARED_LIBS=OFF .. && \
PATH="$HOME/bin:$PATH" make -j$(nproc) && \
make install
}

# librav1e (av1 video)
# we have to specify cargo-c version due to compatiablity
compileLibrav1e(){
echo "Compiling librav1e"
cd $HOME/ffmpeg_sources && \
wget https://github.com/xiph/rav1e/archive/refs/tags/p20230110.tar.gz && \
tar xvf p20230110.tar.gz && \
cd rav1e-p20230110 && \
cargo build --release && \
find target -name rav1e -exec install -m 755 {} $HOME/bin \; && \
strip $HOME/bin/rav1e && \
cd $HOME/ffmpeg_sources && \
rm -rfv rav1e-p20230110 && \
cargo install cargo-c --version=0.9.14+cargo-0.66 && \
cd $HOME/ffmpeg_sources && tar xvf p20230110.tar.gz && \
cd rav1e-p20230110 && \
cargo cinstall --release \
     --prefix=$HOME/ffmpeg_build \
     --libdir=$HOME/ffmpeg_build/lib \
     --includedir=$HOME/ffmpeg_build/include && \
rm -v $HOME/ffmpeg_build/lib/librav1e.so*
}

# libdav1d (av1 decode fast)
compileLibdav1d(){
echo "Compiling libdav1d"
conda install meson
cd $HOME/ffmpeg_sources && \
git -C dav1d pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/dav1d.git && \
mkdir -p dav1d/build && \
cd dav1d/build && \
meson setup -Denable_tools=false -Denable_tests=false --default-library=static .. --prefix "$HOME/ffmpeg_build" --libdir="$HOME/ffmpeg_build/lib" && \
ninja && \
ninja install
}

# nv-codec-headers
compileNVCodec(){
echo "Compling nv-codec-headers"
cd $HOME/ffmpeg_sources && \
# git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
cd nv-codec-headers && \
make -j$(nproc) && \
make install PREFIX="$HOME/ffmpeg_build"
}

# ffmpeg
compileFfmpeg(){
echo "Compling ffmpeg from source"
cd $HOME/ffmpeg_sources && \
wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 && \
tar xjvf ffmpeg-snapshot.tar.bz2 && \
cd ffmpeg && \
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
  --prefix="$HOME/ffmpeg_build" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$HOME/ffmpeg_build/include" \
  --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
  --extra-libs="-lpthread -lm" \
  --ld="g++" \
  --bindir="$HOME/bin" \
  --enable-gpl \
  --enable-libaom \
  --enable-librav1e \
  --enable-libsvtav1 \
  --enable-libdav1d \
  --enable-libvpx \
  --enable-libxvid \
  --enable-libx264 \
  --enable-libx265 \
  --enable-nonfree \
  --enable-cuda-nvcc \
  --enable-libnpp \
  --disable-static \
  --enable-shared \
  --extra-libs="-lpthread" \
  --extra-cflags="-I$CONDA_PREFIX/include" \
  --extra-ldflags="-L$CONDA_PREFIX/lib" && \
PATH="$HOME/bin:$PATH" make -j$(nproc) && \
make install && \
hash -r
}

# If got x265 not found by pkg-config error, 
# delete the x265_config.h in ffmpeg_build/include.

#######################################################################################
# NOTE FOR NVCC ERROR WHILE COMPILING FFMPEG                                          #
#     might caused by the conflict of cudatoolkit                                     #
#                                                                                     #
# Solution:                                                                           #
#     1. Reinstall cudatoolkit-dev                                                    #
#     2. and check compatiablity between nvidia-driver and nv-codec-headers           #
#######################################################################################

#Process
cd $HOME
mkdir ffmpeg_sources bin
setupCondaEnv
# installNasm
# installYasm
compileLibX264
compileLibX265
compileLibVpx
compileLibaom
compileLibsvtav1
compilelibrav1e
compileLibdav1d
compileNVCodec
compileFfmpeg
echo "Complete!"