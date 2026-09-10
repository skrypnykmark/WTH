import XCTest
@testable import WTHCore

final class DestinationResolverTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/tmp/IMG_1234.HEIC")

    func testConvertsWhenNoJPEGExists() {
        let resolver = DestinationResolver { _ in false }
        XCTAssertEqual(
            resolver.resolve(source: source),
            .convert(destination: URL(fileURLWithPath: "/tmp/IMG_1234.jpg"))
        )
    }

    func testSkipsWhenJPEGAlreadyExists() {
        let resolver = DestinationResolver { _ in true }
        XCTAssertEqual(
            resolver.resolve(source: source),
            .skipExistingJPEG(destination: URL(fileURLWithPath: "/tmp/IMG_1234.jpg"))
        )
    }

    func testSkipsUnsupportedFiles() {
        let resolver = DestinationResolver { _ in false }
        XCTAssertEqual(
            resolver.resolve(source: URL(fileURLWithPath: "/tmp/IMG_1234.png")),
            .skipUnsupported
        )
    }
}
