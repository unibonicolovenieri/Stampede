import StampedeCore
import Foundation

/// Barra di avanzamento su stderr, aggiornata al massimo ~12 volte al secondo
/// per non spendere in `write()` il tempo risparmiato sulla GPU.
final class ProgressReporter: @unchecked Sendable {
    private let total: Int
    private let enabled: Bool
    private let started = Date()
    private let lock = NSLock()
    private var done = 0
    private var failed = 0
    private var lastDraw = Date.distantPast
    private var lastLineWidth = 0

    init(total: Int, enabled: Bool) {
        self.total = total
        self.enabled = enabled && isatty(fileno(stderr)) == 1 && total > 0
    }

    func advance(failed didFail: Bool) {
        lock.lock()
        done += 1
        if didFail { failed += 1 }
        let shouldDraw = enabled && (Date().timeIntervalSince(lastDraw) > 0.08 || done == total)
        if shouldDraw { lastDraw = Date() }
        let snapshot = (done, failed)
        lock.unlock()
        if shouldDraw { draw(done: snapshot.0, failed: snapshot.1) }
    }

    private func draw(done: Int, failed: Int) {
        let fraction = Double(done) / Double(total)
        let width = 28
        let filled = Int(fraction * Double(width))
        let bar = String(repeating: "█", count: filled)
            + String(repeating: "░", count: width - filled)

        let elapsed = Date().timeIntervalSince(started)
        let rate = elapsed > 0 ? Double(done) / elapsed : 0
        let remaining = rate > 0 ? Double(total - done) / rate : 0

        var line = "  \(bar) \(done)/\(total)  \(String(format: "%.1f", rate)) img/s"
        if done < total, remaining.isFinite, remaining > 0 {
            line += "  ETA \(Self.clock(remaining))"
        }
        if failed > 0 { line += "  \(failed) errori" }

        lock.lock()
        let padding = max(0, lastLineWidth - line.count)
        lastLineWidth = line.count
        lock.unlock()

        FileHandle.standardError.write(Data("\r\(line)\(String(repeating: " ", count: padding))".utf8))
    }

    func finish() {
        guard enabled else { return }
        FileHandle.standardError.write(Data("\r\(String(repeating: " ", count: lastLineWidth + 2))\r".utf8))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

enum Format {
    static func bytes(_ count: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return index == 0 ? "\(count) B" : String(format: "%.1f %@", value, units[index])
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 1 ? String(format: "%.0f ms", seconds * 1000)
                    : (seconds < 60 ? String(format: "%.1f s", seconds) : ProgressReporter.clock(seconds))
    }
}
