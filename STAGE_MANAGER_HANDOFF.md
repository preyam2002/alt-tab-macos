# AltTab Stage Manager fix — full handoff / state of work

_Last updated: 2026-07-24. This is the single source of truth for resuming. Read it fully before touching code._

## Goal
Fix broken window-preview **thumbnails for windows staged in the Stage Manager side strip** on macOS 26 (Tahoe). Upstream `lwouis/alt-tab-macos` closed the related issues (#4747, #5490, #5315) as "Apple design choice, can't fix." That's wrong on macOS 26: SCK *can* sometimes capture staged windows, it just intermittently returns blank/shelf-sized frames — so the bad frames are filterable client-side.

## Branches & where things live
- Repo (worktree): `/Users/preyam/repo/alt-tab-macos-stage-manager-fix`
- Remotes: `origin` = lwouis/alt-tab-macos, `fork` = preyam2002/alt-tab-macos
- `fix/stage-manager-thumbnails` — the **10.12.0-based** original fix (6 files). Pushed to fork (ahead 2). Messy "chore: save workspace state" commits + `tasklist.md` + `ai/install-stage.sh`. The full 6-file patch is saved at `notes/stage-manager/sm_fix_10.12.0.patch`.
- `fix/sm-thumbnails-11.3.0` — **CURRENT**, based on upstream 11.3.0. The re-port (1 file). **This is where active work is.**
- A git stash `sm-preserve-last-good-wip` held the 10.12.0 preserve-last-good edit (now committed onto the 10.12.0 branch; superseded by the 11.x port).

## Upstream moved 10.12.0 → 11.3.0 (+36 commits). Key facts:
- **Dropped CocoaPods → SPM.** No `Podfile`/`Pods`. Build with `xcodebuild -project alt-tab-macos.xcodeproj -scheme Debug -configuration Debug -derivedDataPath ./DerivedData11 build` (note: `-project`, not `-workspace`). Xcode resolves SPM packages at build time.
- **11.0 introduced "Alt-Tab Pro"** (paid tier). Pulling latest inherits it.
- **Big directory refactor** (1946 files). `src/logic/` → `src/switcher/...`, `src/events/`, `src/kit/`, `src/macos/api-wrappers/`, etc.
- **#5618 "Alt Tab doesn't see multiple windows" is FIXED in 11.1.0** (commit `a8098c39`, `positionsCompatibleForTabSiblings` in `src/switcher/state/TabGroup.swift`). This is the **Ghostty 4↔8 tab-count flicker** we hit — it's a pre-existing, now-fixed upstream bug (NOT ours; reproduced on stock 10.12.0 which is Developer-ID signed by lwouis). So on 11.3.0 that flicker should already be gone.

## The 11.3.0 re-port — CURRENT approach (settled 2026-07-24, "Approach C")
11.x simplified the thumbnail path: `CALayerContents` is back to `{cgImage, pixelBuffer}` (no `transparentPixelBuffer`), and `Window.refreshThumbnail(_ screenshot: CALayerContents)` just does `thumbnail = screenshot`.

**Approach C = capture always; drop only captures that are positively junk; preserve last-good on drop.**
- `src/events/WindowCapturePolicy.swift` (new, pure, testable): when Stage Manager is on, sample a 32×32 alpha grid of the captured buffer; keep the capture only if its opaque bounding box fills **≥50% of the grid in both dimensions** (`minContentRatio`). Fail-open: non-BGRA/unanalyzable buffers are kept. SM off → everything kept (SM-off path byte-identical to stock).
- `src/events/WindowCaptureEvents.swift`: in the SCK capture callback, `guard shouldUseCapture else return` — a dropped capture simply never calls `refreshThumbnail`, so the previous good thumbnail stays; a window never captured shows the app icon via the existing display-time fallback (`TileView.swift` `updateContents`, "if no thumbnail, show appIcon instead").
- `src/events/WindowCapturePolicyTests.swift` (new, 10 tests) — registered in `project.pbxproj` (policy in both targets, tests in unit-tests).

**Why content-only, not the scFrame gate — RE-DERIVED FROM THE RAW DATA 2026-07-24.** The June conclusion "scFrame cleanly separates staged vs normal, and every staged capture is bad" is **wrong**; re-reading `notes/stage-manager/smsig_raw_sample.txt` row by row shows scFrame fails in BOTH directions (correction now written into `smsig_findings.md`):
- **Shelf-framed windows often return perfectly good captures** (`bbox 32x32` on Ghostty 141x145 + 149x137, Calendar 113x124, WhatsApp 127x147; `27x31` Telegram; `24x26` Ghostty). Skipping them all = throwing away real previews = **the wall of icons the user hated**.
- **Full-framed windows still return junk** (Ghostty `1453x903`→`3x5`, Ghostty `1537x842`→`3x5`, Spotify/WhatsApp full-frame→transparent, MergeTabs `1327x777`→`3x5`). A frame gate never drops these, so **the original broken-thumbnail bug survives it**.
- `scWindow.frame` also comes from cached `SCWindow` snapshots that go stale, adding a third failure mode.

Content separates the classes with a wide margin: usable captures all ≥24/32 in both dims, junk all ≤15/32 (usually 3–6) or empty. `minContentRatio = 0.5` sits mid-gap and classifies **every** measured sample correctly — locked in by `WindowCapturePolicyTests.testClassifiesEveryMeasuredMacos26Sample`, which is that table verbatim.

**Why preserve-last-good, not nil→icon:** nil-ing the thumbnail on a bad capture (the June 10 uncommitted draft) re-introduces the icon↔preview size oscillation + full-switcher relayout that `cebcac70` on the 10.12.0 branch fixed and the user explicitly confirmed good. Wall-of-icons (Approach B: skip ALL staged pre-capture) was "you broke everything".

Note: the private-API path (`WindowCaptureScreenshotsPrivateApi`, `CGSHWCaptureWindowList`) is only used on macOS 15 and <14 (`WindowThumbnails.swift`); the SM bug is macOS 26 → always the SCK path → deliberately untouched.

## KEY DATA — the scFrame signal (from instrumented run, 391 samples, SM on)
For each capture while SM is on, logged `scFrame` (SCWindow.frame) vs `req` (requested = window.size):
- **Normal / on-active-stage / other-space windows:** `scFrame == req` exactly (e.g. `1453x903`/`1453x903`), opaque bbox ~100%. GOOD captures.
- **Staged (side-strip) windows:** `scFrame` shelf-sized ~75–165px while `req` is full 700–1700px (≈10%). Content bbox 3x5/32 or fully transparent. BAD captures — EVERY staged sample was bad; none were good.

So `scWindow.frame` shelf-size is a clean, semantic discriminator (no pixel scanning needed). `isStageManagerEnabled()` reads `com.apple.WindowManager / GloballyEnabled` (bool, =1 when on; confirmed).

## Approach history (why C)
- **Approach A (10.12.0 content heuristic, drop→icon):** user saw "**lag between icon and our screenshot**" — staged tiles flip-flopped icon↔preview. Fixed on 10.12.0 by preserve-last-good (`cebcac70`), which the user confirmed good.
- **Approach B (scFrame skip-before-capture, committed in `ea22cbee`):** user said "**you broke everything**" — most likely wall-of-icons (with SM on, most windows are staged → every capture skipped → icons everywhere). Exact symptom never confirmed — still worth asking.
- **Approach C (CURRENT, uncommitted June 10 draft refined 2026-07-24):** capture always, drop only positively-junk frames, preserve last-good on drop.

**Predicted behavior (from the raw data, still to be confirmed visually):** because staged windows return good captures regularly, most staged windows should end up showing a **real preview** — the first good capture sticks, and every junk frame afterwards is discarded instead of overwriting it. That is precisely what neither prior approach did: B skipped the good captures too (icons everywhere), stock let the junk overwrite them (blank/shelf flicker). Windows whose every capture is junk (Cursor, Notion and Anki were junk-only in the sample run) fall back to last-good, or to the app icon if never captured well — a stable icon, not a flicker. Normal windows and SM-off are untouched. If junk-only windows turn out to be common in practice, the remaining unexplored direction is reading the OS-rendered shelf mini-preview via CGS/SkyLight.

## ⚠️ Build/signing state (changed 2026-07-24)
- The "Local Self-Signed" cert **expired 2026-06-11** (30-day validity). A replacement self-signed cert with the SAME name (730-day, expires 2028-07) was minted via openssl and imported into the login keychain with `-A` (no prompts). The old identity was deleted.
- `xcodebuild` in-build codesign with the named identity fails with `errSecInternalComponent` (partition-list quirk; direct `codesign` works). **Workaround: build with `CODE_SIGN_IDENTITY="-"` (ad-hoc) and deep-sign at install** — the install workflow's `codesign --force --deep --sign "Local Self-Signed"` step does this anyway.
- Because the cert changed, TCC (Accessibility + Screen Recording) will likely re-prompt once for `com.preyam.alttab.stage`.
- Unit tests: `xcodebuild -project alt-tab-macos.xcodeproj -scheme Test -configuration Debug -derivedDataPath DerivedData11 test CODE_SIGN_IDENTITY="-"`. `CustomRecorderControlTests` + `KeyboardEventsUtilsTests` crash under CLI xctest ("one-time initialization function for defaultShortcuts") **on clean HEAD too** — pre-existing/environmental, skip with `-skip-testing:`; everything else: 475/475 pass with the fix.

## Test app + build/install workflow
- Test bundle: `/Applications/AltTab Stage.app`, id `com.preyam.alttab.stage` (has Accessibility + Screen-Recording grants; persists across re-signs of same id).
- **GOTCHA — local Debug build crashes on launch:** 11.x Debug `Info.plist` is missing `CFBundleVersion`, and `App.version` force-unwraps it (`App.swift:14`) → fatal nil on launch. Inject it after ditto.
- Install:
  ```bash
  SRC="DerivedData11/Build/Products/Debug/AltTab.app"; DST="/Applications/AltTab Stage.app"
  osascript -e 'quit app "AltTab Stage"'
  ditto "$SRC" "$DST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.preyam.alttab.stage" "$DST/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName AltTab Stage" "$DST/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 11.3.0" "$DST/Contents/Info.plist" || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 11.3.0" "$DST/Contents/Info.plist" || true
  codesign --force --deep --sign "Local Self-Signed" "$DST"
  open "$DST"   # quit stock AltTab first so ⌥-Tab only hits the test build
  ```
- Run with logs: `"/Applications/AltTab Stage.app/Contents/MacOS/AltTab" --logs=error` (or `=debug`).

## Path to a mergeable OSS contribution (status)
1. **Verify it works + no regressions** — code-verified (builds clean, 475 unit tests incl. 10 policy tests pass); ⏳ USER VISUAL TEST PENDING: install the build, toggle SM on, check (a) staged windows show icon or last-good preview — never blank/shelf junk, (b) no icon↔preview flicker, (c) SM off unchanged.
2. **Open an issue first** to gauge maintainer (he closed #4747 as wontfix). Draft ready at `notes/stage-manager/upstream_issue_draft.md` — update it to describe the content-based policy before posting.
3. **Harden heuristic** — ✅ done (content-based, fail-open, stale-frame-immune).
4. **Add XCTest spec** — ✅ done (`WindowCapturePolicyTests`, 10 tests, registered in pbxproj).
5. **Clean branch + conventional commit** — fix committed on this branch; make a fresh clean branch off upstream for the real PR when submitting.

## Artifacts in this repo
- `notes/stage-manager/sm_fix_10.12.0.patch` — the original 6-file fix on 10.12.0.
- `notes/stage-manager/upstream_issue_draft.md` — GitHub issue draft for upstream.
- `notes/stage-manager/smsig_findings.md` — the scFrame signal data + analysis.

## Behavioral feedback to honor (the user is exacting about this)
- Don't claim "fixed" until the ORIGINAL symptom is observed gone (reproduce + watch). Separate verified from assumed.
- Don't deploy speculative fixes in a loop; reason to a confident root cause; prefer one decisive log/test over rebuilds.
- The "broke everything" happened because I rewrote + shipped before the user confirmed the prior build. Confirm each build before moving on.
