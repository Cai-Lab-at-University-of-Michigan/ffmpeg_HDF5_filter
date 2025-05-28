@echo off
setlocal enabledelayedexpansion

:: ----------------------------------------------------------------------------
:: Set up directories
set "HOME=D:\a"
set "FFMPEG_ROOT=%HOME%\ffmpeg_build"
set "HDF5_ROOT=%HOME%\ffmpeg_build"
set "TEMP_BUILD=%HOME%\temp_build"

:: Create required directories
for %%D in ("%FFMPEG_ROOT%" "%FFMPEG_ROOT%\bin" "%FFMPEG_ROOT%\lib" "%FFMPEG_ROOT%\include" "%TEMP_BUILD%") do (
    if not exist %%D mkdir %%D
)

cd /D "%TEMP_BUILD%"

:: ----------------------------------------------------------------------------
:: Check if 7-Zip is available
7z | find "7-Zip" >nul
if errorlevel 1 (
    echo ❌ 7-Zip not found in PATH.
    exit /b 1
)

:: ----------------------------------------------------------------------------
:: Download and extract HDF5 (MSVC-compatible)
echo 📥 Downloading HDF5 for MSVC...
curl -L --retry 3 --retry-delay 5 ^
  https://github.com/HDFGroup/hdf5/releases/download/hdf5_1.14.6/hdf5-1.14.6-win-vs2022_cl.zip ^
  -o hdf5-msvc.zip

echo 📦 Extracting outer HDF5 zip...
7z x hdf5-msvc.zip -ohdf5_outer

:: Go into nested hdf5 folder
pushd hdf5_outer\hdf5

:: ----------------------------------------------------------------------------
:: Extract inner HDF5 zip
echo 🔍 Looking for inner zip file...
set "found_zip=false"
for %%F in (*.zip) do (
    echo 📦 Extracting inner zip: %%F
    7z x "%%F" -ohdf5_msvc
    set found_zip=true
    goto :after_hdf5_unzip
)

:after_hdf5_unzip
if not !found_zip! == true (
    echo ❌ No inner zip file found inside hdf5_outer\hdf5!
    dir /B
    exit /b 1
)

:: ----------------------------------------------------------------------------
:: Copy headers, libs, DLLs
for /D %%D in (hdf5_msvc\HDF5-*-win64) do (
    echo 📁 Copying HDF5 files from %%D...
    xcopy /E /I /Q /Y "%%D\include\*" "%FFMPEG_ROOT%\include\"
    xcopy /E /I /Q /Y "%%D\lib\*" "%FFMPEG_ROOT%\lib\"
    xcopy /E /I /Q /Y "%%D\bin\*.dll" "%FFMPEG_ROOT%\bin\"
)

popd

:: ----------------------------------------------------------------------------
:: Download and extract FFmpeg (MSVC-compatible)
echo 📥 Downloading FFmpeg for MSVC...
curl -L --retry 3 --retry-delay 5 ^
  https://github.com/GyanD/codexffmpeg/releases/download/7.1.1/ffmpeg-7.1.1-full_build-shared.zip ^
  -o ffmpeg-msvc.zip

echo 📦 Extracting FFmpeg...
7z x ffmpeg-msvc.zip -offmpeg_msvc

:: ----------------------------------------------------------------------------
:: Copy FFmpeg headers, libs, DLLs
for /D %%D in (ffmpeg_msvc\ffmpeg-*-full_build-shared) do (
    echo 📁 Copying FFmpeg files from %%D...
    xcopy /E /I /Q /Y "%%D\include\*" "%FFMPEG_ROOT%\include\"
    xcopy /E /I /Q /Y "%%D\lib\*" "%FFMPEG_ROOT%\lib\"
    xcopy /E /I /Q /Y "%%D\bin\*.dll" "%FFMPEG_ROOT%\bin\"
)

:: ----------------------------------------------------------------------------
:: Done
echo.
echo ✅ Prebuilt library setup complete!
echo 🔧 Installed to: %FFMPEG_ROOT%
echo.
dir /S /B "%FFMPEG_ROOT%"