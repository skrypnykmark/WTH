import Foundation
import os

/// Centralized loggers backed by Apple's unified logging system.
///
/// All categories share the `com.wth.app` subsystem so logs can be
/// filtered in Console.app with:
///
///     subsystem == "com.wth.app"
enum Log {
    static let subsystem = "com.wth.app"

    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let converter = Logger(subsystem: subsystem, category: "converter")
}
