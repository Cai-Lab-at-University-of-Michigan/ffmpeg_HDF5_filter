# FFmpeg Build Script for Windows (GitHub Actions Runner)
# PowerShell version of the bash script

param(
    [switch]$Verbose = $false
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Console output colors
$RED = "Red"
$GREEN = "Green"
$YELLOW = "Yellow"

# Logging functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $GREEN
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $YELLOW
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $RED
}

# Initialize build directories
$ROOT_DIR = Get-Location
$BUILD_DIR = Join-Path $ROOT_DIR "ffmpeg_build"
$SRC_DIR = Join-Path $ROOT_DIR "ffmpeg_src" 

# Create directories
New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $SRC_DIR -Force | Out-Null

Write-Info "Building FFmpeg in $BUILD_DIR"
Write-Info "Source code will be in $SRC_DIR"

# Detect number of CPU cores for parallel builds
$NPROC = $env:NUMBER_OF_PROCESSORS
if (-not $NPROC) { $NPROC = 4 }
Write-Info "Using $NPROC CPU cores for build"

function Setup-VSEnvironment {
    Write-Info "Setting up Visual Studio environment..."
    
    # GitHub Actions Windows runners have VS 2022 Enterprise pre-installed
    $vsPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional", 
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise"
    )
    
    $vsPath = $null
    foreach ($path in $vsPaths) {
        $vcvarsPath = Join-Path $path "VC\Auxiliary\Build\vcvars64.bat"
        if (Test-Path $vcvarsPath) {
            $vsPath = $path
            break
        }
    }
    
    if (-not $vsPath) {
        Write-Error "Visual Studio not found or missing vcvars64.bat"
        exit 1
    }
    
    Write-Info "Found Visual Studio at: $vsPath"
    
    # Store VS path for use in other functions
    $global:VS_PATH = $vsPath
    $global:VCVARS_PATH = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    
    Write-Info "Visual Studio environment ready"
}

function Install-Dependencies {
    Write-Info "Installing build dependencies..."
    
    # Check if running in GitHub Actions
    if ($env:GITHUB_ACTIONS -eq "true") {
        Write-Info "Running in GitHub Actions - using pre-installed tools where possible"
        
        # Install additional tools via Chocolatey
        $chocoPackages = @("nasm", "cmake", "ninja")
        
        foreach ($package in $chocoPackages) {
            if (-not (Get-Command $package -ErrorAction SilentlyContinue)) {
                Write-Info "Installing $package..."
                choco install -y $package
            } else {
                Write-Info "$package already available"
            }
        }
    } else {
        # Install all dependencies via Chocolatey for local builds
        Write-Info "Installing build tools via Chocolatey..."
        $packages = @("nasm", "cmake", "ninja", "git")
        
        foreach ($package in $packages) {
            if (-not (Get-Command $package -ErrorAction SilentlyContinue)) {
                Write-Info "Installing $package..."
                choco install -y $package
            }
        }
    }
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Verify tool installations
    Write-Info "Verifying tool installations..."
    try {
        & nasm -v
        & cmake --version
        & ninja --version
        Write-Info "All build tools verified successfully"
    } catch {
        Write-Error "Some build tools are not properly installed: $_"
        exit 1
    }
}

function Invoke-VSCommand {
    param(
        [string]$Command,
        [string]$WorkingDirectory = (Get-Location)
    )
    
    $batchScript = @"
@echo off
call "$global:VCVARS_PATH"
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment
    exit /b 1
)
cd /d "$WorkingDirectory"
$Command
"@
    
    $tempBat = [System.IO.Path]::GetTempFileName() + ".bat"
    $batchScript | Out-File -FilePath $tempBat -Encoding ASCII
    
    try {
        $result = & cmd.exe /c $tempBat
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
        return $result
    } finally {
        Remove-Item $tempBat -ErrorAction SilentlyContinue
    }
}

function Get-GitRepo {
    param(
        [string]$RepoUrl,
        [string]$TargetDir,
        [int]$Depth = 1
    )
    
    if (-not (Test-Path $TargetDir)) {
        Write-Info "Cloning repository: $RepoUrl"
        & git clone --depth $Depth $RepoUrl $TargetDir
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone $RepoUrl"
        }
    } else {
        Write-Info "Repository already exists: $TargetDir. Updating..."
        Push-Location $TargetDir
        try {
            & git pull
        } finally {
            Pop-Location
        }
    }
}

function Build-X264 {
    Write-Info "Building x264 from source..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://code.videolan.org/videolan/x264.git" "x264"
        Push-Location "x264"
        
        try {
            # Configure and build x264
            $configureCmd = "bash configure --prefix=`"$BUILD_DIR`" --enable-shared --enable-pic --disable-cli"
            Invoke-VSCommand $configureCmd
            
            $buildCmd = "make -j$NPROC && make install"
            Invoke-VSCommand $buildCmd
            
            Write-Info "x264 build completed"
        } finally {
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-X265 {
    Write-Info "Building x265 from source..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://bitbucket.org/multicoreware/x265_git.git" "x265"
        Push-Location "x265"
        New-Item -ItemType Directory -Path "build" -Force | Out-Null
        Push-Location "build"
        
        try {
            $cmakeCmd = @"
cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_SHARED=ON ^
    -DHIGH_BIT_DEPTH=ON ^
    -DMAIN10=ON ^
    -DMAIN12=ON ^
    ../source && cmake --build . --config Release --target install
"@
            Invoke-VSCommand $cmakeCmd
            
            Write-Info "x265 build completed"
        } finally {
            Pop-Location
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-DAV1D {
    Write-Info "Building dav1d from source..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://code.videolan.org/videolan/dav1d.git" "dav1d"
        Push-Location "dav1d"
        New-Item -ItemType Directory -Path "build" -Force | Out-Null
        Push-Location "build"
        
        try {
            # Install meson if not available
            if (-not (Get-Command meson -ErrorAction SilentlyContinue)) {
                Write-Info "Installing meson..."
                pip install meson
            }
            
            $mesonCmd = "meson setup --prefix=`"$BUILD_DIR`" --libdir=lib --default-library=shared .. && ninja && ninja install"
            Invoke-VSCommand $mesonCmd
            
            Write-Info "dav1d build completed"
        } finally {
            Pop-Location
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-LibAOM {
    Write-Info "Building libaom from source..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://aomedia.googlesource.com/aom" "aom"
        Push-Location "aom"
        New-Item -ItemType Directory -Path "build" -Force | Out-Null
        Push-Location "build"
        
        try {
            $cmakeCmd = @"
cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_TESTS=OFF ^
    -DENABLE_EXAMPLES=OFF ^
    .. && cmake --build . --config Release --target install
"@
            Invoke-VSCommand $cmakeCmd
            
            Write-Info "libaom build completed"
        } finally {
            Pop-Location
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-Rav1e {
    Write-Info "Building rav1e from source..."
    Push-Location $SRC_DIR
    
    try {
        # Install Rust if not available
        if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
            Write-Info "Installing Rust..."
            Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile "rustup-init.exe"
            ./rustup-init.exe -y --default-toolchain stable
            $env:Path += ";$env:USERPROFILE\.cargo\bin"
        }
        
        Get-GitRepo "https://github.com/xiph/rav1e.git" "rav1e"
        Push-Location "rav1e"
        
        try {
            # Install cargo-c
            & cargo install cargo-c
            
            # Build rav1e C API
            & cargo cinstall --release --prefix="$BUILD_DIR" --libdir="$BUILD_DIR\lib" --includedir="$BUILD_DIR\include" --library-type=cdylib
            
            Write-Info "rav1e build completed"
        } finally {
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-SVTAV1 {
    Write-Info "Building SVT-AV1 from source..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://gitlab.com/AOMediaCodec/SVT-AV1.git" "svtav1"
        Push-Location "svtav1"
        New-Item -ItemType Directory -Path "build" -Force | Out-Null
        Push-Location "build"
        
        try {
            $cmakeCmd = @"
cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON ^
    .. && cmake --build . --config Release --target install
"@
            Invoke-VSCommand $cmakeCmd
            
            Write-Info "SVT-AV1 build completed"
        } finally {
            Pop-Location
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-OneVPL {
    Write-Info "Building Intel oneVPL for QSV support..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://github.com/intel/libvpl.git" "oneVPL"
        Push-Location "oneVPL"
        New-Item -ItemType Directory -Path "build" -Force | Out-Null
        Push-Location "build"
        
        try {
            $cmakeCmd = @"
cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DBUILD_TOOLS=OFF ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_TESTS=OFF ^
    .. && cmake --build . --config Release --target install
"@
            Invoke-VSCommand $cmakeCmd
            
            # Setup compatibility symlinks
            $vplInclude = Join-Path $BUILD_DIR "include\vpl"
            $mfxInclude = Join-Path $BUILD_DIR "include\mfx"
            
            if (Test-Path $vplInclude) {
                New-Item -ItemType Directory -Path $mfxInclude -Force | Out-Null
                Copy-Item "$vplInclude\*" $mfxInclude -Recurse -Force
            }
            
            Write-Info "Intel oneVPL build completed"
        } finally {
            Pop-Location
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Setup-NVENCHeaders {
    Write-Info "Setting up NVIDIA encoder headers..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://git.videolan.org/git/ffmpeg/nv-codec-headers.git" "nv-codec-headers"
        Push-Location "nv-codec-headers"
        
        try {
            $nvcodecInclude = Join-Path $BUILD_DIR "include\ffnvcodec"
            New-Item -ItemType Directory -Path $nvcodecInclude -Force | Out-Null
            Copy-Item "include\ffnvcodec\*.h" $nvcodecInclude -Force
            
            Write-Info "NVIDIA encoder headers installed successfully"
        } finally {
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Build-Xvid {
    Write-Info "Building Xvid..."
    Push-Location $SRC_DIR
    
    try {
        # Create directory and download
        New-Item -ItemType Directory -Path "xvidcore" -Force | Out-Null
        Push-Location "xvidcore"
        
        try {
            Write-Info "Downloading Xvid..."
            Invoke-WebRequest -Uri "https://downloads.xvid.com/downloads/xvidcore-1.3.7.zip" -OutFile "xvidcore-1.3.7.zip"
            Expand-Archive -Path "xvidcore-1.3.7.zip" -DestinationPath "." -Force
            
            Push-Location "xvidcore\build\generic"
            
            try {
                # Build using MSVC
                $buildCmd = @"
nmake /f makefile.vc CFG=Win32-General-Release &&
xcopy "..\..\..\bin\release" "$BUILD_DIR\bin\" /Y /E &&
xcopy "..\..\..\lib" "$BUILD_DIR\lib\" /Y /E &&
xcopy "..\..\..\include" "$BUILD_DIR\include\" /Y /E
"@
                Invoke-VSCommand $buildCmd
                
                Write-Info "Xvid build completed"
            } finally {
                Pop-Location
            }
        } finally {
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function New-PkgConfigFiles {
    Write-Info "Generating pkg-config files..."
    
    $pkgConfigDir = Join-Path $BUILD_DIR "lib\pkgconfig"
    New-Item -ItemType Directory -Path $pkgConfigDir -Force | Out-Null
    
    # Create pkg-config files for each library
    $pkgConfigs = @{
        "x264.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib  
includedir=`${prefix}/include

Name: x264
Description: x264 library
Version: 0.164.3094
Libs: -L`${libdir} -lx264
Cflags: -I`${includedir}
"@
        "x265.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: x265
Description: x265 library  
Version: 3.5
Libs: -L`${libdir} -lx265
Cflags: -I`${includedir}
"@
        "dav1d.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: dav1d
Description: AV1 decoder
Version: 1.0.0
Libs: -L`${libdir} -ldav1d
Cflags: -I`${includedir}
"@
        "aom.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: aom
Description: AOM AV1 codec library
Version: 3.5.0
Libs: -L`${libdir} -laom
Cflags: -I`${includedir}
"@
        "rav1e.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: rav1e
Description: The fastest and safest AV1 encoder
Version: 0.6.0
Libs: -L`${libdir} -lrav1e
Cflags: -I`${includedir}
"@
        "SvtAv1Enc.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: SvtAv1Enc
Description: SVT-AV1 Encoder
Version: 1.8.0
Libs: -L`${libdir} -lSvtAv1Enc
Cflags: -I`${includedir}
"@
        "xvid.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: xvid
Description: Xvid MPEG-4 video codec
Version: 1.3.7
Libs: -L`${libdir} -lxvidcore
Cflags: -I`${includedir}
"@
        "libvpl.pc" = @"
prefix=$BUILD_DIR
exec_prefix=`${prefix}
libdir=`${prefix}/lib
includedir=`${prefix}/include

Name: libvpl
Description: Intel oneAPI Video Processing Library
Version: 2.8.0
Libs: -L`${libdir} -lvpl
Cflags: -I`${includedir}
"@
    }
    
    foreach ($file in $pkgConfigs.Keys) {
        $filePath = Join-Path $pkgConfigDir $file
        $pkgConfigs[$file] | Out-File -FilePath $filePath -Encoding UTF8
    }
    
    Write-Info "pkg-config files generated successfully"
}

function Build-FFmpeg {
    Write-Info "Building FFmpeg..."
    Push-Location $SRC_DIR
    
    try {
        Get-GitRepo "https://github.com/FFmpeg/FFmpeg.git" "ffmpeg"
        Push-Location "ffmpeg"
        
        try {
            # Set environment variables
            $env:PATH += ";$BUILD_DIR\bin"
            $env:PKG_CONFIG_PATH = Join-Path $BUILD_DIR "lib\pkgconfig"
            
            # Configure FFmpeg
            $configureCmd = @"
bash configure \
  --toolchain=msvc \
  --prefix="$BUILD_DIR" \
  --enable-shared \
  --disable-static \
  --disable-debug \
  --enable-gpl \
  --enable-version3 \
  --enable-nonfree \
  --enable-asm \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libaom \
  --enable-libdav1d \
  --enable-librav1e \
  --enable-libsvtav1 \
  --enable-libvpl \
  --enable-libxvid \
  --enable-nvenc \
  --extra-cflags="-I$BUILD_DIR/include" \
  --extra-ldflags="-LIBPATH:$BUILD_DIR/lib"
"@
            
            Write-Info "Configuring FFmpeg..."
            Invoke-VSCommand $configureCmd
            
            Write-Info "Building FFmpeg..."
            $buildCmd = "nmake -j $NPROC && nmake install"
            Invoke-VSCommand $buildCmd
            
            Write-Info "FFmpeg build completed"
        } finally {
            Pop-Location
        }
    } finally {
        Pop-Location
    }
}

function Test-Build {
    Write-Info "Verifying FFmpeg build..."
    
    $ffmpegExe = Join-Path $BUILD_DIR "bin\ffmpeg.exe"
    
    if (-not (Test-Path $ffmpegExe)) {
        Write-Error "FFmpeg executable not found at $ffmpegExe"
        Get-ChildItem (Join-Path $BUILD_DIR "bin") -ErrorAction SilentlyContinue
        exit 1
    }
    
    Write-Info "FFmpeg executable found successfully"
    
    # Test FFmpeg version
    try {
        & $ffmpegExe -version
        Write-Info "FFmpeg version check passed"
    } catch {
        Write-Error "Failed to run FFmpeg executable: $_"
        exit 1
    }
    
    # Check for DLLs
    $dllCount = (Get-ChildItem (Join-Path $BUILD_DIR "bin") -Filter "*.dll").Count
    Write-Info "Found $dllCount DLL files"
    
    # Check for headers
    $codecHeaders = Join-Path $BUILD_DIR "include\libavcodec"
    $utilHeaders = Join-Path $BUILD_DIR "include\libavutil"
    
    if (-not (Test-Path $codecHeaders) -or -not (Test-Path $utilHeaders)) {
        Write-Error "FFmpeg headers not found"
        exit 1
    }
    
    Write-Info "FFmpeg headers verified"
    
    # Check encoders
    Write-Info "Checking encoder support..."
    try {
        $encoders = & $ffmpegExe -encoders 2>$null
        
        if ($encoders -match "nvenc") {
            Write-Info "NVENC support detected"
        } else {
            Write-Warning "No NVENC encoders found"
        }
        
        if ($encoders -match "qsv") {
            Write-Info "QSV support detected"
        } else {
            Write-Warning "No QSV encoders found"
        }
        
        if ($encoders -match "av1") {
            Write-Info "AV1 support detected"
        } else {
            Write-Warning "No AV1 encoders found"
        }
    } catch {
        Write-Warning "Could not check encoder support: $_"
    }
    
    Write-Info "FFmpeg build verification completed successfully"
}

# Main execution
function Main {
    Write-Info "Starting FFmpeg build for Windows using PowerShell..."
    
    try {
        # Setup environment
        Setup-VSEnvironment
        Install-Dependencies
        
        # Build dependencies
        Build-OneVPL
        Build-X264
        Build-X265
        Build-DAV1D
        Build-LibAOM
        Build-Xvid
        Build-SVTAV1
        Build-Rav1e
        Setup-NVENCHeaders
        New-PkgConfigFiles
        
        # Build FFmpeg
        Build-FFmpeg
        
        # Verify build
        Test-Build
        
        Write-Info "======================================="
        Write-Info "FFmpeg build successful!"
        Write-Info "FFmpeg binaries: $BUILD_DIR\bin"
        Write-Info "FFmpeg libraries: $BUILD_DIR\lib"
        Write-Info "FFmpeg headers: $BUILD_DIR\include"
        Write-Info "======================================="
        
        # Create completion marker
        New-Item -ItemType File -Path (Join-Path $BUILD_DIR ".build_completed") -Force | Out-Null
        
    } catch {
        Write-Error "Build failed: $_"
        Write-Error $_.ScriptStackTrace
        exit 1
    }
}

# Execute main function
Main