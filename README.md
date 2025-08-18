# FFMPEG HDF5 Filter Enables High-Ratio Image Compression for Faithful Scientific Analysis

The FFMPEG HDF5 filter enables high-ratio compression of scientific datasets in HDF5 files using video codec technology. It supports a wide range of codecs (H.264, H.265/HEVC, AV1, etc.) with hardware acceleration options for NVIDIA GPUs and Intel QuickSync.

## Features

- **High Compression Ratios**: Achieve 10-10,000× compression while preserving analysis fidelity
- **Multiple Codec Support**: H.264, H.265/HEVC, AV1, and more
- **Hardware Acceleration**: NVIDIA GPU and Intel QuickSync support
- **Simple Python API**: Easy-to-use interface for H5Py
- **Automated Optimization**: Film grain synthesis and artifact minimization
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **ImageJ/Fiji Plugin Support**: Direct visualization and analysis in popular scientific imaging tools

## Installation

### Via pip (recommended)

```bash
pip install h5ffmpeg
```

### Using pre-built binaries for ImageJ/Fiji

We recommend using our imageJ update sites. We support Windows, Ubuntu, MacOS (ARM64). 

**MacOS users**: Run **setup_macos_fiji.sh** to prevent crashes during compression/decompression. 

**SetUpH5FFMPEG.ijm**: This macro runs automatically. After system restarts, open Fiji twice to configure HDF5_PLUGIN_PATH properly.

**Ubuntu users**: After the first time opening Fiji, You may need to Logout and LogIn for Fiji picking up the HDF5_PLUGIN_PATH enviroment variable.

**Note:** Due to the limitation of built ffmpeg to comply with Java, some codecs are not supported. We **strongly recommend** using our python package. If working with large-scale dataset, [SISF_CDN](https://github.com/Cai-Lab-at-University-of-Michigan/SISF_CDN) with [neuroglancer](https://github.com/google/neuroglancer) is recommended.

### From source (not recommended)

```bash
git clone https://github.com/Cai-Lab-at-University-of-Michigan/ffmpeg_HDF5_filter.git
cd ffmpeg_HDF5_filter
pip install -e .
```

**This is not recommended since it requires compiling FFmpeg from source with HDF5 support, which is complex and error-prone. Our pip package includes pre-built, tested binaries.**

## Quick Start

```python
import h5py
import numpy as np
import h5ffmpeg as hf

# Create sample data
data = np.random.rand(100, 512, 512).astype(np.uint8)

# Save with default settings (H.264)
with h5py.File("compressed.h5", "w") as f:
    f.create_dataset("data", data=data, **hf.x264())

# Save with H.265/HEVC compression
with h5py.File("compressed_hevc.h5", "w") as f:
    f.create_dataset("data", data=data, **hf.x265(crf=28))

# Save with AV1 compression (highest ratio)
with h5py.File("compressed_av1.h5", "w") as f:
    f.create_dataset("data", data=data, **hf.svtav1(crf=30))

# Use with NVIDIA GPU acceleration
with h5py.File("compressed_gpu.h5", "w") as f:
    f.create_dataset("data", data=data, **hf.h264_nvenc())
```

## Advanced Usage

### Custom Codec Configuration

```python
import h5ffmpeg as hf

# Access the full ffmpeg API for complete control
compression_options = hf.ffmpeg(
    codec="libx264",        # Codec to use
    preset="medium",        # Encoding speed vs compression efficiency
    tune="film",            # Content-specific optimization
    crf=23,                 # Quality level (lower = higher quality)
    bit_mode=hf.BitMode.BIT_10,  # 8, 10, or 12-bit encoding
    film_grain=50,          # Film grain synthesis (0-50)
    gpu_id=0                # GPU ID (Default: 0)
)
```

### Automated Hardware Acceleration

The library can detect and use available hardware acceleration:

```python
import h5ffmpeg as hf

# This will automatically use NVIDIA GPU if available, 
# or fall back to CPU if not
compression_options = hf.ffmpeg(
    codec="h264_nvenc" if hf.has_nvidia_gpu() else "libx264",
    preset="p4" if hf.has_nvidia_gpu() else "medium",
    crf=23
)
```

## Available Codecs

| Codec | Implementation | Description | Typical Use Case |
|-------|-------------|-------------|------------------|
| XVID | `libxvid` | MPEG-4 codec | Legacy support |
| H.264 | `libx264` | General-purpose codec | Good balance of quality and speed |
| H.265/HEVC | `libx265` | Higher efficiency than H.264 | Better compression for same quality |
| AV1 | `libsvtav1` | Next-gen open codec | Highest compression ratio |
| AV1 | `librav1e` | Rust AV1 encoder | Alternative AV1 implementation |
| H.264 NVENC | `h264_nvenc` | NVIDIA GPU-accelerated H.264 | Fast encoding on NVIDIA GPUs |
| HEVC NVENC | `hevc_nvenc` | NVIDIA GPU-accelerated HEVC | High-quality, fast encoding on NVIDIA GPUs |
| AV1 NVENC | `av1_nvenc` | NVIDIA GPU-accelerated AV1 | Next-gen encoding on newest NVIDIA GPUs |
| AV1 QSV | `av1_qsv` | Intel QuickSync AV1 | Hardware acceleration on Intel GPUs |

## Compatibility

- **Python**: 3.11+
- **Operating Systems**: Linux-x86_64, macOS Apple Silicon, and Windows-AMD64
- **hdf5**: 1.14+
- **h5py**: 3.8+

## License

MIT License

## Citation

If you use this software in your research, please cite:

```
Duan, B., Walker, L.A., Xie, B., Lee, W.J., Lin, A., Yan, Y., and Cai, D. (2024).
Artifact-Minimized High-Ratio Image Compression with Preserved Analysis Fidelity.
```

## Acknowledgments

This work was funded by the United States National Institutes of Health (NIH) grants RF1MH123402, RF1MH124611, and RF1MH133764.

## Community and Support

- **GitHub Issues**: For bug reports and feature requests
- **Contact**: Feel free to reach out to us with questions

## Related Projects

Feel free to check out other tools from the Cai Lab:)
- [nGauge](https://github.com/Cai-Lab-at-University-of-Michigan/nGauge): Python library for neuron morphology analysis
- [nTracer2](https://github.com/Cai-Lab-at-University-of-Michigan/nTracer2): Browser-based tool for neuron tracing
- [pySISF](https://github.com/Cai-Lab-at-University-of-Michigan/pySISF): Python wrapper for SISF format
- [SISF_CDN](https://github.com/Cai-Lab-at-University-of-Michigan/SISF_CDN):Scalable Image Storage Format CDN