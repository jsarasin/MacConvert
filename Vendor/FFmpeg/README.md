# Bundled FFmpeg

MacConvert currently bundles a **local-only, nonredistributable** FFmpeg 8.1.2 and ffprobe pair. It is an Apple-silicon build linked to codec libraries in `/opt/homebrew`; it is not portable to another Mac and must not be shipped in a release.

Run `Scripts/build-ffmpeg-local-nonfree.sh` to reproduce this developer-machine build. It enables GPLv3 and FFmpeg's `--enable-nonfree` mode, including FDK AAC, x264, x265, AOM/SVT-AV1/rav1e, VP8/VP9, VVC, WebP, JPEG XL, OpenJPEG, and other Homebrew-provided libraries. Apple-framework support is left to FFmpeg's normal configure auto-detection rather than explicitly enabled or disabled. The package preflight in that script is the exact dependency list. The resulting configure header and log are retained as `config-local-nonfree-arm64.*`.

Minimum deployment target: macOS 14.0. Official source archive SHA-256: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`.

The official source archive remains at `Vendor/FFmpeg/Source/ffmpeg-8.1.2.tar.xz`. License and warning materials copied into the application resources are under `MacConvert/Resources/FFmpeg`.

For a portable release, replace these helpers by running `Scripts/build-ffmpeg.sh`. That script produces universal `arm64` + `x86_64` LGPL helpers without `--enable-gpl` or `--enable-nonfree`. Complete a fresh license review and release validation before distributing any build.
