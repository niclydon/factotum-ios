import Foundation

/// Tiered logging system matching the TypeScript console-logger pattern.
/// Levels (cumulative):
///   minimal  — errors and warnings only
///   normal   — key lifecycle events (default)
///   verbose  — function entry/exit, timing, branch outcomes
///   debug    — raw responses, intermediate state, poll cycles
enum LogLevel: Int, Comparable {
    case minimal = 0
    case normal = 1
    case verbose = 2
    case debug = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Shared logger with configurable level.
/// Set `Logger.shared.level` at startup (from .env, UserDefaults, or launch arg).
@Observable
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    var level: LogLevel = .normal

    private init() {
        // Check for LOG_LEVEL env var or UserDefaults
        if let envLevel = ProcessInfo.processInfo.environment["LOG_LEVEL"] {
            switch envLevel.lowercased() {
            case "minimal": level = .minimal
            case "verbose": level = .verbose
            case "debug": level = .debug
            default: level = .normal
            }
        }
    }

    /// Errors and warnings — always prints regardless of level
    func logMinimal(_ prefix: String, _ items: Any...) {
        print("[\(prefix)]", items.map { "\($0)" }.joined(separator: " "))
    }

    /// Key lifecycle events — prints at normal+
    func log(_ prefix: String, _ items: Any...) {
        guard level >= .normal else { return }
        print("[\(prefix)]", items.map { "\($0)" }.joined(separator: " "))
    }

    /// Function entry/exit, timing, branch outcomes — prints at verbose+
    func logVerbose(_ prefix: String, _ items: Any...) {
        guard level >= .verbose else { return }
        print("[\(prefix)]", items.map { "\($0)" }.joined(separator: " "))
    }

    /// Raw responses, intermediate state — prints at debug only
    func logDebug(_ prefix: String, _ items: Any...) {
        guard level >= .debug else { return }
        print("[\(prefix)]", items.map { "\($0)" }.joined(separator: " "))
    }

    /// Returns elapsed time in ms when called
    func time(_ prefix: String, _ label: String) -> () -> Void {
        let start = Date()
        return {
            guard self.level >= .verbose else { return }
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            print("[\(prefix)] \(label): \(elapsed)ms")
        }
    }
}
