#!/bin/bash

mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=~/ffmpeg_build
make
cd ..
