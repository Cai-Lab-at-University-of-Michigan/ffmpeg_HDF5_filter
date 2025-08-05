"""
GPU detection and validation utilities for FFMPEG HDF5 filter.
"""

import os
import subprocess
import logging

logger = logging.getLogger(__name__)

def has_nvidia_gpu():
    """
    Detect if NVIDIA GPU is available for hardware acceleration.

    Returns:
    --------
    bool
        True if NVIDIA GPU is available, False otherwise.
    """
    try:
        result = subprocess.run(
            ["nvidia-smi"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2
        )
        return result.returncode == 0
    except (subprocess.SubprocessError, FileNotFoundError):
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
        if os.name == "posix":
            result = subprocess.run(
                ["vainfo"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2
            )
            return result.returncode == 0 and b"VA-API version" in result.stdout
        elif os.name == "nt":
            result = subprocess.run(
                ["wmic", "path", "win32_VideoController", "get", "name"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=2,
            )
            return result.returncode == 0 and b"Intel" in result.stdout
        else:
            return False
    except (subprocess.SubprocessError, FileNotFoundError):
        return False

def detect_available_gpus():
    """
    Detect available GPUs and return GPU count for each type.
    
    Returns:
    --------
    dict
        Dictionary with "nvidia" and "intel" keys containing GPU counts
    """
    gpu_info = {"nvidia": 0, "intel": 0}
    
    # Check NVIDIA GPUs
    try:
        result = subprocess.run(
            ["nvidia-smi", "--list-gpus"], 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            timeout=2
        )
        if result.returncode == 0:
            gpu_lines = [line for line in result.stdout.decode().strip().split("\n") if line.strip()]
            gpu_info["nvidia"] = len(gpu_lines)
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
    
    # Check Intel GPUs
    if has_intel_gpu():
        gpu_info["intel"] = 1
    
    return gpu_info

def validate_and_adjust_gpu_id(codec, requested_gpu_id):
    """
    Validate GPU ID and adjust if necessary based on available hardware.
    
    Parameters:
    -----------
    codec : str
        The codec being used
    requested_gpu_id : int
        The requested GPU ID
        
    Returns:
    --------
    int
        Valid GPU ID to use, or -1 for CPU-only
    """
    if requested_gpu_id < 0:
        return -1  # CPU-only requested
    
    gpu_info = detect_available_gpus()
    
    # For NVIDIA codecs
    if "nvenc" in codec or "cuvid" in codec:
        if gpu_info["nvidia"] == 0:
            logger.warning(f"NVIDIA codec {codec} requested but no NVIDIA GPUs detected. Falling back to CPU.")
            return -1
        elif requested_gpu_id >= gpu_info["nvidia"]:
            adjusted_id = min(requested_gpu_id, gpu_info["nvidia"] - 1)
            logger.warning(f"GPU {requested_gpu_id} not available for {codec}. Using GPU {adjusted_id}.")
            return adjusted_id
    
    # For Intel QSV codecs
    elif "qsv" in codec:
        if gpu_info["intel"] == 0:
            logger.warning(f"Intel QSV codec {codec} requested but no Intel GPU detected. Falling back to CPU.")
            return -1
        # Intel QSV typically uses GPU 0
        return 0
    
    return requested_gpu_id