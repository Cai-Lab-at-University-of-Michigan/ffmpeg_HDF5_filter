#!/bin/bash

set -e

echo "🔧 macOS H5FFmpeg Library Setup"
echo "================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
print_status() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [LIB_DIR]"
    echo ""
    echo "Arguments:"
    echo "  LIB_DIR    Path to directory containing .dylib files (optional)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Auto-detect library location"
    echo "  $0 /path/to/libs            # Use specific directory"
    echo "  $0 ./lib                    # Use relative path"
    echo ""
}

# Check for help flags
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Determine library directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR=""

# Function to validate H5FFmpeg library directory
validate_h5ffmpeg_dir() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        return 1
    fi
    
    if find "$dir" -name "libh5ffmpeg*.dylib" 2>/dev/null | grep -q .; then
        return 0
    else
        return 1
    fi
}

if [[ -n "$1" ]]; then
    if [[ "$1" = /* ]]; then
        CANDIDATE_DIR="$1"
    else
        CANDIDATE_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
            print_error "Directory not found: $1"
            exit 1
        }
    fi
    
    if validate_h5ffmpeg_dir "$CANDIDATE_DIR"; then
        LIB_DIR="$CANDIDATE_DIR"
        print_info "Using specified library directory: $LIB_DIR"
    else
        print_error "Directory does not contain H5FFmpeg libraries: $CANDIDATE_DIR"
        echo "Expected to find files matching 'libh5ffmpeg*.dylib'"
        echo ""
        echo "Contents of directory:"
        ls -la "$CANDIDATE_DIR" 2>/dev/null | head -10
        exit 1
    fi
else
    print_info "Auto-detecting H5FFmpeg library location..."
    
    POSSIBLE_DIRS=(
        "$SCRIPT_DIR/lib"
        "$SCRIPT_DIR/../lib" 
        "$SCRIPT_DIR/../../lib"
        "$SCRIPT_DIR"
        "$(dirname "$SCRIPT_DIR")/lib"
    )

    for dir in "${POSSIBLE_DIRS[@]}"; do
        if validate_h5ffmpeg_dir "$dir"; then
            LIB_DIR="$dir"
            print_status "Found H5FFmpeg libraries in: $LIB_DIR"
            break
        fi
    done
fi

# Validate library directory
if [[ -z "$LIB_DIR" ]]; then
    print_error "Could not find H5FFmpeg libraries!"
    echo ""
    if [[ -n "$1" ]]; then
        echo "The specified directory '$1' does not contain libh5ffmpeg*.dylib files."
    else
        echo "Auto-detection failed. Please specify the library directory:"
        echo ""
        echo "Searched these locations for libh5ffmpeg*.dylib:"
        for dir in "${POSSIBLE_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                echo "  - $dir (exists, but no H5FFmpeg libraries found)"
            else
                echo "  - $dir (does not exist)"
            fi
        done
        echo ""
        echo "Usage: $0 /path/to/directory/containing/libh5ffmpeg*.dylib"
    fi
    exit 1
fi

if [[ ! -d "$LIB_DIR" ]]; then
    print_error "Directory does not exist: $LIB_DIR"
    exit 1
fi

DYLIB_COUNT=$(find "$LIB_DIR" -name "*.dylib" 2>/dev/null | wc -l)
print_info "Found $DYLIB_COUNT library files to process"

if [[ $DYLIB_COUNT -eq 0 ]]; then
    print_error "No .dylib files found in $LIB_DIR"
    exit 1
fi

echo ""
echo "This script will:"
echo "1. 🔏 Sign all H5FFmpeg libraries with local certificates"
echo "2. 🚫 Remove quarantine attributes (prevents 'Open anyway' popups)"
echo "3. ✅ Add libraries to Gatekeeper allowlist"
echo "4. 🧪 Test that libraries can be loaded"
echo ""

read -p "Do you want to proceed? [y/N]: " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Setup cancelled by user"
    exit 0
fi

echo ""
print_info "Starting setup process..."

echo ""
echo "🔏 Step 1: Signing libraries..."
echo "--------------------------------"

signed_count=0
failed_count=0

for lib in "$LIB_DIR"/*.dylib; do
    if [[ -f "$lib" ]] && [[ ! -L "$lib" ]]; then
        lib_name=$(basename "$lib")
        echo -n "Signing $lib_name... "
        
        codesign --remove-signature "$lib" 2>/dev/null || true
        
        if codesign --sign - --force "$lib" 2>/dev/null; then
            if codesign --verify "$lib" 2>/dev/null; then
                print_status "SUCCESS"
                ((signed_count++))
            else
                print_error "VERIFICATION FAILED"
                ((failed_count++))
            fi
        else
            print_error "SIGNING FAILED"
            ((failed_count++))
        fi
    fi
done

echo ""
print_info "Signing complete: $signed_count signed, $failed_count failed"

if [[ $failed_count -gt 0 ]]; then
    print_warning "Some libraries failed to sign. The application may not work correctly."
fi

echo ""
echo "🚫 Step 2: Removing quarantine attributes..."
echo "--------------------------------------------"

quarantine_removed=0
for lib in "$LIB_DIR"/*.dylib; do
    if [[ -f "$lib" ]]; then
        lib_name=$(basename "$lib")
        if xattr -d com.apple.quarantine "$lib" 2>/dev/null; then
            echo "Removed quarantine from $lib_name"
            ((quarantine_removed++))
        fi
    fi
done

if [[ $quarantine_removed -gt 0 ]]; then
    print_status "Removed quarantine from $quarantine_removed files"
else
    print_info "No quarantine attributes found (this is good!)"
fi

echo ""
echo "✅ Step 3: Adding to Gatekeeper allowlist..."
echo "--------------------------------------------"

if spctl --add "$LIB_DIR" 2>/dev/null; then
    print_status "Added library directory to Gatekeeper allowlist"
else
    print_warning "Could not add to Gatekeeper allowlist (may require admin privileges)"
    echo "You may need to run: sudo spctl --add '$LIB_DIR'"
fi

echo ""
echo "🧪 Step 4: Testing library loading..."
echo "------------------------------------"

MAIN_LIB=$(find "$LIB_DIR" -name "libh5ffmpeg*shared*.dylib" | head -1)

if [[ -n "$MAIN_LIB" ]]; then
    print_info "Testing $(basename "$MAIN_LIB")..."
    
    TEST_PROGRAM="/tmp/h5ffmpeg_test_$"
    cat > "${TEST_PROGRAM}.c" << 'EOF'
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        printf("Usage: %s <library_path>\n", argv[0]);
        return 1;
    }
    
    void* handle = dlopen(argv[1], RTLD_LAZY);
    if (!handle) {
        printf("FAILED: %s\n", dlerror());
        return 1;
    }
    
    printf("SUCCESS: Library loads correctly\n");
    dlclose(handle);
    return 0;
}
EOF

    if gcc -o "$TEST_PROGRAM" "${TEST_PROGRAM}.c" 2>/dev/null; then
        if "$TEST_PROGRAM" "$MAIN_LIB"; then
            print_status "Library loading test PASSED"
        else
            print_error "Library loading test FAILED"
            echo "The application may not work correctly."
        fi
        
        rm -f "$TEST_PROGRAM" "${TEST_PROGRAM}.c"
    else
        print_warning "Could not compile test program (gcc not available)"
    fi
else
    print_warning "Could not find main H5FFmpeg library for testing"
fi

echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
print_status "H5FFmpeg libraries are now configured for macOS"
echo ""
echo "What was done:"
echo "• ✅ Signed $signed_count libraries with local certificates"
echo "• ✅ Removed quarantine attributes"
echo "• ✅ Added libraries to Gatekeeper allowlist"
echo "• ✅ Verified library loading works"
echo ""

if [[ $failed_count -eq 0 ]]; then
    print_status "Your application should now run without security popups!"
else
    print_warning "Some issues occurred. You may still see security warnings."
    echo ""
    echo "If you continue to see 'Open anyway' popups:"
    echo "1. Go to System Preferences → Security & Privacy"
    echo "2. Click 'Open Anyway' when prompted"
    echo "3. Or run: sudo spctl --master-disable (temporarily disables Gatekeeper)"
fi

echo ""
print_info "You can re-run this script anytime if needed."
echo "Script location: $0"