"""
FFMPEG HDF5 Filter for Python

This package provides Python bindings for the FFMPEG HDF5 filter,
enabling high-ratio compression of scientific datasets using video codecs.
"""

import os
import sys
import warnings
import logging
import traceback
import ctypes

os.environ["SVT_LOG"] = "1"

logger = logging.getLogger(__name__)

# Import version first
try:
    from ._version import __version__
except ImportError:
    __version__ = "unknown"

# Import constants early (needed for FFMPEG_ID)
from .constants import FFMPEG_ID

# Try to import C extension
try:
    from ._ffmpeg_filter import (
        register_filter,
        get_filter_id,
    )

    # Verify the filter ID matches
    extension_id = get_filter_id()
    if extension_id != FFMPEG_ID:
        logger.warning(f"Filter ID mismatch: constants={FFMPEG_ID}, extension={extension_id}")
    
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
                logger.error(
                    f"Failed to register FFMPEG filter with HDF5: error code {result}"
                )
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
            if sys.platform.startswith("win"):
                ext_pattern = "_ffmpeg_filter*.pyd"
            elif sys.platform.startswith("darwin"):
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
            if not hasattr(lib, "H5PLget_plugin_info"):
                logger.error(
                    "H5PLget_plugin_info function not found in extension module"
                )
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
                logger.info(
                    f"Successfully registered FFMPEG filter (ID: {FFMPEG_ID}) with h5py"
                )
                return True

            except Exception as e:
                logger.error(
                    f"Error calling H5PLget_plugin_info or registering filter: {str(e)}"
                )
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
        try:
            from .patches import dummy
        except ImportError:
            logger.warning("Could not import patches module")
else:
    FILTER_REGISTERED = False

# Import from the organized modules
from .constants import (
    EncoderCodec,
    DecoderCodec, 
    Preset,
    Tune,
    BitMode,
)

from .gpu_utils import (
    has_nvidia_gpu,
    has_intel_gpu,
    detect_available_gpus,
)

from .ffmpeg_filter import (
    # Main API functions
    ffmpeg,
    # Convenience functions
    mpeg4,
    x264,
    x265,
    rav1e,
    svtav1,
    h264_nvenc,
    hevc_nvenc,
    av1_nvenc,
    av1_qsv,
    # Native functions
    ffmpeg_native,
    compress_native,
    decompress_native,
    NATIVE_AVAILABLE,
    # Filter class
    FFMPEG,
)

# Import additional modules
try:
    from .anm import film_grain_optimizer
except ImportError:
    logger.warning("Could not import film_grain_optimizer from anm module")
    film_grain_optimizer = None

__all__ = [
    # Version and status
    "__version__",
    "FFMPEG_ID", 
    "FILTER_REGISTERED",
    "NATIVE_AVAILABLE",
    # Main API functions
    "ffmpeg",
    "FFMPEG",
    # Convenience functions
    "mpeg4",
    "x264",
    "x265",
    "svtav1",
    "rav1e", 
    "h264_nvenc",
    "hevc_nvenc",
    "av1_nvenc",
    "av1_qsv",
    # Native functions
    "ffmpeg_native",
    "compress_native",
    "decompress_native",
    # Constants and enums
    "EncoderCodec",
    "DecoderCodec",
    "Preset", 
    "Tune",
    "BitMode",
    # Hardware detection
    "has_nvidia_gpu",
    "has_intel_gpu",
    "detect_available_gpus",
    # Additional utilities
    "film_grain_optimizer",
]

# Remove None values from __all__ if imports failed
__all__ = [item for item in __all__ if globals().get(item) is not None]