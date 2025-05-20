import os
import sys
import platform
import glob
import sysconfig
from setuptools import setup, Extension, find_packages
from setuptools.command.build_ext import build_ext

# Configuration
FFMPEG_ROOT = os.environ.get('FFMPEG_ROOT', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ffmpeg_build'))
HDF5_ROOT = os.environ.get('HDF5_ROOT')

# Debug information
src_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src')
print(f"Source directory: {src_dir}")
print(f"FFMPEG_ROOT: {FFMPEG_ROOT}")
print(f"HDF5_ROOT: {HDF5_ROOT}")

# Check for important C source files
required_files = [
    os.path.join(src_dir, 'ffmpeg_h5filter.h'),
    os.path.join(src_dir, 'ffmpeg_h5filter.c'),
    os.path.join(src_dir, 'ffmpeg_h5plugin.c')
]

for file_path in required_files:
    if os.path.exists(file_path):
        print(f"Found required file: {file_path}")
    else:
        print(f"ERROR: Required file not found: {file_path}")
        sys.exit(1)

# Detect platform specifics
system = platform.system().lower()
machine = platform.machine().lower()
print(f"Building for {system} on {machine}")

# Base directories
include_dirs = [
    src_dir,
    os.path.join(FFMPEG_ROOT, 'include')
]

library_dirs = [
    os.path.join(FFMPEG_ROOT, 'lib')
]

# Platform-specific library extensions
if system == 'windows':
    shared_lib_ext = '.dll'
    static_lib_ext = '.lib'
    lib_prefix = ''
elif system == 'darwin':  # macOS
    shared_lib_ext = '.dylib'
    static_lib_ext = '.a'
    lib_prefix = 'lib'
else:  # Linux and others
    shared_lib_ext = '.so'
    static_lib_ext = '.a'
    lib_prefix = 'lib'

# Function to find libraries
def find_library(lib_name, search_dirs, prefix=lib_prefix, extensions=[shared_lib_ext, static_lib_ext]):
    """Find a library in the given search directories."""
    for dir_path in search_dirs:
        if not os.path.exists(dir_path):
            continue
            
        for ext in extensions:
            lib_path = os.path.join(dir_path, f"{prefix}{lib_name}{ext}")
            if os.path.exists(lib_path):
                print(f"Found library: {lib_path}")
                return dir_path
    return None

# Try to find HDF5 libraries
if HDF5_ROOT:
    hdf5_include_dir = os.path.join(HDF5_ROOT, 'include')
    hdf5_library_dir = os.path.join(HDF5_ROOT, 'lib')
    print(f"Using HDF5 from environment: include={hdf5_include_dir}, lib={hdf5_library_dir}")
else:
    # Common locations for HDF5
    potential_include_dirs = [
        '/usr/include/hdf5/serial',
        '/usr/local/include',
        '/opt/homebrew/include',
        '/usr/local/opt/hdf5/include',
        '/usr/include',
        '/usr/include/hdf5',
    ]
    
    potential_library_dirs = [
        '/usr/lib/x86_64-linux-gnu',
        '/usr/local/lib',
        '/opt/homebrew/lib',
        '/usr/local/opt/hdf5/lib',
        '/usr/lib',
        '/usr/lib64',
    ]
    
    # Search for HDF5 header
    hdf5_include_dir = None
    for dir_path in potential_include_dirs:
        if os.path.exists(os.path.join(dir_path, 'hdf5.h')):
            hdf5_include_dir = dir_path
            print(f"Found HDF5 header at: {os.path.join(dir_path, 'hdf5.h')}")
            break
    
    # Search for HDF5 library
    hdf5_library_dir = find_library('hdf5', potential_library_dirs)
    
# Try using pkg-config as a fallback
if not hdf5_include_dir or not hdf5_library_dir:
    try:
        import subprocess
        
        # Get HDF5 cflags and libs from pkg-config
        hdf5_cflags = subprocess.check_output(['pkg-config', '--cflags', 'hdf5'], 
                                            universal_newlines=True).strip()
        hdf5_libs = subprocess.check_output(['pkg-config', '--libs', 'hdf5'], 
                                           universal_newlines=True).strip()
        
        print(f"pkg-config HDF5 cflags: {hdf5_cflags}")
        print(f"pkg-config HDF5 libs: {hdf5_libs}")
        
        # Extract include dirs from cflags
        for flag in hdf5_cflags.split():
            if flag.startswith('-I'):
                include_dir = flag[2:]
                if os.path.exists(os.path.join(include_dir, 'hdf5.h')):
                    hdf5_include_dir = include_dir
                    print(f"Using pkg-config include dir: {hdf5_include_dir}")
        
        # Extract library dirs from libs
        for flag in hdf5_libs.split():
            if flag.startswith('-L'):
                lib_dir = flag[2:]
                if os.path.exists(lib_dir):
                    hdf5_library_dir = lib_dir
                    print(f"Using pkg-config library dir: {hdf5_library_dir}")
                    
    except (subprocess.SubprocessError, FileNotFoundError):
        print("pkg-config not available or could not find HDF5")

# Add HDF5 directories if found
if hdf5_include_dir:
    include_dirs.append(hdf5_include_dir)
    print(f"Added HDF5 include dir: {hdf5_include_dir}")
else:
    print("ERROR: Could not find HDF5 include directory")
    sys.exit(1)

if hdf5_library_dir:
    library_dirs.append(hdf5_library_dir)
    print(f"Added HDF5 library dir: {hdf5_library_dir}")
else:
    print("ERROR: Could not find HDF5 library directory")
    sys.exit(1)

# Find FFmpeg include and libraries
ffmpeg_libs = ['avcodec', 'avutil', 'avformat', 'swscale']
missing_ffmpeg_libs = []

# Check for FFmpeg headers
for lib in ffmpeg_libs:
    header_path = os.path.join(FFMPEG_ROOT, 'include', f'lib{lib}', f'{lib}.h')
    if os.path.exists(header_path):
        print(f"Found FFmpeg header: {header_path}")
    else:
        print(f"WARNING: FFmpeg header not found: {header_path}")

# Check for FFmpeg libraries
for lib in ffmpeg_libs:
    lib_found = False
    for dir_path in library_dirs:
        for ext in [shared_lib_ext, static_lib_ext]:
            lib_path = os.path.join(dir_path, f"{lib_prefix}{lib}{ext}")
            if os.path.exists(lib_path):
                print(f"Found FFmpeg library: {lib_path}")
                lib_found = True
                break
        if lib_found:
            break
    
    if not lib_found:
        missing_ffmpeg_libs.append(lib)
        print(f"WARNING: FFmpeg library not found: {lib}")

if missing_ffmpeg_libs:
    print(f"ERROR: Missing FFmpeg libraries: {', '.join(missing_ffmpeg_libs)}")
    print("You may need to set FFMPEG_ROOT environment variable to point to your FFmpeg installation.")
    # We'll continue anyway, as the libraries might be in system paths

# Define libraries
libraries = ['avcodec', 'avutil', 'avformat', 'swscale', 'hdf5']

# Windows-specific libraries
if system == 'windows':
    libraries.extend(['shlwapi'])

# Platform-specific compile and link arguments
extra_compile_args = []
extra_link_args = []

if system == 'linux':
    extra_compile_args.extend(['-std=c99', '-fPIC', '-D_POSIX_C_SOURCE=200809L'])
    extra_link_args.extend(['-Wl,--no-as-needed'])
    # Add runtime path to find shared libraries
    extra_link_args.extend([f'-Wl,-rpath,{dir_path}' for dir_path in library_dirs])
elif system == 'darwin':  # macOS
    extra_compile_args.extend(['-std=c99', '-fPIC'])
    # Handle macOS rpath
    extra_link_args.extend([
        '-Wl,-rpath,@loader_path',
        '-Wl,-rpath,@loader_path/../../',
        f'-Wl,-rpath,{FFMPEG_ROOT}/lib'
    ])
elif system == 'windows':
    # Windows MSVC compiler settings
    extra_compile_args.extend(['/std:c11'])

# Define important macros
extra_compile_args.append('-DFFMPEG_H5_FILTER_EXPORTS')

# Define the extension module
ffmpeg_module = Extension(
    'h5ffmpeg._ffmpeg_filter',
    sources=[
        os.path.join('h5ffmpeg', '_ffmpeg_filter.c'), 
        os.path.join('src', 'ffmpeg_h5filter.c'),
        os.path.join('src', 'ffmpeg_h5plugin.c')
    ],
    include_dirs=include_dirs,
    library_dirs=library_dirs,
    libraries=libraries,
    extra_compile_args=extra_compile_args,
    extra_link_args=extra_link_args,
)

# Custom build_ext command that adds numpy include directory
class CustomBuildExt(build_ext):
    def finalize_options(self):
        build_ext.finalize_options(self)
        # Prevent numpy from thinking it is still in its setup process
        import builtins
        builtins.__NUMPY_SETUP__ = False
        import numpy
        self.include_dirs.append(numpy.get_include())
        
    def build_extension(self, ext):
        # Print debug info before building
        print(f"Building extension: {ext.name}")
        print(f"  Sources: {ext.sources}")
        print(f"  Include dirs: {ext.include_dirs}")
        print(f"  Library dirs: {ext.library_dirs}")
        print(f"  Libraries: {ext.libraries}")
        print(f"  Extra compile args: {ext.extra_compile_args}")
        print(f"  Extra link args: {ext.extra_link_args}")
        
        # Continue with standard build
        super().build_extension(ext)
        
        # Print output location
        output_dir = os.path.abspath(os.path.dirname(self.get_ext_fullpath(ext.name)))
        print(f"Extension built and saved to: {output_dir}")
        
        # On Unix platforms, ensure library is executable
        if system != 'windows':
            lib_file = self.get_ext_fullpath(ext.name)
            if os.path.exists(lib_file):
                os.chmod(lib_file, 0o755)
                print(f"Set executable permission on {lib_file}")

# Get long description from README
try:
    with open('README.md', 'r', encoding='utf-8') as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "HDF5 filter plugin for FFMPEG video codec compression"
    print("WARNING: README.md not found, using default description")

# Setup package
setup(
    name="h5ffmpeg",
    version="1.0.0",
    description="HDF5 filter plugin for FFMPEG video codec compression",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="Bin Duan@Cailab, University of Michigan",
    author_email="duanb@umich.edu",
    url="https://github.com/Cai-Lab-at-University-of-Michigan/ffmpeg_HDF5_filter",
    packages=find_packages(),
    ext_modules=[ffmpeg_module],
    install_requires=[
        "h5py>=3.8.0",
        "numpy>=1.15.0",
        "colorama>=0.4.6",
        "tabulate>=0.9.0",
        "matplotlib>=3.10.3",
        "scikit-image>=0.25.2",
    ],
    extras_require={
        'nvidia': ['cupy-cuda11x'],  # For NVIDIA GPU support
        'intel': ['intel-openmp'],   # For Intel QSV support
    },
    python_requires=">=3.9",
    cmdclass={'build_ext': CustomBuildExt},
    license="MIT",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Scientific/Engineering",
        "Topic :: Scientific/Engineering :: Image Compression",
        "Topic :: Scientific/Engineering :: Image Processing",
    ],
    package_data={
        'h5ffmpeg': ['*.so', '*.dll', '*.dylib', '*.pyd'],
    },
    include_package_data=True,
    zip_safe=False,  # Ensure extension modules can be properly loaded
)