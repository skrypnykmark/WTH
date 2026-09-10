import ImageIO
import XCTest
@testable import WTHCore

final class ImageOrientationTests: XCTestCase {
    func testBakedOrientationMatchesAppleForAllOrientations() throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        for orientation in 1...8 {
            let source = temp.file("o\(orientation).HEIC")
            try TestImages.writeHEIC(
                to: source,
                image: TestImages.makeQuadImage(width: 200, height: 100),
                orientation: UInt32(orientation)
            )

            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
            let raw = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            let reference = try XCTUnwrap(
                CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1000,
                ] as CFDictionary)
            )

            let baked = ImageOrientation.apply(UInt32(orientation), to: raw)

            XCTAssertEqual(baked.width, reference.width, "orientation \(orientation) width")
            XCTAssertEqual(baked.height, reference.height, "orientation \(orientation) height")
            XCTAssertEqual(
                TestImages.quadrantColors(of: baked),
                TestImages.quadrantColors(of: reference),
                "orientation \(orientation) pixels"
            )
        }
    }

    func testRotatedOrientationsSwapDimensions() {
        let image = TestImages.makeQuadImage(width: 200, height: 100)
        for orientation in [5, 6, 7, 8] {
            let baked = ImageOrientation.apply(UInt32(orientation), to: image)
            XCTAssertEqual(baked.width, 100, "orientation \(orientation) width")
            XCTAssertEqual(baked.height, 200, "orientation \(orientation) height")
        }
    }
}
