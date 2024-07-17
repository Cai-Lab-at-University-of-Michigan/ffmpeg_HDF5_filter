## FFMPEG HDF5 Filter
* Lossy and lossless compressions supprted filter based on ffmpeg.

## Getting Started
- [x] install ffmepg and other codecs, example [ffmpeg compiled from source](doc/install_ffmpeg.md)
- [x] install hdf5 (1.12.1)
- [x] download current repo

## Restrictions
* Only 8-bit unsigned data arrays are supported.
* Arrays must be either:
    * 2-D Grayscale [Depth, Height, Width] (ZYX)
    * 3-D RGB [Depth, Height, Width, 3] (ZYXC)
* **NOTE**: We convert grayscale or rgb to YUV420P internally, where compressing rgb stacks can be pretty lossy. If we want more faithful compression, we can alternatively reshape the multi-channel (>1 channel) data for grayscale compression.

## Compliling the Filter
- [x] install cmake >= 2.10 
- [x] change -DFFMPEG_BUILD_PATH in `scripts/compile.sh`
- [x] run `scripts/compile_ffmpeg.sh` in current folder
- [x] set `$HDF5_PLUGIN_PATH` to the `build` dir of `ffmpeg_HDF5_filter`
- [x] open `$HOME/.bashrc`, add one line at the end `export HDF5_PLUGIN_PATH=$HOME/ffmpeg_HDF5_filter/build`
- [x] run `source $HOME/.bashrc`
- [x] `echo $HDF5_PLUGIN_PATH`, should be `$HOME/ffmpeg_HDF5_filter/build`

## Running Example
* run `build/exampe` and will generate `example.h5` in current folder
* if `$HDF5_PLUGIN_PATH` set, run `h5dump --properties example.h5 | more` to inspect compressed data

## Performance


## Acknowledgments
The cmake file borrows heavily from the [jpegHDF5](https://github.com/CARS-UChicago/jpegHDF5). Part of the encoding and decoding codes are modified from [ffmpeg examples](https://github.com/FFmpeg/FFmpeg). The imagej-hdf5-viewer is modified based on [ch.psi.imagej.hdf5](https://github.com/paulscherrerinstitute/ch.psi.imagej.hdf5). Very much thanks for their great work.
