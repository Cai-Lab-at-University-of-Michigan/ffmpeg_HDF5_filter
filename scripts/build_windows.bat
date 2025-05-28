@echo off
setlocal enabledelayedexpansion

:: Set paths
set HOME=D:\a
set FFMPEG_ROOT=%HOME%\ffmpeg_build

:: Create required directories
for %%D in (%FFMPEG_ROOT% %FFMPEG_ROOT%\bin %FFMPEG_ROOT%\lib %FFMPEG_ROOT%\include %HOME%\temp_build) do (
    if not exist "%%D" mkdir "%%D"
)

cd /D %HOME%\temp_build

:: ----------------------------------------------------------------------------
:: Download and extract HDF5 (MSVC-compatible)
echo Downloading HDF5 for MSVC...
curl -L --retry 3 --retry-delay 5 ^
  https://github.com/HDFGroup/hdf5/releases/download/hdf5_1.14.6/hdf5-1.14.6-win-vs2022_cl.zip ^
  -o hdf5-msvc.zip

:: First unzip: outer archive
7z x hdf5-msvc.zip -ohdf5_outer

:: Second unzip: nested HDF5 zip file
for %%F in (hdf5_outer\*.zip) do (
    7z x "%%F" -ohdf5_msvc
)

:: Copy headers, libs, DLLs
for /D %%D in (hdf5_msvc\HDF5-*-win64) do (
    xcopy "%%D\include\*" %FFMPEG_ROOT%\include\ /E /I /Q
    xcopy "%%D\lib\*" %FFMPEG_ROOT%\lib\ /E /I /Q
    xcopy "%%D\bin\*.dll" %FFMPEG_ROOT%\bin\ /E /I /Q
)

:: ----------------------------------------------------------------------------
:: Download and extract FFmpeg (MSVC-compatible)
echo Downloading FFmpeg for MSVC...
curl -L --retry 3 --retry-delay 5 ^
  https://github.com/GyanD/codexffmpeg/releases/download/7.1.1/ffmpeg-7.1.1-full_build-shared.zip ^
  -o ffmpeg-msvc.zip

7z x ffmpeg-msvc.zip -offmpeg_msvc

for /D %%D in (ffmpeg_msvc\ffmpeg-*-full_build-shared) do (
    xcopy "%%D\include\*" %FFMPEG_ROOT%\include\ /E /I /Q
    xcopy "%%D\lib\*" %FFMPEG_ROOT%\lib\ /E /I /Q
    xcopy "%%D\bin\*.dll" %FFMPEG_ROOT%\bin\ /E /I /Q
)

:: ----------------------------------------------------------------------------
echo.
echo ✅ Prebuilt library setup complete!
echo 🔧 Installed to: %FFMPEG_ROOT%
echo.
dir /S /B %FFMPEG_ROOT%