# Stage Manager capture signal findings (macOS 26, instrumented run)

Instrumented `WindowCaptureScreenshots.oneTimeCapture` to log, for every capture while Stage
Manager is on: SCWindow.frame (`scFrame`), the requested logical size (`req` = window.size),
`isActive`, `isOnScreen`, whether the pixel buffer is fully transparent (`transp`), the opaque
content bounding box on a 32×32 grid (`bbox`), and the (downscaled) pixel-buffer size (`pb`).
Raw unique samples in `smsig_raw_sample.txt`.

## Headline result
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
- In **every** staged sample here the capture was bad (none of the "sometimes good" 3-way the
  old notes mentioned showed up in this run). So we cannot rely on getting a good live capture of a
  staged window — only icon or last-good is available.
- `isActive`/`isOnScreen` did NOT discriminate (staged windows reported `active:true onScreen:true`).
  The old 10.12.0 heuristic's `scWindow.isActive && !scWindow.isOnScreen` gate is therefore unreliable
  here — `scFrame` ratio is the good signal.
- One window (`now.typeless.desktop` "Status") had `scFrame == req` but was fully transparent — a
  genuinely-blank window, NOT a staged shelf. `scFrame`-only detection correctly leaves it alone.

## Why scFrame-skip still "broke everything"
Detection is clean, but the *behavior* is the problem: skipping all staged captures means that with
SM on (where most windows are staged), the switcher fills with app icons instead of previews. Need a
better answer than "icon for every staged window" (see HANDOFF open-problem section).
