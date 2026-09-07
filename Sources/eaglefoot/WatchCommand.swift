import ArgumentParser
import EagleFootCore
import Foundation

struct Watch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Sorveglia una cartella e applica il watermark alle foto che arrivano.",
        discussion: """
        Pensato per la consegna a flusso continuo: scarichi la scheda dentro la cartella
        sorvegliata e le foto escono già firmate (e già su Drive, se hai passato --drive).

        Un file viene preso in carico solo quando la sua dimensione resta stabile per
        --stable-for secondi: così non si lavora mai un JPEG copiato a metà.
        Ctrl-C per fermarsi.
        """)

    @Argument(help: ArgumentHelp("Cartella da sorvegliare.", valueName: "cartella"))
    var directory: String

    @OptionGroup(title: "Watermark")
    var watermarkOptions: WatermarkOptions

    @OptionGroup(title: "Output")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Motore")
    var engineOptions: EngineOptions

    @OptionGroup(title: "Google Drive")
    var driveOptions: DriveOptions

    @OptionGroup(title: "Varie")
    var verbosity: VerbosityOptions

    @Flag(name: [.short, .long], help: "Sorveglia anche le sottocartelle.")
    var recursive: Bool = false

    @Option(help: ArgumentHelp("Secondi fra una scansione e l'altra.", valueName: "s"))
    var interval: Double = 2

    @Option(name: .customLong("stable-for"), help: ArgumentHelp(
        "Per quanti secondi la dimensione di un file deve restare ferma prima di lavorarlo.",
        valueName: "s"))
    var stableFor: Double = 1.5

    @Flag(name: .customLong("process-existing"), help:
        "Lavora anche le foto già presenti all'avvio (di default si parte dal contenuto attuale come 'già visto').")
    var processExisting: Bool = false

    func run() async throws {
        verbosity.apply()

        let watchRoot = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: watchRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw ValidationError("`\(watchRoot.path)` non è una cartella.") }

        let assembled = try JobRunner.assemble(watermarkOptions: watermarkOptions,
                                               outputOptions: outputOptions,
                                               engineOptions: engineOptions,
                                               driveOptions: driveOptions)
        if assembled.runner.driveAfterBatch {
            Log.warn("--drive-after-batch non ha senso in watch: uso l'upload in streaming")
        }

        var seen = Set<String>()
        if !processExisting {
            let existing = FileDiscovery.scan(directory: watchRoot, recursive: recursive).files
            seen = Set(existing.map(\.path))
            Log.info("\(existing.count) foto già presenti verranno ignorate (usa --process-existing per lavorarle)")
        }

        let stopped = StopFlag()
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler { stopped.raise() }
        signalSource.resume()
        signal(SIGINT, SIG_IGN)

        Log.success("in ascolto su \(watchRoot.path) — Ctrl-C per fermarsi")

        // `sizes` ricorda quanto era grande un file al giro precedente: se non è
        // cambiato ed è passato abbastanza tempo, la copia è finita.
        var sizes: [String: (bytes: Int, since: Date)] = [:]
        var totalProcessed = 0

        while !stopped.isRaised {
            let candidates = FileDiscovery.scan(directory: watchRoot, recursive: recursive).files
                .filter { !seen.contains($0.path) }

            var ready: [URL] = []
            let now = Date()
            for file in candidates {
                let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? nil
                guard let bytes else { continue }
                if let previous = sizes[file.path], previous.bytes == bytes {
                    if now.timeIntervalSince(previous.since) >= stableFor { ready.append(file) }
                } else {
                    sizes[file.path] = (bytes, now)
                }
            }

            if !ready.isEmpty {
                let sorted = ready.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                Log.info("\(sorted.count) nuove foto")
                let report = try await assembled.runner.run(files: sorted,
                                                            inputRoot: watchRoot,
                                                            dryRun: false,
                                                            showProgress: !verbosity.quiet)
                Summary.print(report, dryRun: false)
                totalProcessed += report.succeeded
                for file in sorted {
                    seen.insert(file.path)
                    sizes.removeValue(forKey: file.path)
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(max(0.2, interval) * 1_000_000_000))
        }

        signalSource.cancel()
        Log.success("fermato — \(totalProcessed) foto lavorate in questa sessione")
    }
}

/// Piccolo flag condiviso fra il gestore di SIGINT e il ciclo principale.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.lock(); defer { lock.unlock() }
        return raised
    }

    func raise() {
        lock.lock(); raised = true; lock.unlock()
        Log.warn("interruzione richiesta, chiudo dopo il batch in corso…")
    }
}
