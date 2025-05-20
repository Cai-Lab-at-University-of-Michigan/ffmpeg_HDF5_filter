"""
FFMPEG HDF5 Filter for Python

This package provides Python bindings for the FFMPEG HDF5 filter,
enabling high-ratio compression of scientific datasets using video codecs.
"""

__version__ = "1.0.0"

import os
import sys
import warnings
import logging
import traceback
import ctypes
import functools

logger = logging.getLogger(__name__)

try:
    from ._ffmpeg_filter import (
        register_filter, 
        get_filter_id,
    )

    FFMPEG_ID = get_filter_id()
    
    # Initialize registration status
    HAS_EXTENSION = True
except ImportError as e:
    logger.error(f"Failed to import the FFMPEG HDF5 filter extension: {str(e)}")
    # Fall back to a stub implementation
    warnings.warn(
        "FFMPEG HDF5 filter C extension could not be loaded. "
        "This could be due to missing dependencies or incompatible platform. "
        "The filter will not be available for compression."
    )
    FFMPEG_ID = 32030
    HAS_EXTENSION = False

# Register the filter with HDF5 and h5py
def _register_with_h5py():
    """Register the FFMPEG filter with HDF5 and h5py"""
    if not HAS_EXTENSION:
        return False

    try:
        # First register with HDF5
        try:
            result = register_filter()
            if result < 0:
                logger.error(f"Failed to register FFMPEG filter with HDF5: error code {result}")
                return False
        except Exception as e:
            logger.error(f"Error registering FFMPEG filter with HDF5: {str(e)}")
            return False
            
        import h5py
        
        try:
            # Find our extension module file
            module_path = None
            module_dir = os.path.dirname(os.path.abspath(__file__))
            
            # Find the extension file
            if sys.platform.startswith('win'):
                ext_pattern = "_ffmpeg_filter*.pyd"
            elif sys.platform.startswith('darwin'):
                ext_pattern = "_ffmpeg_filter*.so"
            else:
                ext_pattern = "_ffmpeg_filter*.so"
                
            import glob
            ext_files = glob.glob(os.path.join(module_dir, ext_pattern))
            
            if not ext_files:
                logger.error(f"Could not find extension module in {module_dir}")
                return False
                
            module_path = ext_files[0]
            logger.info(f"Found extension module at: {module_path}")
            
            # Load the module as a shared library
            try:
                lib = ctypes.CDLL(module_path)
                logger.info(f"Loaded module as shared library: {module_path}")
            except OSError as e:
                logger.error(f"Failed to load extension as shared library: {str(e)}")
                logger.error(traceback.format_exc())
                return False
                
            # Check if H5PLget_plugin_info exists
            if not hasattr(lib, 'H5PLget_plugin_info'):
                logger.error("H5PLget_plugin_info function not found in extension module")
                return False
                
            # Set the correct return type
            lib.H5PLget_plugin_info.restype = ctypes.c_void_p
            
            # Call the function and register with h5py
            try:
                plugin_info_ptr = lib.H5PLget_plugin_info()
                if not plugin_info_ptr:
                    logger.error("H5PLget_plugin_info() returned NULL")
                    return False
                    
                logger.info(f"Got plugin info pointer: {plugin_info_ptr}")
                
                # Register with h5py
                h5py.h5z.register_filter(plugin_info_ptr)
                logger.info(f"Successfully registered FFMPEG filter (ID: {FFMPEG_ID}) with h5py")
                return True
                
            except Exception as e:
                logger.error(f"Error calling H5PLget_plugin_info or registering filter: {str(e)}")
                logger.error(traceback.format_exc())
                return False
                
        except Exception as e:
            logger.error(f"Failed to register FFMPEG filter with h5py: {str(e)}")
            logger.error(traceback.format_exc())
            return False
            
    except Exception as e:
        logger.error(f"Unexpected error registering FFMPEG filter: {str(e)}")
        logger.error(traceback.format_exc())
        return False

# Attempt to register the filter
if HAS_EXTENSION:
    FILTER_REGISTERED = _register_with_h5py()
    if not FILTER_REGISTERED:
        warnings.warn(
            "FFMPEG HDF5 filter was loaded but registration with h5py failed. "
            "The filter may not be available for compression."
        )
    else:
        from .patches import dummy
else:
    FILTER_REGISTERED = False

# Import the other modules
from .ffmpeg_filter import (
    # Main API functions
    ffmpeg, mpeg4, x264, x265, rav1e, svtav1, h264_nvenc, hevc_nvenc, av1_nvenc, av1_qsv,
    
    # Classes for constants and enum values
    EncoderCodec, DecoderCodec, Preset, Tune, BitMode,
    
    # Helper functions for hardware detection
    has_nvidia_gpu, has_intel_gpu
)

from .anm import film_grain_optimizer


# Define what gets imported with "from h5ffmpeg import *"
__all__ = [
    'ffmpeg', 'mpeg4', 'x264', 'x265', 'svtav1', 'rav1e', 'h264_nvenc', 'hevc_nvenc', 'av1_nvenc', 'av1_qsv',
    'EncoderCodec', 'DecoderCodec', 'Preset', 'Tune', 'BitMode', 'has_nvidia_gpu', 'has_intel_gpu', 
    'FFMPEG_ID', 'film_grain_optimizer', 'FILTER_REGISTERED'
]