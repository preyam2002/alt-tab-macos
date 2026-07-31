# WindowCapturePolicy — Specs

## Summary

`WindowCapturePolicy` holds the pure decision for whether a ScreenCaptureKit capture is usable as a
thumbnail, extracted from `WindowCaptureScreenshots` so it's unit-testable (same pattern as
`SchedulingPolicy`):

- With Stage Manager on (macOS 26), captures of side-strip windows intermittently come back fully
  transparent or holding only a tiny shelf-sized image; applying one replaces a good thumbnail with a
  blank or broken one. `shouldUseCapture` drops those, so the previous thumbnail (or the app icon)
  stays shown.
- The capture is judged by its content — the bounding box of opaque samples on a 32×32 alpha grid must
  fill ≥50% of the buffer in both dimensions. `SCWindow.frame` is deliberately not used: measured on
  macOS 26, shelf-framed windows often return usable captures and full-framed windows still return
  junk, so a frame gate fails in both directions.
- Fail-open: with Stage Manager off, or for a buffer that can't be analyzed (non-BGRA), the capture is
  always kept. Only a capture positively identified as junk is dropped.

## Test scenarios

Mirrors `WindowCapturePolicyTests.swift` 1:1.

### A. shouldUseCapture
- **testKeepsAnyCaptureWhenStageManagerIsOff** — Stage Manager off → even a blank capture is kept.
- **testDropsBlankCaptureWhenStageManagerIsOn** — fully transparent buffer → dropped.
- **testDropsAlmostTransparentCaptureWhenStageManagerIsOn** — alpha at the threshold everywhere → dropped.
- **testDropsShelfSizedContentWhenStageManagerIsOn** — small opaque patch in a corner → dropped.
- **testDropsSliverThatFillsOnlyOneDimension** — tall thin strip → dropped (must fill both dimensions).
- **testKeepsFullCaptureWhenStageManagerIsOn** — fully opaque buffer → kept.
- **testKeepsCaptureWithTransparentMarginsWhenStageManagerIsOn** — opaque center with margins → kept.
- **testClassifiesEveryMeasuredMacos26Sample** — every distinct bounding box observed in an instrumented
  run on macOS 26 (usable ≥24/32, junk ≤15/32) classifies correctly at the 50% threshold.
- **testKeepsCaptureItCannotAnalyze** — non-BGRA (planar) buffer → `opaqueBounds` is nil → kept.

### B. opaqueBounds
- **testOpaqueBoundsFindsExactGridBounds** — a centered opaque square maps to the exact grid rectangle.
- **testOpaqueBoundsHonorsRowPadding** — odd width/height (padded `bytesPerRow`) still scans correctly.
- **testOpaqueBoundsOnImageSmallerThanGrid** — an 8×8 opaque buffer still reads as filling the grid.
