import XCTest
@testable import WTHCore

final class FileStabilityCheckerTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/IMG_1234.HEIC")

    private func makeChecker(
        snapshots: [FileSnapshot?],
        clock: TestClock,
        pollInterval: TimeInterval = 0.1,
        requiredStableReadings: Int = 3,
        timeout: TimeInterval = 10,
        minimumSize: Int64 = 1
    ) -> FileStabilityChecker {
        FileStabilityChecker(
            configuration: FileStabilityConfiguration(
                pollInterval: pollInterval,
                requiredStableReadings: requiredStableReadings,
                timeout: timeout,
                minimumSize: minimumSize
            ),
            probe: ScriptedProbe(snapshots: snapshots),
            sleep: { clock.advance($0) },
            now: { clock.read() }
        )
    }

    func testReturnsOnceFileIsStable() async throws {
        let snapshot = makeSnapshot(size: 100)
        let clock = TestClock()
        let checker = makeChecker(snapshots: Array(repeating: snapshot, count: 5), clock: clock)
        let result = try await checker.waitUntilStable(at: url)
        XCTAssertEqual(result, snapshot)
    }

    func testWaitsThroughGrowingFile() async throws {
        let clock = TestClock()
        let checker = makeChecker(
            snapshots: [
                makeSnapshot(size: 10),
                makeSnapshot(size: 20),
                makeSnapshot(size: 30),
                makeSnapshot(size: 30),
                makeSnapshot(size: 30),
            ],
            clock: clock
        )
        let result = try await checker.waitUntilStable(at: url)
        XCTAssertEqual(result.size, 30)
    }

    func testTimesOutWhenFileNeverAppears() async {
        let clock = TestClock()
        let checker = makeChecker(
            snapshots: [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
            clock: clock,
            pollInterval: 0.1,
            timeout: 0.5
        )
        do {
            _ = try await checker.waitUntilStable(at: url)
            XCTFail("Expected a timeout")
        } catch let error as FileStabilityError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIgnoresEmptyFiles() async {
        let clock = TestClock()
        let empty = makeSnapshot(size: 0)
        let checker = makeChecker(
            snapshots: Array(repeating: empty, count: 50),
            clock: clock,
            pollInterval: 0.1,
            timeout: 0.5
        )
        do {
            _ = try await checker.waitUntilStable(at: url)
            XCTFail("Expected a timeout")
        } catch let error as FileStabilityError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
