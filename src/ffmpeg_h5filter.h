/*
 * FFMPEG HDF5 filter
 *
 * Author: Bin Duan <bduan2@hawk.iit.edu>
 * Created: 2022
 *
 */


#ifndef FFMPEG_H5FILTER_H
#define FFMPEG_H5FILTER_H

#define H5Z_class_t_vers 2

#include "hdf5.h"

#define FFMPEG_H5FILTER 32027 /* filter id here */


H5_DLLVAR H5Z_class_t ffmpeg_H5Filter[1];


/* ---- ffmpeg_register_h5filter ----
 *
 * Register the ffmpeg HDF5 filter within the HDF5 library.
 *
 * Important: Call this before using the ffmpeg HDF5 filter from C
 * unless dynamically loaded filters.
 *
 */
int ffmpeg_register_h5filter(void);


#endif // FFMPEG_H5FILTER_H