#!/bin/zsh
set -euo pipefail

FFMPEG_VERSION="8.1.2"
PROJECT_ROOT="${0:A:h:h}"
VENDOR_DIR="$PROJECT_ROOT/Vendor/FFmpeg"
SOURCE_ARCHIVE="$VENDOR_DIR/Source/ffmpeg-$FFMPEG_VERSION.tar.xz"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
BUILD_ROOT="${TMPDIR:-/tmp}/macconvert-ffmpeg-$FFMPEG_VERSION"
TOOLS_DIR="$PROJECT_ROOT/MacConvert/Resources/Tools"
NOTICE_DIR="$PROJECT_ROOT/MacConvert/Resources/FFmpeg"
MINIMUM_MACOS="14.0"

mkdir -p "$VENDOR_DIR/Source" "$TOOLS_DIR" "$NOTICE_DIR"

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    curl --fail --location --output "$SOURCE_ARCHIVE" "$SOURCE_URL"
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/source"
tar -xf "$SOURCE_ARCHIVE" -C "$BUILD_ROOT/source" --strip-components=1

build_architecture() {
    local architecture="$1"
    local build_dir="$BUILD_ROOT/build-$architecture"
    local install_dir="$BUILD_ROOT/install-$architecture"
    local extra_options=()

    if [[ "$architecture" == "x86_64" ]] && ! command -v nasm >/dev/null && ! command -v yasm >/dev/null; then
        extra_options+=(--disable-x86asm)
    fi

    mkdir -p "$build_dir"
    cd "$build_dir"
    "$BUILD_ROOT/source/configure" \
        --prefix="$install_dir" \
        --target-os=darwin \
        --arch="$architecture" \
        --cc=clang \
        --disable-gpl \
        --disable-nonfree \
        --disable-doc \
        --disable-debug \
        --disable-ffplay \
        --disable-shared \
        --enable-static \
        --enable-ffmpeg \
        --enable-ffprobe \
        --enable-audiotoolbox \
        --extra-cflags="-arch $architecture -mmacosx-version-min=$MINIMUM_MACOS" \
        --extra-ldflags="-arch $architecture -mmacosx-version-min=$MINIMUM_MACOS" \
        "${extra_options[@]}"
    make -j8
    make install
}

build_architecture arm64
build_architecture x86_64

lipo -create \
    "$BUILD_ROOT/install-arm64/bin/ffmpeg" \
    "$BUILD_ROOT/install-x86_64/bin/ffmpeg" \
    -output "$TOOLS_DIR/ffmpeg"
lipo -create \
    "$BUILD_ROOT/install-arm64/bin/ffprobe" \
    "$BUILD_ROOT/install-x86_64/bin/ffprobe" \
    -output "$TOOLS_DIR/ffprobe"

chmod 755 "$TOOLS_DIR/ffmpeg" "$TOOLS_DIR/ffprobe"
cp "$BUILD_ROOT/source/COPYING.LGPLv2.1" "$NOTICE_DIR/COPYING.LGPLv2.1.txt"
cp "$BUILD_ROOT/source/LICENSE.md" "$NOTICE_DIR/FFmpeg-LICENSE.md"
cp "$BUILD_ROOT/build-arm64/config.h" "$VENDOR_DIR/config-arm64.h"
cp "$BUILD_ROOT/build-x86_64/config.h" "$VENDOR_DIR/config-x86_64.h"

"$TOOLS_DIR/ffmpeg" -hide_banner -version
"$TOOLS_DIR/ffprobe" -hide_banner -version
lipo -archs "$TOOLS_DIR/ffmpeg"
