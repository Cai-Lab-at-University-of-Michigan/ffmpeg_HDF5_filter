## FFMPEG HDF5 Filter
* Lossy and lossless compressions supprted filter based on ffmpeg.

## Getting Started
- [x] compile ffmepg and libraries, run `bash compile_ffmpeg.sh`
- [x] download current repo and compile this filter, run `bash compile_hdf5_filter.sh`


## Tests

| Compression ratio| Parameters |
| -----------------| ----------- |
| 5                | 6 6 64 64 64 0 401 400 5 0 0  |
| 12               | 6 6 64 64 64 0 403 400 15 0 0 |
| 20               | 6 6 64 64 64 0 402 400 20 0 0 |