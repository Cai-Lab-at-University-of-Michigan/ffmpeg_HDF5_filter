import os
import sys
import platform
import glob
import sysconfig
import subprocess
from setuptools import setup, Extension, find_packages
from setuptools.command.build_ext import build_ext

# Check if we're building sdist (source distribution)
def is_building_sdist():
    """Check if we're building a source distribution"""
    return 'sdist' in sys.argv or 'egg_info' in sys.argv

def get_ffmpeg_root():
    """Get FFmpeg root directory with proper fallbacks for CI"""
    if 'FFMPEG_ROOT' in os.environ:
        return os.environ['FFMPEG_ROOT']
    
    # CI-appropriate fallback locations (matching pyproject.toml)
    system = platform.system().lower()
    if system == 'windows':
        return 'D:/a/ffmpeg_build'
    elif system == 'darwin':
        return os.path.expanduser('~/ffmpeg')
    else:  # Linux
        return '/opt/ffmpeg'

def get_hdf5_root():
    """Get HDF5 root directory with CI-aware fallbacks"""
    if 'HDF5_ROOT' in os.environ:
        return os.environ['HDF5_ROOT']
    
    # Platform-specific fallbacks for CI environments
    system = platform.system().lower()
    if system == 'windows':
        # Check for conda-forge installation (from pyproject.toml)
        conda_hdf5 = 'D:/a/miniconda3/Library'
        if os.path.exists(os.path.join(conda_hdf5, 'include', 'hdf5.h')):
            return conda_hdf5
    
    return None

# Skip dependency checks for sdist builds
if is_building_sdist():
    print("Building source distribution - skipping FFmpeg/HDF5 dependency checks")
    
    # Create minimal extension for sdist (won't be compiled)
    ffmpeg_module = Extension(
        'h5ffmpeg._ffmpeg_filter',
        sources=[
            os.path.join('h5ffmpeg', '_ffmpeg_filter.c'), 
            os.path.join('src', 'ffmpeg_h5filter.c'),
            os.path.join('src', 'ffmpeg_h5plugin.c')
        ]
    )
    
    # Simple build_ext class for sdist
    class CustomBuildExt(build_ext):
        pass
        
else:
    # Full dependency checking and configuration for wheel builds
    
    # Configuration
    FFMPEG_ROOT = get_ffmpeg_root()
    HDF5_ROOT = get_hdf5_root()

    # Debug information
    src_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src')
    print(f"Source directory: {src_dir}")
    print(f"FFMPEG_ROOT: {FFMPEG_ROOT}")
    print(f"HDF5_ROOT: {HDF5_ROOT}")
    print(f"Building for: {platform.system()} {platform.machine()}")

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

    # Verify FFmpeg installation
    if not os.path.exists(FFMPEG_ROOT):
        print(f"ERROR: FFmpeg directory not found: {FFMPEG_ROOT}")
        print("Make sure FFMPEG_ROOT environment variable is set correctly or FFmpeg is built.")
        sys.exit(1)

    ffmpeg_include = os.path.join(FFMPEG_ROOT, 'include')
    ffmpeg_lib = os.path.join(FFMPEG_ROOT, 'lib')

    if not os.path.exists(ffmpeg_include):
        print(f"ERROR: FFmpeg include directory not found: {ffmpeg_include}")
        print(f"Contents of FFMPEG_ROOT: {os.listdir(FFMPEG_ROOT) if os.path.exists(FFMPEG_ROOT) else 'Directory does not exist'}")
        sys.exit(1)

    if not os.path.exists(ffmpeg_lib):
        print(f"ERROR: FFmpeg lib directory not found: {ffmpeg_lib}")
        print(f"Contents of FFMPEG_ROOT: {os.listdir(FFMPEG_ROOT) if os.path.exists(FFMPEG_ROOT) else 'Directory does not exist'}")
        sys.exit(1)

    # Detect platform specifics
    system = platform.system().lower()
    machine = platform.machine().lower()

    # Base directories
    include_dirs = [
        src_dir,
        ffmpeg_include
    ]

    library_dirs = [
        ffmpeg_lib
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

    # HDF5 Configuration with improved CI support
    def configure_hdf5():
        """Configure HDF5 include and library paths with CI-aware detection"""
        
        # First try explicit HDF5_ROOT
        if HDF5_ROOT:
            hdf5_include_dir = os.path.join(HDF5_ROOT, 'include')
            hdf5_library_dir = os.path.join(HDF5_ROOT, 'lib')
            
            if os.path.exists(hdf5_include_dir) and os.path.exists(hdf5_library_dir):
                if os.path.exists(os.path.join(hdf5_include_dir, 'hdf5.h')):
                    include_dirs.append(hdf5_include_dir)
                    library_dirs.append(hdf5_library_dir)
                    print(f"Using HDF5 from HDF5_ROOT: include={hdf5_include_dir}, lib={hdf5_library_dir}")
                    return True
                else:
                    print(f"WARNING: hdf5.h not found in {hdf5_include_dir}")
            else:
                print(f"WARNING: HDF5_ROOT directories don't exist: include={hdf5_include_dir}, lib={hdf5_library_dir}")
        
        # Try pkg-config (works well in Linux CI)
        try:
            hdf5_cflags = subprocess.check_output(['pkg-config', '--cflags', 'hdf5'], 
                                                universal_newlines=True, stderr=subprocess.DEVNULL).strip()
            hdf5_libs = subprocess.check_output(['pkg-config', '--libs', 'hdf5'], 
                                               universal_newlines=True, stderr=subprocess.DEVNULL).strip()
            
            print(f"pkg-config HDF5 cflags: {hdf5_cflags}")
            print(f"pkg-config HDF5 libs: {hdf5_libs}")
            
            # Extract include dirs from cflags
            hdf5_found = False
            for flag in hdf5_cflags.split():
                if flag.startswith('-I'):
                    include_dir = flag[2:]
                    if os.path.exists(os.path.join(include_dir, 'hdf5.h')):
                        include_dirs.append(include_dir)
                        hdf5_found = True
                        print(f"Added HDF5 include dir from pkg-config: {include_dir}")
            
            # Extract library dirs from libs
            for flag in hdf5_libs.split():
                if flag.startswith('-L'):
                    lib_dir = flag[2:]
                    if os.path.exists(lib_dir):
                        library_dirs.append(lib_dir)
                        print(f"Added HDF5 library dir from pkg-config: {lib_dir}")
            
            if hdf5_found:
                print("Successfully configured HDF5 using pkg-config")
                return True
                        
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("pkg-config not available or could not find HDF5")
        
        # Platform-specific fallback locations
        potential_include_dirs = []
        potential_library_dirs = []
        
        if system == 'linux':
            potential_include_dirs = [
                '/usr/include/hdf5/serial',
                '/usr/include/hdf5',
                '/usr/include',
                '/usr/local/include'
            ]
            potential_library_dirs = [
                '/usr/lib/x86_64-linux-gnu/hdf5/serial',
                '/usr/lib/x86_64-linux-gnu',
                '/usr/lib64',
                '/usr/lib',
                '/usr/local/lib'
            ]
        elif system == 'darwin':
            potential_include_dirs = [
                '/opt/homebrew/include',
                '/usr/local/include',
                '/usr/local/opt/hdf5/include'
            ]
            potential_library_dirs = [
                '/opt/homebrew/lib',
                '/usr/local/lib',
                '/usr/local/opt/hdf5/lib'
            ]
        elif system == 'windows':
            # Windows fallbacks (if conda installation failed)
            potential_include_dirs = [
                'C:\\Program Files\\HDF5\\include',
                'C:\\HDF5\\include'
            ]
            potential_library_dirs = [
                'C:\\Program Files\\HDF5\\lib',
                'C:\\HDF5\\lib'
            ]
        
        # Search for HDF5 header
        hdf5_include_found = False
        for dir_path in potential_include_dirs:
            if os.path.exists(os.path.join(dir_path, 'hdf5.h')):
                include_dirs.append(dir_path)
                hdf5_include_found = True
                print(f"Found HDF5 header at: {os.path.join(dir_path, 'hdf5.h')}")
                break
        
        # Search for HDF5 library
        hdf5_lib_found = False
        hdf5_library_dir = find_library('hdf5', potential_library_dirs)
        if hdf5_library_dir:
            library_dirs.append(hdf5_library_dir)
            hdf5_lib_found = True
        
        if not hdf5_include_found or not hdf5_lib_found:
            print("ERROR: Could not find HDF5 development libraries.")
            print("Please ensure HDF5 is installed:")
            print("  Linux: sudo apt-get install libhdf5-dev")
            print("  macOS: brew install hdf5") 
            print("  Windows: Install HDF5 or set HDF5_ROOT environment variable")
            sys.exit(1)
        
        return True

    # Configure HDF5
    configure_hdf5()

    # Find FFmpeg include and libraries
    ffmpeg_libs = ['avcodec', 'avutil', 'avformat', 'swscale']
    missing_ffmpeg_libs = []

    # Check for FFmpeg headers
    print("Checking FFmpeg headers...")
    for lib in ffmpeg_libs:
        header_path = os.path.join(FFMPEG_ROOT, 'include', f'lib{lib}', f'{lib}.h')
        if os.path.exists(header_path):
            print(f"Found FFmpeg header: {header_path}")
        else:
            print(f"WARNING: FFmpeg header not found: {header_path}")

    # Check for FFmpeg libraries
    print("Checking FFmpeg libraries...")
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
        print(f"Checked in directories: {library_dirs}")
        print("Make sure FFmpeg is properly built and installed.")
        # Continue anyway, as libraries might be in system paths

    # Define libraries
    libraries = ['avcodec', 'avutil', 'avformat', 'swscale', 'hdf5']

    # Windows-specific libraries
    if system == 'windows':
        libraries.extend(['shlwapi'])

    # Platform-specific compile and link arguments
    extra_compile_args = ['-DFFMPEG_H5_FILTER_EXPORTS']
    extra_link_args = []

    if system == 'linux':
        extra_compile_args.extend(['-std=c99', '-fPIC', '-D_POSIX_C_SOURCE=200809L'])
        extra_link_args.extend(['-Wl,--no-as-needed'])
        # Add runtime path to find shared libraries
        for dir_path in library_dirs:
            extra_link_args.append(f'-Wl,-rpath,{dir_path}')
    elif system == 'darwin':  # macOS
        extra_compile_args.extend(['-std=c99', '-fPIC'])
        # Handle macOS rpath
        extra_link_args.extend([
            '-Wl,-rpath,@loader_path',
            '-Wl,-rpath,@loader_path/../../',
        ])
        for dir_path in library_dirs:
            extra_link_args.append(f'-Wl,-rpath,{dir_path}')
    elif system == 'windows':
        # Windows MSVC compiler settings
        extra_compile_args.extend(['/std:c11'])

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
            print(f"Added numpy include directory: {numpy.get_include()}")
            
        def build_extension(self, ext):
            # Print comprehensive debug info before building
            print(f"\n{'='*50}")
            print(f"Building extension: {ext.name}")
            print(f"{'='*50}")
            print(f"Sources: {ext.sources}")
            print(f"Include dirs: {ext.include_dirs}")
            print(f"Library dirs: {ext.library_dirs}")
            print(f"Libraries: {ext.libraries}")
            print(f"Extra compile args: {ext.extra_compile_args}")
            print(f"Extra link args: {ext.extra_link_args}")
            print(f"{'='*50}\n")
            
            # Continue with standard build
            super().build_extension(ext)
            
            # Print output location
            output_dir = os.path.abspath(os.path.dirname(self.get_ext_fullpath(ext.name)))
            print(f"Extension built and saved to: {output_dir}")
            
            # On Unix platforms, ensure library is executable
            system = platform.system().lower()
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
    python_requires=">=3.11",
    cmdclass={'build_ext': CustomBuildExt},
    license="MIT",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "Programming Language :: Python :: 3",
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