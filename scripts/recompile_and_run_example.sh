#!/bin/bash

rm -rf ./build
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=~/ffmpeg_build
make
cd ..
build/example 1
#build/encode tmp_video mpeg1video
#build/decode tmp_video tmp_video_decode
