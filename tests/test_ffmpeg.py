#!/usr/bin/env python3
"""
Test FFmpeg integration with Python.
"""
import os
import sys
import subprocess
import platform
import pytest

def get_ffmpeg_path():
    """Get the FFmpeg executable path based on platform."""
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ffmpeg_dir = os.path.join(root_dir, "ffmpeg_build")
    
    if platform.system() == "Windows":
        return os.path.join(ffmpeg_dir, "bin", "ffmpeg.exe")
    else:
        return os.path.join(ffmpeg_dir, "bin", "ffmpeg")

def set_library_path():
    """Set the appropriate library path for the current platform."""
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ffmpeg_dir = os.path.join(root_dir, "ffmpeg_build")
    lib_dir = os.path.join(ffmpeg_dir, "lib")
    
    if platform.system() == "Windows":
        # Add bin directory to PATH for Windows (DLLs are in bin)
        bin_dir = os.path.join(ffmpeg_dir, "bin")
        os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
    elif platform.system() == "Darwin":  # macOS
        # Set DYLD_LIBRARY_PATH for macOS
        os.environ["DYLD_LIBRARY_PATH"] = lib_dir + os.pathsep + os.environ.get("DYLD_LIBRARY_PATH", "")
    else:  # Linux
        # Set LD_LIBRARY_PATH for Linux
        os.environ["LD_LIBRARY_PATH"] = lib_dir + os.pathsep + os.environ.get("LD_LIBRARY_PATH", "")
    
    # Set PKG_CONFIG_PATH for all platforms
    os.environ["PKG_CONFIG_PATH"] = os.path.join(lib_dir, "pkgconfig") + os.pathsep + os.environ.get("PKG_CONFIG_PATH", "")

def test_ffmpeg_version():
    """Test that FFmpeg runs and returns version information."""
    ffmpeg_path = get_ffmpeg_path()
    set_library_path()
    
    try:
        result = subprocess.run([ffmpeg_path, "-version"], 
                               stdout=subprocess.PIPE, 
                               stderr=subprocess.PIPE,
                               text=True)
        
        assert result.returncode == 0, f"FFmpeg version command failed: {result.stderr}"
        assert "ffmpeg version" in result.stdout, "Expected version string not found"
        
        print(f"FFmpeg version: {result.stdout.splitlines()[0]}")
        return True
    except Exception as e:
        pytest.fail(f"Exception occurred: {e}")
        return False

def test_ffmpeg_codecs():
    """Test that FFmpeg supports the expected codecs."""
    ffmpeg_path = get_ffmpeg_path()
    set_library_path()
    
    try:
        result = subprocess.run([ffmpeg_path, "-encoders"], 
                               stdout=subprocess.PIPE, 
                               stderr=subprocess.PIPE,
                               text=True)
        
        assert result.returncode == 0, f"FFmpeg encoders command failed: {result.stderr}"
        
        encoders = result.stdout
        
        # Check for important codecs - at least one should be found
        important_codecs = ["264", "265", "av1", "vp9"]
        found_codecs = [codec for codec in important_codecs if codec in encoders]
        
        assert len(found_codecs) > 0, "No important codecs were found"
        
        for codec in found_codecs:
            print(f"Found codec: {codec}")
        
        return True
    except Exception as e:
        pytest.fail(f"Exception occurred: {e}")
        return False
