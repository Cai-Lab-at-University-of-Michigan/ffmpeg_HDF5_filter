#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <numpy/arrayobject.h>
#include <hdf5.h>

#include "ffmpeg_h5filter.h"

#define FFMPEG_FILTER_ID 32030

extern H5Z_class_t ffmpeg_H5Filter[1];

// Patched version of the filter registration function
static PyObject* register_filter(PyObject *self, PyObject *args) {
    
    // Call the C function
    int result = ffmpeg_register_h5filter();
    
    return PyLong_FromLong(result);
}

// Get the filter ID
static PyObject* get_filter_id(PyObject *self, PyObject *args) {
    return PyLong_FromLong(FFMPEG_FILTER_ID);
}

// Module's function table
static PyMethodDef FFMPEGFilterMethods[] = {
    {"register_filter", register_filter, METH_NOARGS, 
     "Register the FFMPEG filter with HDF5."},
    {"get_filter_id", get_filter_id, METH_NOARGS,
     "Get the filter ID for the FFMPEG filter."},
    {NULL, NULL, 0, NULL}  // Sentinel
};

// Module definition
static struct PyModuleDef ffmpeg_filter_module = {
    PyModuleDef_HEAD_INIT,
    "_ffmpeg_filter",  // Module name
    "FFMPEG HDF5 filter extension module.",  // Module docstring
    -1,  // Module keeps state in global variables
    FFMPEGFilterMethods
};

// Module initialization function
PyMODINIT_FUNC PyInit__ffmpeg_filter(void) {
    PyObject *m;
    
    // Create the module
    m = PyModule_Create(&ffmpeg_filter_module);
    if (m == NULL)
        return NULL;
    
    // Import numpy arrays
    import_array();
    
    // Add the filter ID constant
    PyModule_AddIntConstant(m, "FFMPEG_ID", FFMPEG_FILTER_ID);
    
    return m;
}