import h5py
import numpy as np
import math
from collections.abc import Iterable
import functools

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
    
    if not norm and beta == 1.0:
        return data
    
    dtype = data.dtype
    bit = self.attrs.get('bit', 8)
    max_bitType_val = (1 << bit) - 1
    max_val = self.attrs.get('init_max_intensity', np.iinfo(dtype).max)
    min_val = self.attrs.get('init_min_intensity', 0)
    
    data = data.astype(np.float32, copy=False)
    if norm:
        if beta != 1.0 and beta > 0:
            np.power(data / max_bitType_val, beta, out=data)
            data *= (max_val - min_val)
            data += min_val
        else:
            data = data / max_bitType_val * (max_val - min_val) + min_val
    elif beta != 1.0 and beta > 0:
        np.power(data, 1 / beta, out=data)
        np.clip(data, min_val, max_val, out=data)
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
    
    dtype = data.dtype
    data = np.asarray(value, dtype=np.float32)
    bit = self.attrs.get('bit', 8)
    max_bitType_val = (1 << bit) - 1
    max_val = self.attrs.get('init_max_intensity', np.iinfo(dtype).max)
    min_val = self.attrs.get('init_min_intensity', 0)
    
    if norm:
        range_val = max_val - min_val
        if range_val > 0:
            data = (data - min_val) / range_val
            if beta != 1.0 and beta > 0:
                np.power(data, beta, out=data)
            data *= max_bitType_val
    elif beta != 1.0 and beta > 0:
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
    norm = kwargs.pop('norm', False)
    compression = kwargs.get('compression', 0)
    compression_opts = kwargs.get('compression_opts', ())
    bit = {0: 8, 1: 10, 2: 12}.get(compression_opts[5] if len(compression_opts) > 5 else 0, 8)
    use_quant = compression == FFMPEG_ID or bit in [8, 10, 12]

    if compression == FFMPEG_ID:
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
    beta = 1.0
    init_max = init_min = None
    
    if use_quant and data is not None:
        data_dtype = data.dtype
        data_array = np.asarray(data, dtype=np.float32)
        init_max = np.amax(data_array)
        init_min = np.amin(data_array)
        max_bit_val = (1 << bit) - 1
        
        if norm:
            range_val = init_max - init_min
            if range_val > 0:
                data_array = (data_array - init_min) * (max_bit_val / range_val)
        elif init_max > init_min:
            beta = math.log(max_bit_val) / math.log(init_max - init_min)
            data_array = np.power(data_array - init_min, beta)
        
        data = data_array.astype(data_dtype, copy=False)

    # Create dataset and add attributes
    dset = _original_group_create_dataset(self, name, shape, dtype, data, **kwargs)
    
    if use_quant:
        if norm:
            dset.attrs['norm'] = norm
        dset.attrs['bit'] = bit
        if beta != 1.0:
            dset.attrs['beta'] = beta
            
        final_dtype = dtype or (data.dtype if data is not None else np.uint8)
        dset.attrs['init_max_intensity'] = init_max if init_max is not None else np.iinfo(np.dtype(final_dtype)).max
        dset.attrs['init_min_intensity'] = init_min if init_min is not None else 0
    
    return dset

h5py.Group.create_dataset = _patched_create_dataset


def dummy():
    pass