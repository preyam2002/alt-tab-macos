# AltTab Stage Manager fix — full handoff / state of work

_Last updated: 2026-06-06. This is the single source of truth for resuming. Read it fully before touching code._

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

## The 11.3.0 re-port (current code, 1 file: `src/events/WindowCaptureEvents.swift`)
11.x simplified the thumbnail path: `CALayerContents` is back to `{cgImage, pixelBuffer}` (no `transparentPixelBuffer`), and `Window.refreshThumbnail(_ screenshot: CALayerContents)` just does `thumbnail = screenshot`. So the fix is simply: **when Stage Manager is on, skip the capture for staged windows** (don't call `refreshThumbnail`), which preserves whatever thumbnail was there.

Detection signal (DATA-DRIVEN, see below): in `oneTimeCapture`, skip when `stageManagerEnabled && isStagedShelfCapture(scWindow.frame.size, requestedSize)`, where a staged window's SCK-reported frame is ≪ the requested logical size.

## KEY DATA — the scFrame signal (from instrumented run, 391 samples, SM on)
For each capture while SM is on, logged `scFrame` (SCWindow.frame) vs `req` (requested = window.size):
- **Normal / on-active-stage / other-space windows:** `scFrame == req` exactly (e.g. `1453x903`/`1453x903`), opaque bbox ~100%. GOOD captures.
- **Staged (side-strip) windows:** `scFrame` shelf-sized ~75–165px while `req` is full 700–1700px (≈10%). Content bbox 3x5/32 or fully transparent. BAD captures — EVERY staged sample was bad; none were good.

So `scWindow.frame` shelf-size is a clean, semantic discriminator (no pixel scanning needed). `isStageManagerEnabled()` reads `com.apple.WindowManager / GloballyEnabled` (bool, =1 when on; confirmed).

## ⚠️ OPEN PROBLEM — the current approach is NOT right
- **Approach A (content heuristic: transparent OR small opaque bbox):** user saw "**lag between icon and our screenshot**" — staged tiles flip-flop icon↔preview as captures vary.
- **Approach B (current: scFrame skip-before-capture):** user said "**you broke everything**." Most likely **wall-of-icons**: with SM on, *most* windows are staged → all their captures are skipped → switcher shows icons instead of previews (worse than broken thumbnails, not better). **NOT yet confirmed what exactly they saw** — must ask on resume.
- **Fundamental tension:** staged windows can't be live-captured well on macOS 26. Options: (1) show broken thumbnails (stock), (2) skip → icons (approach B), (3) preserve last-good (only helps windows captured before being staged; staged-whole-session → still icon).
- **Directions to explore next:** aggressive preserve-last-good vs icon; whether the OS-rendered shelf thumbnail itself can be read (CGS/SkyLight, the strip already shows a live mini-preview); whether a different SCStreamConfiguration/SCContentFilter captures staged windows correctly; or accept icons and confirm with user whether that's actually acceptable.

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
1. **Verify it works + no regressions** — ❌ NOT achieved (approach B broke things; rethink needed).
2. **Open an issue first** to gauge maintainer (he closed #4747 as wontfix). Draft ready at `notes/stage-manager/upstream_issue_draft.md`.
3. **Harden heuristic** — partly done (scFrame signal is clean), but the *behavior* (icons) is the problem, not the detection.
4. **Add XCTest spec** — NOT done. Tests are XCTest, co-located (e.g. `src/events/*Tests.swift`), and **must be registered in `alt-tab-macos.xcodeproj/project.pbxproj`** (no Xcode-16 filesystem-synchronized groups; 4 entries per file). `isStagedShelfCapture(_:_:)` is a pure `CGSize`→`Bool` fn, easy to test once the approach is settled.
5. **Clean branch + conventional commit** — pending (this branch is a checkpoint, make a fresh clean branch for the real PR).

## Artifacts in this repo
- `notes/stage-manager/sm_fix_10.12.0.patch` — the original 6-file fix on 10.12.0.
- `notes/stage-manager/upstream_issue_draft.md` — GitHub issue draft for upstream.
- `notes/stage-manager/smsig_findings.md` — the scFrame signal data + analysis.

## Behavioral feedback to honor (the user is exacting about this)
- Don't claim "fixed" until the ORIGINAL symptom is observed gone (reproduce + watch). Separate verified from assumed.
- Don't deploy speculative fixes in a loop; reason to a confident root cause; prefer one decisive log/test over rebuilds.
- The "broke everything" happened because I rewrote + shipped before the user confirmed the prior build. Confirm each build before moving on.
