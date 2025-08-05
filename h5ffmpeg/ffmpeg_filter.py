"""
FFMPEG HDF5 filter - Python interface

This module provides a Python interface to the FFMPEG HDF5 filter,
allowing compression of HDF5 datasets using various video codecs.
"""

import numpy as np
import h5py
import logging
import struct

from .constants import (
    FFMPEG_ID, METADATA_FIELDS, HEADER_SIZE, Preset, Tune, BitMode,
    CODEC_TO_ENCODER, CODEC_TO_DECODER, PRESET_MAPPING, TUNE_MAPPING,
    DEFAULT_DECODER, DEFAULT_GPU_DECODER, get_current_header_version
)
from .gpu_utils import has_nvidia_gpu, has_intel_gpu, validate_and_adjust_gpu_id

logger = logging.getLogger(__name__)

def get_codec_name_from_encoder_id(enc_id):
    """Get codec name from encoder ID"""
    for codec_name, codec_id in CODEC_TO_ENCODER.items():
        if codec_id == enc_id:
            return codec_name
    return "unknown"

def modify_compression_opts(compression_opts):
    """
    Design to handle hardware decompression
        use different GPU [different systems]
    or
        Fall Back to Software Decompression
    """
    compression_opts = list(compression_opts)
    enc_id = compression_opts[0]
    dec_id = compression_opts[1]
    gpu_id = compression_opts[10]

    if dec_id in DEFAULT_GPU_DECODER.values():
        codec_name = get_codec_name_from_encoder_id(enc_id)
        actual_gpu_id = validate_and_adjust_gpu_id(codec_name, gpu_id)
        if actual_gpu_id < 0:
            dec_id = DEFAULT_DECODER[enc_id]
            compression_opts[10] = 0
        else:
            compression_opts[10] = actual_gpu_id
        compression_opts[1] = dec_id

    return tuple(compression_opts)

class FFMPEG(h5py.filters.FilterRefBase):
    """
    FFMPEG HDF5 filter class for h5py

    This class implements the FFMPEG HDF5 filter interface for h5py,
    allowing compression of HDF5 datasets using video codecs.
    """

    filter_name = "ffmpeg"
    filter_id = FFMPEG_ID

    def __init__(
        self,
        enc_id,
        dec_id,
        depth,
        height,
        width,
        bit_mode,
        preset,
        tune,
        crf,
        film_grain,
        gpu_id,
    ):
        """
        Create an FFMPEG filter instance with the given parameters.

        Parameters:
        -----------
        enc_id : int
            Encoder codec ID
        dec_id : int
            Decoder codec ID
        depth : int
            Number of frames (depth of the 3D volume)
        height : int
            Height of the video frames
        width : int
            Width of the video frames
        bit_mode : int
            Bit depth mode (8, 10, or 12)
        preset : int
            Preset ID for encoding speed/quality tradeoff
        tune : int
            Tune ID for specific content optimization
        crf : int
            Constant Rate Factor for quality control
        film_grain : int
            Film grain synthesis parameter (0-50, 0 means disabled)
        gpu_id : int
            GPU ID for hardware acceleration
        """
        self.filter_options = (
            int(enc_id),
            int(dec_id),
            int(width),
            int(height),
            int(depth),
            int(bit_mode),
            int(preset),
            int(tune),
            int(crf),
            int(film_grain),
            int(gpu_id),
        )


def ffmpeg(
    codec="libx264",
    decoder=None,
    preset=None,
    tune=None,
    crf=None,
    bit_mode=BitMode.BIT_8,
    film_grain=0,
    gpu_id=0,
    width=None,
    height=None,
    depth=None,
    **kwargs,
):
    """
    Create HDF5 filter parameters for FFMPEG compression.

    Parameters:
    -----------
    codec : str
        Video codec to use (e.g., "libx264", "libx265", "libsvtav1")
    decoder : str, optional
        Decoder to use for decompression. If None, a default decoder is selected.
    preset : str, optional
        Encoder preset (slower = better compression)
    tune : str, optional
        Tuning parameter for specific content types
    crf : int, optional
        Constant Rate Factor for quality control (lower = better quality)
    bit_mode : int, optional
        Bit depth mode (8, 10, or 12 bits)
    film_grain : int, optional
        Film grain synthesis parameter (0-100, 0 means disabled)
    gpu_id : int, optional
        GPU ID for hardware acceleration (-1 means CPU-only)
    width : int, optional
        Custom width override (default: auto-detected from data)
    height : int, optional
        Custom height override (default: auto-detected from data)
    depth : int, optional
        Custom depth override (default: auto-detected from data)
    **kwargs : dict
        Additional parameters (reserved for future use)

    Returns:
    --------
    dict
        Filter parameters for h5py.create_dataset
    """

    # Get encoder ID for the codec
    if codec not in CODEC_TO_ENCODER:
        raise ValueError(
            f"Unknown codec: {codec}. Available codecs: {', '.join(CODEC_TO_ENCODER.keys())}"
        )

    enc_id = CODEC_TO_ENCODER[codec]

    # Select decoder
    if decoder is None:
        # Use GPU decoder if using GPU encoder and no specific decoder is requested
        if gpu_id >= 0 and enc_id in DEFAULT_GPU_DECODER:
            dec_id = DEFAULT_GPU_DECODER[enc_id]
        else:
            # Use default decoder for the encoder
            dec_id = DEFAULT_DECODER[enc_id]
    else:
        if decoder not in CODEC_TO_DECODER:
            raise ValueError(
                f"Unknown decoder: {decoder}. Available decoders: {', '.join(CODEC_TO_DECODER.keys())}"
            )
        dec_id = CODEC_TO_DECODER[decoder]

    # Get preset ID
    preset_id = Preset.NONE
    if preset is not None:
        if codec in PRESET_MAPPING and preset in PRESET_MAPPING[codec]:
            preset_id = PRESET_MAPPING[codec][preset]
        else:
            valid_presets = list(PRESET_MAPPING.get(codec, {}).keys())
            raise ValueError(
                f"Invalid preset '{preset}' for codec '{codec}'. Valid presets: {', '.join(valid_presets)}"
            )

    # Get tune ID
    tune_id = Tune.NONE
    if tune is not None:
        if codec in TUNE_MAPPING and tune in TUNE_MAPPING[codec]:
            tune_id = TUNE_MAPPING[codec][tune]
        else:
            valid_tunes = list(TUNE_MAPPING.get(codec, {}).keys())
            raise ValueError(
                f"Invalid tune '{tune}' for codec '{codec}'. Valid tunes: {', '.join(valid_tunes)}"
            )

    # Check for hardware acceleration conflicts
    if gpu_id >= 0:
        # For NVIDIA encoders, check if NVIDIA GPU is available
        if "nvenc" in codec and not has_nvidia_gpu():
            raise RuntimeError(f"{codec} requested but NVIDIA GPU not detected.")

        # For Intel QSV encoders, check if Intel GPU is available
        if "qsv" in codec and not has_intel_gpu():
            raise RuntimeError(f"{codec} requested but Intel GPU not detected.")

    # Pack all parameters into the filter options
    filter_options = (
        enc_id,
        dec_id,
        width or 0,
        height or 0,
        depth or 0,
        bit_mode,
        preset_id,
        tune_id,
        crf or 0,
        film_grain,
        gpu_id,
    )

    return {
        "compression": FFMPEG_ID,
        "compression_opts": filter_options,
        "norm": kwargs.pop("norm", True),
        "beta": kwargs.pop("beta", 1.0),
    }


# Convenience functions for specific codecs
def mpeg4(crf=3, **kwargs):
    """Convenience function for H.264 compression"""
    return ffmpeg(codec="libxvid", crf=crf, **kwargs)


def x264(preset="medium", crf=23, tune=None, **kwargs):
    """Convenience function for H.264 compression"""
    return ffmpeg(codec="libx264", preset=preset, crf=crf, tune=tune, **kwargs)


def x265(preset="medium", crf=28, tune=None, **kwargs):
    """Convenience function for H.265/HEVC compression"""
    return ffmpeg(codec="libx265", preset=preset, crf=crf, tune=tune, **kwargs)


def rav1e(preset="6", crf=30, tune=None, **kwargs):
    """Convenience function for AV1 compression"""
    return ffmpeg(codec="librav1e", preset=preset, crf=crf, tune=tune, **kwargs)


def svtav1(preset="6", crf=30, tune="fastdecode", **kwargs):
    """Convenience function for AV1 compression"""
    return ffmpeg(codec="libsvtav1", preset=preset, crf=crf, tune=tune, **kwargs)


def h264_nvenc(preset="p4", crf=23, **kwargs):
    """Convenience function for NVIDIA H.264 hardware compression"""
    gpu_id = kwargs.pop("gpu_id", 0)  # Default to first GPU
    return ffmpeg(codec="h264_nvenc", preset=preset, crf=crf, gpu_id=gpu_id, **kwargs)


def hevc_nvenc(preset="p4", crf=23, **kwargs):
    """Convenience function for NVIDIA H.265/HEVC hardware compression"""
    gpu_id = kwargs.pop("gpu_id", 0)  # Default to first GPU
    return ffmpeg(codec="hevc_nvenc", preset=preset, crf=crf, gpu_id=gpu_id, **kwargs)


def av1_nvenc(preset="p4", crf=23, **kwargs):
    """Convenience function for NVIDIA H.265/HEVC hardware compression"""
    gpu_id = kwargs.pop("gpu_id", 0)  # Default to first GPU
    return ffmpeg(codec="av1_nvenc", preset=preset, crf=crf, gpu_id=gpu_id, **kwargs)


def av1_qsv(preset="medium", crf=30, tune=None, **kwargs):
    """Convenience function for Intel AV1 QSV hardware compression"""
    return ffmpeg(codec="av1_qsv", preset=preset, crf=crf, tune=tune, **kwargs)


# native functions
try:
    from ._ffmpeg_filter import ffmpeg_native_c

    def read_metadata_from_compressed(compressed_data):
        """Extract metadata from compressed data"""
        if len(compressed_data) < HEADER_SIZE:
            raise ValueError("Invalid compressed data: too short")

        # Read header: metadata size + version
        metadata_size, version = struct.unpack("II", compressed_data[:8])
        
        current_version = get_current_header_version()
        if version != current_version:
            raise ValueError(
                f"Version mismatch: file uses version {version}, "
                f"current implementation supports version {current_version}"
            )
        
        if len(compressed_data) < HEADER_SIZE + metadata_size:
            raise ValueError("Invalid compressed data: metadata size mismatch")

        offset = 8
        
        # Read metadata fields (11 uint32 values INCLUDING gpu_id)
        metadata_values = struct.unpack("I" * METADATA_FIELDS, 
                                    compressed_data[offset:offset + METADATA_FIELDS * 4])
        offset += METADATA_FIELDS * 4
        
        # Read compressed_size as uint64_t (always 8 bytes, platform-agnostic)
        compressed_size = struct.unpack("Q", compressed_data[offset:offset + 8])[0]
        offset += 8
        
        (enc_id, dec_id, width, height, depth, bit_mode, 
        preset_id, tune_id, crf, film_grain, stored_gpu_id) = metadata_values

        return {
            "enc_id": enc_id,
            "dec_id": dec_id,
            "preset_id": preset_id,
            "tune_id": tune_id,
            "width": width,
            "height": height,
            "depth": depth,
            "bit_mode": bit_mode,
            "crf": crf,
            "film_grain": film_grain,
            "stored_gpu_id": stored_gpu_id,
            "compressed_size": compressed_size,
            "data_offset": offset,
            "version": version,
        }

    def ffmpeg_native(
        flags,
        data,
        codec="libx264",
        preset=None,
        tune=None,
        crf=23,
        bit_mode=BitMode.BIT_8,
        film_grain=0,
        gpu_id=0,
    ):
        """Single native function for compress (flags=0) and decompress (flags=1)"""

        if flags == 0:  # Compress
            enc_id = CODEC_TO_ENCODER[codec]
            dec_id = DEFAULT_DECODER[enc_id]

            # Validate and adjust GPU ID for compression
            validated_gpu_id = validate_and_adjust_gpu_id(codec, gpu_id)

            if validated_gpu_id < 0:
                raise RuntimeError("No GPU Detected!")

            preset_id = (
                PRESET_MAPPING.get(codec, {}).get(preset, Preset.NONE)
                if preset
                else Preset.NONE
            )
            tune_id = (
                TUNE_MAPPING.get(codec, {}).get(tune, Tune.NONE) if tune else Tune.NONE
            )

            data = np.ascontiguousarray(
                data, dtype=(np.uint8 if bit_mode == BitMode.BIT_8 else np.uint16)
            )

            if data.ndim != 3:
                raise ValueError("Data must be a 3D array (depth, height, width)")

            depth, height, width = data.shape
            buf_size = data.nbytes

            stored_gpu_id = gpu_id
            actual_gpu_id = validated_gpu_id

        else:  # Decompress (flags=1)
            # Read metadata from the compressed bytes
            metadata = read_metadata_from_compressed(data)

            # Extract values from metadata
            width = metadata["width"]
            height = metadata["height"]
            depth = metadata["depth"]
            bit_mode = metadata["bit_mode"]
            enc_id = metadata["enc_id"]
            dec_id = metadata["dec_id"]
            preset_id = metadata["preset_id"]
            tune_id = metadata["tune_id"]
            crf = metadata["crf"]
            film_grain = metadata["film_grain"]
            stored_gpu_id = metadata["stored_gpu_id"]

            if dec_id in DEFAULT_GPU_DECODER.values():
                codec_name = get_codec_name_from_encoder_id(enc_id)
                requested_gpu_id = gpu_id if gpu_id != 0 else stored_gpu_id
                actual_gpu_id = validate_and_adjust_gpu_id(codec_name, requested_gpu_id)

                if actual_gpu_id < 0:
                    dec_id = DEFAULT_DECODER[enc_id]
                    actual_gpu_id = 0
                else:
                    dec_id = DEFAULT_GPU_DECODER[enc_id]

                # Log if we're using different GPU than stored
                if actual_gpu_id != stored_gpu_id:
                    logger.info(
                        f"GPU ID adjusted: stored={stored_gpu_id}, "
                        f"requested={requested_gpu_id}, using={actual_gpu_id}"
                    )
            else:
                actual_gpu_id = 0

            # Extract only the compressed data (skip metadata)
            data_offset = metadata["data_offset"]
            data = data[data_offset:]
            buf_size = len(data)

        # Build cd_values tuple (exactly 11 elements as expected by C function)
        cd_values = (
            enc_id,
            dec_id,
            width,
            height,
            depth,
            bit_mode,
            preset_id,
            tune_id,
            crf,
            film_grain,
            actual_gpu_id,  # Use validated GPU ID for actual operation
        )

        # Call C function
        return ffmpeg_native_c(flags, cd_values, buf_size, data)

    # Convenience functions
    def compress_native(data, **kwargs):
        """Compress data using native FFMPEG"""
        return ffmpeg_native(0, data, **kwargs)

    def decompress_native(compressed_data, **kwargs):
        """Decompress data using native FFMPEG"""
        return ffmpeg_native(1, compressed_data, **kwargs)

    NATIVE_AVAILABLE = True

except ImportError:

    def ffmpeg_native(*args, **kwargs):
        raise RuntimeError(
            "Native functions not available - C extension not compiled with native support"
        )

    def compress_native(*args, **kwargs):
        raise RuntimeError(
            "Native functions not available - C extension not compiled with native support"
        )

    def decompress_native(*args, **kwargs):
        raise RuntimeError(
            "Native functions not available - C extension not compiled with native support"
        )

    NATIVE_AVAILABLE = False
