/*
 * Dynamically loaded filter plugin for HDF5 FFMPEG filter.
 *
 * Author: Bin Duan <bduan2@hawk.iit.edu>
 * Created: 2022
 *
 */


#include "ffmpeg_h5filter.h"
#include "H5PLextern.h"

H5PL_type_t H5PLget_plugin_type(void) { return H5PL_TYPE_FILTER; }

const void *H5PLget_plugin_info(void) { return ffmpeg_H5Filter; }