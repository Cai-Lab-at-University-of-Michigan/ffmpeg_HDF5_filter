"""
Test utilities for the FFMPEG HDF5 filter tests.

This module provides utility functions for generating 3D test data and 
evaluating compression results for the FFMPEG HDF5 filter.
"""

import os
import numpy as np
import h5py

from h5ffmpeg.utils import *


def generate_3d_data(width=512, height=512, depth=100, dtype=np.uint8, pattern="random", seed=None):
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


def test_codec_availability():
    """
    Test availability of each codec by attempting to use it for compression.
    
    Returns:
    --------
    dict
        Dictionary with codec names as keys and dictionaries containing:
        - 'available': Boolean indicating if codec is functional
        - 'error': Error message if any
        - 'compression_ratio': Compression ratio if successful
        - 'psnr': PSNR value if successful
    """
    # Import the codec convenience functions
    import h5ffmpeg as hf
    
    # Generate a small test dataset
    test_data = generate_3d_data(width=164, height=164, depth=32, pattern="gradient")
    
    # List of codec functions to test
    codec_functions = {
        "mpeg4": hf.mpeg4,
        "x264": hf.x264,
        "x265": hf.x265,
        "rav1e": hf.rav1e,
        "svtav1": hf.svtav1,
        "h264_nvenc": hf.h264_nvenc,
        "hevc_nvenc": hf.hevc_nvenc,
        "av1_nvenc": hf.av1_nvenc,
        "av1_qsv": hf.av1_qsv
    }
    
    results = {}
    
    # Test each codec
    for codec_name, codec_func in codec_functions.items():
        print(f"Testing {codec_name}...")
        results[codec_name] = {
            'available': False,
            'error': None,
            'compression_ratio': None,
            'psnr': None
        }
        
        try:
            # Get compression options using the convenience function
            compression_options = codec_func()
            
            # Try to compress and decompress using the codec
            decompressed_data, compression_ratio, _, _ = compress_and_decompress(
                test_data, compression_options
            )
            
            # Calculate PSNR
            psnr = calculate_psnr(test_data, decompressed_data)

            if compression_ratio > 1:
                # Update results
                results[codec_name]['available'] = True
                results[codec_name]['compression_ratio'] = compression_ratio
                results[codec_name]['psnr'] = psnr
            else:
                results[codec_name]['available'] = False
                results[codec_name]['compression_ratio'] = 'n/a'
                results[codec_name]['psnr'] = 'n/a'
                results[codec_name]['error'] = 'See console above'
            
        except Exception as e:
            # Capture the error message
            results[codec_name]['error'] = str(e)
    
    return results


def get_available_codecs():
    """
    Get a list of available codecs.
    
    Returns:
    --------
    dict
        Dictionary with codec names as keys and boolean availability as values
    """
    # Test all codecs
    test_results = test_codec_availability()
    
    # Extract just the availability information
    return {codec: results['available'] for codec, results in test_results.items()}

def print_codec_availability():
    """
    Print a formatted report of codec availability with color highlighting,
    centered in the terminal window.
    
    This is useful for diagnostic purposes and understanding
    which codecs are available on the current system.
    """
    import colorama
    from colorama import Fore, Back, Style
    import shutil  # For getting terminal size
    
    # Initialize colorama for cross-platform color support
    colorama.init(autoreset=True)
    
    results = test_codec_availability()
    
    # Define constant widths
    TOTAL_WIDTH = 65  # Width of the report content
    CODEC_COL = 15
    AVAIL_COL = 11
    DESC_COL = 35
    
    # Get terminal width
    terminal_width, _ = shutil.get_terminal_size()
    
    # Calculate padding to center the report
    left_padding = max(0, (terminal_width - TOTAL_WIDTH) // 2)
    padding = ' ' * left_padding
    
    # Helper function to ensure blue borders with colored content
    def blue_border_line(content, width=TOTAL_WIDTH):
        return f"{padding}{Style.BRIGHT}{Fore.BLUE}║{Style.RESET_ALL}{content}{Style.BRIGHT}{Fore.BLUE}║{Style.RESET_ALL}"
    
    # Top border
    print(f"\n{padding}{Style.BRIGHT}{Fore.BLUE}╔{'═' * (TOTAL_WIDTH - 2)}╗{Style.RESET_ALL}")
    
    # Title
    title = "Codec Availability Report"
    title_padding = (TOTAL_WIDTH - len(title) - 2) // 2
    title_line = f"{' ' * title_padding}{title}{' ' * (TOTAL_WIDTH - len(title) - title_padding - 2)}"
    print(blue_border_line(title_line))
    
    # Headers
    print(f"{padding}{Style.BRIGHT}{Fore.BLUE}╠{'═' * CODEC_COL}╦{'═' * AVAIL_COL}╦{'═' * DESC_COL}╣{Style.RESET_ALL}")
    header_line = f" {'Codec':<{CODEC_COL-2}} {Style.BRIGHT}{Fore.BLUE}║{Style.RESET_ALL} {'Available':<{AVAIL_COL-2}} {Style.BRIGHT}{Fore.BLUE}║{Style.RESET_ALL} {'Description':<{DESC_COL-2}} "
    print(blue_border_line(header_line))
    print(f"{padding}{Style.BRIGHT}{Fore.BLUE}╠{'═' * CODEC_COL}╬{'═' * AVAIL_COL}╬{'═' * DESC_COL}╣{Style.RESET_ALL}")
    
    # Codec descriptions
    codec_descriptions = {
        "mpeg4": "MPEG-4 Part 2 visual codec (legacy)",
        "x264": "H.264/AVC, high compatibility & efficiency",
        "x265": "H.265/HEVC, better compression than H.264",
        "svtav1": "AV1 codec, best compression, royalty-free",
        "rav1e": "AV1 codec, open-source",
        "h264_nvenc": "NVIDIA GPU accelerated H.264 encoding",
        "hevc_nvenc": "NVIDIA GPU accelerated H.265 encoding",
        "av1_nvenc": "NVIDIA GPU accelerated AV1 encoding",
        "h264_qsv": "Intel QuickSync H.264 hardware encoding",
        "hevc_qsv": "Intel QuickSync H.265 hardware encoding",
        "av1_qsv": "Intel QuickSync AV1 hardware encoding",
        "av1": "Generic AV1 implementation, newer standard"
    }
    
    # Data rows
    for codec, result in results.items():
        available = result['available']
        
        # Get description instead of error
        description = codec_descriptions.get(codec, "General purpose video codec")
        if len(description) > DESC_COL - 2:
            description = description[:DESC_COL - 5] + "..."
        
        # Color coding: green for available, red for unavailable
        status_color = Fore.GREEN if available else Fore.RED
        status_text = "✓ Yes" if available else "✗ No"
        
        # Use white for description text
        desc_color = Fore.WHITE
        
        row_content = f" {Fore.CYAN}{codec:<{CODEC_COL-2}}{Style.RESET_ALL} {Style.BRIGHT}{Fore.BLUE}║{Style.RESET_ALL} {status_color}{status_text:<{AVAIL_COL-2}}{Style.RESET_ALL} {Style.BRIGHT}{Fore.BLUE}║{Style.RESET_ALL} {desc_color}{description:<{DESC_COL-2}}{Style.RESET_ALL} "
        print(blue_border_line(row_content))
    
    # Separator
    print(f"{padding}{Style.BRIGHT}{Fore.BLUE}╠{'═' * CODEC_COL}╩{'═' * AVAIL_COL}╩{'═' * DESC_COL}╣{Style.RESET_ALL}")
    
    # Available codecs section
    available_codecs = [codec for codec, result in results.items() if result['available']]
    
    if available_codecs:
        # Header for available codecs
        available_header = f" {Fore.GREEN}Available codecs:{' ' * (TOTAL_WIDTH - 20)}"
        print(blue_border_line(available_header))
        
        # Available codecs list
        codec_list = ", ".join(available_codecs)
        
        # Handle multi-line display if needed
        if len(codec_list) > TOTAL_WIDTH - 4:
            # Calculate how to split into multiple lines
            max_line_length = TOTAL_WIDTH - 4
            words = codec_list.split(", ")
            lines = []
            current_line = ""
            
            for word in words:
                if len(current_line) + len(word) + (2 if current_line else 0) <= max_line_length:
                    if current_line:
                        current_line += ", " + word
                    else:
                        current_line = word
                else:
                    lines.append(current_line)
                    current_line = word
            
            if current_line:
                lines.append(current_line)
            
            # Print each line
            for i, line in enumerate(lines):
                prefix = "  " if i > 0 else " "
                codec_line = f"{prefix}{Fore.GREEN}{line}{' ' * (TOTAL_WIDTH - len(line) - len(prefix) - 1)}"
                print(blue_border_line(codec_line))
        else:
            # Single line display
            codec_line = f" {Fore.GREEN}{codec_list}{' ' * (TOTAL_WIDTH - len(codec_list) - 3)}"
            print(blue_border_line(codec_line))
    else:
        # No codecs available
        no_codecs_line = f" {Fore.RED}No codecs available!{' ' * (TOTAL_WIDTH - 21)}"
        print(blue_border_line(no_codecs_line))
    
    # Bottom border
    print(f"{padding}{Style.BRIGHT}{Fore.BLUE}╚{'═' * (TOTAL_WIDTH - 2)}╝{Style.RESET_ALL}")
    
    # Reset colorama settings
    colorama.deinit()

if __name__ == '__main__':
    print_codec_availability()
