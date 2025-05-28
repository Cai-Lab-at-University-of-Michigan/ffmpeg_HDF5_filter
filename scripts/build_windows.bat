:: build_ffmpeg_complete.bat
@echo off
setlocal enabledelayedexpansion

:: Set environment variables
set HOME=D:\a
set FFMPEG_ROOT=%HOME%\ffmpeg_build
set HDF5_ROOT=%HOME%\miniconda3\Library
set PKG_CONFIG_PATH=%FFMPEG_ROOT%\lib\pkgconfig;%HOME%\miniconda3\Library\lib\pkgconfig
set INCLUDE=%FFMPEG_ROOT%\include;%HOME%\miniconda3\Library\include
set LIB=%FFMPEG_ROOT%\lib;%HOME%\miniconda3\Library\lib

:: Download and setup Miniconda
echo Downloading Miniconda...
curl -L --retry 3 --retry-delay 5 https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe -o miniconda.exe
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to download Miniconda
    exit /b 1
)

echo Installing Miniconda...
miniconda.exe /InstallationType=JustMe /RegisterPython=0 /S /D=%HOME%\miniconda3

:: Configure conda
echo Setting up conda...
%HOME%\miniconda3\Scripts\conda.exe config --add channels conda-forge
%HOME%\miniconda3\Scripts\conda.exe config --add channels nvidia
%HOME%\miniconda3\Scripts\conda.exe config --set channel_priority strict
%HOME%\miniconda3\Scripts\conda.exe update -y conda

:: Install dependencies
echo Installing build dependencies...
%HOME%\miniconda3\Scripts\conda.exe install -y hdf5 hdf5-external-filter-plugins pkg-config cmake ninja nasm yasm git msys2-conda-epoch m2-base m2-autoconf m2-automake m2-libtool m2-make -c conda-forge
%HOME%\miniconda3\Scripts\conda.exe install -y wget x264 x265 libaom libvpx dav1d rav1e svt-av1 zlib bzip2 xz lz4 zstd -c conda-forge
%HOME%\miniconda3\Scripts\conda.exe install -y openssl -c conda-forge

:: Install CUDA if available
pip install nvidia-cuda-nvcc || echo CUDA libs not available

:: Create build directories
echo Creating build directories...
mkdir %FFMPEG_ROOT% 2>nul
mkdir %FFMPEG_ROOT%\bin 2>nul
mkdir %FFMPEG_ROOT%\lib 2>nul
mkdir %FFMPEG_ROOT%\include 2>nul
mkdir %HOME%\temp_build 2>nul

:: Setup build environment
set PKG_CONFIG_PATH=%HOME%\miniconda3\Library\lib\pkgconfig
set INCLUDE=%HOME%\miniconda3\Library\include;%INCLUDE%
set LIB=%HOME%\miniconda3\Library\lib;%LIB%
set PATH=%FFMPEG_ROOT%\bin;%HOME%\miniconda3\Library\bin;%HOME%\miniconda3\Scripts;%PATH%

cd /D %HOME%\temp_build

:: Configure git for large repos
echo Configuring git...
git config --global http.postBuffer 524288000
git config --global http.maxRequestBuffer 100M
git config --global core.compression 0

:: Build NVIDIA codec headers
echo Building NVIDIA codec headers...
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX="%FFMPEG_ROOT%"
cd /D %HOME%\temp_build

:: Download libvpl package manually
echo Downloading libvpl...
curl -L --retry 3 --retry-delay 5 https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libvpl-2.15.0-1-any.pkg.tar.zst -o libvpl.pkg.tar.zst

:: 7-Zip two-step extraction
7z x libvpl.pkg.tar.zst -olibvpl_extracted_zst
7z x libvpl_extracted_zst\*.tar -olibvpl_extracted_tar

:: Copy libraries, headers, DLLs, and pkg-config files
xcopy libvpl_extracted_tar\mingw64\lib\* %FFMPEG_ROOT%\lib\ /E /I /Q
xcopy libvpl_extracted_tar\mingw64\include\* %FFMPEG_ROOT%\include\ /E /I /Q
xcopy libvpl_extracted_tar\mingw64\bin\*.dll %FFMPEG_ROOT%\bin\ /I /Q
cd /D %HOME%\temp_build


:: Download ffmpeg package manually
echo Downloading ffmpeg...
curl -L --retry 3 --retry-delay 5 https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-ffmpeg-7.1.1-4-any.pkg.tar.zst -o ffmpeg.pkg.tar.zst

:: 7-Zip two-step extraction
7z x ffmpeg.pkg.tar.zst -offmpeg_extracted_zst
7z x ffmpeg_extracted_zst\*.tar -offmpeg_extracted_tar
dir /S /B ffmpeg_extracted_tar

:: Copy libraries, headers, DLLs, and pkg-config files
xcopy ffmpeg_extracted_tar\mingw64\lib\* %FFMPEG_ROOT%\lib\ /E /I /Q
xcopy ffmpeg_extracted_tar\mingw64\include\* %FFMPEG_ROOT%\include\ /E /I /Q
xcopy ffmpeg_extracted_tar\mingw64\bin\*.dll %FFMPEG_ROOT%\bin\ /I /Q

cd /D %FFMPEG_ROOT%
dir /S /B %FFMPEG_ROOT%