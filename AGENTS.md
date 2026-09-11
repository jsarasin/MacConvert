# MacConvert implementation contract

This file is the authoritative product and engineering specification for MacConvert. Implement the app described here unless the user explicitly changes a requirement. When requirements appear to conflict, protect the original source file first, then preserve the exact published output filename, then favor a native macOS interaction over a custom one.

## Product goal

Build a native macOS utility named **MacConvert**. People drag files from Finder into its window, and the app converts them locally into a selected, broadly compatible format. Video output defaults are MP4, H.264, AAC, and Preserve Quality. Picture output defaults to the adaptive `PNG / APNG` target and Preserve Quality: still inputs produce PNG and animated inputs produce APNG. Audio output defaults to M4A, AAC-LC, and Preserve Quality. Animated GIF, APNG, and animated WebP are first-class picture inputs; animation must never be flattened silently.

## App icon

Use the selected blue MacConvert icon as the default application icon: a deep-blue rounded squircle containing paired charcoal and white media documents with blue play glyphs, surrounded by cyan circular conversion arrows. Keep the transparent high-resolution master at `MacConvert/Resources/AppIcon-Master.png` and the complete native macOS 16–1024 px representations in `MacConvert/Assets.xcassets/AppIcon.appiconset`. Preserve this design and transparent outer corners when regenerating icon assets.

The app must work with files on local disks and volumes already mounted through Finder, including network volumes. It does not mount or authenticate network shares itself.

The source file must remain untouched in its original location until a converted output has been created locally, validated, successfully published, and checked at the destination. By default, delete the source after those checks without retaining a backup. Backups are opt-in; when enabled for a job, finalize and verify its archived original before deleting the source. Never overwrite an existing file.

## Non-negotiable behavior

- Use Swift and SwiftUI for the app and native macOS controls. Bridge to AppKit only where SwiftUI does not expose needed behavior cleanly.
- Ship a bundled, signed `ffmpeg` and `ffprobe` and use them by default, so MacConvert never requires Homebrew or a separately installed executable. Advanced Settings may instead select a matching pair found in the app's inherited `$PATH` or two explicitly chosen executable URLs.
- All media inspection and conversion goes through FFmpeg/ffprobe. The main application must contain no VideoToolbox-specific code: do not call it, prefer it, prohibit it, or encode policy around it. Do not pass an explicit VideoToolbox encoder merely because the app runs on macOS. FFmpeg itself remains free to auto-detect and use its own available backends. The default H.264 option is `H.264 (FFmpeg Default)` and omits an explicit video encoder argument.
- Default to direct Developer ID distribution with Hardened Runtime and notarization. App Sandbox/App Store distribution is not an initial requirement.
- Target macOS 14 or newer unless the user changes the deployment target. Produce a universal app for Apple silicon and Intel when the bundled FFmpeg build supports both.
- Process jobs sequentially by default. The concurrency limit may be changed in Settings.
- Never overwrite an output, original archive, or unrelated file.
- Never silently alter a target filename. If a rename can resolve an invalid or unsupported target name, pause that job and ask the person to choose a new target basename.
- Reject an input that is already in its selected target format, for example MP4 to MP4 or PNG to PNG, with a clear failed status.
- A failed job must not stop subsequent queued jobs unless the person pauses the queue.
- Settings and profile changes affect only jobs added afterward. Every job stores an immutable snapshot of its profile and relevant paths.

## Native macOS design requirements

Follow Apple’s current Human Interface Guidelines, especially:

- Designing for macOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/
- Windows: https://developer.apple.com/design/human-interface-guidelines/windows
- Menus: https://developer.apple.com/design/human-interface-guidelines/menus
- Pop-up buttons: https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons
- Lists and tables: https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- Drag and drop: https://developer.apple.com/design/human-interface-guidelines/drag-and-drop
- Progress indicators: https://developer.apple.com/design/human-interface-guidelines/progress-indicators
- Settings: https://developer.apple.com/design/human-interface-guidelines/settings
- Alerts: https://developer.apple.com/design/human-interface-guidelines/alerts
- Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- File management: https://developer.apple.com/design/human-interface-guidelines/file-management
- Color: https://developer.apple.com/design/human-interface-guidelines/color

Apply these design adjustments:

- Use labeled native pop-up buttons for mutually exclusive format and quality selections. Keep the useful defaults visible and use `Custom…` because it opens another view.
- Keep the conversion controls in a compact content/header band below the window toolbar, not crowded into a custom title bar.
- Use the menu bar for complete command access and keyboard shortcuts. Do not put a Settings button in the main toolbar.
- Use a native, bordered macOS list/table with system selection and alternating content background colors. Take inspiration from Transmission’s compact information hierarchy, but do not clone its custom chrome or hard-code its colors.
- Use system colors, materials, fonts, controls, separators, focus rings, and the person’s accent color. Support Light, Dark, Increase Contrast, Reduce Transparency, Reduce Motion, and keyboard-only use.
- Do not communicate status by color alone. Always pair color with a label and/or SF Symbol.
- Use SF Symbols for compact row actions, with tooltips and accessibility labels. Use `arrow.clockwise.circle` for Retry and `xmark.circle` for Cancel unless a more semantically appropriate native symbol is available on the deployment target.
- Use native sheets for job details, filename correction, and custom encoding settings. Reserve alerts for urgent or destructive confirmations. A filename correction sheet is preferable to an alert because it contains an editable field.
- Use a native Settings scene/window opened from **MacConvert > Settings…** with `Command-,`. For multiple settings panes, use a stable, noncustomizable toolbar, show the selected pane, and restore the last pane.
- Support multiple-file Finder drops and visibly highlight the drop target during a valid drag. Also provide **File > Add Files…** and an `Add Files…` button using `NSOpenPanel`.
- Keep the main window at a compact fixed content width of about 680 points and allow it to resize vertically only, with a minimum height around 520 points. Avoid truncating the only copy of important information at larger accessibility text sizes.
- MacConvert is a single-purpose utility: closing its main window quits the application, even if an auxiliary window such as Settings is open.
- Use the macOS system font and normal semantic text styles. Keep standard body text at approximately the macOS 13-point default and never below the recommended minimum.

## Main window

Lay out the main window from top to bottom:

1. A compact output-profile band with three labeled rows:
   - **Video:** Container, Video Encoding, Audio Encoding, Quality.
   - **Picture:** Picture Output Format, Quality.
   - **Audio:** Container, Audio Encoding, Quality.
2. A prominent Finder drop zone and `Add Files…` button.
3. The job-history list immediately below the drop area, filling the remaining window.
4. A narrow footer showing a summary such as `8 jobs • 1 converting • 2 warnings`, plus `Clear History` and `Show Originals` when a backup folder is available. Keep `Show Temporary` in the menu bar, not in the footer.

Present the output-profile band as one native `GroupBox` titled `Output formats`. Place each `Video`, `Picture`, and `Audio` section label above its left-aligned row of controls, and separate the three sections with horizontal dividers. Controls use stable, compact explicit widths and small gaps instead of expanding or changing width with the selected value. Keep Picture and Audio substantially narrower than Video. Keep the drop zone to the minimum practical vertical height, and give all remaining vertical space to the job-history list.

Default controls:

- Video container: MP4.
- Video encoding: H.264.
- Audio encoding: AAC-LC.
- Video quality: Preserve Quality.
- Picture output format: PNG / APNG. Produce PNG for a still source and APNG for an animated source.
- Picture quality: Preserve Quality; display it as lossless where appropriate.
- Audio container: M4A.
- Audio encoding: AAC-LC.
- Audio quality: Preserve Quality.

Use AAC-LC as the default audio profile for broad macOS, Windows, Android, iPhone, TV, and browser compatibility. A typical Preserve Quality fallback for stereo AAC may use a high-quality bitrate, but the exact value must be selected based on the source and encoder instead of blindly reducing higher-quality audio.

## Menu bar

Provide conventional native menus and retain the standard macOS items automatically supplied by SwiftUI/AppKit.

- **MacConvert:** About MacConvert, Settings… (`Command-,`), Services, Hide, Quit.
- **File:** Add Files… (`Command-O`), Cancel Selected Job when applicable, Retry Selected Job when applicable, Show Output in Finder when applicable.
- **View:** checked toggle **Show All Supported Formats**, Show Temporary, Show Originals, Show Job Details (`Command-I`) when a row is selected. Show FFMPEG Format Support
- **Job:** Cancel/Inspect/Retry(If it's a failed job)
- **Window:** standard minimize, zoom, and window commands.
- **Help:** MacConvert Help and relevant acknowledgements/license access.

`Show All Supported Formats` is unchecked by default and persists between launches. A checked menu item, not a custom checkbox in the main window, represents this global view option.

## Runtime format discovery

At launch, query the currently selected executable rather than hard-coding what is installed. The bundled executable is selected by default; Advanced Settings may opt into `$PATH` or custom executables:

- `ffmpeg -hide_banner -muxers` for writable container/image muxers.
- `ffmpeg -hide_banner -encoders` for video and audio encoders.
- `ffmpeg -hide_banner -h encoder=<name>` and `-h muxer=<name>` where capability details are needed.
- Cache the parsed catalog and the FFmpeg version that produced it. Invalidate the cache when the executable version changes or the person chooses Refresh Supported Formats.

Populate all format and encoder pop-up buttons from this catalog. In normal mode, intersect the discovered catalog with a curated modern list. Reasonable popular entries include MP4, MOV, Matroska, and WebM for video; M4A, MP3, FLAC, Ogg, Opus, WAV, and CAF for audio; H.264, HEVC, AV1, VP9, and ProRes; AAC, Opus, MP3, FLAC, and ALAC; and the adaptive `PNG / APNG` target, GIF, JPEG, WebP, HEIF/HEIC, and TIFF when actually supported by the bundled build. The adaptive target is one user-facing menu choice backed by PNG for still sources and APNG for animated sources.

When `Show All Supported Formats` changes, repopulate all format and encoder pop-up buttons. Retain a selection if it remains visible and valid. Otherwise select the best valid default and show a nonblocking explanation.

When the video container changes, immediately filter both video and audio encoders to options compatible with that container. When the standalone audio container changes, immediately filter its audio encoders the same way. FFmpeg’s flat encoder list is not a compatibility matrix, so:

- Keep a reviewed compatibility table for the curated popular formats.
- For uncommon/all-formats choices, use a short synthetic FFmpeg probe in a local temporary directory to verify that the selected muxer and encoder combination can initialize and write a valid sample.
- Cache compatibility results by FFmpeg version, container, and encoder.
- Never enqueue a job with an unvalidated combination.

The bundled FFmpeg build must always expose the default MP4/H.264/AAC and adaptive PNG/APNG profiles, plus both decoding and encoding support for animated GIF and APNG. Treat a missing bundled default or required animated-image capability as a packaging/build error. If an optional external build lacks these capabilities, report it as an invalid external configuration and allow the person to return to the bundled tools.

## Quality behavior

All three quality pop-up buttons contain:

- Preserve Quality (default)
- Small File
- Tiny File
- Custom…

`Preserve Quality` means:

- Stream-copy a video or audio stream only when its codec already matches the chosen encoder intent and is valid in the chosen container.
- Otherwise use a high-quality constant-quality encode appropriate for the specific FFmpeg encoder.
- Preserve resolution, frame rate, channel layout, sample rate, bit depth, alpha, color information, metadata, chapters, and subtitles where the destination format allows.
- Never upscale, interpolate frames, normalize audio, sharpen, denoise, or otherwise “enhance” automatically.
- Be honest in the UI: lossy-to-lossy conversion cannot be bit-perfect. Show a conversion-plan summary such as `Video copied without re-encoding` or `VP9 converted to H.264 at high quality`.
- When backups are enabled, the archived original is always a byte-for-byte copy; output-quality settings never modify it.

For lossless picture targets such as PNG, display `Lossless` as the effective quality. Compression effort may change speed and file size but never decoded pixels. Converting a lossy WebP or JPEG to PNG cannot restore detail already lost in the source.

### Custom encoding sheet

Choosing `Custom…` opens a native sheet attached to the main window. Do not expose irrelevant controls. Build the sheet dynamically from the media type, selected container, selected encoder, and supported options.

Video sections may include:

- Video: constant quality versus target bitrate, quality value, preset/speed/effort, codec profile and level, pixel format, bit depth, resolution limit, and frame-rate limit.
- Audio: bitrate or lossless mode, sample rate, and channel layout.
- Container: fast-start optimization, metadata preservation, subtitle handling, and chapter handling.

Picture options may include quality/lossless mode, compression effort, width and height, preserve aspect ratio, pixel format, bit depth, alpha handling, color-profile handling, and metadata preservation. Animated-picture options may additionally include Preserve Original Timing, frame-rate override, loop count, final-frame delay, GIF palette generation, and dithering. Default to the source frame timing and loop behavior.

The sheet has `Reset to Preserve Quality`, `Cancel`, and `Apply`. Validate values inline and disable incompatible settings with a concise explanation. Applying changes sets the menu to `Custom` and shows a compact summary in job details. If the person later changes the selected container or encoder, clear incompatible custom values and return that profile to Preserve Quality. Never accept arbitrary shell text as “advanced FFmpeg arguments.”

## Accepted input and media classification

Use URL/file metadata for a quick preliminary check, then use ffprobe JSON as the authority. Do not trust filename extensions alone.

- Initial video inputs: WebM and MKV.
- Initial picture inputs include static and animated WebP, animated and static GIF, APNG, and other still formats that the bundled FFmpeg can decode safely.
- Initial audio inputs include M4A/AAC, MP3, FLAC, Ogg/Opus, WAV, AIFF, CAF, and other audio formats that the bundled FFmpeg can decode safely.
- Reject directories, aliases that cannot resolve, unsupported media, and source files already in the selected target format.
- Inspect frame count, frame timing, duration, and loop behavior so animated pictures are reliably distinguished from still pictures regardless of extension.
- When the selected target supports animation, preserve all frames, their order and timing, and loop behavior under Preserve Quality. State this in the conversion plan.
- When an animated source is paired with a still-only target such as JPEG, fail the job before copying or conversion. State that the selected output format does not support animation and suggest choosing `PNG / APNG`, GIF, or another discovered animation-capable target. Never export only the first frame.
- Preserve alpha where the target supports it. Warn when animation, alpha, metadata, color profiles, attachments, chapters, subtitle streams, or other meaningful data cannot be retained.

### Animated picture policy

Support both animated GIF and APNG as input and output choices. Neither is universally “best” for macOS:

- GIF is the most predictably recognized animated picture format. Finder Quick Look plays animated GIF, while Preview intentionally presents its frames as individual stills rather than playing them. This Preview behavior must not be misreported as a corrupt conversion.
- APNG preserves full color and alpha far better than GIF and is the preferred Preserve Quality picture target for artwork that needs transparency or smooth gradients, but some apps may show only its first frame.
- Animated WebP can be substantially smaller, but use it only when the destination audience is known to support it.
- MP4/H.264 is often the most predictable playback target for photographic animation without transparency, but it is a video output and must never be substituted for a picture target without the person choosing it.

In the normal/popular Picture Output Format menu, make `PNG / APNG` the default adaptive choice and include `GIF` when the bundled FFmpeg exposes it. With the default selected, a still source produces PNG and an animated source produces APNG automatically, preserving frame timing, loop behavior, full color, and alpha where possible. APNG output should use a consistent extension policy validated against Finder, Quick Look, Safari, and Preview on the deployment target. Keep the resolved output type and extension visible in the conversion plan, history row, and filename sheet.

Every discovered picture output must be classified as animation-capable or still-only in the format catalog. If the person explicitly selects a still-only format and drops an animated picture, fail with `Selected output format does not support animation`. Do not prompt, switch formats automatically, or offer a first-frame conversion. If the bundled FFmpeg lacks APNG support, treat the required default profile as a packaging error.

## Output naming and collisions

By default, keep the exact source basename and change only the extension required by the selected target:

- `Holiday.mkv` becomes `Holiday.mp4`.
- `photo.webp` becomes `photo.png`.
- `animation.gif` becomes `animation.apng` when the job explicitly chooses Animated PNG and that is the validated extension policy.

Never add `converted`, a number, or a timestamp to the new output filename automatically. If the exact destination already exists, fail before conversion with a clear collision message. Do not overwrite it.

Before copying locally, validate the proposed target filename against the destination volume’s limitations. Account for prohibited separators, NUL, reserved names on network filesystems, component/path byte limits, and any error that can reasonably be resolved by a rename. If renaming can fix it, pause the job in an `Awaiting Filename` state and present a native sheet containing:

- A plain-language explanation.
- The rejected target path.
- An editable target basename.
- The required extension shown separately and kept fixed.
- Cancel and Continue buttons.

The new basename applies only to that target output and job. Do not rename the source. The archived original independently uses the timestamped local-original naming policy below.

### Timestamped local original names

When backups are enabled, name the temporary local source copy and archived original by inserting the job's Unix epoch timestamp in milliseconds between the exact original basename and extension, for example `myvideo_1786401234567.webm`. Use the same timestamped filename in both locations when archiving. Without backups, use a short internal source filename in the isolated job directory. Neither internal naming policy affects the converted output filename.

Before copying, verify that the timestamped name does not exist in the job's temporary directory or, when backups are enabled, the archive root. If an exact timestamped collision occurs, fail clearly and never overwrite either file.

## File locations

Default locations:

- Converted output: beside the original source file.
- Original handling: delete the source after the converted output is published and verified; backups are off by default, including when migrating older preferences.
- Archived originals root: none by default. Saving a backup requires opting in and choosing a folder in Settings.
- Temporary working directory: an app-owned `MacConvert` directory inside `FileManager.default.temporaryDirectory`, with an isolated subdirectory for each job. Ignore legacy saved temporary paths.

Do not create `~/MacConverted/` or any originals folder by default. Clean up each job's temporary source, converted output, and diagnostics after success or failure; retain recovery files if needed to restore a source. When backups are enabled, store each archived original directly in the chosen archive root using its timestamped local-original filename, without a containing hierarchy. `Show Originals` opens an existing backup folder; `Show Temporary` opens the operating-system temporary working location.

Output location and optional original backups are configurable in Settings; temporary working files always use the operating system's temporary location. A fixed output directory is allowed as an alternative to “Beside source.” Optional archive locations must be local writable folders; reject network volumes. Use standard folder panels, not a custom file browser. Store security-scoped bookmarks for selected folders to make the design future-proof even though the initial direct-distribution build is not sandboxed. Capture the original-handling policy and relevant paths when adding a job so later Settings changes do not affect queued jobs.

## Authoritative per-job transaction

Represent the transaction explicitly as durable job phases. Never infer completion only from FFmpeg’s exit code.

1. Resolve the dropped URL and capture the current conversion profile and location settings in the job.
2. Verify that the source exists, is readable, is a regular file, is not already the selected target format, and is stable enough to process. Verify that its parent directory is writable because output publication and eventual source deletion require it.
3. Resolve the provisional target URL and, only when backups are enabled, the timestamped archive URL. Verify that neither destination exists and that the provisional target filename is valid. If a rename can fix a target-name error, enter `Awaiting Filename` and show the correction sheet.
4. Inspect the source with ffprobe and reject structurally invalid, corrupt-at-probe-time, unsupported, or empty media. Record all streams, chapters, attachments, metadata, duration, dimensions, frame rate, color information, audio layout, frame count, per-frame timing, and animation loop behavior needed for later comparison. Resolve `PNG / APNG` to PNG for a still source or APNG for an animated source, then re-resolve and validate the exact target URL. If an animated picture has a still-only selected target, fail immediately with `Selected output format does not support animation` before copying or conversion.
5. Ensure local free space can hold the source copy, estimated converted output, and a safety reserve. Create an isolated job directory in the operating-system temporary location.
6. Resolve the internal filename for the temporary source copy and, when backups are enabled, the shared timestamped archive filename. Verify that it collides with neither applicable location.
7. Copy the original source into the isolated temporary directory under its internal filename. Convert from this local copy, never directly from the network/source URL. Confirm the copied file exists and has the expected byte count before conversion.
8. Convert the local source copy to the selected target in the same temporary directory. Give partial output an app-owned temporary name until FFmpeg finishes.
9. If conversion fails or is cancelled, record the diagnostic, delete both the temporary source copy and partial/temporary converted output, remove any app-created partial destination if safe and possible, mark the job Failed or Cancelled, stop this job, and continue the queue.
10. If FFmpeg exits successfully, first validate the **local** output before any network transfer. Run ffprobe against it, verify expected container/streams/dimensions/duration, and perform a full local decode check with FFmpeg using a null output. Compare input and output manifests to determine expected omissions and warnings.
11. Publish the validated converted file to the configured output location. For a different volume, treat “move” as copy plus deletion. Prefer an app-owned hidden sibling staging file and a same-directory rename so the final filename never appears partially copied. Never replace an existing target.
12. Perform a lightweight post-publication check: confirm the destination exists, has the expected byte count, is readable, and can be probed. The full media validation already happened locally to avoid an unnecessary full network reread.
13. If backups were enabled when the job was added, finalize the temporary source copy directly in the configured archive root, retaining the shared timestamped filename. Confirm it exists and matches the source copy. Never create a containing directory for an archived original. Skip this phase entirely by default.
14. Only after the published output and any requested archived original pass their checks, confirm the source has not changed, check cancellation, and delete the original source from its original directory.
15. Clean the app’s remaining temporary artifacts and mark the job Successful or Successful with Warning.

If any step after local conversion but before source deletion fails, keep the source in its original location. Best-effort roll back only files created by this job; never delete or rename an unrelated preexisting item. Retain enough durable journal state to reconcile a crash on next launch. If the source was already deleted but final cleanup/status persistence fails, recovery must detect the valid output and any requested archived original and complete without converting again; a backup is not required for jobs that opted out.

## FFmpeg execution details

- Invoke executables with `Process` and an argument array. Never build a shell command string.
- Resolve helpers from the signed application bundle by default. Only search the exact `$PATH` environment inherited by MacConvert when the person explicitly selects that source in Advanced Settings; never invoke a shell to discover or launch a helper. Custom mode uses the two executable URLs explicitly selected by the person. Validate that FFmpeg and ffprobe are executable, launch successfully, and report matching versions before using either external pair.
- Use ffprobe JSON (`-show_format`, `-show_streams`, appropriate chapter/frame information, `-of json`) and decode into typed Swift models.
- Use `-progress pipe:1`, `-nostdin`, and a controlled stats period for machine-readable progress. Keep diagnostic stderr separate from progress parsing.
- Parse duration from the probe result and progress timestamps from FFmpeg to produce determinate video progress.
- Cancellation must terminate the child process gracefully, wait briefly, then force termination only if necessary. Always run transaction cleanup.
- Avoid locale-dependent parsing by forcing machine-readable outputs wherever possible.
- Keep paths as `URL` values until passing `.path` as one Process argument. Correctly support spaces, Unicode, normalization differences, and network-volume paths.
- Sanitize logs so they do not expose more user path information than the local job-details interface requires.

The default MP4 profile should produce H.264 video, AAC-LC audio, and MP4 fast-start metadata. Under Preserve Quality, copy already matching H.264/AAC streams when the MP4 muxer accepts them; otherwise transcode only incompatible streams. Preserve multiple audio streams and supported subtitles/chapters where possible. Never silently discard streams.

For image conversion, use FFmpeg’s selected image encoder/muxer. PNG and APNG are lossless for decoded pixels. For animated output, validate dimensions, frame count, total duration, representative frame timing, loop behavior, alpha behavior, and the ability to decode every frame. For GIF output, generate an appropriate palette and use deliberate dithering under Preserve Quality; record unavoidable palette/transparency limitations in the conversion plan.

## FFmpeg packaging and licensing

- Build or obtain reproducible FFmpeg/ffprobe binaries for the intended architectures and minimum macOS deployment target.
- Prefer an LGPL-compatible build without `--enable-gpl` or `--enable-nonfree` unless the project owner explicitly chooses GPL distribution. The current explicitly chosen local nonfree build leaves FFmpeg's Apple-framework auto-detection at its upstream default and does not explicitly enable or disable VideoToolbox.
- The project owner explicitly chose a local-only nonfree developer build on 2026-08-09. The helpers currently in `MacConvert/Resources/Tools` are arm64, dynamically use `/opt/homebrew` codec libraries, and were configured with `--enable-gpl`, `--enable-version3`, and `--enable-nonfree`. They are nonredistributable and must never be used for a release artifact. Reproduce them with `Scripts/build-ffmpeg-local-nonfree.sh`. Before any distribution, replace them with the universal LGPL helpers from `Scripts/build-ffmpeg.sh` and repeat packaging, license, and compatibility validation.
- Enable the decoders, muxers, encoders, parsers, and Apple frameworks required for the promised default and curated formats.
- Sign embedded helpers as part of the app, enable Hardened Runtime, validate architecture slices and deployment targets, and include them in notarization testing.
- Preserve the exact FFmpeg source/version/configuration used to build distributed binaries and satisfy FFmpeg’s license, source, notice, About-box, and acknowledgement requirements. Start with https://ffmpeg.org/legal.html and obtain legal review before public commercial distribution.
- Include an About/Acknowledgements surface with the FFmpeg version and license information.

## Job history and Transmission-inspired rows

Use a compact, wide native row. Each row contains:

- A file icon or Quick Look thumbnail on the leading edge.
- A prominent filename.
- The original source file size in adaptively rounded decimal MB or GB. Capture and retain the byte count on the job so it remains visible after the source is archived and removed.
- A secondary profile summary such as `MKV → MP4 • H.264 • AAC • Preserve Quality`, `WebP → PNG • Lossless`, or `GIF → APNG • Animation Preserved`.
- A full-width determinate progress bar only while video conversion has measurable progress.
- An indeterminate progress indicator for active single-image operations or phases without meaningful percentages. Do not switch indicator styles mid-phase in a visually disruptive way.
- A detail/status line such as `Converting — 42% • 01:18 remaining`, `Successful`, `Successful with warnings — 2 subtitle tracks omitted`, or `Failed — destination is not writable`.
- Trailing native retry/cancel controls only when relevant. Retry is available for eligible Failed or Cancelled jobs. Cancel is available for queued/active jobs. Completed jobs are not retryable unless a valid archived original and a nonconflicting new destination make retry safe.

Job states should include at least: Queued, Inspecting, Awaiting Filename, Copying Locally, Converting, Validating Locally, Publishing, Validating Destination, Archiving Original, Removing Source, Successful, Successful with Warning, Failed, and Cancelled.

Suggested semantic presentation:

- Active/queued: accent/blue plus explicit text.
- Successful: system green plus checkmark and text.
- Successful with warning: system orange/yellow plus warning symbol and text.
- Failed: system red plus error symbol and text.
- Cancelled: secondary/gray plus cancellation symbol and text.

Double-clicking a row opens its job-details sheet. Also support selection plus `Command-I`, an Info context-menu item, and an accessible labeled info control if included. Each row's context menu includes `Show Original` when the live source or finalized archived original exists, preferring the archived original once archival has begun, and `Show Replacement` only when the published converted file actually exists. Both commands select the resolved file in Finder. The sheet shows:

- Current/final state and timestamps.
- Input, temporary, archived-original, and output URLs when applicable.
- Source and output media manifests.
- Captured container, encoders, quality profile, and custom values.
- Conversion-plan summary describing copied versus encoded streams.
- Included and omitted streams and metadata.
- Warnings and errors in plain language, with expandable technical FFmpeg diagnostics.

Render file paths as link-style controls. Clicking a path calls Finder through `NSWorkspace` to open its containing directory and select the item. If the item no longer exists, open the nearest existing parent and explain that the item moved or was removed.

`Clear History` removes only finished, warned, failed, and cancelled rows and their persisted history records. It never deletes media, archives, output, or active jobs. Confirm only if clearing includes diagnostic information the person may reasonably expect to keep; avoid unnecessary alerts.

## Warnings and errors

Errors must state what failed, why when known, what happened to the source, and a useful next action. Keep technical logs behind disclosure in the details sheet.

Complete as `Successful with Warning` when the output is valid and published but meaningful content could not be preserved, including omitted subtitle/attachment/chapter/audio streams, lost metadata, lost color profile, lost alpha, or the specified different-file/same-temporary-name condition. Animation loss is not a warning case because an animated source paired with a still-only target must fail before conversion.

Expected lossy re-encoding under the selected profile is not itself a warning, but the conversion plan must describe it honestly. Never claim byte-perfect preservation after a lossy encode.

Use inline row status for routine failures. Use an alert/sheet only when the person must decide something, such as correcting a target filename, confirming cancellation of an active operation when that setting is enabled, or resolving a location permission problem.

## Settings window

Open Settings from the native App menu and `Command-,`. Use native panes such as Locations, Conversion, General, and Advanced. Changes apply to future jobs.

### Locations

- Converted output: Beside Source (default) or a chosen output folder.
- Save a backup of originals: off by default; choose a local folder when enabled.
- Temporary working files: managed by macOS, with no custom folder selection.
- Each row has `Choose…`, `Show in Finder`, and `Restore Default` where appropriate.
- Show write-access and available-space state. Validate a new location before saving it and retain the previous valid value when validation fails.

### Conversion defaults

- Default container, video encoder, audio encoder, picture format, and quality presets.
- Configure the default custom profile through the same custom sheet.
- Let FFmpeg choose its default implementation unless the person explicitly selects a particular encoder from the discovered encoder menu.
- Preserve metadata, chapters, subtitles, color profiles, and transparency where supported.

### General

- Start jobs immediately after drop (on by default).
- Continue after an individual failure (on by default).
- Prevent idle system sleep during active conversion.
- Notify when the queue finishes.
- Remember job history between launches.
- Optional automatic cleanup age for completed history, affecting records only.
- Confirm before cancelling an active conversion.

### Advanced

- Maximum simultaneous conversions, default 1.
- Required free-space reserve.
- Retain detailed FFmpeg logs and a bounded retention duration.
- FFmpeg source: Bundled (default and recommended), Search `$PATH`, or Custom Locations. Show the active FFmpeg and ffprobe paths and version, validate that both tools come from a matching build, and retain the bundled tools as an always-available fallback.
- Refresh supported-format information.
- Reset compatibility cache.
- Restore all settings to defaults with appropriate confirmation.

## Persistence and recovery

- Persist preferences with `UserDefaults`/`@AppStorage` where appropriate, but use typed settings models and migration/versioning.
- Persist job history and a minimal transaction journal under Application Support, not the media temporary directory.
- Write journal phase transitions atomically before destructive steps.
- On launch, reconcile incomplete jobs by checking source, local copy, output, and any requested archive URLs. Never assume a missing source means failure; it may indicate the final deletion succeeded before status persistence. Do not require an archive for jobs with backups disabled.
- Keep logs bounded by size/age. Clear History removes associated persisted job/log records but not media.
- Do not persist security-scoped access tokens longer than necessary except configured folder bookmarks.

## Suggested code organization

Keep UI, FFmpeg interaction, and destructive file transactions separate and testable. A sensible structure is:

- `MacConvertApp` and command/menu definitions.
- Views: main window, output profile band, drop zone, history list, job row, footer, job details, filename correction, custom encoding, Settings panes.
- Models: `ConversionJob`, `JobState`, `MediaKind`, `MediaManifest`, `StreamManifest`, `ConversionProfile`, `VideoProfile`, `PictureProfile`, `QualityProfile`, `AppSettings`, `ConversionWarning`.
- Services/actors: `FormatCatalog`, `FFmpegRunner`, `MediaInspector`, `ConversionPlanner`, `CompatibilityResolver`, `JobQueue`, `TransactionCoordinator`, `ArchiveManager`, `HistoryStore`, `FolderAccessStore`, `FinderService`, `SleepAssertionService`, and notification service.
- Protocols around process execution and filesystem operations so tests can inject failures at every transaction phase.

Use structured concurrency and actors for mutable shared state. UI state changes occur on `MainActor`. Do not block the main thread with hashing, copying, probing, conversion, or directory enumeration.

## Accessibility and keyboard behavior

- Provide VoiceOver labels, values, hints, and state announcements for drop target, jobs, progress, warnings, and symbol-only buttons.
- Make every command available without drag and drop. Support Full Keyboard Access, logical tab order, Space/Return activation, menu shortcuts, and context menus.
- Respect system font sizing and avoid truncating the only copy of important status text. Allow details to wrap or reveal in the sheet.
- Use symbols/text in addition to color. Test color-blind modes, Increase Contrast, Reduce Transparency, Reduce Motion, Light, and Dark appearances.
- Announce when a drop is accepted/rejected and when a job finishes or requires attention without producing excessive spoken updates for progress.

## Testing and acceptance criteria

Add unit, integration, UI, packaging, and manual network tests. At minimum cover:

- Keep routine unit and integration tests in a standalone, headless test target. Running them must never launch `MacConvert.app` or wait for the application to quit. Put tests that intentionally drive the application in a separate UI-test target and run them only when explicitly requested.

- Format/encoder parsing and cache invalidation.
- Popular/all-formats menu repopulation and container-dependent encoder filtering.
- Default MP4/H.264/AAC and adaptive PNG/APNG profiles plus animated GIF/APNG read/write capabilities exist in the shipped bundle.
- Preserve Quality planning for remux, partial transcode, full transcode, PNG/APNG lossless output, GIF palette generation, and custom settings.
- WebM VP8/VP9/AV1 plus Opus/Vorbis; MKV containing H.264/AAC, HEVC/AC-3, multiple audio streams, subtitles, chapters, and attachments.
- Static and animated WebP; static and animated GIF; APNG; and JPEG/PNG/TIFF with alpha, orientation, EXIF, and ICC profiles as applicable.
- Animated GIF to APNG and APNG to GIF with variable frame delays, transparency, disposal modes, finite/infinite loops, and frame counts large enough to exercise progress and cancellation.
- Adaptive `PNG / APNG` resolution for still and animated inputs, plus immediate failure when an animated source is paired with any still-only selected target.
- Corrupt/truncated input, zero-byte input, no-video media, unsupported formats, and already-target-format input.
- Exact output collision and target filename correction for a restrictive SMB destination.
- Same-name temporary collision with matching and differing SHA-256 hashes.
- Local free-space exhaustion, archive-space exhaustion, target read-only, source parent read-only, and permission changes mid-job.
- SMB/network disconnect during source copy, output publication, destination validation, and source deletion; reconnect and retry/recovery.
- Cancellation during every phase and app termination/crash immediately before and after each journaled file mutation.
- Confirm that the original source is never deleted before validated output exists and, only for jobs with backups enabled, the archive has been finalized. Verify default conversions create no originals folder and clean their operating-system temporary files.
- Confirm that failure cleanup only removes app-owned temporary/partial files.
- Unicode, composed/decomposed Unicode, spaces, emoji, very long names, and filenames with network-incompatible characters.
- Multiple dropped files, queue continuation after failure, sequential default, changed settings while jobs are queued, retry, Clear History, and clickable Finder paths.
- VoiceOver, keyboard-only operation, appearance/accessibility modes, window resizing, and native menu commands.
- Universal binary slices, helper signatures, Hardened Runtime, notarization, clean-machine launch, and operation without Homebrew.

Use tiny deterministic fixtures for routine tests. Keep larger media/network tests opt-in. Never run destructive tests against real user media; create isolated temporary directories and simulated filesystems.

## Definition of done

MacConvert is ready for its first release only when:

- A clean Mac can run the signed/notarized app without installing dependencies.
- Finder drag-and-drop and Add Files… both accept batches from local and mounted network volumes.
- Default video, still-image, animated-image, and audio conversions produce validated output with the exact basename and requested extension.
- The authoritative transaction protects the source across failures and crashes.
- Format menus accurately reflect the bundled FFmpeg and enforce container compatibility.
- Preserve Quality, other presets, and Custom settings behave honestly and predictably.
- The Transmission-inspired history UI, details, warnings, Finder links, Settings, menus, keyboard access, and accessibility requirements are complete.
- All required automated tests pass and the critical network/disconnect scenarios have been manually verified.
- FFmpeg licensing materials, source correspondence, acknowledgements, code signing, and notarization are complete.
