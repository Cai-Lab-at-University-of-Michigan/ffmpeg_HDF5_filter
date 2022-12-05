#!/bin/bash

rm -rf ./build
mkdir build && cd build
cmake ..
make
cd ..
build/example 1
#build/encode tmp_video mpeg1video
#build/decode tmp_video tmp_video_decode
