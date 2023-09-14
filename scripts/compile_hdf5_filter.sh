#!/bin/bash
if [ -d "build" ] 
then
    rm -rf build
fi
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=$HOME/ffmpeg_build -DVPL_ROOT_DIR=$HOME/ffmpeg_build -DUSE_VPL_ENCODER=ON -DBUILD_PLUGIN=ON
make
cd ..
