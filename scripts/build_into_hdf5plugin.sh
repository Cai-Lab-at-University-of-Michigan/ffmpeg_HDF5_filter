echo "recompile ffmpeg plugin"
cd ../ffmpeg_hdf5_filter
rm -rf build
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=/home/binduan/ffmpeg_build
make
cd ..

# compile hdf5plugin wrapper
cd ../hdf5plugin

rm -rf ./build
mkdir build

rm -rf src/hdf5plugin.egg-info

echo "copy source code to src"
mkdir src/ffmpeg
mkdir src/ffmpeg/src

cp ../ffmpeg_hdf5_filter/src/ffmpeg_h5filter.c src/ffmpeg/src
cp ../ffmpeg_hdf5_filter/src/ffmpeg_h5filter.h src/ffmpeg/src
cp ../ffmpeg_hdf5_filter/src/ffmpeg_h5plugin.c src/ffmpeg/src

/home/binduan/anaconda3/envs/compress/bin/python -m pip uninstall -y hdf5plugin
/home/binduan/anaconda3/envs/compress/bin/python setup.py install