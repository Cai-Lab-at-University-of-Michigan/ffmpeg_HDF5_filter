import os
import sys
import platform
import glob
import subprocess
from setuptools import setup, Extension, find_packages
from setuptools.command.build_ext import build_ext

__VERSION__ = "2.4.0"

def is_building_sdist():
    return "sdist" in sys.argv or "egg_info" in sys.argv


def get_ffmpeg_root():
    if "FFMPEG_ROOT" in os.environ:
        return os.environ["FFMPEG_ROOT"]

    system = platform.system().lower()
    if system == "windows":
        home = os.environ.get("HOME", "D:\\a")
        return os.path.join(home, "ffmpeg_build")
    elif system == "darwin":
        home = os.path.expanduser("~")
        return os.path.join(home, "ffmpeg")
    else:
        return "/opt/ffmpeg"


def get_hdf5_root():
    if "HDF5_ROOT" in os.environ:
        return os.environ["HDF5_ROOT"]

    system = platform.system().lower()
    if system == "windows":
        home = os.environ.get("HOME", "D:\\a")
        hdf5_dir = os.path.join(home, "ffmpeg_build")

        if os.path.exists(os.path.join(hdf5_dir, "include", "hdf5.h")):
            return hdf5_dir
    elif system == "darwin":
        possible_paths = [
            "/opt/homebrew/opt/hdf5",
            "/usr/local/opt/hdf5",
            os.path.expanduser("~/miniconda3/lib"),
        ]
        for path in possible_paths:
            if os.path.exists(os.path.join(path, "include", "hdf5.h")):
                return path
    else:
        possible_paths = [
            "/usr/include/hdf5",
            "/usr/local/include/hdf5",
            "/opt/conda/include"
        ]
        for path in possible_paths:
            if os.path.exists(os.path.join(path, "hdf5.h")):
                return os.path.dirname(path)

    return None


def check_hdf5_installation():
    """Check what HDF5 files are actually available"""
    if HDF5_ROOT:
        lib_dir = os.path.join(HDF5_ROOT, "lib")
        bin_dir = os.path.join(HDF5_ROOT, "bin")

        print(f"\n=== HDF5 Installation Check ===")
        print(f"HDF5_ROOT: {HDF5_ROOT}")

        if os.path.exists(lib_dir):
            print(f"\nLibrary files in {lib_dir}:")
            lib_files = [f for f in os.listdir(lib_dir) if f.endswith(".lib")]
            for lib_file in sorted(lib_files):
                print(f"  {lib_file}")
        else:
            print(f"Library directory not found: {lib_dir}")

        if os.path.exists(bin_dir):
            print(f"\nDLL files in {bin_dir}:")
            dll_files = [f for f in os.listdir(bin_dir) if f.endswith(".dll")]
            for dll_file in sorted(dll_files):
                print(f"  {dll_file}")
        else:
            print(f"Binary directory not found: {bin_dir}")

        print("=================================\n")


if is_building_sdist():
    print("Building source distribution - skipping FFmpeg/HDF5 dependency checks")

    ffmpeg_module = Extension(
        "h5ffmpeg._ffmpeg_filter",
        sources=[
            os.path.join("h5ffmpeg", "_ffmpeg_filter.c"),
            os.path.join("src", "ffmpeg_h5filter.c"),
            os.path.join("src", "ffmpeg_native.c"),
            os.path.join("src", "ffmpeg_utils.c"),
            os.path.join("src", "ffmpeg_h5plugin.c"),
        ],
    )

    class CustomBuildExt(build_ext):
        pass

else:
    FFMPEG_ROOT = get_ffmpeg_root()
    HDF5_ROOT = get_hdf5_root()

    src_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
    print(f"Source directory: {src_dir}")
    print(f"FFMPEG_ROOT: {FFMPEG_ROOT}")
    print(f"HDF5_ROOT: {HDF5_ROOT}")
    print(f"Building for: {platform.system()} {platform.machine()}")

    required_files = [
        os.path.join(src_dir, "ffmpeg_h5filter.h"),
        os.path.join(src_dir, "ffmpeg_utils.h"),
        os.path.join(src_dir, "ffmpeg_h5filter.c"),
        os.path.join(src_dir, "ffmpeg_h5plugin.c"),
        os.path.join(src_dir, "ffmpeg_utils.c"),
        os.path.join(src_dir, "ffmpeg_native.c"),
    ]

    for file_path in required_files:
        if os.path.exists(file_path):
            print(f"Found required file: {file_path}")
        else:
            print(f"ERROR: Required file not found: {file_path}")
            sys.exit(1)

    if not os.path.exists(FFMPEG_ROOT):
        print(f"ERROR: FFmpeg directory not found: {FFMPEG_ROOT}")
        print(
            "Make sure FFMPEG_ROOT environment variable is set correctly or FFmpeg is built."
        )
        sys.exit(1)

    ffmpeg_include = os.path.join(FFMPEG_ROOT, "include")
    ffmpeg_lib = os.path.join(FFMPEG_ROOT, "lib")

    if not os.path.exists(ffmpeg_include):
        print(f"ERROR: FFmpeg include directory not found: {ffmpeg_include}")
        print(
            f"Contents of FFMPEG_ROOT: {os.listdir(FFMPEG_ROOT) if os.path.exists(FFMPEG_ROOT) else 'Directory does not exist'}"
        )
        sys.exit(1)

    if not os.path.exists(ffmpeg_lib):
        print(f"ERROR: FFmpeg lib directory not found: {ffmpeg_lib}")
        print(
            f"Contents of FFMPEG_ROOT: {os.listdir(FFMPEG_ROOT) if os.path.exists(FFMPEG_ROOT) else 'Directory does not exist'}"
        )
        sys.exit(1)

    system = platform.system().lower()
    machine = platform.machine().lower()

    include_dirs = [src_dir, ffmpeg_include]

    library_dirs = [ffmpeg_lib]

    if system == "windows":
        shared_lib_ext = ".dll"
        static_lib_ext = ".lib"
        lib_prefix = ""
        ffmpeg_bin = os.path.join(FFMPEG_ROOT, "bin")
        if os.path.exists(ffmpeg_bin):
            library_dirs.append(ffmpeg_bin)
    elif system == "darwin":
        shared_lib_ext = ".dylib"
        static_lib_ext = ".a"
        lib_prefix = "lib"
    else:
        shared_lib_ext = ".so"
        static_lib_ext = ".a"
        lib_prefix = "lib"

    def find_library(
        lib_name,
        search_dirs,
        prefix=lib_prefix,
        extensions=[shared_lib_ext, static_lib_ext],
    ):
        for dir_path in search_dirs:
            if not os.path.exists(dir_path):
                continue

            for ext in extensions:
                lib_path = os.path.join(dir_path, f"{prefix}{lib_name}{ext}")
                if os.path.exists(lib_path):
                    print(f"Found library: {lib_path}")
                    return dir_path

            if system == "windows":
                dll_patterns = [f"{lib_name}*.dll", f"lib{lib_name}*.dll"]

                for pattern in dll_patterns:
                    dll_files = glob.glob(os.path.join(dir_path, pattern))
                    if dll_files:
                        print(f"Found Windows DLL: {dll_files[0]}")
                        return dir_path

        return None

    def configure_hdf5():
        if HDF5_ROOT:
            hdf5_include_dir = os.path.join(HDF5_ROOT, "include")
            hdf5_library_dir = os.path.join(HDF5_ROOT, "lib")

            if os.path.exists(hdf5_include_dir) and os.path.exists(hdf5_library_dir):
                if os.path.exists(os.path.join(hdf5_include_dir, "hdf5.h")):
                    include_dirs.append(hdf5_include_dir)
                    library_dirs.append(hdf5_library_dir)
                    print(
                        f"Using HDF5 from HDF5_ROOT: include={hdf5_include_dir}, lib={hdf5_library_dir}"
                    )
                    return True
                else:
                    print(f"WARNING: hdf5.h not found in {hdf5_include_dir}")
            else:
                print(
                    f"WARNING: HDF5_ROOT directories don't exist: include={hdf5_include_dir}, lib={hdf5_library_dir}"
                )

        try:
            hdf5_cflags = subprocess.check_output(
                ["pkg-config", "--cflags", "hdf5"],
                universal_newlines=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            hdf5_libs = subprocess.check_output(
                ["pkg-config", "--libs", "hdf5"],
                universal_newlines=True,
                stderr=subprocess.DEVNULL,
            ).strip()

            print(f"pkg-config HDF5 cflags: {hdf5_cflags}")
            print(f"pkg-config HDF5 libs: {hdf5_libs}")

            hdf5_found = False
            for flag in hdf5_cflags.split():
                if flag.startswith("-I"):
                    include_dir = flag[2:]
                    if os.path.exists(os.path.join(include_dir, "hdf5.h")):
                        include_dirs.append(include_dir)
                        hdf5_found = True
                        print(f"Added HDF5 include dir from pkg-config: {include_dir}")

            for flag in hdf5_libs.split():
                if flag.startswith("-L"):
                    lib_dir = flag[2:]
                    if os.path.exists(lib_dir):
                        library_dirs.append(lib_dir)
                        print(f"Added HDF5 library dir from pkg-config: {lib_dir}")

            if hdf5_found:
                print("Successfully configured HDF5 using pkg-config")
                return True

        except (subprocess.CalledProcessError, FileNotFoundError):
            print("pkg-config not available or could not find HDF5")

        potential_include_dirs = []
        potential_library_dirs = []

        if system == "linux":
            potential_include_dirs = [
                "/usr/include/hdf5/serial",
                "/usr/include/hdf5",
                "/usr/include",
                "/usr/local/include",
            ]
            potential_library_dirs = [
                "/usr/lib/x86_64-linux-gnu/hdf5/serial",
                "/usr/lib/x86_64-linux-gnu",
                "/usr/lib64",
                "/usr/lib",
                "/usr/local/lib",
            ]
        elif system == "darwin":
            potential_include_dirs = [
                "/opt/homebrew/include",
                "/usr/local/include",
                "/usr/local/opt/hdf5/include",
            ]
            potential_library_dirs = [
                "/opt/homebrew/lib",
                "/usr/local/lib",
                "/usr/local/opt/hdf5/lib",
            ]
        elif system == "windows":
            potential_include_dirs = [
                "C:\\Program Files\\HDF5\\include",
                "C:\\HDF5\\include",
            ]
            potential_library_dirs = ["C:\\Program Files\\HDF5\\lib", "C:\\HDF5\\lib"]

        hdf5_include_found = False
        for dir_path in potential_include_dirs:
            if os.path.exists(os.path.join(dir_path, "hdf5.h")):
                include_dirs.append(dir_path)
                hdf5_include_found = True
                print(f"Found HDF5 header at: {os.path.join(dir_path, 'hdf5.h')}")
                break

        hdf5_lib_found = False
        hdf5_library_dir = find_library("hdf5", potential_library_dirs)
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

    configure_hdf5()
    check_hdf5_installation()

    ffmpeg_libs = ["avcodec", "avutil", "avformat", "swscale"]
    missing_ffmpeg_libs = []

    print("Checking FFmpeg headers...")
    for lib in ffmpeg_libs:
        header_path = os.path.join(FFMPEG_ROOT, "include", f"lib{lib}", f"{lib}.h")
        if os.path.exists(header_path):
            print(f"Found FFmpeg header: {header_path}")
        else:
            print(f"WARNING: FFmpeg header not found: {header_path}")

    print("Checking FFmpeg libraries...")
    for lib in ffmpeg_libs:
        lib_found = find_library(lib, library_dirs)
        if not lib_found:
            missing_ffmpeg_libs.append(lib)
            print(f"WARNING: FFmpeg library not found: {lib}")

    if missing_ffmpeg_libs:
        print(f"WARNING: Missing FFmpeg libraries: {', '.join(missing_ffmpeg_libs)}")
        print(f"Checked in directories: {library_dirs}")
        print("Continuing build - libraries may be found at runtime")

    # Base libraries for all platforms
    libraries = ["avcodec", "avutil", "avformat", "swscale"]

    # Add HDF5 libraries - Windows needs multiple HDF5 libs
    if system == "windows":
        libraries.extend(
            [
                "hdf5",  # Main HDF5 library
                "hdf5_hl",  # High-level HDF5 APIs
                "shlwapi",  # Windows system library
            ]
        )
    else:
        libraries.extend(["hdf5"])

    extra_compile_args = ["-DFFMPEG_H5_FILTER_EXPORTS", "-DFFMPEG_NATIVE_SUPPORT"]
    extra_link_args = []

    if system == "linux":
        extra_compile_args.extend(["-std=c99", "-fPIC", "-D_POSIX_C_SOURCE=200809L"])
        extra_link_args.extend(["-Wl,--no-as-needed"])
        for dir_path in library_dirs:
            extra_link_args.append(f"-Wl,-rpath,{dir_path}")
    elif system == "darwin":
        extra_compile_args.extend(["-std=c99", "-fPIC"])
        extra_link_args.extend(
            [
                "-Wl,-rpath,@loader_path",
                "-Wl,-rpath,@loader_path/../../",
            ]
        )
        for dir_path in library_dirs:
            extra_link_args.append(f"-Wl,-rpath,{dir_path}")
    elif system == "windows":
        extra_compile_args.extend(
            [
                "/std:c11",
                "-D_CRT_SECURE_NO_WARNINGS",
                "-DH5_BUILT_AS_DYNAMIC_LIB",
                "-D_HDF5USEDLL_",
            ]
        )

    ffmpeg_module = Extension(
        "h5ffmpeg._ffmpeg_filter",
        sources=[
            os.path.join("h5ffmpeg", "_ffmpeg_filter.c"),
            os.path.join("src", "ffmpeg_h5filter.c"),
            os.path.join("src", "ffmpeg_h5plugin.c"),
            os.path.join("src", "ffmpeg_native.c"),
            os.path.join("src", "ffmpeg_utils.c"),
        ],
        include_dirs=include_dirs,
        library_dirs=library_dirs,
        libraries=libraries,
        extra_compile_args=extra_compile_args,
        extra_link_args=extra_link_args,
    )

    class CustomBuildExt(build_ext):
        def finalize_options(self):
            build_ext.finalize_options(self)
            import builtins

            builtins.__NUMPY_SETUP__ = False
            import numpy

            self.include_dirs.append(numpy.get_include())
            print(f"Added numpy include directory: {numpy.get_include()}")

        def build_extension(self, ext):
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

            super().build_extension(ext)

            output_dir = os.path.abspath(
                os.path.dirname(self.get_ext_fullpath(ext.name))
            )
            print(f"Extension built and saved to: {output_dir}")

            system = platform.system().lower()
            if system != "windows":
                lib_file = self.get_ext_fullpath(ext.name)
                if os.path.exists(lib_file):
                    os.chmod(lib_file, 0o755)
                    print(f"Set executable permission on {lib_file}")


def write_version_py(version, filename="h5ffmpeg/_version.py"):
    """Write version info to a file."""
    try:
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with open(filename, "w") as f:
            f.write(f"__version__ = '{version}'\n")
        print(f"Version file written: {filename}")
    except Exception as e:
        print(f"WARNING: Could not write version file {filename}: {e}")


try:
    write_version_py(__VERSION__)
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "HDF5 filter plugin for FFMPEG video codec compression"
    print("WARNING: README.md not found, using default description")

setup(
    name="h5ffmpeg",
    version=__VERSION__,
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
        "nvidia": ["cupy-cuda11x"],
        "intel": ["intel-openmp"],
    },
    python_requires=">=3.10,<4.0",
    cmdclass={"build_ext": CustomBuildExt},
    license="MIT",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: 3.13",
        "Topic :: Scientific/Engineering",
        "Topic :: Scientific/Engineering :: Bio-Informatics",
        "Topic :: Scientific/Engineering :: Image Processing",
        "Topic :: Multimedia :: Video :: Conversion",
    ],
    package_data={
        "h5ffmpeg": ["*.so", "*.dll", "*.dylib", "*.pyd"],
    },
    include_package_data=True,
    zip_safe=False,
)
