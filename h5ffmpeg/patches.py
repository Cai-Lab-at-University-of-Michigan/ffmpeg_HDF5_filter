import h5py
import numpy as np
import math
from collections.abc import Iterable

FFMPEG_ID = 32030
MAX_CHUNK_SIZE = 4 * 1024**3  # 4 GB

# Store the original methods
_original_dataset_getitem = h5py.Dataset.__getitem__
_original_dataset_setitem = h5py.Dataset.__setitem__

# Define new getitem method
def _patched_getitem(self, key):
    data = _original_dataset_getitem(self, key)

    # Check if this dataset should be quantized
    if 'bit' not in self.attrs:
        return data
    
    norm = self.attrs.get('norm', False)
    beta = self.attrs.get('beta', 1.0)
    dtype_map = {0: np.uint8, 1: np.uint16, 2: np.float32}
    dtype = dtype_map.get(self.attrs.get('data_type', 0), np.uint8)
    
    if not norm and beta == 1.0:
        return data
    
    bit = self.attrs.get('bit', 8)
    max_bitType_val = (1 << bit) - 1
    max_val = self.attrs.get('init_max_intensity', max_bitType_val)
    min_val = self.attrs.get('init_min_intensity', 0)
    
    data = data.astype(np.float32, copy=False)
    if norm:
        if beta != 1.0 and beta > 0:
            np.power(data / max_bitType_val, 1 / beta, out=data)
            data *= max_val - min_val
            data += min_val
        else:
            data = data / max_bitType_val * (max_val - min_val) + min_val
    elif beta != 1.0 and beta > 0:
        np.power(data, 1 / beta, out=data)
        np.clip(data + min_val, min_val, max_val, out=data)
    else:
        np.clip(data, min_val, max_val, out=data)
            
    return data.astype(dtype, copy=False)

# Define new setitem method
def _patched_setitem(self, key, value):
    # Check if this dataset should be quantized
    if 'bit' not in self.attrs:
        _original_dataset_setitem(self, key, value)
        return
    
    norm = self.attrs.get('norm', False)
    beta = self.attrs.get('beta', 1.0)
    
    if not norm and beta == 1.0:
        _original_dataset_setitem(self, key, value)
        return
    
    if value.dtype == np.float32:
        dtype = np.uint8
    else:
        dtype = value.dtype
    
    data = np.asarray(value, dtype=np.float32)
    bit = self.attrs.get('bit', 8)
    max_bitType_val = (1 << bit) - 1
    
    # Fix: Safe handling of dtype for np.iinfo
    try:
        default_max = np.iinfo(dtype).max if dtype in [np.uint8, np.uint16] else 255
    except:
        default_max = 255
    max_val = self.attrs.get('init_max_intensity', default_max)
    min_val = self.attrs.get('init_min_intensity', 0)
    
    if norm:
        data -= min_val
        data /= max_val - min_val
        if beta != 1.0 and beta > 0:
            np.power(data, beta, out=data)
        data *= max_bitType_val
    elif beta != 1.0 and beta > 0:
        data -= min_val  # Fix: Subtract min_val before power scaling
        np.power(data, beta, out=data)
        np.clip(data, 0, max_bitType_val, out=data)
    else:
        np.clip(data, 0, max_bitType_val, out=data)
    
    _original_dataset_setitem(self, key, data.astype(dtype, copy=False))

# Apply the patches
h5py.Dataset.__getitem__ = _patched_getitem
h5py.Dataset.__setitem__ = _patched_setitem

# Original create_dataset patching with modifications
_original_group_create_dataset = h5py.Group.create_dataset

def _patched_create_dataset(self, name, shape=None, dtype=None, data=None, **kwargs):
    compression = kwargs.get('compression', 0)

    if compression == FFMPEG_ID:
        norm = kwargs.pop('norm', False)
        beta = kwargs.pop('beta', 1.0)
        compression_opts = list(kwargs.get('compression_opts', ()))
        bit = {0: 8, 1: 10, 2: 12}.get(compression_opts[5] if len(compression_opts) > 5 else 0, 8)
        use_quant = False

        if data is not None:
            assert data.dtype in [np.uint8, np.uint16, np.float32]
            use_quant = data.dtype != np.uint8
            if not use_quant and len(compression_opts) > 5:
                compression_opts[5] = 0
                bit = 8
            
            kwargs['compression_opts'] = tuple(compression_opts)

        if dtype is not None:
            assert dtype in [np.uint8, np.uint16]
            use_quant = dtype != np.uint8

        user_chunks = kwargs.get('chunks', None)
        
        if user_chunks is None or user_chunks is True:
            final_shape = shape or (np.shape(data) if data is not None else None)
            if final_shape is None:
                raise RuntimeError("Either 'data' or 'shape' must be provided for chunking.")
                
            final_dtype = np.dtype(dtype) if dtype is not None else (np.asarray(data).dtype if data is not None else np.uint8)
            element_size = final_dtype.itemsize
            full_size = math.prod(final_shape) * element_size
            
            if full_size <= MAX_CHUNK_SIZE:
                chunks = final_shape
            else:
                scale = (MAX_CHUNK_SIZE / full_size) ** (1 / len(final_shape))
                chunks = tuple(max(1, min(dim, int(dim * scale))) for dim in final_shape)
                
            kwargs['chunks'] = chunks
            
        elif isinstance(user_chunks, tuple):
            chunks = user_chunks
            
        else:
            raise ValueError(f"For FFMPEG compression, 'chunks' must be True, None, or a tuple, got {user_chunks}")
        
        comp_opts = list(kwargs.get('compression_opts', ()) if isinstance(kwargs.get('compression_opts', ()), Iterable) 
                        else [kwargs.get('compression_opts', ())])
                        
        comp_opts[2:5] = chunks[::-1]
        kwargs['compression_opts'] = tuple(comp_opts)
    
        # Process data for quantization
        init_max = None
        init_min = None
        
        if use_quant and data is not None:
            data_dtype = data.dtype
            if data_dtype == np.uint16:
                data = np.asarray(data, dtype=np.float32)
                init_max = np.amax(data)
                max_bit_val = (1 << bit) - 1

                if norm:
                    data = data / init_max * max_bit_val
                    data = np.power(data, beta)
                else:
                    beta = math.log(max_bit_val, init_max) - np.finfo(float).eps
                    data = np.power(data, beta)

            elif data_dtype == np.float32: # MRI/CT has negative values
                init_min, init_max = np.amin(data), np.amax(data)
                max_bit_val = (1 << bit) - 1

                if norm:
                    data = (data - init_min) / (init_max - init_min) * max_bit_val
                    data = np.power(data, beta)
                else:
                    beta = math.log(max_bit_val, init_max - init_min) - np.finfo(float).eps
                    data = np.power(data - init_min, beta)

            if bit == 8:
                data = data.astype(np.uint8, copy=False)
                dtype = np.uint8
            else:
                data = data.astype(np.uint16, copy=False)
                dtype = np.uint16

        # Create dataset and add attributes
        dset = _original_group_create_dataset(self, name, shape, dtype, data, **kwargs)
        
        if use_quant:
            if norm:
                dset.attrs['norm'] = norm
            dset.attrs['bit'] = bit
            if beta != 1.0:
                dset.attrs['beta'] = beta
                
            final_dtype = dtype or (data.dtype if data is not None else np.uint8)
            max_bit_val = (1 << bit) - 1
            dset.attrs['init_max_intensity'] = init_max if init_max is not None else max_bit_val
            dset.attrs['init_min_intensity'] = init_min if init_min is not None else 0
            dtype_map = {'uint8': 0, 'uint16': 1, 'float32': 2}
            dset.attrs['data_type'] = dtype_map.get(str(data_dtype), 0)
        
        return dset
    else:
        return _original_group_create_dataset(self, name, shape, dtype, data, **kwargs)

h5py.Group.create_dataset = _patched_create_dataset


def dummy():
    pass