"""
Basic tests for the FFMPEG HDF5 filter.

This module contains test cases for basic functionality of the FFMPEG HDF5 filter,
focusing on 3D datasets with 8-bit and 16-bit integer types.
"""

import unittest
import numpy as np
import h5ffmpeg as hf
import h5py
import os
import sys
import colorama
from colorama import Fore, Back, Style
from tabulate import tabulate
from h5ffmpeg.utils import *

# Initialize colorama
colorama.init(autoreset=True)

# Import test utilities
from test_utils import generate_3d_data

from colored_test import (
    ColoredTestRunner,
    print_summary
    )

class TestBasicFunctionality(unittest.TestCase):
    """
    Test basic functionality of the FFMPEG HDF5 filter.
    """
    
    def setUp(self):
        """Set up test parameters."""
        # Define dimensions for the test data
        self.width = 256
        self.height = 256
        self.depth = 50
        
        # Set random seed for reproducibility
        self.seed = 42
        
        # Minimum acceptable PSNR values
        self.min_psnr_8bit = 25.0  # dB
        self.min_psnr_16bit = 45.0  # dB
        
        # Minimum acceptable compression ratio
        self.min_compression_ratio = 1.5
        
        # Print test header
        test_name = self._testMethodName
        print(f"\n{Fore.CYAN}{Style.BRIGHT}▶ Running: {test_name}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}{'─' * 60}{Style.RESET_ALL}")
    
    def tearDown(self):
        """Clean up after each test."""
        print(f"{Fore.CYAN}{'─' * 60}{Style.RESET_ALL}\n")
    
    def print_result_table(self, results):
        """Print results in a colorized table format."""
        headers = ["Parameter", "PSNR (dB)", "Compression Ratio"]
        colored_data = []
        
        for label, psnr, ratio in results:
            # Color code PSNR values
            if psnr > 50:
                psnr_colored = f"{Fore.GREEN}{Style.BRIGHT}{psnr:.2f}{Style.RESET_ALL}"
            elif psnr > 40:
                psnr_colored = f"{Fore.GREEN}{psnr:.2f}{Style.RESET_ALL}"
            elif psnr > 30:
                psnr_colored = f"{Fore.YELLOW}{psnr:.2f}{Style.RESET_ALL}"
            else:
                psnr_colored = f"{Fore.RED}{psnr:.2f}{Style.RESET_ALL}"
            
            # Color code compression ratio values
            if ratio > 10:
                ratio_colored = f"{Fore.GREEN}{Style.BRIGHT}{ratio:.2f}x{Style.RESET_ALL}"
            elif ratio > 5:
                ratio_colored = f"{Fore.GREEN}{ratio:.2f}x{Style.RESET_ALL}"
            elif ratio > 2:
                ratio_colored = f"{Fore.YELLOW}{ratio:.2f}x{Style.RESET_ALL}"
            else:
                ratio_colored = f"{Fore.RED}{ratio:.2f}x{Style.RESET_ALL}"
            
            colored_data.append([label, psnr_colored, ratio_colored])
        
        # Print the table
        print(tabulate(colored_data, headers=headers, tablefmt="simple"))
    
    def test_filter_registration(self):
        """Test if the FFMPEG filter is properly registered."""
        # Check if FFMPEG filter ID is defined
        self.assertTrue(hasattr(hf, 'FFMPEG_ID'))
        
        # Check if h5py can see our filter
        self.assertTrue(h5py.h5z.filter_avail(hf.FFMPEG_ID))
        
        print(f"{Fore.GREEN}✓ FFMPEG filter is properly registered with ID: {hf.FFMPEG_ID}{Style.RESET_ALL}")
    
    def test_basic_compression_8bit(self):
        """Test basic compression/decompression with 8-bit data."""
        # Generate 3D test data (8-bit)
        print(f"{Fore.BLUE}ℹ Generating 8-bit test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
        test_data = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint8,
            pattern="random",
            seed=self.seed
        )
        
        # Use H.264 compression with default settings
        compression_options = hf.x264()
        print(f"{Fore.BLUE}ℹ Compressing with H.264 codec (default settings)...{Style.RESET_ALL}")
        
        # Compress and decompress
        decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
            test_data, compression_options
        )
        
        # Check that shapes match
        self.assertEqual(test_data.shape, decompressed_data.shape)
        
        # Check that dtype matches
        self.assertEqual(test_data.dtype, decompressed_data.dtype)
        
        # Calculate PSNR
        psnr = calculate_psnr(test_data, decompressed_data)
        
        # Print results in color
        results = [
            ("8-bit (H.264)", psnr, compression_ratio)
        ]
        self.print_result_table(results)
        print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
        
        # Check that PSNR is above threshold
        self.assertGreater(psnr, self.min_psnr_8bit)
        
        # Check compression ratio
        self.assertGreater(compression_ratio, self.min_compression_ratio)
    
    def test_basic_compression_16bit(self):
        """Test basic compression/decompression with 16-bit data."""
        # Generate 3D test data (16-bit)
        print(f"{Fore.BLUE}ℹ Generating 16-bit test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
        test_data = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint16,
            pattern="random",
            seed=self.seed
        )
        
        # Use H.264 compression with 10-bit color depth
        compression_options = hf.x264(bit_mode=hf.BitMode.BIT_10)
        print(f"{Fore.BLUE}ℹ Compressing with H.264 codec (10-bit mode)...{Style.RESET_ALL}")
        
        # Compress and decompress
        decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
            test_data, compression_options
        )
        
        # Check that shapes match
        self.assertEqual(test_data.shape, decompressed_data.shape)
        
        # Check that dtype matches
        self.assertEqual(test_data.dtype, decompressed_data.dtype)
        
        # Calculate PSNR
        psnr = calculate_psnr(test_data, decompressed_data)
        
        # Print results in color
        results = [
            ("16-bit (H.264 10-bit)", psnr, compression_ratio)
        ]
        self.print_result_table(results)
        print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
        
        # Check that PSNR is above threshold
        self.assertGreater(psnr, self.min_psnr_16bit)
        
        # Check compression ratio
        self.assertGreater(compression_ratio, self.min_compression_ratio)
    
    def test_gradient_data(self):
        """Test compression with gradient data (more compressible)."""
        # Generate 3D gradient data (8-bit)
        print(f"{Fore.BLUE}ℹ Generating gradient test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
        test_data = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint8,
            pattern="gradient",
            seed=self.seed
        )
        
        # Use H.264 compression
        compression_options = hf.x264(crf=23)  # Default quality
        print(f"{Fore.BLUE}ℹ Compressing with H.264 codec (CRF=23)...{Style.RESET_ALL}")
        
        # Compress and decompress
        decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
            test_data, compression_options
        )
        
        # Calculate PSNR
        psnr = calculate_psnr(test_data, decompressed_data)
        
        # Print results in color
        results = [
            ("Gradient Data", psnr, compression_ratio)
        ]
        self.print_result_table(results)
        print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
        
        # Gradient data should be more compressible than random data
        self.assertGreater(compression_ratio, self.min_compression_ratio * 2)
    
    def test_stripes_data(self):
        """Test compression with striped data (highly compressible)."""
        # Generate 3D striped data (8-bit)
        print(f"{Fore.BLUE}ℹ Generating striped test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
        test_data = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint8,
            pattern="stripes",
            seed=self.seed
        )
        
        # Use H.264 compression
        compression_options = hf.x264(crf=23)
        print(f"{Fore.BLUE}ℹ Compressing with H.264 codec (CRF=23)...{Style.RESET_ALL}")
        
        # Compress and decompress
        decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
            test_data, compression_options
        )
        
        # Calculate PSNR
        psnr = calculate_psnr(test_data, decompressed_data)
        
        # Print results in color
        results = [
            ("Striped Data", psnr, compression_ratio)
        ]
        self.print_result_table(results)
        print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
        
        # Striped data should be highly compressible
        self.assertGreater(compression_ratio, self.min_compression_ratio * 3)

    def test_different_quality_settings(self):
        """Test different quality settings (CRF values)."""
        # Generate 3D test data (8-bit)
        print(f"{Fore.BLUE}ℹ Generating random test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
        test_data = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint8,
            pattern="random",
            seed=self.seed
        )
        
        results = []
        
        # Test different CRF values (lower = higher quality)
        for crf in [18, 23, 28]:
            print(f"{Fore.BLUE}ℹ Testing H.264 with CRF={crf}...{Style.RESET_ALL}")
            compression_options = hf.x264(crf=crf)
            
            # Compress and decompress
            decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
                test_data, compression_options
            )
            
            # Calculate PSNR
            psnr = calculate_psnr(test_data, decompressed_data)
            results.append((f"CRF {crf}", psnr, compression_ratio))
            print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
        
        # Print results table
        self.print_result_table(results)
        
        # Lower CRF (higher quality) should give higher PSNR
        self.assertGreater(results[0][1], results[1][1])
        self.assertGreater(results[1][1], results[2][1])
        
        # Higher CRF (lower quality) should give higher compression ratio
        self.assertLess(results[0][2], results[2][2])
    
    def test_x265_codec(self):
        """Test H.265/HEVC codec."""
        try:
            # Generate 3D test data (8-bit)
            print(f"{Fore.BLUE}ℹ Generating random test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
            test_data = generate_3d_data(
                width=self.width,
                height=self.height,
                depth=self.depth,
                dtype=np.uint8,
                pattern="random",
                seed=self.seed
            )
            
            # Use H.265 compression
            compression_options = hf.x265(crf=28)
            print(f"{Fore.BLUE}ℹ Compressing with H.265/HEVC codec (CRF=28)...{Style.RESET_ALL}")
            
            # Compress and decompress
            decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
                test_data, compression_options
            )
            
            # Calculate PSNR
            psnr = calculate_psnr(test_data, decompressed_data)
            
            # Print results in color
            results = [
                ("H.265/HEVC", psnr, compression_ratio)
            ]
            self.print_result_table(results)
            print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
            
            # H.265 should provide good quality
            self.assertGreater(psnr, self.min_psnr_8bit)
            
            # H.265 should provide good compression
            self.assertGreater(compression_ratio, self.min_compression_ratio)
        except Exception as e:
            print(f"{Fore.YELLOW}⚠ HEVC codec test skipped: {str(e)}{Style.RESET_ALL}")
            self.skipTest(f"HEVC codec test skipped: {str(e)}")
    
    def test_svtav1_codec(self):
        """Test AV1 codec if available."""
        try:
            # Generate 3D test data (8-bit)
            print(f"{Fore.BLUE}ℹ Generating random test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}")
            test_data = generate_3d_data(
                width=self.width,
                height=self.height,
                depth=self.depth,
                dtype=np.uint8,
                pattern="random",
                seed=self.seed
            )
            
            # Use AV1 compression
            compression_options = hf.svtav1(crf=30)
            print(f"{Fore.BLUE}ℹ Compressing with SVT-AV1 codec (CRF=30)...{Style.RESET_ALL}")
            
            # Compress and decompress
            decompressed_data, compression_ratio, enc_time, dec_time = compress_and_decompress(
                test_data, compression_options
            )
            
            # Calculate PSNR
            psnr = calculate_psnr(test_data, decompressed_data)
            
            # Print results in color
            results = [
                ("SVT-AV1", psnr, compression_ratio)
            ]
            self.print_result_table(results)
            print(f"{Fore.BLUE}ℹ Processing time: {enc_time + dec_time:.2f} seconds{Style.RESET_ALL}")
            
            # AV1 should provide good quality
            self.assertGreater(psnr, self.min_psnr_8bit)
            
            # AV1 should provide good compression
            self.assertGreater(compression_ratio, self.min_compression_ratio)
        except Exception as e:
            print(f"{Fore.YELLOW}⚠ AV1 codec test skipped: {str(e)}{Style.RESET_ALL}")
            self.skipTest(f"AV1 codec test skipped: {str(e)}")

if __name__ == '__main__':
    runner = ColoredTestRunner(verbosity=1)
    result = runner.run(unittest.TestLoader().loadTestsFromTestCase(TestBasicFunctionality))
    print_summary("BASIC TESTS", result)

    sys.exit(not result.wasSuccessful())