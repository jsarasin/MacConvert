#!/bin/zsh
set -euo pipefail

FFMPEG_VERSION="8.1.2"
PROJECT_ROOT="${0:A:h:h}"
VENDOR_DIR="$PROJECT_ROOT/Vendor/FFmpeg"
SOURCE_ARCHIVE="$VENDOR_DIR/Source/ffmpeg-$FFMPEG_VERSION.tar.xz"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
BUILD_ROOT="${TMPDIR:-/tmp}/macconvert-ffmpeg-$FFMPEG_VERSION-local-nonfree"
TOOLS_DIR="$PROJECT_ROOT/MacConvert/Resources/Tools"
NOTICE_DIR="$PROJECT_ROOT/MacConvert/Resources/FFmpeg"
MINIMUM_MACOS="14.0"
HOMEBREW_PREFIX="/opt/homebrew"

if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 "This local build script currently targets the Apple-silicon Homebrew installation at $HOMEBREW_PREFIX."
    exit 1
fi

required_packages=(
    aom chromaprint codec2 dav1d fdk-aac game-music-emu jpeg-xl lame lcms2
    libaribcaption libass libbluray libbs2b libilbc liblc3 libmodplug libopenmpt
    librist libsoxr libssh libvidstab libvmaf libvorbis libvpx openapv openh264
    openjpeg openssl@3 opus rav1e rubberband snappy speex srt svt-av1 theora
    two-lame vvenc webp x264 x265 xvid zimg zeromq
)

for package in "${required_packages[@]}"; do
    if ! brew --prefix "$package" >/dev/null 2>&1; then
        print -u2 "Missing Homebrew dependency: $package"
        exit 1
    fi
done

mkdir -p "$VENDOR_DIR/Source" "$TOOLS_DIR" "$NOTICE_DIR"
if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    curl --fail --location --output "$SOURCE_ARCHIVE" "$SOURCE_URL"
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/source" "$BUILD_ROOT/build" "$BUILD_ROOT/install"
tar -xf "$SOURCE_ARCHIVE" -C "$BUILD_ROOT/source" --strip-components=1

cd "$BUILD_ROOT/build"
PKG_CONFIG_PATH="$HOMEBREW_PREFIX/lib/pkgconfig:$HOMEBREW_PREFIX/share/pkgconfig" \
    "$BUILD_ROOT/source/configure" \
    --prefix="$BUILD_ROOT/install" \
    --target-os=darwin \
    --arch=arm64 \
    --cc=clang \
    --enable-gpl \
    --enable-version3 \
    --enable-nonfree \
    --disable-doc \
    --disable-debug \
    --disable-ffplay \
    --disable-shared \
    --enable-static \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-audiotoolbox \
    --enable-openssl \
    --enable-lcms2 \
    --enable-fontconfig \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libharfbuzz \
    --enable-libaom \
    --enable-libaribcaption \
    --enable-libass \
    --enable-libbluray \
    --enable-libbs2b \
    --enable-libcodec2 \
    --enable-libdav1d \
    --enable-libfdk-aac \
    --enable-libgme \
    --enable-libgsm \
    --enable-libilbc \
    --enable-libjxl \
    --enable-liblc3 \
    --enable-libmodplug \
    --enable-libmp3lame \
    --enable-liboapv \
    --enable-libopenh264 \
    --enable-libopenjpeg \
    --enable-libopenmpt \
    --enable-libopus \
    --enable-librav1e \
    --enable-librist \
    --enable-librubberband \
    --enable-libsnappy \
    --enable-libsoxr \
    --enable-libspeex \
    --enable-libsrt \
    --enable-libssh \
    --enable-libsvtav1 \
    --enable-libtheora \
    --enable-libtwolame \
    --enable-libvidstab \
    --enable-libvmaf \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libvvenc \
    --enable-libwebp \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libxvid \
    --enable-libzimg \
    --enable-libzmq \
    --enable-chromaprint \
    --extra-cflags="-arch arm64 -mmacosx-version-min=$MINIMUM_MACOS -I$HOMEBREW_PREFIX/include" \
    --extra-ldflags="-arch arm64 -mmacosx-version-min=$MINIMUM_MACOS -L$HOMEBREW_PREFIX/lib"

make -j8
make install

cp "$BUILD_ROOT/install/bin/ffmpeg" "$TOOLS_DIR/ffmpeg"
cp "$BUILD_ROOT/install/bin/ffprobe" "$TOOLS_DIR/ffprobe"
chmod 755 "$TOOLS_DIR/ffmpeg" "$TOOLS_DIR/ffprobe"
cp "$BUILD_ROOT/source/COPYING.GPLv3" "$NOTICE_DIR/COPYING.GPLv3.txt"
cp "$BUILD_ROOT/source/LICENSE.md" "$NOTICE_DIR/FFmpeg-LICENSE.md"
cp "$BUILD_ROOT/build/config.h" "$VENDOR_DIR/config-local-nonfree-arm64.h"
cp "$BUILD_ROOT/build/ffbuild/config.log" "$VENDOR_DIR/config-local-nonfree-arm64.log"

"$TOOLS_DIR/ffmpeg" -hide_banner -version
"$TOOLS_DIR/ffprobe" -hide_banner -version
"$TOOLS_DIR/ffmpeg" -hide_banner -encoders | grep -E 'libfdk_aac|libx264|libx265|libaom|librav1e|libsvtav1|libvpx|libvvenc|libwebp'
file "$TOOLS_DIR/ffmpeg" "$TOOLS_DIR/ffprobe"
