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
* If we want to compress multi-channel (>1 channel) image stack, we can reshape (ZCYX) to ((ZC)YX) for grayscale compression.
* NOTE: we convert grayscale or rgb to YUV420P internally, where compressing rgb stacks can be pretty lossy. If we want to more faithful compression, we can alternatively reshape the data for grayscale compression.

## Compliling the Filter
- [x] install cmake >= 2.10 
- [x] change -DFFMPEG_BUILD_PATH in `scripts/compile.sh`
- [x] run `scripts/compile.sh` in current folder
- [x] open `~/.bashrc`, add one line at the end `export $HDF5_PLUGIN_PATH=~/ffmpeg_HDF5_filter/build`
- [x] run `source ~/.bashrc`
- [x] `echo $HDF5_PLUGIN_PATH`, should be `~/ffmpeg_HDF5_filter/build`

## Running Example
* run `build/exampe` and will generate `example.h5` in current folder
* if `$HDF5_PLUGIN_PATH` set, run `h5dump --properties example.h5 | more` to inspect compressed data

## Performance


## Acknowledgments
The cmake file borrows heavily from the [jpegHDF5](https://github.com/CARS-UChicago/jpegHDF5). Part of the encoding and decoding codes are modified from [ffmpeg examples](https://github.com/FFmpeg/FFmpeg). Very much thanks.
