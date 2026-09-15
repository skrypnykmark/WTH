import Foundation
import XCTest
@testable import WTHCore

final class ConversionEngineTests: XCTestCase {
    private func makeEngine() -> ConversionEngine {
        ConversionEngine(
            stabilityChecker: FileStabilityChecker(
                configuration: FileStabilityConfiguration(
                    pollInterval: 0.01,
                    requiredStableReadings: 2,
                    timeout: 2,
                    minimumSize: 1
                )
            )
        )
    }

    func testConvertsFileAndKeepsOriginal() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_1234.HEIC")
        try TestImages.writeHEIC(to: source, orientation: 6)
        let originalData = try Data(contentsOf: source)

        let collector = OutcomeCollector()
        let engine = makeEngine()
        await engine.setOutcomeHandler { collector.record($0) }

        await engine.process(source)

        let destination = temp.file("IMG_1234.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: source), originalData)

        XCTAssertEqual(collector.outcomes.count, 1)
        guard case let .converted(_, reportedDestination)? = collector.outcomes.first else {
            return XCTFail("Expected a converted outcome")
        }
        XCTAssertEqual(reportedDestination, destination)
    }

    func testSkipsConversionWhenJPEGExists() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_1234.HEIC")
        try TestImages.writeHEIC(to: source)

        let destination = temp.file("IMG_1234.jpg")
        let existing = Data("user's own jpeg".utf8)
        try existing.write(to: destination)

        let collector = OutcomeCollector()
        let engine = makeEngine()
        await engine.setOutcomeHandler { collector.record($0) }

        await engine.process(source)

        XCTAssertEqual(try Data(contentsOf: destination), existing)
        guard case .skippedExistingJPEG? = collector.outcomes.first else {
            return XCTFail("Expected a skip outcome")
        }
    }

    func testFailedConversionLeavesOriginalUntouched() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("IMG_1234.HEIC")
        let brokenData = Data("not a real image".utf8)
        try brokenData.write(to: source)

        let collector = OutcomeCollector()
        let engine = makeEngine()
        await engine.setOutcomeHandler { collector.record($0) }

        await engine.process(source)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.file("IMG_1234.jpg").path))
        XCTAssertEqual(try Data(contentsOf: source), brokenData)
        guard case .failed? = collector.outcomes.first else {
            return XCTFail("Expected a failed outcome")
        }
    }

    func testProcessAllScansDirectory() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        try TestImages.writeHEIC(to: temp.file("A.HEIC"))
        try TestImages.writeHEIC(to: temp.file("B.HEIC"))
        try Data("ignore me".utf8).write(to: temp.file("notes.txt"))

        let collector = OutcomeCollector()
        let engine = makeEngine()
        await engine.setOutcomeHandler { collector.record($0) }

        await engine.processAll(in: temp.url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.file("A.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.file("B.jpg").path))
        XCTAssertEqual(collector.outcomes.count, 2)
    }

    func testProcessReturnsOutcomeForConversion() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("CHOSEN.HEIC")
        try TestImages.writeHEIC(to: source)

        let engine = makeEngine()
        let outcome = await engine.process(source, force: true, waitForStability: false)

        guard case let .converted(_, destination)? = outcome else {
            return XCTFail("Expected a converted outcome")
        }
        XCTAssertEqual(destination, temp.file("CHOSEN.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testProcessReturnsNilForUnsupportedFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let source = temp.file("note.txt")
        try Data("hello".utf8).write(to: source)

        let engine = makeEngine()
        let outcome = await engine.process(source, force: true, waitForStability: false)
        XCTAssertNil(outcome)
    }
}
