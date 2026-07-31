import CoreGraphics
import CoreVideo

/// Pure decision for whether a ScreenCaptureKit capture is usable as a thumbnail, extracted from
/// `WindowCaptureScreenshots` so it's unit-testable (same pattern as `SchedulingPolicy`). The owner reads
/// the Stage Manager state and dispatches; it just branches on this.
///
/// With Stage Manager on (macOS 26), captures of windows staged in the side strip intermittently come back
/// fully transparent, or holding only a tiny shelf-sized image in a corner of the requested buffer; applying
/// one replaces a good thumbnail with a blank or broken one. The capture is judged by its content, not by
/// `SCWindow.frame`: measured on macOS 26, staged windows with a shelf-sized frame often return full, usable
/// captures, and windows whose frame matches the request still return junk — a frame gate fails in both
/// directions (and cached `SCWindow` snapshots can describe a window's previous state entirely).
enum WindowCapturePolicy {
    static let opaqueGridSize = 32
    static let alphaThreshold: UInt8 = 16
    // measured on macOS 26: usable captures fill >=24/32 of the grid in both dimensions, junk fills <=15/32
    // (usually 3-6) or nothing; half the grid sits in the middle of that gap
    static let minContentRatio: CGFloat = 0.5

    /// bounding box, in grid coordinates, of the samples whose alpha is above `alphaThreshold`
    struct OpaqueBounds: Equatable {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int

        static let empty = OpaqueBounds(minX: -1, minY: -1, maxX: -1, maxY: -1)

        var isEmpty: Bool { maxX < 0 || maxY < 0 }

        func fillsBuffer(in gridSize: Int, ratio: CGFloat) -> Bool {
            guard !isEmpty, gridSize > 0 else { return false }
            return CGFloat(maxX - minX + 1) / CGFloat(gridSize) >= ratio
                && CGFloat(maxY - minY + 1) / CGFloat(gridSize) >= ratio
        }
    }

    /// fail-open: only a capture positively identified as junk is dropped; anything unanalyzable is kept
    static func shouldUseCapture(_ stageManagerEnabled: Bool, _ pixelBuffer: CVPixelBuffer) -> Bool {
        guard stageManagerEnabled else { return true }
        guard let bounds = opaqueBounds(pixelBuffer) else { return true }
        return bounds.fillsBuffer(in: opaqueGridSize, ratio: minContentRatio)
    }

    /// samples the buffer on an `opaqueGridSize` x `opaqueGridSize` grid; nil if the buffer can't be analyzed
    static func opaqueBounds(_ pixelBuffer: CVPixelBuffer) -> OpaqueBounds? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return .empty }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var minX = opaqueGridSize
        var minY = opaqueGridSize
        var maxX = -1
        var maxY = -1
        for sampleY in 0..<opaqueGridSize {
            let y = min(height - 1, sampleY * height / opaqueGridSize)
            let rowStart = y * bytesPerRow
            for sampleX in 0..<opaqueGridSize {
                let x = min(width - 1, sampleX * width / opaqueGridSize)
                if ptr[rowStart + x * 4 + 3] > alphaThreshold {
                    if sampleX < minX { minX = sampleX }
                    if sampleY < minY { minY = sampleY }
                    if sampleX > maxX { maxX = sampleX }
                    if sampleY > maxY { maxY = sampleY }
                }
            }
        }
        return maxX < 0 ? .empty : OpaqueBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
