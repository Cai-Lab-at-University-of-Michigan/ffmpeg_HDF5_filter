import os
import tempfile
import numpy as np
import h5py

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
        with h5py.File(temp_file, 'w') as f:\
            f.create_dataset(dataset_name, data=data, **compression_options)
        
        # Get compressed file size
        compressed_size = get_file_size(temp_file)
        
        # Read back the data
        with h5py.File(temp_file, 'r') as f:
            decompressed_data = f[dataset_name][:]
        
        # Calculate compression ratio
        original_size = data.nbytes
        compression_ratio = calculate_compression_ratio(original_size, compressed_size)
        
        return decompressed_data, compression_ratio, compressed_size
    except Exception as e:
        print(str(e))
    
    finally:
        # Clean up temporary file
        cleanup_temp_file(temp_file)