# Stage Manager capture signal findings (macOS 26, instrumented run)

Instrumented `WindowCaptureScreenshots.oneTimeCapture` to log, for every capture while Stage
Manager is on: SCWindow.frame (`scFrame`), the requested logical size (`req` = window.size),
`isActive`, `isOnScreen`, whether the pixel buffer is fully transparent (`transp`), the opaque
content bounding box on a 32×32 grid (`bbox`), and the (downscaled) pixel-buffer size (`pb`).
Raw unique samples in `smsig_raw_sample.txt`.

## ⚠️ CORRECTED 2026-07-24 — the original headline below was WRONG
The first pass read this run as "`scFrame` cleanly separates staged vs normal; every staged capture is
bad." **Re-reading `smsig_raw_sample.txt` row by row disproves both halves**, and that error is what
produced the scFrame-skip build the user reported as "you broke everything":

- **Staged windows DO return good captures**, often. `scFrame`-shelf rows with a full `bbox 32x32`:
  Ghostty wid:48116 (`141x145`), Ghostty wid:50043 (`149x137`), Calendar (`113x124`), WhatsApp
  (`127x147`), plus Telegram at `27x31` and Ghostty at `24x26`. Skipping every shelf-framed window
  therefore **throws away usable previews** → wall of icons.
- **Windows whose frame matches the request still return junk.** `scFrame == req` rows with junk
  content: Ghostty wid:48116 `1453x903` → `bbox 3x5`; Ghostty wid:50043 `1537x842` → `bbox 3x5`;
  Spotify `1495x972` → transparent; WhatsApp `1330x906` → transparent; MergeTabs `1327x777` →
  `bbox 3x5`. A frame-based gate **misses these entirely** → the original bug survives.

`scFrame` is thus wrong in both directions, on this very dataset. **Content is the signal**; the frame
only correlates with it. (Frame is also read from cached `SCWindow` snapshots, which go stale.)

## Content separates the two classes cleanly (the actual result)

| capture quality | opaque bbox (32×32 grid) | seen on |
|---|---|---|
| **usable** | 24×26, 27×31, 31×30, 31×32, 32×32 — all ≥24/32 in both dims | staged AND normal windows |
| **junk** | empty (transparent), 3×4, 3×5, 4×3, 4×4, 4×5, 5×26, 6×8, 14×15 — ≤15/32 | staged AND normal windows |

Gap between the classes is 15→24 of 32, so a **≥50% fill in both dimensions** threshold sits mid-gap
and classifies every measured sample correctly (`WindowCapturePolicy.minContentRatio`, unit-tested
against this exact table in `WindowCapturePolicyTests.testClassifiesEveryMeasuredMacos26Sample`).

## Original (superseded) headline
**`scFrame` cleanly separates staged vs normal windows. No pixel scan needed.**

| window state | scFrame vs req | content bbox | transp | capture |
|---|---|---|---|---|
| normal / active stage / other space | `scFrame == req` (exact) | ~31–32 / 32 (~100%) | false | GOOD |
| **staged (side strip)** | `scFrame ≈ 10% of req` (e.g. 164×138 vs 1703×958) | 3×5 / 32 (~10%) or empty | often true | **BAD** |

Representative staged samples (`scFrame` / `req`):
```
Cursor    164x138 / 1703x958   bbox 3x5    transp false
Telegram  142x153 / 1452x1013  bbox 3x5    transp false
Calendar  113x122 / 1162x821   bbox -      transp true
Notion    123x124 / 1280x858   bbox -      transp true
Anki      109x157 / 1119x979   bbox -      transp true
WhatsApp  127x147 / 1330x906   bbox -      transp true
SwUpdate   75x127 / 723x836    bbox 4x5    transp false
```
Representative normal samples:
```
Ghostty   1453x903 / 1453x903  bbox 32x32  transp false  (active stage)
Spotify   1495x972 / 1495x972  bbox 32x32  transp false
Codex     1280x968 / 1280x968  bbox 32x32  transp false  (other space, active:false onScreen:false)
Chrome    1920x1080/ 1920x1080 bbox 31x30  transp false
```

## Interpretation
- Staged windows: AX/logical `window.size` stays FULL, but ScreenCaptureKit reports a shelf-sized
  `SCWindow.frame` (~10%) and renders only that shelf into the full-size buffer → tiny/blank content.
- ~~In **every** staged sample here the capture was bad~~ **FALSE — see the correction above.** Staged
  windows return good full-content captures regularly; the 3-way behaviour in the old notes is real.
  This single wrong sentence is what justified skipping staged captures outright.
- `isActive`/`isOnScreen` did NOT discriminate (staged windows reported `active:true onScreen:true`).
  The old 10.12.0 heuristic's `scWindow.isActive && !scWindow.isOnScreen` gate is therefore unreliable
  here — `scFrame` ratio is the good signal.
- One window (`now.typeless.desktop` "Status") had `scFrame == req` but was fully transparent — a
  genuinely-blank window, NOT a staged shelf. Content-based filtering drops its capture too, so with
  SM on it shows its app icon instead of an invisible tile. Known, accepted trade-off (a fully
  transparent thumbnail renders as nothing anyway).

## Why scFrame-skip "broke everything"
Two compounding reasons, both visible in the raw data above: skipping every shelf-framed window
discards the many **good** staged captures (→ switcher fills with app icons), and it simultaneously
**fails to drop** the junk captures that arrive with a full-sized frame (→ broken thumbnails persist).
Content-based filtering fixes both.
