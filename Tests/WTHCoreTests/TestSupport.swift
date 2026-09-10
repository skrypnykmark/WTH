import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WTHCore

enum TestImages {
    static func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func makeNoiseImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = context.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                bytes[offset] = UInt8.random(in: 0...255)
                bytes[offset + 1] = UInt8.random(in: 0...255)
                bytes[offset + 2] = UInt8.random(in: 0...255)
                bytes[offset + 3] = 255
            }
        }
        return context.makeImage()!
    }

    static func makeQuadImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2
        func fill(_ rect: CGRect, _ color: CGColor) {
            context.setFillColor(color)
            context.fill(rect)
        }
        fill(CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        fill(CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight), CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        fill(CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight), CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        fill(CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight), CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        return context.makeImage()!
    }

    static func quadrantColors(of image: CGImage, sampleSize: Int = 8) -> [UInt8] {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var buffer = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: sampleSize * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        }
        let quarter = sampleSize / 4
        let threeQuarters = sampleSize * 3 / 4
        var result: [UInt8] = []
        for (x, y) in [(quarter, quarter), (threeQuarters, quarter), (quarter, threeQuarters), (threeQuarters, threeQuarters)] {
            let offset = (y * sampleSize + x) * 4
            result.append(contentsOf: buffer[offset..<offset + 3])
        }
        return result
    }

    static func writeHEIC(
        to url: URL,
        width: Int = 800,
        height: Int = 600,
        orientation: UInt32 = 1,
        model: String = "iPhone 15 Pro"
    ) throws {
        try writeHEIC(
            to: url,
            image: makeImage(width: width, height: height),
            orientation: orientation,
            model: model
        )
    }

    static func writeHEIC(
        to url: URL,
        image: CGImage,
        orientation: UInt32 = 1,
        model: String = "iPhone 15 Pro"
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw XCTSkip("HEIC encoding is not available on this system.")
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: model],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5,
                kCGImagePropertyGPSLatitudeRef: "N",
            ],
        ]

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("HEIC encoding failed on this system.")
        }
    }
}

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wth-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}

final class OutcomeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConversionOutcome] = []

    func record(_ outcome: ConversionOutcome) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(outcome)
    }

    var outcomes: [ConversionOutcome] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(contentsOf: urls)
    }

    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

final class ScriptedProbe: FileProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshots: [FileSnapshot?]
    private var index = 0

    init(snapshots: [FileSnapshot?]) {
        self.snapshots = snapshots
    }

    func snapshot(at url: URL) throws -> FileSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let snapshot: FileSnapshot?
        if index < snapshots.count {
            snapshot = snapshots[index]
        } else {
            snapshot = snapshots.last ?? nil
        }
        index += 1

        guard let snapshot else {
            throw CocoaError(.fileNoSuchFile)
        }
        return snapshot
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        time += interval
    }

    func read() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return time
    }
}

func makeSnapshot(size: Int64, date: Date = Date(timeIntervalSince1970: 0)) -> FileSnapshot {
    FileSnapshot(size: size, modificationDate: date)
}
