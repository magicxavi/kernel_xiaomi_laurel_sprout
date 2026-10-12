#!/bin/bash

# Colors
green='\033[01;32m'
red='\033[01;31m'
blink_red='\033[05;31m'
cyan='\033[0;36m'
yellow='\033[0;33m'
blue='\033[0;34m'
default='\033[0m'

# Define variables
CLANG_VER="${CLANG_VER:-clang-r574158}"
ROM_PATH="${ROM_PATH:-$HOME/linux-x86}"
PCLANG_DIR="$ROM_PATH/$CLANG_VER"
CLANG_PATH_FILE="$HOME/.clang_path"
KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Anykernel_DIR="$KERNEL_DIR/AnyKernel3"
DEFCONFIG="vendor/laurel_sprout-perf_defconfig"
DATE=$(date +"[%d%m%Y]")
TIME=$(date +"%H.%M.%S")
KERNEL_NAME="NoName"
DEVICE="MI_A3"
ANDROID_VER="[a12+]"
KERNEL_SUBVER="[V9]"
FINAL_ZIP="$DEVICE-$KERNEL_NAME-$KERNEL_SUBVER-$ANDROID_VER-$DATE"
JOBS="$(nproc --all)"

# Initialize variables
USE_PCLANG=false
DIRTY=false
KEEP_OUT=false
CUSTOM_CLANG_DIR=""

display_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d             Dirty build (skip defconfig re-generation if .config exists)"
    echo "  -k             Keep out/ directory after build (default: clean out/ after compile)"
    echo "  -p             Use PCLANG_DIR ($PCLANG_DIR)"
    echo "  -c <path>      Specify custom Clang directory path"
    echo "  -j <jobs>      Number of parallel compile jobs (default: $JOBS)"
    echo "  -h             Show this help message"
}

# Parse flags
while getopts "pdkc:j:h" flag; do
    case "${flag}" in
        p) USE_PCLANG=true ;;
        d) DIRTY=true ;;
        k) KEEP_OUT=true ;;
        c) CUSTOM_CLANG_DIR="${OPTARG}" ;;
        j) JOBS="${OPTARG}" ;;
        h) display_usage; exit 0 ;;
        *) display_usage; exit 1 ;;
    esac
done

BUILD_START=$(date +"%s")

# Clean previous zip staging in AnyKernel3
rm -rf "$Anykernel_DIR"/MI_A3-NoName*.zip
rm -rf "$Anykernel_DIR/Image.gz-dtb"
rm -rf "$Anykernel_DIR/dtbo.img"

# Helper function to validate clang directory
validate_clang() {
    local dir="$1"
    if [ -n "$dir" ] && [ -d "$dir" ] && [ -x "$dir/bin/clang" ]; then
        echo "$dir"
        return 0
    fi
    return 1
}

# Determine CLANG_DIR
if [ -n "$CUSTOM_CLANG_DIR" ]; then
    if ! CLANG_DIR=$(validate_clang "$CUSTOM_CLANG_DIR"); then
        echo -e "${red}Error: Specified Clang directory '$CUSTOM_CLANG_DIR' does not contain bin/clang.${default}"
        exit 1
    fi
    echo -e "${blue}Using custom Clang directory: $CLANG_DIR${default}"
elif $USE_PCLANG; then
    if ! CLANG_DIR=$(validate_clang "$PCLANG_DIR"); then
        echo -e "${red}Error: PCLANG_DIR $PCLANG_DIR does not exist or has no bin/clang. Exiting.${default}"
        exit 1
    fi
    echo -e "${blue}Using PCLANG_DIR: $CLANG_DIR${default}"
else
    # 1. Check saved CLANG_PATH_FILE if matching CLANG_VER
    if [ -f "$CLANG_PATH_FILE" ]; then
        SAVED_DIR=$(cat "$CLANG_PATH_FILE" 2>/dev/null)
        if CLANG_DIR=$(validate_clang "$SAVED_DIR"); then
            if [ "$(basename "$CLANG_DIR")" = "$CLANG_VER" ]; then
                echo -e "${blue}Using cached Clang: $CLANG_DIR${default}"
            else
                echo -e "${yellow}Cached Clang ($(basename "$CLANG_DIR")) differs from $CLANG_VER. Searching...${default}"
                CLANG_DIR=""
            fi
        else
            CLANG_DIR=""
        fi
    fi

    # 2. Check candidate locations quickly without slow find
    if [ -z "$CLANG_DIR" ]; then
        CANDIDATES=(
            "$KERNEL_DIR/../../../prebuilts/clang/host/linux-x86/$CLANG_VER"
            "$KERNEL_DIR/../../prebuilts/clang/host/linux-x86/$CLANG_VER"
            "${ANDROID_BUILD_TOP:-}/prebuilts/clang/host/linux-x86/$CLANG_VER"
            "/home/magicxavi/drive1/pos162/prebuilts/clang/host/linux-x86/$CLANG_VER"
            "/home/magicxavi/drive1/crDroid16/prebuilts/clang/host/linux-x86/$CLANG_VER"
            "$ROM_PATH/$CLANG_VER"
            "$HOME/linux-x86/$CLANG_VER"
            "$HOME/prebuilts/clang/host/linux-x86/$CLANG_VER"
        )

        for cand in "${CANDIDATES[@]}"; do
            if CLANG_DIR=$(validate_clang "$cand"); then
                CLANG_DIR=$(realpath "$CLANG_DIR")
                echo -e "${green}Found $CLANG_VER at: $CLANG_DIR${default}"
                break
            fi
        done
    fi

    # 3. Constrained shallow search as fallback (avoid scanning whole / or multi-TB roots)
    if [ -z "$CLANG_DIR" ]; then
        echo -e "${yellow}Searching for $CLANG_VER in common drive directories...${default}"
        SEARCH_PATHS=()
        [ -d "$HOME/drive1" ] && SEARCH_PATHS+=("$HOME/drive1")
        [ -d "$HOME/drive2" ] && SEARCH_PATHS+=("$HOME/drive2")
        [ -d "$HOME" ] && SEARCH_PATHS+=("$HOME")

        for sp in "${SEARCH_PATHS[@]}"; do
            FOUND=$(find "$sp" -maxdepth 6 -type d -name "$CLANG_VER" 2>/dev/null | head -n 1)
            if CLANG_DIR=$(validate_clang "$FOUND"); then
                CLANG_DIR=$(realpath "$CLANG_DIR")
                echo -e "${green}Found $CLANG_VER at: $CLANG_DIR${default}"
                break
            fi
        done
    fi

    if [ -z "$CLANG_DIR" ]; then
        echo -e "${red}Error: $CLANG_VER not found. Please specify using -c <path> or set CLANG_DIR.${default}"
        exit 1
    fi

    # Save resolved path
    echo "$CLANG_DIR" > "$CLANG_PATH_FILE"
fi

# Export variables
export TARGET_KERNEL_CLANG_COMPILE=true
export PATH="$CLANG_DIR/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64

# Suppress newer Clang compiler warnings from turning into -Werror in techpack drivers
KCFLAGS="${KCFLAGS:--Wno-error -Wno-implicit-enum-enum-cast}"

echo -e "***********************************************"
echo -e "          Compiling $KERNEL_NAME Kernel              "
echo -e "          Clang: $($CLANG_DIR/bin/clang --version | head -n 1)"
echo -e "***********************************************"

mkdir -p "$KERNEL_DIR/out"

# Generate defconfig if not dirty build or .config is missing
if ! $DIRTY || [ ! -f "$KERNEL_DIR/out/.config" ]; then
    echo -e "${blue}Generating defconfig ($DEFCONFIG)...${default}"
    make O=out ARCH=arm64 "$DEFCONFIG" || {
        echo -e "${red}Error: Failed to configure kernel with $DEFCONFIG.${default}"
        exit 1
    }
else
    echo -e "${yellow}Dirty build requested (-d): reusing existing out/.config${default}"
fi

# Finally build kernel and dtbo
echo -e "${blue}Building Image.gz-dtb and dtbo.img using $JOBS jobs...${default}"
make -j"$JOBS" O=out ARCH=arm64 \
    CC=clang \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE="$CLANG_DIR/bin/llvm-" \
    LLVM=1 LLVM_IAS=1 \
    KCFLAGS="$KCFLAGS" \
    Image.gz-dtb dtbo.img || {
        echo -e "${red}Error: Kernel compilation failed.${default}"
        exit 1
    }

# Verify output images exist
if [ ! -f "$KERNEL_DIR/out/arch/arm64/boot/Image.gz-dtb" ] || [ ! -f "$KERNEL_DIR/out/arch/arm64/boot/dtbo.img" ]; then
    echo -e "${red}Error: Kernel images were not found in out/arch/arm64/boot/. Build incomplete.${default}"
    exit 1
fi

echo -e "$yellow***********************************************"
echo "                Zipping Kernel                     "
echo -e "***********************************************"

# Create the flashable zip
cp -f "$KERNEL_DIR/out/arch/arm64/boot/Image.gz-dtb" "$Anykernel_DIR/"
cp -f "$KERNEL_DIR/out/arch/arm64/boot/dtbo.img" "$Anykernel_DIR/"
cd "$Anykernel_DIR" || exit 1
zip -r9 "$FINAL_ZIP.zip" * -x .git README.md *placeholder || {
    echo -e "${red}Error: Failed to create AnyKernel3 zip.${default}"
    cd "$KERNEL_DIR"
    exit 1
}

# Move flashable zip to KERNEL_DIR for convenience
mv -f "$FINAL_ZIP.zip" "$KERNEL_DIR/"
cd "$KERNEL_DIR" || exit 1

echo -e "$cyan***********************************************"
echo "                 Cleaning up                    "
echo -e "***********************************************$default"

# Clean staging images in AnyKernel3
rm -rf "$Anykernel_DIR/Image.gz-dtb"
rm -rf "$Anykernel_DIR/dtbo.img"

# Clean out directory after compile
if $KEEP_OUT; then
    echo -e "${green}Kept out/ directory (-k specified).${default}"
else
    echo -e "${yellow}Cleaning out/ directory...${default}"
    rm -rf "$KERNEL_DIR/out"
fi

# Build complete
BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "$green***********************************************"
echo -e " Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
echo -e " Flashable zip: $KERNEL_DIR/$FINAL_ZIP.zip"
echo -e "***********************************************$default"
