echo "recompile ffmpeg plugin"
cd ../ffmpeg_HDF5_filter
rm -rf build
mkdir build && cd build
cmake .. -DFFMPEG_BUILD_PATH=$HOME/ffmpeg_build -DVPL_ROOT_DIR=$HOME/ffmpeg_build -DUSE_VPL_ENCODER=ON -DBUILD_PLUGIN=ON
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

cp ../ffmpeg_HDF5_filter/src/ffmpeg_h5filter.c src/ffmpeg/src
cp ../ffmpeg_HDF5_filter/src/ffmpeg_h5filter.h src/ffmpeg/src
cp ../ffmpeg_HDF5_filter/src/ffmpeg_h5plugin.c src/ffmpeg/src

$HOME/anaconda3/envs/ffmpeg/bin/python -m pip uninstall -y hdf5plugin
$HOME/anaconda3/envs/ffmpeg/bin/python setup.py install
