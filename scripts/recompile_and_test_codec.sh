#!/bin/bash

rm -rf ./build
rm -f tmp_video*
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=~/ffmpeg_build
make
cd ..
echo "Begin encoding video"
build/encode tmp_video librav1e
echo "END"
echo "Begin decoding video and saving to separated files"
build/decode tmp_video tmp_video_decode libaom-av1
echo "END"
