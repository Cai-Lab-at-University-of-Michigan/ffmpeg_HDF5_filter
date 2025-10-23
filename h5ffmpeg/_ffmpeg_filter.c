#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <numpy/arrayobject.h>
#include <hdf5.h>

#include "ffmpeg_utils.h"

#define FFMPEG_FILTER_ID 32030

extern H5Z_class_t ffmpeg_H5Filter[1];

extern size_t ffmpeg_native(unsigned flags, const unsigned int cd_values[], size_t buf_size, void **buf);

// Patched version of the filter registration function
static PyObject *register_filter(PyObject *self, PyObject *args)
{

    // Call the C function
    int result = ffmpeg_register_h5filter();

    return PyLong_FromLong(result);
}

// Get the filter ID
static PyObject *get_filter_id(PyObject *self, PyObject *args)
{
    return PyLong_FromLong(FFMPEG_FILTER_ID);
}

static PyObject *ffmpeg_native_c(PyObject *self, PyObject *args, PyObject *kwargs)
{
    PyObject *input_data = NULL;
    PyObject *cd_values_list = NULL;
    unsigned int flags;
    size_t buf_size;

    static char *kwlist[] = {"flags", "cd_values", "buf_size", "data", NULL};

    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "IOkO", kwlist,
                                     &flags, &cd_values_list, &buf_size, &input_data))
    {
        return NULL;
    }

    // Convert Python list/tuple to C array
    if (!PyList_Check(cd_values_list) && !PyTuple_Check(cd_values_list))
    {
        PyErr_SetString(PyExc_TypeError, "cd_values must be a list or tuple");
        return NULL;
    }

    Py_ssize_t list_size = PySequence_Size(cd_values_list);
    if (list_size != 11)
    {
        PyErr_SetString(PyExc_ValueError, "cd_values must have 11 elements");
        return NULL;
    }

    unsigned int cd_values[11];
    for (int i = 0; i < 11; i++)
    {
        PyObject *item = PySequence_GetItem(cd_values_list, i);
        if (!PyLong_Check(item))
        {
            Py_DECREF(item);
            PyErr_SetString(PyExc_TypeError, "All cd_values elements must be integers");
            return NULL;
        }
        cd_values[i] = PyLong_AsUnsignedLong(item);
        Py_DECREF(item);

        // Check for conversion errors
        if (PyErr_Occurred())
        {
            PyErr_SetString(PyExc_ValueError, "Invalid integer value in cd_values");
            return NULL;
        }
    }

    void *buf = NULL;

    // Get data and copy it
    if (flags == 0)
    { 
        // Compress
        // First check if input_data is actually a NumPy array
        if (!PyArray_Check(input_data)) {
            PyErr_SetString(PyExc_TypeError, "Input data must be a numpy array for compression");
            return NULL;
        }
        
        // Cast to PyArrayObject* and get contiguous array
        PyArrayObject *input_array = (PyArrayObject *)input_data;
        PyArrayObject *array = (PyArrayObject *)PyArray_GETCONTIGUOUS(input_array);
        if (!array)
            return NULL;

        size_t actual_buf_size = PyArray_NBYTES(array);
        // Use the larger of provided buf_size or actual array size
        if (buf_size == 0)
            buf_size = actual_buf_size;

        buf = malloc(buf_size);
        if (!buf)
        {
            Py_DECREF(array);
            PyErr_SetString(PyExc_MemoryError, "Failed to allocate memory");
            return NULL;
        }
        memcpy(buf, PyArray_DATA(array), actual_buf_size);
        Py_DECREF(array);
    }
    else
    { // Decompress
        char *data_ptr;
        Py_ssize_t size;
        if (PyBytes_AsStringAndSize(input_data, &data_ptr, &size) < 0)
        {
            return NULL;
        }

        // The Python code has already parsed the metadata and stripped it
        // So data_ptr now points directly to the compressed data
        buf_size = size;
        buf = malloc(buf_size);
        if (!buf)
        {
            PyErr_SetString(PyExc_MemoryError, "Failed to allocate memory");
            return NULL;
        }
        memcpy(buf, data_ptr, size);
    }

    // Release GIL during CPU-intensive ffmpeg operation
    size_t result_size;
    //Py_BEGIN_ALLOW_THREADS
    result_size = ffmpeg_native(flags, cd_values, buf_size, &buf);
    //Py_END_ALLOW_THREADS

    if (result_size == 0)
    {
        free(buf);
        PyErr_SetString(PyExc_RuntimeError, "Operation failed");
        return NULL;
    }

    PyObject *result;
    if (flags == 0)
    { 
        // Compression: Return metadata + compressed data
        // Create metadata structure with size_t for compressed_size

        PyObject *module = PyImport_ImportModule("h5ffmpeg._ffmpeg_filter");
        PyObject *version_obj = PyObject_GetAttrString(module, "HEADER_VERSION");
        unsigned int header_version = version_obj ? (unsigned int)PyLong_AsUnsignedLong(version_obj) : 2;
        Py_XDECREF(version_obj);
        Py_XDECREF(module);

        size_t metadata_size = 11 * sizeof(unsigned int) + sizeof(uint64_t); // 11 uint32 + 1 size_t
        size_t header_size = 8; // metadata_size(4) + version(4)
        size_t total_size = header_size + metadata_size + result_size;
        
        char *output_buf = malloc(total_size);
        if (!output_buf) {
            free(buf);
            PyErr_SetString(PyExc_MemoryError, "Failed to allocate output buffer");
            return NULL;
        }
        
        size_t offset = 0;
        
        // Write header: metadata size + version
        *(unsigned int*)(output_buf + offset) = (unsigned int)metadata_size;
        offset += sizeof(unsigned int);
        *(unsigned int*)(output_buf + offset) = header_version;
        offset += sizeof(unsigned int);
        
        // Write metadata fields (11 unsigned ints)
        unsigned int metadata[11] = {
            cd_values[0],  // enc_id
            cd_values[1],  // dec_id
            cd_values[2],  // width
            cd_values[3],  // height
            cd_values[4],  // depth
            cd_values[5],  // bit_mode
            cd_values[6],  // preset_id
            cd_values[7],  // tune_id
            cd_values[8],  // crf
            cd_values[9],  // film_grain
            cd_values[10], // gpu_id
        };
        
        memcpy(output_buf + offset, metadata, 11 * sizeof(unsigned int));
        offset += 11 * sizeof(unsigned int);
        
        // Write compressed_size as uint64_t
        *(uint64_t*)(output_buf + offset) = (uint64_t)result_size;
        offset += sizeof(uint64_t);
        
        // Write compressed data
        memcpy(output_buf + offset, buf, result_size);
        
        result = PyBytes_FromStringAndSize(output_buf, total_size);
        free(output_buf);
    }
    else
    { 
        // Decompression: Return numpy array
        // Extract dimensions from cd_values
        unsigned int width = cd_values[2];
        unsigned int height = cd_values[3];
        unsigned int depth = cd_values[4];
        unsigned int bit_mode = cd_values[5];

        npy_intp dims[3] = {depth, height, width};
        int typenum = (bit_mode == 0) ? NPY_UINT8 : NPY_UINT16;
        PyArrayObject *array = (PyArrayObject *)PyArray_SimpleNew(3, dims, typenum);
        if (!array)
        {
            free(buf);
            return NULL;
        }
        memcpy(PyArray_DATA(array), buf, result_size);
        result = (PyObject *)array;
    }

    free(buf);
    return result;
}

// Module's function table
static PyMethodDef FFMPEGFilterMethods[] = {
    {"register_filter", register_filter, METH_NOARGS,
     "Register the FFMPEG filter with HDF5."},
    {"get_filter_id", get_filter_id, METH_NOARGS,
     "Get the filter ID for the FFMPEG filter."},
    {"ffmpeg_native_c", (PyCFunction)ffmpeg_native_c, METH_VARARGS | METH_KEYWORDS,
     "Native FFMPEG function."},
    {NULL, NULL, 0, NULL} // Sentinel
};

// Module definition
static struct PyModuleDef ffmpeg_filter_module = {
    PyModuleDef_HEAD_INIT,
    "_ffmpeg_filter",                       // Module name
    "FFMPEG HDF5 filter extension module.", // Module docstring
    -1,                                     // Module keeps state in global variables
    FFMPEGFilterMethods};

// Module initialization function
PyMODINIT_FUNC PyInit__ffmpeg_filter(void)
{
    PyObject *m;

    // Create the module
    m = PyModule_Create(&ffmpeg_filter_module);
    if (m == NULL)
        return NULL;

    // Import numpy arrays
    import_array();

    // Add the filter ID constant
    PyModule_AddIntConstant(m, "FFMPEG_ID", FFMPEG_FILTER_ID);

    PyObject *constants_module = PyImport_ImportModule("h5ffmpeg.constants");
    if (constants_module) {
        PyObject *get_version_func = PyObject_GetAttrString(constants_module, "get_current_header_version");
        if (get_version_func && PyCallable_Check(get_version_func)) {
            PyObject *version_result = PyObject_CallObject(get_version_func, NULL);
            if (version_result && PyLong_Check(version_result)) {
                long header_version = PyLong_AsLong(version_result);
                PyModule_AddIntConstant(m, "HEADER_VERSION", (int)header_version);
            }
            Py_XDECREF(version_result);
        }
        Py_XDECREF(get_version_func);
        Py_DECREF(constants_module);
    }
    
    return m;
}