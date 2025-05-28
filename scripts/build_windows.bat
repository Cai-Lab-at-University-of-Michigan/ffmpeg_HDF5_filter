@echo off
setlocal enabledelayedexpansion

:: ----------------------------------------------------------------------------
:: Set up directories
set "HOME=D:\a"
set "FFMPEG_ROOT=%HOME%\ffmpeg_build"
set "TEMP_BUILD=%HOME%\temp_build"

:: Create required directories
for %%D in ("%FFMPEG_ROOT%" "%FFMPEG_ROOT%\bin" "%FFMPEG_ROOT%\lib" "%FFMPEG_ROOT%\include" "%TEMP_BUILD%") do (
    if not exist %%D mkdir %%D
)

cd /D "%TEMP_BUILD%"

:: ----------------------------------------------------------------------------
:: Download and extract HDF5 (MSVC-compatible)
echo Downloading HDF5 for MSVC...
curl -L --retry 3 --retry-delay 5 ^
  https://github.com/HDFGroup/hdf5/releases/download/hdf5_1.14.6/hdf5-1.14.6-win-vs2022_cl.zip ^
  -o hdf5-msvc.zip

7z x hdf5-msvc.zip -ohdf5_outer

pushd hdf5_outer

:: Extract nested zip (wildcard in case of version variation)
for %%F in (*.zip) do (
    7z x "%%F" -ohdf5_msvc
    goto :hdf5_unzipped
)
:hdf5_unzipped

for /D %%D in (hdf5_msvc\HDF5-*-win64) do (
    echo Copying HDF5 files from %%D...
    xcopy /E /I /Q /Y "%%D\include\*" "%FFMPEG_ROOT%\include\"
    xcopy /E /I /Q /Y "%%D\lib\*" "%FFMPEG_ROOT%\lib\"
    xcopy /E /I /Q /Y "%%D\bin\*.dll" "%FFMPEG_ROOT%\bin\"
)

popd

:: ----------------------------------------------------------------------------
:: Download and extract FFmpeg (MSVC-compatible)
echo Downloading FFmpeg for MSVC...
curl -L --retry 3 --retry-delay 5 ^
  https://github.com/GyanD/codexffmpeg/releases/download/7.1.1/ffmpeg-7.1.1-full_build-shared.zip ^
  -o ffmpeg-msvc.zip

7z x ffmpeg-msvc.zip -offmpeg_msvc

for /D %%D in (ffmpeg_msvc\ffmpeg-*-full_build-shared) do (
    echo Copying FFmpeg files from %%D...
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