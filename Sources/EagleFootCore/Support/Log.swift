import Foundation

/// Logger minimale, thread-safe, con livelli e output su stderr
/// (stdout resta pulito per output machine-readable).
public enum Log {
    public enum Level: Int, Comparable, Sendable {
        case debug = 0, info = 1, warn = 2, error = 3, quiet = 4
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    nonisolated(unsafe) public static var level: Level = .info
    nonisolated(unsafe) public static var useColor: Bool = isatty(fileno(stderr)) == 1
    private static let lock = NSLock()

    private static func emit(_ prefix: String, _ color: String, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = useColor ? "\(color)\(prefix)\u{001B}[0m \(message)\n" : "\(prefix) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    public static func debug(_ m: @autoclosure () -> String) {
        guard level <= .debug else { return }
        emit("[debug]", "\u{001B}[2m", m())
    }
    public static func info(_ m: @autoclosure () -> String) {
        guard level <= .info else { return }
        emit("[eaglefoot]", "\u{001B}[36m", m())
    }
    public static func warn(_ m: @autoclosure () -> String) {
        guard level <= .warn else { return }
        emit("[attenzione]", "\u{001B}[33m", m())
    }
    public static func error(_ m: @autoclosure () -> String) {
        guard level <= .error else { return }
        emit("[errore]", "\u{001B}[31m", m())
    }
    public static func success(_ m: @autoclosure () -> String) {
        guard level <= .info else { return }
        emit("[ok]", "\u{001B}[32m", m())
    }
}
