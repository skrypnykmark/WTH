import XCTest
@testable import WTHCore

final class ImageFilesTests: XCTestCase {
    func testDetectsHEICCaseInsensitively() {
        for name in ["IMG_1234.HEIC", "IMG_1234.heic", "IMG_1234.HeIc", "IMG_1234.HEIF", "IMG_1234.heif"] {
            XCTAssertTrue(ImageFiles.isSupportedSource(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }

    func testIgnoresNonHEICFiles() {
        for name in ["photo.jpg", "photo.jpeg", "photo.png", "photo", "photo.heic.jpg", ".heic", "archive.heic.zip"] {
            XCTAssertFalse(ImageFiles.isSupportedSource(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }

    func testDestinationKeepsBaseNameAndUsesJPEGExtension() {
        let source = URL(fileURLWithPath: "/Users/me/Downloads/IMG_1234.HEIC")
        XCTAssertEqual(
            ImageFiles.jpegDestination(for: source).path,
            "/Users/me/Downloads/IMG_1234.jpg"
        )
    }

    func testDestinationHandlesMultipleDots() {
        let source = URL(fileURLWithPath: "/Users/me/Downloads/my.photo.HEIF")
        XCTAssertEqual(ImageFiles.jpegDestination(for: source).lastPathComponent, "my.photo.jpg")
    }
}
