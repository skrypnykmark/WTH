import CoreGraphics

/// Applies EXIF orientation to bitmap data.
///
/// The primary conversion path preserves the orientation tag untouched. This
/// helper is used by the fallback path, which bakes the orientation into the
/// pixels and writes an orientation of `1`, so the resulting JPEG renders
/// correctly even in tools that ignore EXIF orientation.
enum ImageOrientation {
    static func apply(_ orientation: UInt32, to image: CGImage) -> CGImage {
        guard orientation != 1 else { return image }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let transform: CGAffineTransform
        var outputWidth = width
        var outputHeight = height

        switch orientation {
        case 2:
            transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        case 3:
            transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 4:
            transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        case 5:
            transform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
            outputWidth = height
            outputHeight = width
        case 6:
            transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
            outputWidth = height
            outputHeight = width
        case 7:
            transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
            outputWidth = height
            outputHeight = width
        case 8:
            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
            outputWidth = height
            outputHeight = width
        default:
            return image
        }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(outputWidth),
            height: Int(outputHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage() ?? image
    }
}
