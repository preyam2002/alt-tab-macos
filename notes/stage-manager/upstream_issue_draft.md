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

In the ScreenCaptureKit path (`WindowCaptureScreenshots.oneTimeCapture`), when Stage Manager is enabled, judge the returned buffer before applying it, and skip the `refreshThumbnail` call for a bad one so the previous good thumbnail is preserved (and the spurious relayout is avoided). Detection is cheap and purely content-based: sample a 32×32 alpha grid and keep the capture only if its opaque bounding box fills at least half the buffer in both dimensions.

Measured over an instrumented run on macOS 26, that threshold separates the two classes with a wide margin — usable captures covered ≥24/32 of the grid in both dimensions, junk covered ≤15/32 (typically 3–6) or nothing at all.

Two things worth flagging, because they rule out the cheaper heuristic one would reach for first:

- **`SCWindow.frame` is not a usable signal.** A staged window reports a shelf-sized frame (~10% of the requested size), so it looks like an obvious discriminator — but staged windows with a shelf-sized frame frequently return *good* captures (skipping them fills the switcher with app icons), and windows whose frame matches the request still return blank or shelf-sized junk (so a frame gate misses the actual bug). It fails in both directions.
- Buffers that can't be analyzed (non-BGRA) are kept, so the check can only ever discard a frame it positively identified as junk.

Everything is gated on Stage Manager being on, so the default (SM-off) capture path is byte-for-byte unchanged.

I have a working patch (1 new file + a guard in the capture callback, no new dependencies) with unit tests covering the classifier, including a table of every capture measured in that run. Happy to open a PR if you're open to it — wanted to check receptiveness first given #4747.
