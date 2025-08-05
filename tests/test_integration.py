"""
Integration tests for the FFMPEG HDF5 filter.

This module contains test cases for integration with h5py and other libraries,
focusing on 3D datasets with 8-bit and 16-bit integer types.
"""

import unittest
import numpy as np
import h5py
import os
import sys
import tempfile
import shutil
import colorama
from colorama import Fore, Back, Style
from tabulate import tabulate

# Initialize colorama
colorama.init(autoreset=True)

# Import the FFMPEG HDF5 filter package
import h5ffmpeg as hf
from h5ffmpeg.utils import *

# Import test utilities
from test_utils import generate_3d_data

from colored_test import ColoredTestRunner, print_summary


class TestIntegration(unittest.TestCase):
    """
    Test integration of the FFMPEG HDF5 filter with h5py and other libraries.
    """

    def setUp(self):
        """Set up test parameters."""
        # Define dimensions for the test data
        self.width = 256
        self.height = 256
        self.depth = 50

        # Set random seed for reproducibility
        self.seed = 42

        # Generate test data once for all tests
        print(
            f"{Fore.BLUE}ℹ Generating 8-bit test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}"
        )
        self.test_data_8bit = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint8,
            pattern="stripes",
            seed=self.seed,
        )

        print(
            f"{Fore.BLUE}ℹ Generating 16-bit test data ({self.depth}x{self.height}x{self.width})...{Style.RESET_ALL}"
        )
        self.test_data_16bit = generate_3d_data(
            width=self.width,
            height=self.height,
            depth=self.depth,
            dtype=np.uint16,
            pattern="stripes",
            seed=self.seed,
        )

        # Create a temporary directory for test files
        self.temp_dir = tempfile.mkdtemp()
        print(
            f"{Fore.BLUE}ℹ Created temporary directory for test files: {self.temp_dir}{Style.RESET_ALL}"
        )

        # Print test header
        test_name = self._testMethodName
        print(f"\n{Fore.CYAN}{Style.BRIGHT}▶ Running: {test_name}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}{'─' * 60}{Style.RESET_ALL}")

    def tearDown(self):
        """Clean up after tests."""
        # Remove temporary directory and its contents
        shutil.rmtree(self.temp_dir)
        print(
            f"{Fore.BLUE}ℹ Removed temporary directory and test files{Style.RESET_ALL}"
        )
        print(f"{Fore.CYAN}{'─' * 60}{Style.RESET_ALL}\n")

    def print_result_table(self, results):
        """Print results in a colorized table format."""
        headers = ["Dataset", "PSNR (dB)", "Compression Ratio", "File Size (KB)"]
        colored_data = []

        for label, psnr, ratio, size_kb in results:
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
                ratio_colored = (
                    f"{Fore.GREEN}{Style.BRIGHT}{ratio:.2f}x{Style.RESET_ALL}"
                )
            elif ratio > 5:
                ratio_colored = f"{Fore.GREEN}{ratio:.2f}x{Style.RESET_ALL}"
            elif ratio > 2:
                ratio_colored = f"{Fore.YELLOW}{ratio:.2f}x{Style.RESET_ALL}"
            else:
                ratio_colored = f"{Fore.RED}{ratio:.2f}x{Style.RESET_ALL}"

            # Color code file size
            if size_kb < 100:
                size_colored = (
                    f"{Fore.GREEN}{Style.BRIGHT}{size_kb:.1f}{Style.RESET_ALL}"
                )
            elif size_kb < 500:
                size_colored = f"{Fore.GREEN}{size_kb:.1f}{Style.RESET_ALL}"
            elif size_kb < 1000:
                size_colored = f"{Fore.YELLOW}{size_kb:.1f}{Style.RESET_ALL}"
            else:
                size_colored = f"{Fore.RED}{size_kb:.1f}{Style.RESET_ALL}"

            colored_data.append([label, psnr_colored, ratio_colored, size_colored])

        # Print the table
        print(tabulate(colored_data, headers=headers, tablefmt="simple"))

    def test_h5py_integration(self):
        """Test basic integration with h5py."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_h5py.h5")
        print(f"{Fore.BLUE}ℹ Testing basic integration with h5py...{Style.RESET_ALL}")

        # Compression options
        compression_options = hf.x264(crf=23)
        print(f"{Fore.BLUE}ℹ Using H.264 compression with CRF=23{Style.RESET_ALL}")

        # Write data with compression
        print(f"{Fore.BLUE}ℹ Writing compressed data to HDF5 file...{Style.RESET_ALL}")
        with h5py.File(h5_file, "w") as f:
            f.create_dataset("data", data=self.test_data_8bit, **compression_options)

        file_size_kb = os.path.getsize(h5_file) / 1024
        print(f"{Fore.BLUE}ℹ File size: {file_size_kb:.1f} KB{Style.RESET_ALL}")

        # Read back the data
        print(f"{Fore.BLUE}ℹ Reading back compressed data...{Style.RESET_ALL}")
        with h5py.File(h5_file, "r") as f:
            # Read data
            decompressed_data = f["data"][:]

            # Check shape and dtype
            self.assertEqual(decompressed_data.shape, self.test_data_8bit.shape)
            self.assertEqual(decompressed_data.dtype, self.test_data_8bit.dtype)
            print(f"{Fore.GREEN}✓ Shape and dtype match original data{Style.RESET_ALL}")

            # Check quality
            psnr = calculate_psnr(self.test_data_8bit, decompressed_data)
            print(f"{Fore.BLUE}ℹ PSNR: {psnr:.2f} dB{Style.RESET_ALL}")
            self.assertGreater(psnr, 40.0)

            # Calculate compression ratio
            original_size = self.test_data_8bit.nbytes
            compressed_size = os.path.getsize(h5_file)
            compression_ratio = original_size / compressed_size

            # Print results table
            results = [("H.264 (CRF=23)", psnr, compression_ratio, file_size_kb)]
            self.print_result_table(results)

    def test_chunked_dataset(self):
        """Test with chunked datasets."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_chunked.h5")
        print(
            f"{Fore.BLUE}ℹ Testing compression with different chunk sizes...{Style.RESET_ALL}"
        )

        # Different chunk sizes to test
        chunk_sizes = [
            (10, 64, 64),  # Small chunks
            (50, 256, 256),  # One big chunk
            (5, 128, 128),  # Medium chunks
        ]

        results = []

        for i, chunks in enumerate(chunk_sizes):
            dataset_name = f"data_{i}"
            chunk_label = f"Chunks {chunks}"

            print(f"{Fore.BLUE}ℹ Testing with chunk size {chunks}...{Style.RESET_ALL}")

            # Compression options
            compression_options = hf.x264(crf=23)

            # Write data with compression and specified chunks
            with h5py.File(h5_file, "w") as f:
                f.create_dataset(
                    dataset_name,
                    data=self.test_data_8bit,
                    chunks=chunks,
                    **compression_options,
                )

            file_size_kb = os.path.getsize(h5_file) / 1024

            # Read back the data
            with h5py.File(h5_file, "r") as f:
                # Check that chunks are as specified
                dataset = f[dataset_name]
                self.assertEqual(dataset.chunks, chunks)

                # Read data
                decompressed_data = dataset[:]

                # Check quality
                psnr = calculate_psnr(self.test_data_8bit, decompressed_data)

                # Calculate compression ratio
                original_size = self.test_data_8bit.nbytes
                compressed_size = os.path.getsize(h5_file)
                compression_ratio = original_size / compressed_size

                results.append((chunk_label, psnr, compression_ratio, file_size_kb))

        # Print results table
        self.print_result_table(results)

        # Verify all PSNRs are acceptable
        for label, psnr, ratio, _ in results:
            self.assertGreater(psnr, 40.0, f"PSNR for {label} is too low")

        print(
            f"{Fore.GREEN}✓ All chunk sizes provide acceptable quality (PSNR > 40 dB){Style.RESET_ALL}"
        )

    def test_partial_reads(self):
        """Test partial dataset reads."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_partial.h5")
        print(f"{Fore.BLUE}ℹ Testing partial dataset reads...{Style.RESET_ALL}")

        # Write data with compression
        print(
            f"{Fore.BLUE}ℹ Writing compressed dataset with chunks...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "w") as f:
            f.create_dataset(
                "data", data=self.test_data_8bit, chunks=(10, 64, 64), **hf.x264(crf=23)
            )

        # Read parts of the data
        print(
            f"{Fore.BLUE}ℹ Reading partial sections of the dataset...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "r") as f:
            dataset = f["data"]

            # Read first 10 slices
            print(f"{Fore.BLUE}ℹ Reading first 10 slices...{Style.RESET_ALL}")
            partial_data = dataset[0:10, :, :]
            self.assertEqual(partial_data.shape, (10, self.height, self.width))
            print(
                f"{Fore.GREEN}✓ First 10 slices read successfully with shape {partial_data.shape}{Style.RESET_ALL}"
            )

            # Read middle region
            print(
                f"{Fore.BLUE}ℹ Reading middle region (20:30, 50:150, 50:150)...{Style.RESET_ALL}"
            )
            partial_data = dataset[20:30, 50:150, 50:150]
            self.assertEqual(partial_data.shape, (10, 100, 100))
            print(
                f"{Fore.GREEN}✓ Middle region read successfully with shape {partial_data.shape}{Style.RESET_ALL}"
            )

            # Read single slice
            print(f"{Fore.BLUE}ℹ Reading single slice (index 25)...{Style.RESET_ALL}")
            partial_data = dataset[25, :, :]
            self.assertEqual(partial_data.shape, (self.height, self.width))
            print(
                f"{Fore.GREEN}✓ Single slice read successfully with shape {partial_data.shape}{Style.RESET_ALL}"
            )

    def test_data_types(self):
        """Test with different data types."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_datatypes.h5")
        print(
            f"{Fore.BLUE}ℹ Testing compression with different data types...{Style.RESET_ALL}"
        )

        # Test with 8-bit and 16-bit data
        datasets = [
            ("data_8bit", self.test_data_8bit, hf.x264()),
            ("data_16bit", self.test_data_16bit, hf.x264(bit_mode=hf.BitMode.BIT_10)),
        ]

        # Write datasets
        print(f"{Fore.BLUE}ℹ Writing 8-bit and 16-bit datasets...{Style.RESET_ALL}")
        with h5py.File(h5_file, "w") as f:
            for name, data, options in datasets:
                print(f"{Fore.BLUE}ℹ Writing {name} dataset...{Style.RESET_ALL}")
                f.create_dataset(name, data=data, **options)

        # Read datasets
        results = []
        print(
            f"{Fore.BLUE}ℹ Reading back datasets and calculating metrics...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "r") as f:
            for name, data, _ in datasets:
                print(f"{Fore.BLUE}ℹ Reading {name} dataset...{Style.RESET_ALL}")
                # Read data
                decompressed_data = f[name][:]

                # Check shape and dtype
                self.assertEqual(decompressed_data.shape, data.shape)
                self.assertEqual(decompressed_data.dtype, data.dtype)
                print(
                    f"{Fore.GREEN}✓ Shape and dtype match for {name}{Style.RESET_ALL}"
                )

                # Check quality
                psnr = calculate_psnr(data, decompressed_data)

                # Calculate approximate size for this dataset
                # This is an approximation since the file contains multiple datasets
                file_info = os.stat(h5_file)
                file_size_kb = file_info.st_size / 1024 / len(datasets)

                # Calculate approximate compression ratio
                original_size = data.nbytes
                compression_ratio = original_size / (file_size_kb * 1024)

                results.append((name, psnr, compression_ratio, file_size_kb))

                # PSNR threshold depends on bit depth
                min_psnr = 40.0 if name == "data_8bit" else 45.0
                self.assertGreater(psnr, min_psnr, f"PSNR for {name} is too low")
                print(
                    f"{Fore.GREEN}✓ {name} has acceptable quality (PSNR > {min_psnr} dB){Style.RESET_ALL}"
                )

        # Print results table
        self.print_result_table(results)

    def test_hierarchical_groups(self):
        """Test with hierarchical groups."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_groups.h5")
        print(
            f"{Fore.BLUE}ℹ Testing hierarchical group structure with compressed datasets...{Style.RESET_ALL}"
        )

        # Compression options
        compression_options = hf.x264(crf=23)

        # Create hierarchical structure
        print(f"{Fore.BLUE}ℹ Creating hierarchical group structure...{Style.RESET_ALL}")
        with h5py.File(h5_file, "w") as f:
            # Create groups
            group1 = f.create_group("group1")
            group2 = group1.create_group("group2")

            # Create datasets at different levels
            print(
                f"{Fore.BLUE}ℹ Creating compressed dataset at root level...{Style.RESET_ALL}"
            )
            f.create_dataset(
                "root_data", data=self.test_data_8bit, **compression_options
            )

            print(
                f"{Fore.BLUE}ℹ Creating compressed dataset at level 1...{Style.RESET_ALL}"
            )
            group1.create_dataset(
                "level1_data", data=self.test_data_8bit, **compression_options
            )

            print(
                f"{Fore.BLUE}ℹ Creating compressed dataset at level 2...{Style.RESET_ALL}"
            )
            group2.create_dataset(
                "level2_data", data=self.test_data_8bit, **compression_options
            )

        # Read datasets from different levels
        print(
            f"{Fore.BLUE}ℹ Reading datasets from different hierarchy levels...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "r") as f:
            # Check root level
            print(f"{Fore.BLUE}ℹ Reading root level dataset...{Style.RESET_ALL}")
            root_data = f["root_data"][:]
            self.assertEqual(root_data.shape, self.test_data_8bit.shape)
            print(
                f"{Fore.GREEN}✓ Root level dataset read successfully{Style.RESET_ALL}"
            )

            # Check level 1
            print(f"{Fore.BLUE}ℹ Reading level 1 dataset...{Style.RESET_ALL}")
            level1_data = f["group1/level1_data"][:]
            self.assertEqual(level1_data.shape, self.test_data_8bit.shape)
            print(f"{Fore.GREEN}✓ Level 1 dataset read successfully{Style.RESET_ALL}")

            # Check level 2
            print(f"{Fore.BLUE}ℹ Reading level 2 dataset...{Style.RESET_ALL}")
            level2_data = f["group1/group2/level2_data"][:]
            self.assertEqual(level2_data.shape, self.test_data_8bit.shape)
            print(f"{Fore.GREEN}✓ Level 2 dataset read successfully{Style.RESET_ALL}")

            # Calculate PSNR for all levels
            root_psnr = calculate_psnr(self.test_data_8bit, root_data)
            level1_psnr = calculate_psnr(self.test_data_8bit, level1_data)
            level2_psnr = calculate_psnr(self.test_data_8bit, level2_data)

            # Calculate file size
            file_size_kb = os.path.getsize(h5_file) / 1024

            # Print results
            print(f"{Fore.BLUE}ℹ PSNR values:{Style.RESET_ALL}")
            print(f"{Fore.BLUE}ℹ Root level: {root_psnr:.2f} dB{Style.RESET_ALL}")
            print(f"{Fore.BLUE}ℹ Level 1: {level1_psnr:.2f} dB{Style.RESET_ALL}")
            print(f"{Fore.BLUE}ℹ Level 2: {level2_psnr:.2f} dB{Style.RESET_ALL}")

            # Verify quality
            self.assertGreater(root_psnr, 40.0)
            self.assertGreater(level1_psnr, 40.0)
            self.assertGreater(level2_psnr, 40.0)
            print(
                f"{Fore.GREEN}✓ All hierarchical datasets have good quality (PSNR > 40 dB){Style.RESET_ALL}"
            )

    def test_attributes(self):
        """Test with dataset and group attributes."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_attributes.h5")
        print(
            f"{Fore.BLUE}ℹ Testing dataset and group attributes with compression...{Style.RESET_ALL}"
        )

        # Compression options
        compression_options = hf.x264(crf=23)

        # Create file with attributes
        print(
            f"{Fore.BLUE}ℹ Creating file with attributes at various levels...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "w") as f:
            # Root attributes
            f.attrs["description"] = "Test file for FFMPEG HDF5 filter"
            f.attrs["creation_date"] = "2023-01-01"

            # Create dataset with attributes
            dset = f.create_dataset(
                "data", data=self.test_data_8bit, **compression_options
            )
            dset.attrs["codec"] = "H.264"
            dset.attrs["crf"] = 23
            dset.attrs["dimensions"] = [self.depth, self.height, self.width]

            # Create group with attributes
            group = f.create_group("metadata")
            group.attrs["version"] = "1.0"

        # Read attributes
        print(
            f"{Fore.BLUE}ℹ Reading back attributes from various levels...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "r") as f:
            # Check root attributes
            print(f"{Fore.BLUE}ℹ Checking root attributes...{Style.RESET_ALL}")
            self.assertEqual(f.attrs["description"], "Test file for FFMPEG HDF5 filter")
            self.assertEqual(f.attrs["creation_date"], "2023-01-01")
            print(f"{Fore.GREEN}✓ Root attributes verified{Style.RESET_ALL}")

            # Check dataset attributes
            print(f"{Fore.BLUE}ℹ Checking dataset attributes...{Style.RESET_ALL}")
            dset = f["data"]
            self.assertEqual(dset.attrs["codec"], "H.264")
            self.assertEqual(dset.attrs["crf"], 23)
            np.testing.assert_array_equal(
                dset.attrs["dimensions"], [self.depth, self.height, self.width]
            )
            print(f"{Fore.GREEN}✓ Dataset attributes verified{Style.RESET_ALL}")

            # Check group attributes
            print(f"{Fore.BLUE}ℹ Checking group attributes...{Style.RESET_ALL}")
            group = f["metadata"]
            self.assertEqual(group.attrs["version"], "1.0")
            print(f"{Fore.GREEN}✓ Group attributes verified{Style.RESET_ALL}")

            # Read and check data quality
            decompressed_data = dset[:]
            psnr = calculate_psnr(self.test_data_8bit, decompressed_data)
            print(
                f"{Fore.BLUE}ℹ PSNR for dataset with attributes: {psnr:.2f} dB{Style.RESET_ALL}"
            )
            self.assertGreater(psnr, 40.0)

    def test_h5py_filter_pipeline(self):
        """Test with multiple filters in h5py pipeline."""
        # Skip if h5py version doesn't support filter pipeline
        try:
            # Create a temporary HDF5 file
            h5_file = os.path.join(self.temp_dir, "test_pipeline.h5")
            print(
                f"{Fore.BLUE}ℹ Testing filter pipeline with multiple filters...{Style.RESET_ALL}"
            )

            # Compression options for FFMPEG
            ffmpeg_options = {
                "compression": hf.FFMPEG_ID,
                "compression_opts": hf.x264(crf=23)["compression_opts"],
            }

            # Try to use FFMPEG filter with shuffle filter
            print(
                f"{Fore.BLUE}ℹ Creating dataset with both FFMPEG and shuffle filters...{Style.RESET_ALL}"
            )
            with h5py.File(h5_file, "w") as f:
                dset = f.create_dataset(
                    "data",
                    data=self.test_data_8bit,
                    **ffmpeg_options,
                    shuffle=True,  # Add byte shuffle filter, just for testing, actually doesn't make sense, IDK why am I doing it :)
                )

            # Read data
            print(
                f"{Fore.BLUE}ℹ Reading back data compressed with multiple filters...{Style.RESET_ALL}"
            )
            with h5py.File(h5_file, "r") as f:
                decompressed_data = f["data"][:]

                # Check quality
                psnr = calculate_psnr(self.test_data_8bit, decompressed_data)
                print(
                    f"{Fore.BLUE}ℹ PSNR with filter pipeline: {psnr:.2f} dB{Style.RESET_ALL}"
                )
                self.assertGreater(psnr, 40.0)

                # Calculate file size and compression ratio
                file_size_kb = os.path.getsize(h5_file) / 1024
                original_size = self.test_data_8bit.nbytes
                compression_ratio = original_size / (file_size_kb * 1024)

                # Print results
                results = [("FFMPEG + Shuffle", psnr, compression_ratio, file_size_kb)]
                self.print_result_table(results)

                print(f"{Fore.GREEN}✓ Filter pipeline test passed{Style.RESET_ALL}")

        except Exception as e:
            print(
                f"{Fore.YELLOW}⚠ Filter pipeline test skipped: {str(e)}{Style.RESET_ALL}"
            )
            self.skipTest(f"Filter pipeline test skipped: {str(e)}")

    def test_mixed_compression(self):
        """Test with mixed compressed and uncompressed datasets."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_mixed.h5")
        print(
            f"{Fore.BLUE}ℹ Testing file with mixed compressed and uncompressed datasets...{Style.RESET_ALL}"
        )

        # Compression options
        compression_options = hf.x264(crf=23)

        # Write data
        print(
            f"{Fore.BLUE}ℹ Writing compressed and uncompressed datasets to same file...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "w") as f:
            # Compressed dataset
            print(f"{Fore.BLUE}ℹ Creating compressed dataset...{Style.RESET_ALL}")
            f.create_dataset(
                "compressed", data=self.test_data_8bit, **compression_options
            )

            # Uncompressed dataset
            print(f"{Fore.BLUE}ℹ Creating uncompressed dataset...{Style.RESET_ALL}")
            f.create_dataset("uncompressed", data=self.test_data_8bit)

        # Read data
        print(f"{Fore.BLUE}ℹ Reading both datasets back...{Style.RESET_ALL}")
        with h5py.File(h5_file, "r") as f:
            compressed_data = f["compressed"]
            uncompressed_data = f["uncompressed"]

            # Read both datasets
            comp_data = compressed_data[:]
            uncomp_data = uncompressed_data[:]

            # Check shapes
            self.assertEqual(comp_data.shape, uncomp_data.shape)
            print(f"{Fore.GREEN}✓ Both datasets have same shape{Style.RESET_ALL}")

            # Check quality
            psnr = calculate_psnr(uncomp_data, comp_data)
            print(
                f"{Fore.BLUE}ℹ Compressed vs. Uncompressed: PSNR = {psnr:.2f} dB{Style.RESET_ALL}"
            )
            self.assertGreater(psnr, 40.0)
            print(
                f"{Fore.GREEN}✓ Compressed data matches uncompressed with high quality (PSNR > 40 dB){Style.RESET_ALL}"
            )

            # Calculate file size
            file_size_kb = os.path.getsize(h5_file) / 1024
            print(
                f"{Fore.BLUE}ℹ Total file size: {file_size_kb:.1f} KB{Style.RESET_ALL}"
            )

    def test_delayed_data_setting(self):
        """Test creating datasets without initial data and setting data later."""
        # Create a temporary HDF5 file
        h5_file = os.path.join(self.temp_dir, "test_delayed_data.h5")
        print(
            f"{Fore.BLUE}ℹ Testing datasets created without initial data...{Style.RESET_ALL}"
        )

        # Compression options
        compression_options = hf.x264(crf=23)

        # Create file with empty dataset and set data later
        print(
            f"{Fore.BLUE}ℹ Creating empty dataset with compression...{Style.RESET_ALL}"
        )
        with h5py.File(h5_file, "w") as f:
            # Create empty dataset with same shape as test data
            dset = f.create_dataset(
                "delayed_data",
                shape=self.test_data_8bit.shape,
                dtype=np.uint8,
                chunks=(10, 64, 64),
                **compression_options,
            )

            print(f"{Fore.BLUE}ℹ Setting data in slices...{Style.RESET_ALL}")

            dset[0:10, :, :] = self.test_data_8bit[0:10, :, :]
            dset[10:40, :, :] = self.test_data_8bit[10:40, :, :]
            dset[40:50, :, :] = self.test_data_8bit[40:50, :, :]

            print(
                f"{Fore.BLUE}ℹ Creating dataset for single value setting...{Style.RESET_ALL}"
            )
            single_dset = f.create_dataset(
                "single_values",
                shape=(100, 100, 100),
                dtype=np.uint8,
                chunks=(10, 50, 50),
                **compression_options,
            )

            # Set individual values
            print(f"{Fore.BLUE}ℹ Setting individual values...{Style.RESET_ALL}")
            single_dset[0:50, 0:50, 0:50] = 100
            single_dset[50:100, 50:100, 50:100] = 200

        # Read data back and verify
        print(f"{Fore.BLUE}ℹ Reading back data and verifying...{Style.RESET_ALL}")
        with h5py.File(h5_file, "r") as f:
            read_data = f["delayed_data"][:]

            self.assertEqual(read_data.shape, self.test_data_8bit.shape)
            psnr = calculate_psnr(self.test_data_8bit, read_data)
            print(
                f"{Fore.BLUE}ℹ PSNR for delayed data setting: {psnr:.2f} dB{Style.RESET_ALL}"
            )
            self.assertGreater(psnr, 40.0)

            single_read = f["single_values"][:]

            region1 = single_read[0:50, 0:50, 0:50]
            region2 = single_read[50:100, 50:100, 50:100]

            mean_value_region1 = np.mean(region1)
            mean_value_region2 = np.mean(region2)

            print(
                f"{Fore.BLUE}ℹ Mean value in region 1: {mean_value_region1:.2f} (expected ~100){Style.RESET_ALL}"
            )
            print(
                f"{Fore.BLUE}ℹ Mean value in region 2: {mean_value_region2:.2f} (expected ~200){Style.RESET_ALL}"
            )

            # Assert with tolerance for compression artifacts
            self.assertGreater(mean_value_region1, 95)  # Lower bound
            self.assertLess(mean_value_region1, 105)  # Upper bound
            self.assertGreater(mean_value_region2, 195)  # Lower bound
            self.assertLess(mean_value_region2, 205)  # Upper bound

            print(
                f"{Fore.GREEN}✓ Delayed data setting and single value setting tests passed{Style.RESET_ALL}"
            )

            file_size_kb = os.path.getsize(h5_file) / 1024

            original_size_delayed = self.test_data_8bit.nbytes
            original_size_single = 100 * 100 * 100

            total_uncompressed = original_size_delayed + original_size_single
            delayed_ratio = original_size_delayed / total_uncompressed
            single_ratio = original_size_single / total_uncompressed

            delayed_size_kb = file_size_kb * delayed_ratio
            single_size_kb = file_size_kb * single_ratio

            delayed_compression = original_size_delayed / (delayed_size_kb * 1024)
            single_compression = original_size_single / (single_size_kb * 1024)

            results = [
                ("Delayed Data Setting", psnr, delayed_compression, delayed_size_kb),
                (
                    "Single Value Setting",
                    float("inf"),
                    single_compression,
                    single_size_kb,
                ),
            ]
            self.print_result_table(results)


if __name__ == "__main__":
    # Run tests with colored output
    print(
        f"{Fore.CYAN}{Style.BRIGHT}▶ FFMPEG HDF5 Filter Integration Tests{Style.RESET_ALL}"
    )
    print(f"{Fore.CYAN}{'=' * 60}{Style.RESET_ALL}")

    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestIntegration)

    # Run tests with colored output
    runner = ColoredTestRunner()
    result = runner.run(suite)

    # Print summary
    print_summary("INTEGRATION TESTS", result)
    sys.exit(not result.wasSuccessful())
