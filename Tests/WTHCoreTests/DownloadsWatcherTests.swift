import XCTest
@testable import WTHCore

final class DownloadsWatcherTests: XCTestCase {
    func testDetectsNewlyAddedFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let collector = URLCollector()
        let watcher = DownloadsWatcher(directory: temp.url, reconcileInterval: 60)
        watcher.onNewFiles = { collector.append($0) }
        watcher.start()

        try TestImages.writeHEIC(to: temp.file("IMG_1001.HEIC"))

        let detected = await waitUntil {
            collector.all.contains { $0.lastPathComponent == "IMG_1001.HEIC" }
        }
        watcher.stop()

        XCTAssertTrue(detected, "Expected the watcher to report the new HEIC file")
    }

    func testDoesNotReportExistingFilesAtStart() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        try TestImages.writeHEIC(to: temp.file("EXISTING.HEIC"))

        let collector = URLCollector()
        let watcher = DownloadsWatcher(directory: temp.url, reconcileInterval: 60)
        watcher.onNewFiles = { collector.append($0) }
        watcher.start()

        try await Task.sleep(for: .milliseconds(400))
        watcher.stop()

        XCTAssertTrue(collector.all.isEmpty, "Existing files should form the baseline and not be reported")
    }

    func testReportsExistingFilesWhenRequested() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        try TestImages.writeHEIC(to: temp.file("EXISTING.HEIC"))

        let collector = URLCollector()
        let watcher = DownloadsWatcher(directory: temp.url, reconcileInterval: 60)
        watcher.onNewFiles = { collector.append($0) }
        watcher.start(emitExisting: true)

        let detected = await waitUntil {
            collector.all.contains { $0.lastPathComponent == "EXISTING.HEIC" }
        }
        watcher.stop()

        XCTAssertTrue(detected, "Expected the baseline file when emitExisting is true")
    }

    func testIgnoresNonHEICFiles() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.cleanUp() }

        let collector = URLCollector()
        let watcher = DownloadsWatcher(directory: temp.url, reconcileInterval: 60)
        watcher.onNewFiles = { collector.append($0) }
        watcher.start()

        try Data("hello".utf8).write(to: temp.file("notes.txt"))
        try TestImages.writeHEIC(to: temp.file("IMG_1002.HEIC"))

        let detected = await waitUntil {
            collector.all.contains { $0.lastPathComponent == "IMG_1002.HEIC" }
        }
        watcher.stop()

        XCTAssertTrue(detected)
        XCTAssertFalse(collector.all.contains { $0.lastPathComponent == "notes.txt" })
    }
}
