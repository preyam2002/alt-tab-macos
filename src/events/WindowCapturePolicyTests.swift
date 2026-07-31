import CoreGraphics
import CoreVideo
import XCTest

final class WindowCapturePolicyTests: XCTestCase {
    func testKeepsAnyCaptureWhenStageManagerIsOff() throws {
        let blank = try makePixelBuffer(width: 128, height: 128)
        XCTAssertTrue(WindowCapturePolicy.shouldUseCapture(false, blank))
    }

    func testDropsBlankCaptureWhenStageManagerIsOn() throws {
        let blank = try makePixelBuffer(width: 128, height: 128)
        XCTAssertFalse(WindowCapturePolicy.shouldUseCapture(true, blank))
    }

    func testDropsAlmostTransparentCaptureWhenStageManagerIsOn() throws {
        let ghost = try makePixelBuffer(width: 128, height: 128, opaqueRect: CGRect(x: 0, y: 0, width: 128, height: 128), alpha: WindowCapturePolicy.alphaThreshold)
        XCTAssertFalse(WindowCapturePolicy.shouldUseCapture(true, ghost))
    }

    func testDropsShelfSizedContentWhenStageManagerIsOn() throws {
        let shelf = try makePixelBuffer(width: 128, height: 128, opaqueRect: CGRect(x: 4, y: 4, width: 12, height: 12))
        XCTAssertFalse(WindowCapturePolicy.shouldUseCapture(true, shelf))
    }

    func testDropsSliverThatFillsOnlyOneDimension() throws {
        let sliver = try makePixelBuffer(width: 128, height: 128, opaqueRect: CGRect(x: 4, y: 0, width: 12, height: 128))
        XCTAssertFalse(WindowCapturePolicy.shouldUseCapture(true, sliver))
    }

    func testKeepsFullCaptureWhenStageManagerIsOn() throws {
        let full = try makePixelBuffer(width: 128, height: 128, opaqueRect: CGRect(x: 0, y: 0, width: 128, height: 128))
        XCTAssertTrue(WindowCapturePolicy.shouldUseCapture(true, full))
    }

    func testKeepsCaptureWithTransparentMarginsWhenStageManagerIsOn() throws {
        let inset = try makePixelBuffer(width: 128, height: 128, opaqueRect: CGRect(x: 16, y: 16, width: 96, height: 96))
        XCTAssertTrue(WindowCapturePolicy.shouldUseCapture(true, inset))
    }

    // every distinct opaque bounding box observed in an instrumented run on macOS 26 with Stage Manager on;
    // usable captures cluster at >=24/32, junk at <=15/32
    func testClassifiesEveryMeasuredMacos26Sample() {
        let samples: [(width: Int, height: Int, usable: Bool)] = [
            (32, 32, true), (31, 32, true), (31, 30, true), (27, 31, true), (24, 26, true),
            (14, 15, false), (6, 8, false), (5, 26, false), (4, 5, false), (4, 4, false),
            (4, 3, false), (3, 5, false), (3, 4, false),
        ]
        for sample in samples {
            let bounds = WindowCapturePolicy.OpaqueBounds(minX: 0, minY: 0, maxX: sample.width - 1, maxY: sample.height - 1)
            XCTAssertEqual(bounds.fillsBuffer(in: 32, ratio: WindowCapturePolicy.minContentRatio), sample.usable, "bbox \(sample.width)x\(sample.height)")
        }
        XCTAssertFalse(WindowCapturePolicy.OpaqueBounds.empty.fillsBuffer(in: 32, ratio: WindowCapturePolicy.minContentRatio))
    }

    func testKeepsCaptureItCannotAnalyze() throws {
        var planar: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &planar)
        let buffer = try XCTUnwrap(planar)
        XCTAssertNil(WindowCapturePolicy.opaqueBounds(buffer))
        XCTAssertTrue(WindowCapturePolicy.shouldUseCapture(true, buffer))
    }

    func testOpaqueBoundsFindsExactGridBounds() throws {
        let buffer = try makePixelBuffer(width: 128, height: 128, opaqueRect: CGRect(x: 32, y: 32, width: 32, height: 32))
        let bounds = try XCTUnwrap(WindowCapturePolicy.opaqueBounds(buffer))
        XCTAssertEqual(bounds, WindowCapturePolicy.OpaqueBounds(minX: 8, minY: 8, maxX: 15, maxY: 15))
    }

    func testOpaqueBoundsHonorsRowPadding() throws {
        let padded = try makePixelBuffer(width: 101, height: 67, opaqueRect: CGRect(x: 0, y: 0, width: 101, height: 67))
        let bounds = try XCTUnwrap(WindowCapturePolicy.opaqueBounds(padded))
        XCTAssertEqual(bounds, WindowCapturePolicy.OpaqueBounds(minX: 0, minY: 0, maxX: 31, maxY: 31))
    }

    func testOpaqueBoundsOnImageSmallerThanGrid() throws {
        let tiny = try makePixelBuffer(width: 8, height: 8, opaqueRect: CGRect(x: 0, y: 0, width: 8, height: 8))
        let bounds = try XCTUnwrap(WindowCapturePolicy.opaqueBounds(tiny))
        XCTAssertTrue(bounds.fillsBuffer(in: WindowCapturePolicy.opaqueGridSize, ratio: WindowCapturePolicy.minContentRatio))
    }

    private func makePixelBuffer(width: Int, height: Int, opaqueRect: CGRect? = nil, alpha: UInt8 = 255) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        let buffer = try XCTUnwrap(pixelBuffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        memset(base, 0, bytesPerRow * height)
        guard let opaqueRect else { return buffer }
        let minX = max(0, Int(opaqueRect.minX))
        let minY = max(0, Int(opaqueRect.minY))
        let maxX = min(width, Int(opaqueRect.maxX))
        let maxY = min(height, Int(opaqueRect.maxY))
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in minY..<maxY {
            for x in minX..<maxX {
                ptr[y * bytesPerRow + x * 4 + 3] = alpha
            }
        }
        return buffer
    }
}
