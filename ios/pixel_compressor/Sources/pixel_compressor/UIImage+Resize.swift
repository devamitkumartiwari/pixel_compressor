import UIKit

extension UIImage {
    /// Renderer format shared by every pass: 1x so output is in pixels (the
    /// default is the screen scale), and the standard range so output stays
    /// sRGB (the default produces P3/extended-range bitmaps on wide-gamut
    /// devices and inflates the encoded size).
    private static var pixelRendererFormat: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return format
    }

    /// Min-bound rule (scale down until one side reaches its
    /// bound, never up), then shrunk further to fit the max bounds (0 = unset).
    func scaled(minWidth: CGFloat, minHeight: CGFloat, maxWidth: CGFloat = 0, maxHeight: CGFloat = 0) -> UIImage {
        let actualWidth = size.width
        let actualHeight = size.height
        guard actualWidth > 0, actualHeight > 0 else { return self }

        var scaleRatio: CGFloat
        if actualWidth / actualHeight < minWidth / minHeight {
            scaleRatio = minWidth / actualWidth
        } else {
            scaleRatio = minHeight / actualHeight
        }
        scaleRatio = min(1, scaleRatio)
        if maxWidth > 0 {
            scaleRatio = min(scaleRatio, maxWidth / actualWidth)
        }
        if maxHeight > 0 {
            scaleRatio = min(scaleRatio, maxHeight / actualHeight)
        }

        let rect = CGRect(x: 0, y: 0,
                          width: floor(scaleRatio * actualWidth),
                          height: floor(scaleRatio * actualHeight))
        ImageCompressHandler.log("scale = \(scaleRatio), dst = \(rect.size.width) x \(rect.size.height)")
        return UIGraphicsImageRenderer(size: rect.size, format: Self.pixelRendererFormat).image { _ in
            draw(in: rect)
        }
    }

    /// Rotates around the centre; the canvas grows to the rotated bounding box.
    func rotated(by degrees: CGFloat) -> UIImage {
        ImageCompressHandler.log("will rotate \(degrees)")
        let radians = degrees * .pi / 180
        // Computed without UIKit layout APIs: this runs off the main thread.
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        guard let cgImage = cgImage else { return self }
        let width = size.width
        let height = size.height
        return UIGraphicsImageRenderer(size: rotatedSize, format: Self.pixelRendererFormat).image { context in
            let bitmap = context.cgContext
            bitmap.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            bitmap.rotate(by: radians)
            bitmap.scaleBy(x: 1, y: -1)
            bitmap.draw(cgImage, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
    }

    /// Exactly width×height. fit: 0 = stretch, 1 = contain (padColor, ARGB),
    /// 2 = cover (centre crop).
    func fitted(width: Int, height: Int, fit: Int, padColor: UInt32) -> UIImage {
        let sw = size.width
        let sh = size.height
        guard sw > 0, sh > 0 else { return self }
        let w = CGFloat(width)
        let h = CGFloat(height)
        let drawRect: CGRect
        if fit == 0 {
            drawRect = CGRect(x: 0, y: 0, width: w, height: h)
        } else {
            let s = fit == 1 ? min(w / sw, h / sh) : max(w / sw, h / sh)
            drawRect = CGRect(x: (w - sw * s) / 2, y: (h - sh * s) / 2, width: sw * s, height: sh * s)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: Self.pixelRendererFormat).image { _ in
            if fit == 1 {
                UIColor(red: CGFloat((padColor >> 16) & 0xFF) / 255,
                        green: CGFloat((padColor >> 8) & 0xFF) / 255,
                        blue: CGFloat(padColor & 0xFF) / 255,
                        alpha: CGFloat((padColor >> 24) & 0xFF) / 255).setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: w, height: h))
            }
            draw(in: drawRect)
        }
    }
}
