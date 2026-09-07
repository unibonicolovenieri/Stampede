import Foundation

/// Destinazione remota in sintassi rclone: `remote:cartella/sottocartella`.
public struct RemoteTarget: Sendable, Equatable {
    public let remote: String
    public let path: String

    public var spec: String { path.isEmpty ? "\(remote):" : "\(remote):\(path)" }

    /// Accetta `gdrive:Foto/2026`, `gdrive:` oppure `gdrive`.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let separator = trimmed.firstIndex(of: ":") else {
            self.remote = trimmed
            self.path = ""
            return
        }
        let remote = String(trimmed[trimmed.startIndex..<separator])
        guard !remote.isEmpty else { return nil }
        self.remote = remote
        self.path = String(trimmed[trimmed.index(after: separator)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// Carica su Google Drive (o su qualunque remote rclone) i file man mano che escono
/// dalla pipeline, così la rete lavora mentre la GPU sta ancora macinando le foto dopo.
public final class RcloneUploader: @unchecked Sendable {

    public struct Stats: Sendable {
        public var uploaded = 0
        public var failed = 0
        public var bytes = 0
    }

    public let target: RemoteTarget
    public let executable: URL
    private let localRoot: URL
    private let preserveTree: Bool
    private let extraArguments: [String]

    private let group = DispatchGroup()
    private let slots: DispatchSemaphore
    private let queue = DispatchQueue(label: "it.lumika.stampede.upload",
                                      qos: .utility, attributes: .concurrent)
    private let lock = NSLock()
    private var stats = Stats()

    /// Cerca `rclone` nel PATH e nelle posizioni standard di Homebrew.
    public static func locateExecutable() -> URL? {
        let candidates = ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone", "/usr/bin/rclone"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let search = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in search.split(separator: ":") {
            let candidate = "\(directory)/rclone"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// I remote configurati (`rclone listremotes`), senza i due punti finali.
    public static func configuredRemotes() -> [String] {
        guard let executable = locateExecutable(),
              let output = try? run(executable, ["listremotes"]).stdout
        else { return [] }
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ": \n")) }
            .filter { !$0.isEmpty }
    }

    public init(target: RemoteTarget,
                localRoot: URL,
                preserveTree: Bool = true,
                parallelUploads: Int = 4,
                extraArguments: [String] = []) throws {
        guard let executable = Self.locateExecutable() else { throw StampedeError.rcloneMissing }
        self.executable = executable
        self.target = target
        self.localRoot = PathUtilities.canonical(localRoot)
        self.preserveTree = preserveTree
        self.extraArguments = extraArguments
        self.slots = DispatchSemaphore(value: max(1, parallelUploads))
    }

    /// Accoda un file e torna subito.
    public func enqueue(_ file: URL) {
        group.enter()
        queue.async { [self] in
            slots.wait()
            defer { slots.signal(); group.leave() }
            upload(file)
        }
    }

    private func upload(_ file: URL) {
        let destination = remotePath(for: file)
        var arguments = ["copyto", file.path, destination,
                         "--transfers", "1",
                         "--retries", "3",
                         "--low-level-retries", "10",
                         "--no-traverse"]
        arguments.append(contentsOf: extraArguments)

        do {
            let result = try Self.run(executable, arguments)
            guard result.exitCode == 0 else {
                record(success: false, bytes: 0)
                Log.error("upload fallito \(file.lastPathComponent): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                return
            }
            let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int) ?? 0
            record(success: true, bytes: size)
            Log.debug("caricato \(destination)")
        } catch {
            record(success: false, bytes: 0)
            Log.error("upload fallito \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Ricostruisce sul remote lo stesso albero che il batch ha creato in locale.
    func remotePath(for file: URL) -> String {
        let relative = preserveTree
            ? (PathUtilities.relativeComponents(of: file, under: localRoot) ?? [file.lastPathComponent])
            : [file.lastPathComponent]
        let joined = relative.joined(separator: "/")
        return target.path.isEmpty ? "\(target.remote):\(joined)" : "\(target.remote):\(target.path)/\(joined)"
    }

    private func record(success: Bool, bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        if success {
            stats.uploaded += 1
            stats.bytes += bytes
        } else {
            stats.failed += 1
        }
    }

    /// Attende che la coda si svuoti e restituisce il bilancio.
    public func finish() async -> Stats {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .utility)) { [self] in
                lock.lock(); let snapshot = stats; lock.unlock()
                continuation.resume(returning: snapshot)
            }
        }
    }

    /// Sincronizzazione in blocco: più efficiente della copia file-per-file
    /// quando il batch è già finito e ci sono centinaia di file da spedire.
    @discardableResult
    public func copyAll(transfers: Int = 8, showProgress: Bool = true) throws -> Int32 {
        var arguments = ["copy", localRoot.path, target.spec,
                         "--transfers", String(transfers),
                         "--checkers", String(transfers * 2),
                         "--retries", "3"]
        if showProgress { arguments.append("--progress") }
        arguments.append(contentsOf: extraArguments)
        let result = try Self.run(executable, arguments, inheritOutput: showProgress)
        if result.exitCode != 0 {
            throw StampedeError.rcloneFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.exitCode
    }

    // MARK: - Esecuzione processo

    struct ProcessResult { let exitCode: Int32; let stdout: String; let stderr: String }

    @discardableResult
    static func run(_ executable: URL, _ arguments: [String], inheritOutput: Bool = false) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        if !inheritOutput {
            process.standardOutput = outPipe
            process.standardError = errPipe
        }
        try process.run()

        var outData = Data()
        var errData = Data()
        if !inheritOutput {
            // Letture prima di `waitUntilExit`: una pipe piena bloccherebbe rclone.
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()

        return ProcessResult(exitCode: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}
