#!/bin/bash

rm -rf ./build
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=~/ffmpeg_build
make
cd ..
for ENCID in {0..7}
do
    build/example $ENCID
done
