import CoreGraphics
import CoreVideo

// macOS 26 Stage Manager: ScreenCaptureKit captures of windows staged in the side strip intermittently
// come back fully transparent, or with only a tiny shelf-sized image in a corner of the requested buffer.
// Applying such a capture replaces a good thumbnail with a blank or broken one.
//
// A capture is judged by its content rather than by SCWindow.frame. Frame-based detection fails both ways
// on measured data (notes/stage-manager/smsig_raw_sample.txt): staged windows with a shelf-sized frame
// often DO return a full, usable capture, and windows whose frame matches the request still return blank
// or shelf-sized junk. Cached SCWindow snapshots also go stale, so their frame can describe a window's
// previous state entirely.
struct WindowCapturePolicy {
    static let opaqueGridSize = 32
    static let alphaThreshold: UInt8 = 16
    // A usable capture fills its buffer: every good sample measured on macOS 26 covered >=24/32 of the grid
    // in both dimensions, while junk covered <=15/32 (usually 3-6) or nothing at all. Half the grid sits in
    // the middle of that gap, so both classes clear it by a wide margin.
    static let minContentRatio: CGFloat = 0.5

    struct OpaqueBounds: Equatable {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int

        static let empty = OpaqueBounds(minX: -1, minY: -1, maxX: -1, maxY: -1)

        var isEmpty: Bool { maxX < 0 || maxY < 0 }

        func fillsBuffer(in gridSize: Int, ratio: CGFloat) -> Bool {
            guard !isEmpty, gridSize > 0 else { return false }
            let width = maxX - minX + 1
            let height = maxY - minY + 1
            return CGFloat(width) / CGFloat(gridSize) >= ratio
                && CGFloat(height) / CGFloat(gridSize) >= ratio
        }
    }

    // fail-open: only a capture positively identified as junk is dropped; anything unanalyzable is kept
    static func shouldUseCapture(_ stageManagerEnabled: Bool, _ pixelBuffer: CVPixelBuffer) -> Bool {
        guard stageManagerEnabled else { return true }
        guard let bounds = opaqueBounds(pixelBuffer) else { return true }
        return bounds.fillsBuffer(in: opaqueGridSize, ratio: minContentRatio)
    }

    // bounding box of the pixels above the alpha threshold, in grid coordinates, from a
    // gridSize x gridSize sampling of the buffer; nil if the buffer can't be analyzed
    static func opaqueBounds(_ pixelBuffer: CVPixelBuffer, gridSize: Int = opaqueGridSize) -> OpaqueBounds? {
        guard gridSize > 0,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return .empty }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var minX = gridSize
        var minY = gridSize
        var maxX = -1
        var maxY = -1
        for sampleY in 0..<gridSize {
            let y = min(height - 1, sampleY * height / gridSize)
            let rowStart = y * bytesPerRow
            for sampleX in 0..<gridSize {
                let x = min(width - 1, sampleX * width / gridSize)
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
