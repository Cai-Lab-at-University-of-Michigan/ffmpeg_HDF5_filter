"""
FFMPEG HDF5 filter - Python interface

This module provides a Python interface to the FFMPEG HDF5 filter,
allowing compression of HDF5 datasets using various video codecs.
"""

import os
import subprocess
import numpy as np
import h5py
import functools
import io
import sys
import contextlib
import logging

logger = logging.getLogger(__name__)

FFMPEG_ID = 32030

# Encoder codec IDs
class EncoderCodec:
    """Encoder codec identifiers for FFMPEG HDF5 filter"""
    MPEG4 = 0
    XVID = 1
    X264 = 2
    H264_NVENC = 3
    X265 = 4
    HEVC_NVENC = 5
    SVTAV1 = 6
    RAV1E = 7
    AV1_NVENC = 8
    AV1_QSV = 9

# Decoder codec IDs
class DecoderCodec:
    """Decoder codec identifiers for FFMPEG HDF5 filter"""
    MPEG4 = 0
    H264 = 1
    H264_CUVID = 2
    HEVC = 3
    HEVC_CUVID = 4
    AOMAV1 = 5
    DAV1D = 6
    AV1_CUVID = 7
    AV1_QSV = 8

# Preset IDs
class Preset:
    """Preset identifiers for FFMPEG HDF5 filter"""
    NONE = 0
    
    # libx264 presets
    X264_ULTRAFAST = 10
    X264_SUPERFAST = 11
    X264_VERYFAST = 12
    X264_FASTER = 13
    X264_FAST = 14
    X264_MEDIUM = 15
    X264_SLOW = 16
    X264_SLOWER = 17
    X264_VERYSLOW = 18
    
    # h264_nvenc presets
    H264NV_FASTEST = 100
    H264NV_FASTER = 101
    H264NV_FAST = 102
    H264NV_MEDIUM = 103
    H264NV_SLOW = 104
    H264NV_SLOWER = 105
    H264NV_SLOWEST = 106
    
    # x265 presets
    X265_ULTRAFAST = 200
    X265_SUPERFAST = 201
    X265_VERYFAST = 202
    X265_FASTER = 203
    X265_FAST = 204
    X265_MEDIUM = 205
    X265_SLOW = 206
    X265_SLOWER = 207
    X265_VERYSLOW = 208
    
    # hevc_nvenc presets
    HEVCNV_FASTEST = 300
    HEVCNV_FASTER = 301
    HEVCNV_FAST = 302
    HEVCNV_MEDIUM = 303
    HEVCNV_SLOW = 304
    HEVCNV_SLOWER = 305
    HEVCNV_SLOWEST = 306
    
    # svtav1 presets
    SVTAV1_ULTRAFAST = 400
    SVTAV1_SUPERFAST = 401
    SVTAV1_VERYFAST = 402
    SVTAV1_MUCHFASTER = 403
    SVTAV1_FASTER = 404
    SVTAV1_FAST = 405
    SVTAV1_LESSFAST = 406
    SVTAV1_MEDIUM = 407
    SVTAV1_LESSSLOW = 408
    SVTAV1_SLOW = 409
    SVTAV1_SLOWER = 410
    SVTAV1_MUCHSLOWER = 411
    SVTAV1_VERYSLOW = 412
    SVTAV1_SUPERSLOW = 413
    
    # rav1e presets
    RAV1E_MUCHFASTER = 500
    RAV1E_FASTER = 501
    RAV1E_FAST = 502
    RAV1E_LESSFAST = 503
    RAV1E_MEDIUM = 504
    RAV1E_LESSSLOW = 505
    RAV1E_SLOW = 506
    RAV1E_SLOWER = 507
    RAV1E_MUCHSLOWER = 508
    RAV1E_VERYSLOW = 509
    RAV1E_SUPERSLOW = 510
    
    # av1_nvenc presets
    AV1NV_FASTEST = 600
    AV1NV_FASTER = 601
    AV1NV_FAST = 602
    AV1NV_MEDIUM = 603
    AV1NV_SLOW = 604
    AV1NV_SLOWER = 605
    AV1NV_SLOWEST = 606
    
    # av1_qsv presets
    AV1QSV_FASTEST = 700
    AV1QSV_FASTER = 701
    AV1QSV_FAST = 702
    AV1QSV_MEDIUM = 703
    AV1QSV_SLOW = 704
    AV1QSV_SLOWER = 705
    AV1QSV_SLOWEST = 706

# Tune IDs
class Tune:
    """Tune identifiers for FFMPEG HDF5 filter"""
    NONE = 0
    
    # libx264 tunes
    X264_PSNR = 10
    X264_SSIM = 11
    X264_GRAIN = 12
    X264_FASTDECODE = 13
    X264_ZEROLATENCY = 14
    X264_ANIMATION = 15
    X264_FILM = 16
    X264_STILLIMAGE = 17
    
    # h264_nvenc tunes
    H264NV_HQ = 100
    H264NV_LL = 101
    H264NV_ULL = 102
    H264NV_LOSSLESS = 103
    
    # x265 tunes
    X265_PSNR = 200
    X265_SSIM = 201
    X265_GRAIN = 202
    X265_FASTDECODE = 203
    X265_ZEROLATENCY = 204
    X265_ANIMATION = 205
    
    # hevc_nvenc tunes
    HEVCNV_HQ = 300
    HEVCNV_LL = 301
    HEVCNV_ULL = 302
    HEVCNV_LOSSLESS = 303
    
    # svtav1 tunes
    SVTAV1_VQ = 400
    SVTAV1_PSNR = 401
    SVTAV1_FASTDECODE = 402
    
    # rav1e tunes
    RAV1E_PSNR = 500
    RAV1E_PSYCHOVISUAL = 501
    
    # av1_nvenc tunes
    AV1NV_HQ = 600
    AV1NV_LL = 601
    AV1NV_ULL = 602
    AV1NV_LOSSLESS = 603
    
    # av1_qsv tunes
    AV1QSV_UNKNOWN = 700
    AV1QSV_DISPLAYREMOTING = 701
    AV1QSV_VIDEOCONFERENCE = 702
    AV1QSV_ARCHIVE = 703
    AV1QSV_LIVESTREAMING = 704
    AV1QSV_CAMERACAPTURE = 705
    AV1QSV_VIDEOSURVEILLANCE = 706
    AV1QSV_GAMESTREAMING = 707
    AV1QSV_REMOTEGAMING = 708

# Bit modes
class BitMode:
    """Bit depth modes for FFMPEG HDF5 filter"""
    BIT_8 = 0
    BIT_10 = 1
    BIT_12 = 2

# Mapping of codec names to encoder IDs
CODEC_TO_ENCODER = {
    "mpeg4": EncoderCodec.MPEG4,
    "libxvid": EncoderCodec.XVID,
    "libx264": EncoderCodec.X264,
    "h264_nvenc": EncoderCodec.H264_NVENC,
    "libx265": EncoderCodec.X265,
    "hevc_nvenc": EncoderCodec.HEVC_NVENC,
    "libsvtav1": EncoderCodec.SVTAV1,
    "librav1e": EncoderCodec.RAV1E,
    "av1_nvenc": EncoderCodec.AV1_NVENC,
    "av1_qsv": EncoderCodec.AV1_QSV
}

# Mapping of codec names to decoder IDs
CODEC_TO_DECODER = {
    "mpeg4": DecoderCodec.MPEG4,
    "h264": DecoderCodec.H264,
    "h264_cuvid": DecoderCodec.H264_CUVID,
    "hevc": DecoderCodec.HEVC,
    "hevc_cuvid": DecoderCodec.HEVC_CUVID,
    "libaom-av1": DecoderCodec.AOMAV1,
    "libdav1d": DecoderCodec.DAV1D,
    "av1_cuvid": DecoderCodec.AV1_CUVID,
    "av1_qsv": DecoderCodec.AV1_QSV
}

# Mapping of preset names to preset IDs for each codec
PRESET_MAPPING = {
    "libx264": {
        "ultrafast": Preset.X264_ULTRAFAST,
        "superfast": Preset.X264_SUPERFAST,
        "veryfast": Preset.X264_VERYFAST,
        "faster": Preset.X264_FASTER,
        "fast": Preset.X264_FAST,
        "medium": Preset.X264_MEDIUM,
        "slow": Preset.X264_SLOW,
        "slower": Preset.X264_SLOWER,
        "veryslow": Preset.X264_VERYSLOW
    },
    "h264_nvenc": {
        "p1": Preset.H264NV_FASTEST,
        "p2": Preset.H264NV_FASTER,
        "p3": Preset.H264NV_FAST,
        "p4": Preset.H264NV_MEDIUM,
        "p5": Preset.H264NV_SLOW,
        "p6": Preset.H264NV_SLOWER,
        "p7": Preset.H264NV_SLOWEST
    },
    "libx265": {
        "ultrafast": Preset.X265_ULTRAFAST,
        "superfast": Preset.X265_SUPERFAST,
        "veryfast": Preset.X265_VERYFAST,
        "faster": Preset.X265_FASTER,
        "fast": Preset.X265_FAST,
        "medium": Preset.X265_MEDIUM,
        "slow": Preset.X265_SLOW,
        "slower": Preset.X265_SLOWER,
        "veryslow": Preset.X265_VERYSLOW
    },
    "hevc_nvenc": {
        "p1": Preset.HEVCNV_FASTEST,
        "p2": Preset.HEVCNV_FASTER,
        "p3": Preset.HEVCNV_FAST,
        "p4": Preset.HEVCNV_MEDIUM,
        "p5": Preset.HEVCNV_SLOW,
        "p6": Preset.HEVCNV_SLOWER,
        "p7": Preset.HEVCNV_SLOWEST
    },
    "libsvtav1": {
        "0": Preset.SVTAV1_ULTRAFAST,
        "1": Preset.SVTAV1_SUPERFAST,
        "2": Preset.SVTAV1_VERYFAST,
        "3": Preset.SVTAV1_MUCHFASTER,
        "4": Preset.SVTAV1_FASTER,
        "5": Preset.SVTAV1_FAST,
        "6": Preset.SVTAV1_LESSFAST,
        "7": Preset.SVTAV1_MEDIUM,
        "8": Preset.SVTAV1_LESSSLOW,
        "9": Preset.SVTAV1_SLOW,
        "10": Preset.SVTAV1_SLOWER,
        "11": Preset.SVTAV1_MUCHSLOWER,
        "12": Preset.SVTAV1_VERYSLOW,
        "13": Preset.SVTAV1_SUPERSLOW
    },
    "librav1e": {
        "0": Preset.RAV1E_MUCHFASTER,
        "1": Preset.RAV1E_FASTER,
        "2": Preset.RAV1E_FAST,
        "3": Preset.RAV1E_LESSFAST,
        "4": Preset.RAV1E_MEDIUM,
        "5": Preset.RAV1E_LESSSLOW,
        "6": Preset.RAV1E_SLOW,
        "7": Preset.RAV1E_SLOWER,
        "8": Preset.RAV1E_MUCHSLOWER,
        "9": Preset.RAV1E_VERYSLOW,
        "10": Preset.RAV1E_SUPERSLOW
    },
    "av1_nvenc": {
        "p1": Preset.AV1NV_FASTEST,
        "p2": Preset.AV1NV_FASTER,
        "p3": Preset.AV1NV_FAST,
        "p4": Preset.AV1NV_MEDIUM,
        "p5": Preset.AV1NV_SLOW,
        "p6": Preset.AV1NV_SLOWER,
        "p7": Preset.AV1NV_SLOWEST
    },
    "av1_qsv": {
        "veryfast": Preset.AV1QSV_FASTEST,
        "faster": Preset.AV1QSV_FASTER,
        "fast": Preset.AV1QSV_FAST,
        "medium": Preset.AV1QSV_MEDIUM,
        "slow": Preset.AV1QSV_SLOW,
        "slower": Preset.AV1QSV_SLOWER,
        "veryslow": Preset.AV1QSV_SLOWEST
    }
}

# Mapping of tune names to tune IDs for each codec
TUNE_MAPPING = {
    "libx264": {
        "psnr": Tune.X264_PSNR,
        "ssim": Tune.X264_SSIM,
        "grain": Tune.X264_GRAIN,
        "fastdecode": Tune.X264_FASTDECODE,
        "zerolatency": Tune.X264_ZEROLATENCY,
        "animation": Tune.X264_ANIMATION,
        "film": Tune.X264_FILM,
        "stillimage": Tune.X264_STILLIMAGE
    },
    "h264_nvenc": {
        "hq": Tune.H264NV_HQ,
        "ll": Tune.H264NV_LL,
        "ull": Tune.H264NV_ULL,
        "lossless": Tune.H264NV_LOSSLESS
    },
    "libx265": {
        "psnr": Tune.X265_PSNR,
        "ssim": Tune.X265_SSIM,
        "grain": Tune.X265_GRAIN,
        "fastdecode": Tune.X265_FASTDECODE,
        "zerolatency": Tune.X265_ZEROLATENCY,
        "animation": Tune.X265_ANIMATION
    },
    "hevc_nvenc": {
        "hq": Tune.HEVCNV_HQ,
        "ll": Tune.HEVCNV_LL,
        "ull": Tune.HEVCNV_ULL,
        "lossless": Tune.HEVCNV_LOSSLESS
    },
    "libsvtav1": {
        "vq": Tune.SVTAV1_VQ,
        "psnr": Tune.SVTAV1_PSNR,
        "fastdecode": Tune.SVTAV1_FASTDECODE
    },
    "librav1e": {
        "psnr": Tune.RAV1E_PSNR,
        "psychovisual": Tune.RAV1E_PSYCHOVISUAL
    },
    "av1_nvenc": {
        "hq": Tune.AV1NV_HQ,
        "ll": Tune.AV1NV_LL,
        "ull": Tune.AV1NV_ULL,
        "lossless": Tune.AV1NV_LOSSLESS
    },
    "av1_qsv": {
        "unknown": Tune.AV1QSV_UNKNOWN,
        "displayremoting": Tune.AV1QSV_DISPLAYREMOTING,
        "videoconference": Tune.AV1QSV_VIDEOCONFERENCE,
        "archive": Tune.AV1QSV_ARCHIVE,
        "livestreaming": Tune.AV1QSV_LIVESTREAMING,
        "cameracapture": Tune.AV1QSV_CAMERACAPTURE,
        "videosurveillance": Tune.AV1QSV_VIDEOSURVEILLANCE,
        "gamestreaming": Tune.AV1QSV_GAMESTREAMING,
        "remotegaming": Tune.AV1QSV_REMOTEGAMING
    }
}

# Default decoder mapping for encoders
DEFAULT_DECODER = {
    EncoderCodec.MPEG4: DecoderCodec.MPEG4,
    EncoderCodec.XVID: DecoderCodec.MPEG4,
    EncoderCodec.X264: DecoderCodec.H264,
    EncoderCodec.H264_NVENC: DecoderCodec.H264,
    EncoderCodec.X265: DecoderCodec.HEVC,
    EncoderCodec.HEVC_NVENC: DecoderCodec.HEVC,
    EncoderCodec.SVTAV1: DecoderCodec.AOMAV1,
    EncoderCodec.RAV1E: DecoderCodec.AOMAV1,
    EncoderCodec.AV1_NVENC: DecoderCodec.AOMAV1,
    EncoderCodec.AV1_QSV: DecoderCodec.AOMAV1
}

# Default decoder mapping for GPU-based encoders
DEFAULT_GPU_DECODER = {
    EncoderCodec.H264_NVENC: DecoderCodec.H264_CUVID,
    EncoderCodec.HEVC_NVENC: DecoderCodec.HEVC_CUVID,
    EncoderCodec.AV1_NVENC: DecoderCodec.AV1_CUVID,
    EncoderCodec.AV1_QSV: DecoderCodec.AV1_QSV
}

# Hardware detection functions
def has_nvidia_gpu():
    """
    Detect if NVIDIA GPU is available for hardware acceleration.
    
    Returns:
    --------
    bool
        True if NVIDIA GPU is available, False otherwise.
    """
    try:
        # Try to run nvidia-smi
        result = subprocess.run(
            ["nvidia-smi"], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            timeout=2
        )
        return result.returncode == 0
    except (subprocess.SubprocessError, FileNotFoundError):
        # Command failed or not found
        return False

def has_intel_gpu():
    """
    Detect if Intel GPU with QuickSync support is available.
    
    Returns:
    --------
    bool
        True if Intel GPU with QuickSync is available, False otherwise.
    """
    try:
        # Try to run vainfo (Linux) or check Intel GPU in Windows
        if os.name == 'posix':
            result = subprocess.run(
                ["vainfo"], 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE, 
                timeout=2
            )
            return result.returncode == 0 and b"VA-API version" in result.stdout
        elif os.name == 'nt':
            # On Windows, check for Intel GPU in device manager (simplified)
            result = subprocess.run(
                ["wmic", "path", "win32_VideoController", "get", "name"], 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE, 
                timeout=2
            )
            return result.returncode == 0 and b"Intel" in result.stdout
        else:
            return False
    except (subprocess.SubprocessError, FileNotFoundError):
        # Command failed or not found
        return False

class FFMPEG(h5py.filters.FilterRefBase):
    """
    FFMPEG HDF5 filter class for h5py
    
    This class implements the FFMPEG HDF5 filter interface for h5py,
    allowing compression of HDF5 datasets using video codecs.
    """
    filter_name = "ffmpeg"
    filter_id = FFMPEG_ID

    def __init__(self, enc_id, dec_id, depth, height, width, bit_mode, preset, tune, crf, film_grain, gpu_id):
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
            int(enc_id), int(dec_id), int(width), int(height), int(depth), 
            int(bit_mode), int(preset), int(tune), int(crf), int(film_grain), int(gpu_id)
        )

def ffmpeg(codec="libx264", decoder=None, preset=None, tune=None, crf=None, 
           bit_mode=BitMode.BIT_8, film_grain=0, gpu_id=0, width=None, height=None, depth=None, **kwargs):
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
        raise ValueError(f"Unknown codec: {codec}. Available codecs: {', '.join(CODEC_TO_ENCODER.keys())}")
    
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
            raise ValueError(f"Unknown decoder: {decoder}. Available decoders: {', '.join(CODEC_TO_DECODER.keys())}")
        dec_id = CODEC_TO_DECODER[decoder]
    
    # Get preset ID
    preset_id = Preset.NONE
    if preset is not None:
        if codec in PRESET_MAPPING and preset in PRESET_MAPPING[codec]:
            preset_id = PRESET_MAPPING[codec][preset]
        else:
            valid_presets = list(PRESET_MAPPING.get(codec, {}).keys())
            raise ValueError(f"Invalid preset '{preset}' for codec '{codec}'. Valid presets: {', '.join(valid_presets)}")
    
    # Get tune ID
    tune_id = Tune.NONE
    if tune is not None:
        if codec in TUNE_MAPPING and tune in TUNE_MAPPING[codec]:
            tune_id = TUNE_MAPPING[codec][tune]
        else:
            valid_tunes = list(TUNE_MAPPING.get(codec, {}).keys())
            raise ValueError(f"Invalid tune '{tune}' for codec '{codec}'. Valid tunes: {', '.join(valid_tunes)}")
    
    # Check for hardware acceleration conflicts
    if gpu_id >= 0:
        # For NVIDIA encoders, check if NVIDIA GPU is available
        if "nvenc" in codec and not has_nvidia_gpu():
            logger.error(f"{codec} requested but NVIDIA GPU not detected. Continuing anyway, but may fail.")
        
        # For Intel QSV encoders, check if Intel GPU is available
        if "qsv" in codec and not has_intel_gpu():
            logger.error(f"{codec} requested but Intel GPU not detected. Continuing anyway, but may fail.")
    
    # Pack all parameters into the filter options
    filter_options = (enc_id, dec_id, width or 0, height or 0, depth or 0, 
                     bit_mode, preset_id, tune_id, crf or 0, film_grain, gpu_id)
    
    return {
        'compression': FFMPEG_ID,
        'compression_opts': filter_options
    }


# Convenience functions for specific codecs
def mpeg4(crf=3, tune=None, **kwargs):
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

def svtav1(preset="6", crf=30, tune=None, **kwargs):
    """Convenience function for AV1 compression"""
    return ffmpeg(codec="libsvtav1", preset=preset, crf=crf, tune=tune, **kwargs)

def h264_nvenc(preset="p4", qp=23, **kwargs):
    """Convenience function for NVIDIA H.264 hardware compression"""
    gpu_id = kwargs.pop("gpu_id", 0)  # Default to first GPU
    return ffmpeg(codec="h264_nvenc", preset=preset, crf=0, gpu_id=gpu_id, **kwargs)

def hevc_nvenc(preset="p4", qp=23, **kwargs):
    """Convenience function for NVIDIA H.265/HEVC hardware compression"""
    gpu_id = kwargs.pop("gpu_id", 0)  # Default to first GPU
    return ffmpeg(codec="hevc_nvenc", preset=preset, crf=0, gpu_id=gpu_id, **kwargs)

def av1_nvenc(preset="p4", qp=23, **kwargs):
    """Convenience function for NVIDIA H.265/HEVC hardware compression"""
    gpu_id = kwargs.pop("gpu_id", 0)  # Default to first GPU
    return ffmpeg(codec="av1_nvenc", preset=preset, crf=0, gpu_id=gpu_id, **kwargs)

def av1_qsv(preset="medium", crf=30, tune=None, **kwargs):
    """Convenience function for Intel AV1 QSV hardware compression"""
    return ffmpeg(codec="av1_qsv", preset=preset, crf=crf, tune=tune, **kwargs)