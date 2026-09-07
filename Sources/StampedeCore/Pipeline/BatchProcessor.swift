import CoreImage
import Foundation

/// Tutto ciò che definisce una lavorazione, a parte l'elenco dei file.
public struct JobConfiguration: Sendable {
    public var watermark: WatermarkSpec
    public var output: OutputSpec
    public var outputRoot: URL
    /// Cartella comune degli input, per ricostruire l'albero in destinazione.
    public var inputRoot: URL?
    public var dryRun: Bool

    public init(watermark: WatermarkSpec,
                output: OutputSpec,
                outputRoot: URL,
                inputRoot: URL? = nil,
                dryRun: Bool = false) {
        self.watermark = watermark
        self.output = output
        self.outputRoot = outputRoot
        self.inputRoot = inputRoot
        self.dryRun = dryRun
    }
}

public struct FileOutcome: Sendable {
    public let source: URL
    public let destination: URL
    public let megapixels: Double
    public let bytes: Int
    public let duration: TimeInterval
}

public enum BatchEvent: Sendable {
    case start(total: Int)
    case success(FileOutcome)
    case failure(source: URL, message: String)
    case skipped(source: URL, reason: String)
}

public struct BatchSummary: Sendable {
    public var total = 0
    public var succeeded = 0
    public var failed = 0
    public var skipped = 0
    public var megapixels: Double = 0
    public var bytesWritten = 0
    public var elapsed: TimeInterval = 0

    public var imagesPerSecond: Double { elapsed > 0 ? Double(succeeded) / elapsed : 0 }
    public var megapixelsPerSecond: Double { elapsed > 0 ? megapixels / elapsed : 0 }
}

/// Esegue il watermarking su molte foto sfruttando GPU e core CPU insieme.
///
/// Ogni foto attraversa decodifica (CPU) → composizione (GPU) → codifica (CPU).
/// Tenendo N foto in volo, le tre fasi di immagini diverse si sovrappongono e
/// nessuna delle due unità resta ferma ad aspettare l'altra.
public final class BatchProcessor: @unchecked Sendable {
    private let pool: GPUContextPool
    private let logo: LogoAsset
    private let config: JobConfiguration
    private let workQueue = DispatchQueue(label: "it.lumika.stampede.render",
                                          qos: .userInitiated,
                                          attributes: .concurrent)

    public init(pool: GPUContextPool, logo: LogoAsset, config: JobConfiguration) {
        self.pool = pool
        self.logo = logo
        self.config = config
    }

    /// Concorrenza suggerita: limitata dai core, ma soprattutto dalla memoria.
    ///
    /// Una foto da 45 MP in half-float occupa ~360 MB per copia intermedia; aprirne
    /// dieci insieme farebbe swappare la macchina e andrebbe più piano, non più forte.
    public static func recommendedConcurrency(for files: [URL],
                                              precision: WorkingPrecision = .balanced) -> Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let sample = files.prefix(24).compactMap(ImageLoader.pixelSize)
        guard !sample.isEmpty else { return max(2, min(cores, 6)) }

        let megapixels = sample
            .map { Double($0.width * $0.height) / 1_000_000 }
            .sorted()[sample.count / 2]
        let bytesPerPixel: Double = switch precision {
        case .fast: 4
        case .balanced: 8
        case .maximum: 16
        }
        // ~3.5 copie vive per immagine: sorgente decodificato, intermedio GPU, bitmap di uscita.
        let perImageBytes = max(1, megapixels * 1_000_000 * bytesPerPixel * 3.5)
        let budget = min(Double(ProcessInfo.processInfo.physicalMemory) * 0.45, 8 * 1024 * 1024 * 1024)
        let byMemory = Int(budget / perImageBytes)
        return max(2, min(cores, byMemory, 12))
    }

    /// - Parameter onProduced: chiamato appena un file è su disco. Deve solo accodare
    ///   il lavoro (es. l'upload) e tornare subito: qualunque attesa qui frenerebbe la GPU.
    public func run(files: [URL],
                    concurrency: Int,
                    onEvent: @escaping @Sendable (BatchEvent) -> Void,
                    onProduced: (@Sendable (URL) -> Void)? = nil) async -> BatchSummary {
        var summary = BatchSummary()
        summary.total = files.count
        onEvent(.start(total: files.count))
        guard !files.isEmpty else { return summary }

        let started = Date()
        let limit = max(1, min(concurrency, files.count))

        await withTaskGroup(of: BatchEvent.self) { group in
            var next = 0
            // Finestra scorrevole: sempre `limit` immagini in volo, mai una di più.
            // Appena una esce dalla pipeline ne entra un'altra.
            func schedule() {
                guard next < files.count else { return }
                let file = files[next]
                let index = next
                next += 1
                group.addTask { [self] in await processAsync(file, index: index) }
            }

            for _ in 0..<limit { schedule() }

            while let event = await group.next() {
                onEvent(event)
                switch event {
                case .success(let outcome):
                    summary.succeeded += 1
                    summary.megapixels += outcome.megapixels
                    summary.bytesWritten += outcome.bytes
                    if !config.dryRun { onProduced?(outcome.destination) }
                case .failure:
                    summary.failed += 1
                case .skipped:
                    summary.skipped += 1
                case .start:
                    break
                }
                schedule()
            }
        }

        summary.elapsed = Date().timeIntervalSince(started)
        pool.clearCaches()
        return summary
    }

    // MARK: - Lavorazione di un singolo file

    private func processAsync(_ source: URL, index: Int) async -> BatchEvent {
        await withCheckedContinuation { continuation in
            // Decodifica e codifica sono sincrone e bloccanti: le teniamo fuori dal
            // thread pool cooperativo di Swift Concurrency, che non va mai bloccato.
            workQueue.async { [self] in
                continuation.resume(returning: process(source, index: index))
            }
        }
    }

    private func process(_ source: URL, index: Int) -> BatchEvent {
        let started = Date()
        do {
            let destination = try outputURL(for: source, index: index)
            if PathUtilities.sameFile(destination, source) {
                return .failure(source: source,
                                message: "la destinazione coincide con l'originale — usa -o oppure --suffix")
            }
            if !config.output.overwrite, FileManager.default.fileExists(atPath: destination.path) {
                return .skipped(source: source, reason: "esiste già (usa --overwrite)")
            }
            if config.dryRun {
                return .success(FileOutcome(source: source, destination: destination,
                                            megapixels: 0, bytes: 0,
                                            duration: Date().timeIntervalSince(started)))
            }

            let loaded = try ImageLoader.load(source)
            let composed = try WatermarkRenderer.compose(base: loaded.image,
                                                         logo: logo,
                                                         spec: config.watermark,
                                                         resize: config.output.resize)
            let result = try ImageWriter.write(composed,
                                               to: destination,
                                               context: pool.next(),
                                               source: loaded,
                                               output: config.output)
            let outputMegapixels = Double(result.pixelSize.width * result.pixelSize.height) / 1_000_000
            return .success(FileOutcome(source: source,
                                        destination: result.url,
                                        megapixels: outputMegapixels,
                                        bytes: result.bytes,
                                        duration: Date().timeIntervalSince(started)))
        } catch {
            return .failure(source: source,
                            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func outputURL(for source: URL, index: Int) throws -> URL {
        let filename = config.output.outputFilename(source: source, index: index)
        var directory = config.outputRoot

        if config.output.preserveTree, let root = config.inputRoot {
            for component in PathUtilities.relativeDirectories(of: source, under: root) {
                directory.appendPathComponent(component)
            }
        }
        return directory.appendingPathComponent(filename).standardizedFileURL
    }
}
