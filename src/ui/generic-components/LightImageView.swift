import Cocoa

/// thin NSView wrapper around LightImageLayer, for use where AppKit requires an NSView (contentView, Auto Layout, NSStackView)
class LightImageView: NSView {
    let imageLayer: LightImageLayer

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    init(frame frameRect: NSRect = .zero, withTransparencyChecks: Bool = false) {
        imageLayer = LightImageLayer(withTransparencyChecks: withTransparencyChecks)
        super.init(frame: frameRect)
        wantsLayer = true
        layer!.addSublayer(imageLayer)
        layerContentsRedrawPolicy = .never
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func updateContents(_ caLayerContents: CALayerContents, _ size: NSSize) {
        imageLayer.updateContents(caLayerContents, size)
        if frame.size != size {
            frame.size = size
        }
    }

    func releaseImage() {
        imageLayer.releaseImage()
    }
}

enum CALayerContents {
    case cgImage(CGImage?)
    case pixelBuffer(CVPixelBuffer?)
    case transparentPixelBuffer(CVPixelBuffer?)

    func isFullyTransparent() -> Bool {
        switch self {
        case .cgImage(let image):
            return image?.isFullyTransparent() ?? false
        case .pixelBuffer:
            return false
        case .transparentPixelBuffer:
            return true
        }
    }

    func isUsableThumbnail() -> Bool {
        switch self {
        case .cgImage(let image):
            return image != nil && !isFullyTransparent()
        case .pixelBuffer(let pixelBuffer):
            return pixelBuffer != nil
        case .transparentPixelBuffer:
            return false
        }
    }

    func size() -> NSSize? {
        switch self {
        case .cgImage(let image):
            return image?.size()
        case .pixelBuffer(let pixelBuffer), .transparentPixelBuffer(let pixelBuffer):
            return pixelBuffer?.size()
        }
    }
}
