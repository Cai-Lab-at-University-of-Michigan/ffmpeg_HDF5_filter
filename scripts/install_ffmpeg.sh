cd ~/ffmpeg_sources && \
wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 && \
tar xjvf ffmpeg-snapshot.tar.bz2 && \
cd ffmpeg && \
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
  --prefix="$HOME/ffmpeg_build" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$HOME/ffmpeg_build/include" \
  --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
  --extra-libs="-lpthread -lm -lrt" \
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
  --extra-cflags="-I$CONDA_PREFIX/include" \
  --extra-ldflags="-L$CONDA_PREFIX/lib" && \
PATH="$HOME/bin:$PATH" make && \
make install && \
hash -r