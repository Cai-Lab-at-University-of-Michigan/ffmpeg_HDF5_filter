#!/bin/bash

rm -rf ./build
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=~/ffmpeg_build
make
cd ..
for ENC in {0..1}
do
    build/example 0
done

for PRESET in {10..18}
do  
    for TUNE in {10..17}
    do
        build/example 2 $PRESET $TUNE
    done
done

for PRESET in {100..106}
do
    for TUNE in {100..103}
    do
        build/example 3 $PRESET $TUNE
    done
done

for PRESET in {200..208}
do
    for TUNE in {200..205}
    do
        build/example 4 $PRESET $TUNE
    done
done

for PRESET in {300..306}
do
    for TUNE in {300..303}
    do
        build/example 5 $PRESET $TUNE
    done
done

for PRESET in {400..413}
do
    for TUNE in {400..402}
    do
        build/example 6 $PRESET $TUNE
    done
done

for PRESET in {500..510}
do
    for TUNE in {500..501}
    do
        build/example 7 $PRESET $TUNE
    done
done