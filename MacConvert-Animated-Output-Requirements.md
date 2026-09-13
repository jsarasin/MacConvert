# MacConvert Animated Output Requirements

This document describes the approved product and implementation changes for converting videos to Animated PNG and Animated GIF, handling long videos and same-container conversions, and controlling original-file removal.

This is a planning document. No implementation is included here.

## Decisions at a glance

- Add `Animated PNG` and `Animated GIF` to the Video target choices.
- Keep `PNG / APNG` and `GIF` available in the Picture output choices for picture inputs.
- Hide Video Encoding and Audio Encoding when an animated-image target is selected.
- Show `Loop animation` only for Animated PNG and Animated GIF.
- Use source timing automatically.
- Strip audio intentionally and report it as an informational note on a successful job.
- Show `Awaiting Confirmation` for video-to-animation inputs longer than 30 seconds.
- Show `Awaiting Confirmation` for same-container conversions.
- Pending confirmations do not count as in-progress work and do not block later approved jobs.
- Use `-converted`, then numbered suffixes, only when the source and destination would otherwise be the exact same path.
- Keep `Show Originals` permanently visible and lazily create `~/Documents/MacConvert Originals` when needed.
- Add `Remove original after success` beside `Show Originals`.

## 1. Video output targets

Add these user-facing choices to the Video target/container menu:

- `Animated PNG`
- `Animated GIF`

These choices should appear only when the selected FFmpeg build supports the required animation encoders and muxers.

The output extensions are fixed:

- Animated PNG → `.apng`
- Animated GIF → `.gif`

The original basename should normally be retained.

Animated PNG and Animated GIF remain valid Picture output targets as well. The existing Picture behavior is not being replaced:

- `PNG / APNG` remains the adaptive Picture target.
- `GIF` remains available for picture inputs when supported.
- The changes in this document apply the new contextual controls and confirmation behavior to the Video target path.
- Video and Picture paths may share internal animation-target, encoding, and validation models.

## 2. Contextual Video controls

When `Animated PNG` or `Animated GIF` is selected in the Video section:

- Hide `Video Encoding`.
- Hide `Audio Encoding`.
- Keep `Quality` visible.
- Show `Loop animation`.

When the target changes back to another video container:

- Re-show Video Encoding.
- Re-show Audio Encoding.
- Hide `Loop animation`.
- Restore previous encoding selections when they remain valid.

The job row should show only controls that apply to the selected target. For example, an animation profile should not claim to use H.264 or AAC when those encoders are not involved.

## 3. Loop behavior

`Loop animation` is checked by default.

- Checked: loop indefinitely.
- Unchecked: play once.
- Applies to both Animated PNG and Animated GIF.
- Does not affect animation speed.
- Does not expose a finite loop-count control.

For video sources, the checkbox defines the output loop behavior because ordinary video does not have an animation loop count to preserve.

For existing animated picture inputs, the existing Preserve Quality behavior should continue preserving the source loop behavior.

## 4. Automatic animation timing

Animation timing is configured automatically from the source:

- Preserve source frame timing and total duration.
- Preserve variable frame timing when available.
- Do not speed up or slow down the output.
- Do not add a separate speed control initially.
- If a quality preset drops frames, adjust frame delays so playback speed and total duration remain as close to the source as practical.

GIF timing will use a pragmatic conversion to the format's representable frame delays. Ordinary timing rounding is expected and should not produce a user-facing warning. The output must still decode every frame and retain the intended overall playback behavior.

## 5. Quality behavior

Animated PNG and Animated GIF use the standard quality choices:

- `Preserve Quality`
- `Small File`
- `Tiny File`
- `Custom…`

### Animated PNG

`Preserve Quality` should:

- Produce lossless decoded pixels.
- Preserve source dimensions and timing.
- Preserve full color and alpha where supported.
- Use the source frame rate without an arbitrary reduction.

`Small File` and `Tiny File` may reduce frame rate and dimensions while keeping each resulting frame lossless. Initial implementation presets may use centrally defined limits such as:

- Small File: up to 15 fps and a 1,280-pixel longest edge.
- Tiny File: up to 10 fps and a 720-pixel longest edge.

Compression effort may also be adjusted, but compression effort alone should not be presented as a meaningful quality reduction for APNG.

### Animated GIF

GIF is retained as a compatibility and special-purpose format despite its limitations.

`Preserve Quality` should use:

- An optimized palette of up to 256 colors.
- High-quality error-diffusion dithering.
- Source dimensions.
- A maximum of 20 fps; sources below 20 fps retain their source rate.

`Small File` should initially use:

- Up to 128 colors.
- A maximum of 12 fps.
- A maximum 720-pixel longest edge.

`Tiny File` should initially use:

- Up to 64 colors.
- A maximum of 8 fps.
- A maximum 480-pixel longest edge.

When GIF reduces the frame rate, it should preserve the overall playback speed and duration by adjusting frame delays. The UI should explain that GIF may lose color and transparency fidelity because of its palette and transparency limitations.

`Custom…` should expose only relevant animation controls, such as dimensions, frame rate, palette generation, dithering, and compression effort.

Quality summaries should be honest. Examples include:

- `APNG • Lossless`
- `GIF • 256-color palette`
- `GIF • Reduced palette and frame rate`

## 6. Audio handling

Animated PNG and GIF cannot contain audio.

When the source contains audio:

- Strip it intentionally during conversion.
- Show an informational note before conversion:
  `Audio will be stripped because Animated PNG does not support audio.`
- Include `Audio stripped` in the conversion plan and job details.
- Keep the final job status as `Successful`, not `Successful with warnings`.

Example:

`MP4 → GIF • Animation preserved • Loops continuously • Audio stripped`

Intentional and disclosed format limitations should be informational. Unexpected omissions of subtitles, chapters, attachments, metadata, alpha, or color information may still produce `Successful with warnings` when they cannot be retained.

Conversion, validation, publication, and collision failures remain failed jobs.

## 7. Awaiting Confirmation

Add a durable `Awaiting Confirmation` job phase. It applies in exactly these scenarios:

### Long video to Animated PNG/GIF

When a video source is longer than 30 seconds and the selected Video target is Animated PNG or Animated GIF:

- Run a read-only ffprobe metadata check to obtain duration and standard row information.
- Do not copy the source yet.
- Do not start FFmpeg conversion yet.
- Do not create or publish an output yet.
- Do not modify or delete the source.

ffprobe reads metadata and does not rewrite the file or change how the later conversion operates. It may take slightly longer on a network volume, but it is a normal preflight step.

### Same-container conversions

When the normalized source container matches the selected destination container, such as MP4 → MP4 or MKV → MKV:

- Do not fail the job.
- Put it in `Awaiting Confirmation`.
- Explain whether the selected profile will copy, remux, or re-encode streams.
- Allow the person to proceed even when Preserve Quality may result in little visible change.

The comparison must use ffprobe/container metadata rather than filename extensions alone.

### Confirmation row

The job row should retain its standard information:

- Filename
- Captured source file size
- Source-to-target description
- Quality selection
- Timing behavior
- Loop behavior
- Audio-stripping note when applicable
- Applicable encoder information, or an explicit indication that video/audio encoders do not apply

Replace the progress area with an icon and message such as:

`This video is longer than 30 seconds and may create a large animated file. It may take a while to convert or load in some applications.`

For a same-container conversion, use a message such as:

`The source is already an MP4. Proceed using the selected MP4 profile?`

Provide two native buttons:

- `Proceed with conversion`
- `Cancel Job`

If both confirmation reasons apply, show one combined confirmation rather than multiple prompts.

Selecting `Proceed with conversion` starts the normal transaction using the profile captured when the job was added. Selecting `Cancel Job` marks the job as cancelled without modifying the source.

Awaiting-confirmation jobs:

- Do not display a progress bar.
- Do not count as converting or in-progress work.
- Do not block later approved jobs from running sequentially.
- Remain pending until the person chooses Proceed or Cancel.
- Restore their state after relaunch through the durable job journal.

## 8. Same-container standardization

Same-container conversion should support cleaning up unusual or incompatible files.

The selected target profile is the canonical output profile. For example, the standard MP4 profile remains H.264, AAC-LC, and MP4 fast-start behavior.

Under `Preserve Quality`:

- Copy or remux streams only when they are genuinely compatible with the selected target profile.
- Re-encode incompatible codecs or unusual stream parameters at high quality.
- Preserve compatible streams when copying does not compromise the selected standard.

`Small File`, `Tiny File`, and applicable `Custom…` settings should re-encode as required.

The conversion plan should distinguish cases such as:

- `MP4 remuxed — streams already compatible`
- `H.264 re-encoded for MP4 compatibility`
- `AAC-LC re-encoded — source audio format not suitable`

No separate Cleanup mode is required.

## 9. Output naming

Automatic suffixing is permitted only when the resolved source and destination would otherwise be the exact same path.

For example:

- `Movie.mp4` → `Movie-converted.mp4`
- If that exists: `Movie-converted-1.mp4`
- Then: `Movie-converted-2.mp4`, `Movie-converted-3.mp4`, and so on

Use the first available name without overwriting anything. Keep the target extension fixed.

If the output is going to a different directory, retain the normal basename unless an unrelated existing file causes a collision. Existing collision protections still apply in that case.

This naming rule makes same-container conversion practical beside the source while preserving the source until the new output has been validated.

## 10. Original removal and Originals folder

Add this checkbox in the footer beside `Show Originals`:

`Remove original after success`

Behavior:

- Checked by default.
- Persists between launches.
- Applies only to jobs added after the checkbox changes.
- Is captured in each job's immutable snapshot.
- Removes the source only after output validation, publication, and destination verification.
- Finalizes and verifies a backup first when backups are enabled.
- Retains the source when unchecked.
- Records whether the original was removed or retained in job details.

`Show Originals` must always remain visible. Preserve its existing behavior when an archive folder is already configured.

If no archive folder exists, lazily create and open:

`~/Documents/MacConvert Originals`

Creating this empty folder must not enable backups automatically. The folder remains empty until the person enables original archiving or otherwise selects it for backups.

Keep `View > Show Temporary` as the separate menu command for opening MacConvert's operating-system temporary working directory. Temporary source copies are not archived originals and should continue to be cleaned up after each job.

## 11. Implementation approach

The implementation should add:

- Target types for Animated PNG and Animated GIF.
- Target metadata describing animation capability, audio capability, extension, and applicable encoders.
- A contextual profile model for loop behavior and animation quality settings.
- A durable `Awaiting Confirmation` phase with long-video and same-container reasons.
- Immutable job snapshots containing target, quality, loop, original-removal, output, and backup settings.
- Conditional SwiftUI controls in the existing Output formats group.
- Native Proceed and Cancel buttons in job rows.
- Conversion-plan generation that distinguishes stream copying, remuxing, video re-encoding, raster animation encoding, and intentional audio stripping.
- FFmpeg invocation through `Process` and argument arrays, never shell command strings.
- ffprobe-based preflight for duration, stream compatibility, and same-container detection.
- GIF palette generation and deliberate dithering.
- Loop metadata generated from the `Loop animation` checkbox.
- Local output validation with ffprobe and a full decode pass.
- Validation of frame count, duration, dimensions, alpha behavior, loop behavior, and expected audio omission.
- Durable recovery for jobs awaiting confirmation or interrupted after conversion.

The existing transaction guarantees remain unchanged: the source stays untouched until the new output has been fully validated, published, and verified.

## 12. Acceptance examples

### Long video to Animated PNG

`screen-recording.mp4` with a 45-second duration becomes:

`Awaiting Confirmation`

The row shows the source size, `MP4 → APNG`, quality, timing, loop setting, and any `Audio stripped` note, with Proceed and Cancel buttons.

### Same-container quality reduction

`Movie.mp4` with `MP4` selected and `Small File` quality becomes:

`Awaiting Confirmation`

After proceeding, the output is named `Movie-converted.mp4`. If that exists, MacConvert tries `Movie-converted-1.mp4`, then subsequent numbers.

### Unusual MP4 cleanup

An MP4 using a codec or stream configuration incompatible with the standard MP4 profile enters confirmation, then re-encodes the incompatible streams instead of failing solely because the container already matches.

### Video to GIF with audio

The completed job status is `Successful`, with a detail note:

`Audio stripped — Animated GIF does not support audio.`
