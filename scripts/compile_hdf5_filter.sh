#!/bin/bash
if [ -d "build" ] 
then
    rm -rf build
fi
mkdir build && cd build
TO_CMAKE_PATH="C:\Users\Wei\hdf5" cmake .. -DFFMPEG_BUILD_PATH="C:\Users\Wei\ffmpeg" -DVPL_ROOT_DIR="C:\Users\Wei\ffmpeg" -DUSE_VPL_ENCODER=ON -DBUILD_PLUGIN=ON
make
cd ..
