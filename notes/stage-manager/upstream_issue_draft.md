# Stage Manager (macOS 26): thumbnails flash blank / tiny "shelf" images for staged windows

**AltTab version:** 11.3.0
**macOS version:** 26 (Tahoe)
**Related:** #4747 (closed as "Apple design choice"), #5490, #5315

## Describe the bug

With **Stage Manager enabled** on macOS 26, the switcher thumbnails for windows that are *staged* (sitting in the side strip, i.e. not on the active stage) are unreliable: they intermittently render **fully blank/transparent** or a **tiny shelf-sized image inside a full-size tile**, and visibly **flicker** between a real preview and the broken one as the switcher refreshes.

## Why this is fixable client-side (re: #4747)

#4747 was closed with the conclusion that staged-window capture is an Apple design choice that can't be worked around. On **macOS 26** that conclusion no longer holds. Capturing each staged window's `CMSampleBuffer` to PNG shows `SCScreenshotManager.captureSampleBuffer` returns **one of three things** for a staged window, non-deterministically across refreshes:

1. **Correct, full content** — a perfectly good screenshot (most captures).
2. **A fully transparent buffer** — all alpha = 0.
3. **A tiny, shelf-sized opaque region inside an otherwise-empty full-size buffer** — the buffer is allocated at the window's logical (full) size, but SCK only fills a small shelf-sized area.

So SCK *can* capture staged windows correctly; it just occasionally returns (2) or (3). Because the bad frames are objectively distinguishable from good ones (all-transparent, or opaque content occupying a tiny fraction of a full-size buffer), AltTab can simply **discard the bad frame and keep the last good thumbnail** — no private APIs, no fighting Apple.

(For reference: the old `CGSHWCaptureWindowList(.fullSize)` private-API path returns `0x0` for staged windows on macOS 26, so that is not a viable workaround.)

## Proposed fix

In the ScreenCaptureKit path (`WindowCaptureScreenshots.oneTimeCapture`), when Stage Manager is enabled, detect a bad staged capture and skip the `refreshThumbnail` call so the previous good thumbnail is preserved (and the spurious relayout is avoided). Detection is cheap and content-based:

- fully-transparent buffer, or
- opaque-content bounding box occupying a small fraction of the full-size buffer (a staged "shelf" capture).

Gated on Stage Manager being on, so the default (SM-off) capture path is byte-for-byte unchanged.

I have a working patch (2 files, ~100 lines, no new dependencies) and would be happy to open a PR if you're open to it. Wanted to check receptiveness first given #4747.
