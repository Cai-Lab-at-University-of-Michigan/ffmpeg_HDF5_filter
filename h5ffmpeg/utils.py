import os
import tempfile
import numpy as np
import h5py
import time 

def create_temp_h5_file():
    """
    Create a temporary HDF5 file for testing.
    
    Returns:
    --------
    str
        Path to the temporary file
    """
    fd, path = tempfile.mkstemp(suffix='.h5')
    os.close(fd)
    return path

def cleanup_temp_file(file_path):
    """
    Clean up a temporary file.
    
    Parameters:
    -----------
    file_path : str
        Path to the file to be removed
    """
    if os.path.exists(file_path):
        os.remove(file_path)

def calculate_psnr(original, compressed):
    """
    Calculate Peak Signal-to-Noise Ratio between original and compressed data.
    
    Parameters:
    -----------
    original : numpy.ndarray
        Original data
    compressed : numpy.ndarray
        Compressed and decompressed data
        
    Returns:
    --------
    float
        PSNR value in dB
    """
    mse = np.mean((original - compressed) ** 2)
    if mse == 0:
        return float('inf')
    
    if original.dtype == np.uint8:
        max_pixel = 255.0
    else:  # np.uint16
        max_pixel = 65535.0
    
    psnr = 20 * np.log10(max_pixel / np.sqrt(mse))
    return psnr

def calculate_compression_ratio(original_size, compressed_size):
    """
    Calculate compression ratio.
    
    Parameters:
    -----------
    original_size : int
        Size of original data in bytes
    compressed_size : int
        Size of compressed data in bytes
        
    Returns:
    --------
    float
        Compression ratio (original_size / compressed_size)
    """
    return original_size / compressed_size

def get_file_size(file_path):
    """
    Get the size of a file in bytes.
    
    Parameters:
    -----------
    file_path : str
        Path to the file
        
    Returns:
    --------
    int
        File size in bytes
    """
    return os.path.getsize(file_path)

def compress_and_decompress(data, compression_options, dataset_name="data"):
    """
    Compress and decompress data using the FFMPEG HDF5 filter.
    
    Parameters:
    -----------
    data : numpy.ndarray
        Data to compress
    compression_options : dict
        Compression options for h5py.create_dataset
    dataset_name : str
        Name of the dataset in the HDF5 file
        
    Returns:
    --------
    tuple
        (decompressed_data, compression_ratio, file_size)
    """
    assert data.ndim == 3, "Input needs to be 3D"
    # Create a temporary HDF5 file
    temp_file = create_temp_h5_file()
    
    try:
        # Write data with compression
        start_time = time.time()
        with h5py.File(temp_file, 'w') as f:\
            f.create_dataset(dataset_name, data=data, **compression_options)
        enc_time = time.time() - start_time
        
        # Get compressed file size
        compressed_size = get_file_size(temp_file)
        
        # Read back the data
        start_time = time.time()
        with h5py.File(temp_file, 'r') as f:
            decompressed_data = f[dataset_name][:]
        dec_time = time.time() - start_time
        
        # Calculate compression ratio
        original_size = data.nbytes
        compression_ratio = calculate_compression_ratio(original_size, compressed_size)

        return decompressed_data, compression_ratio, compressed_size, enc_time, dec_time
    except Exception as e:
        print(str(e))
    
    finally:
        # Clean up temporary file
        cleanup_temp_file(temp_file)

def generate_3d_sample_vol(width=512, height=512, depth=100, dtype=np.uint8, pattern="stripes", seed=None):
    """
    Generate 3D volume test data.
    """
    if dtype not in [np.uint8, np.uint16]:
        raise ValueError("Only np.uint8 and np.uint16 data types are supported")
    
    if seed is not None:
        np.random.seed(seed)
    
    if pattern == "random":
        if dtype == np.uint8:
            return np.random.randint(0, 256, (depth, height, width), dtype=dtype)
        else:
            return np.random.randint(0, 65536, (depth, height, width), dtype=dtype)
    
    elif pattern == "gradient":
        x = np.linspace(0, 1, width)
        y = np.linspace(0, 1, height)
        z = np.linspace(0, 1, depth)
        xx, yy, zz = np.meshgrid(x, y, z, indexing='ij')
        data = (xx + yy + zz) / 3
        
        if dtype == np.uint8:
            data = (data * 255).astype(dtype)
        else:
            data = (data * 65535).astype(dtype)
        
        return np.transpose(data, [2, 1, 0])
    
    elif pattern == "stripes":
        x = np.arange(width)
        data = np.sin(x * 8 * np.pi / width)
        data = np.tile(data, (depth, height, 1))
        
        data = (data + 1) / 2
        
        if dtype == np.uint8:
            data = (data * 255).astype(dtype)
        else:
            data = (data * 65535).astype(dtype)
        
        return data  
    
    else:
        raise ValueError(f"Unknown pattern: {pattern}")
