import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WTHCore

final class ImageConverterTests: XCTestCase {
    private let converter = ImageConverter()

    func testConvertsHEICToJPEGAndPreservesMetadata() throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_1234.HEIC")
        try TestImages.writeHEIC(to: source, orientation: 6, model: "iPhone 15 Pro")

        let destination = temp.file("IMG_1234.jpg")
        try converter.convert(source: source, destination: destination, quality: 0.9)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(
                XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil)),
                0,
                nil
            ) as? [CFString: Any]
        )

        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? UInt32, 1)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 600)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 800)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFModel] as? String, "iPhone 15 Pro")
        XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(properties[kCGImagePropertyColorModel] as? String, "RGB")
    }

    func testConversionDoesNotOverwriteExistingDestination() throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_1234.HEIC")
        try TestImages.writeHEIC(to: source)

        let destination = temp.file("IMG_1234.jpg")
        let sentinel = Data("do not overwrite".utf8)
        try sentinel.write(to: destination)

        XCTAssertThrowsError(try converter.convert(source: source, destination: destination, quality: 0.9))
        XCTAssertEqual(try Data(contentsOf: destination), sentinel)
    }

    func testConversionFailsForNonImageSource() throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_9999.HEIC")
        try Data("this is not an image".utf8).write(to: source)

        let destination = temp.file("IMG_9999.jpg")
        XCTAssertThrowsError(try converter.convert(source: source, destination: destination, quality: 0.9))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testHigherQualityProducesLargerFile() throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_5678.HEIC")
        try TestImages.writeHEIC(to: source, image: TestImages.makeNoiseImage(width: 400, height: 300))

        let lowQuality = temp.file("low.jpg")
        let highQuality = temp.file("high.jpg")
        try converter.convert(source: source, destination: lowQuality, quality: 0.1)
        try converter.convert(source: source, destination: highQuality, quality: 0.95)

        let lowSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: lowQuality.path)[.size] as? NSNumber).intValue
        let highSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: highQuality.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(highSize, lowSize)
    }

    func testOrientationTransformsSwapDimensions() {
        let image = TestImages.makeImage(width: 800, height: 600)
        let rotated = ImageOrientation.apply(6, to: image)
        XCTAssertEqual(rotated.width, 600)
        XCTAssertEqual(rotated.height, 800)

        let unchanged = ImageOrientation.apply(1, to: image)
        XCTAssertEqual(unchanged.width, 800)
        XCTAssertEqual(unchanged.height, 600)
    }
}
