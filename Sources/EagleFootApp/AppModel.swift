import AppKit
import Combine
import EagleFootCore
import SwiftUI

/// Stato dell'applicazione: cartelle scelte, impostazioni del watermark,
/// anteprima e avanzamento del lavoro.
///
/// Le impostazioni sono gli stessi `WatermarkSpec`/`OutputSpec` che usa la riga di
/// comando, quindi un preset salvato qui funziona identico con `eaglefoot apply`
/// e viceversa.
@MainActor
final class AppModel: ObservableObject {

    // MARK: - Cartelle

    @Published var sourceFolder: URL? { didSet { rescanSource() } }
    @Published var destinationFolder: URL?
    @Published var recursive = true { didSet { rescanSource() } }

    // MARK: - Impostazioni

    @Published var watermark = WatermarkSpec() { didSet { schedulePreview() } }
    @Published var output = OutputSpec() { didSet { schedulePreview() } }
    @Published var precision: WorkingPrecision = .balanced
    @Published var blendSpace: BlendSpace = .srgb
    @Published var jobsOverride: Int?

    // MARK: - Drive

    @Published var driveEnabled = false
    @Published var driveRemote = ""
    @Published var drivePath = ""
    @Published var driveStreaming = true
    @Published private(set) var availableRemotes: [String] = []
    @Published private(set) var rcloneInstalled = false

    // MARK: - Anteprima

    @Published private(set) var sourceFiles: [URL] = []
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var previewIsStale = false
    @Published private(set) var previewError: String?
    @Published var previewIndex = 0 { didSet { loadPreviewBase() } }

    // MARK: - Esecuzione

    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var failed = 0
    @Published private(set) var totalToProcess = 0
    @Published private(set) var throughput = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    // MARK: - Preset

    @Published private(set) var presets: [Preset] = []
    private let presetStore = PresetStore()

    private var previewBase: CIImage?
    private var previewScaleFactor: Double = 1
    private var previewTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private let previewContext = CIContext(options: [.cacheIntermediates: false,
                                                     .highQualityDownsample: true])

    var canRun: Bool {
        !isRunning && destinationFolder != nil && !sourceFiles.isEmpty
            && !watermark.logoPath.isEmpty
    }

    var progressFraction: Double {
        totalToProcess > 0 ? Double(completed + failed) / Double(totalToProcess) : 0
    }

    var logoURL: URL? {
        watermark.logoPath.isEmpty ? nil : URL(fileURLWithPath: watermark.logoPath)
    }

    init() {
        reloadPresets()
        refreshRemotes()
    }

    // MARK: - Sorgente e anteprima

    private func rescanSource() {
        guard let sourceFolder else {
            sourceFiles = []
            previewImage = nil
            previewBase = nil
            return
        }
        let recursive = self.recursive
        Task.detached(priority: .userInitiated) {
            let found = FileDiscovery.scan(directory: sourceFolder, recursive: recursive).files
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            await MainActor.run {
                self.sourceFiles = found
                self.previewIndex = 0
                self.loadPreviewBase()
            }
        }
    }

    /// Carica la foto da usare come sfondo dell'anteprima, ridotta una volta sola:
    /// tutte le regolazioni successive lavorano su questa versione piccola, ed è ciò
    /// che rende l'anteprima istantanea anche su file da 60 megapixel.
    private func loadPreviewBase() {
        previewTask?.cancel()
        guard sourceFiles.indices.contains(previewIndex) else {
            previewBase = nil
            previewImage = nil
            return
        }
        let url = sourceFiles[previewIndex]
        previewIsStale = true
        Task.detached(priority: .userInitiated) {
            do {
                let loaded = try ImageLoader.load(url)
                let longest = max(loaded.pixelSize.width, loaded.pixelSize.height)
                let target: CGFloat = 1400
                let factor = longest > target ? target / longest : 1
                let reduced = factor < 1
                    ? WatermarkRenderer.resized(loaded.image,
                                                with: ResizeSpec(mode: .longest, value: Double(target)))
                    : loaded.image
                let normalized = WatermarkRenderer.normalize(reduced)
                await MainActor.run {
                    self.previewBase = normalized
                    self.previewScaleFactor = Double(factor)
                    self.previewError = nil
                    self.renderPreview()
                }
            } catch {
                await MainActor.run {
                    self.previewBase = nil
                    self.previewImage = nil
                    self.previewIsStale = false
                    self.previewError = error.localizedDescription
                }
            }
        }
    }

    private func schedulePreview() {
        previewIsStale = true
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            // Piccola pausa: trascinando uno slider arrivano decine di modifiche al
            // secondo, e ridisegnare per ognuna sprecherebbe lavoro senza che si veda.
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled else { return }
            self?.renderPreview()
        }
    }

    private func renderPreview() {
        guard let previewBase else { return }
        guard !watermark.logoPath.isEmpty else {
            previewImage = nsImage(from: previewBase)
            previewIsStale = false
            return
        }
        do {
            let logo = try LogoCache.shared.asset(for: URL(fileURLWithPath: watermark.logoPath))
            // Il ridimensionamento di output non si applica all'anteprima: cambierebbe
            // solo il numero di pixel, non l'aspetto, e il logo è in proporzione.
            let spec = watermark.scaled(by: previewScaleFactor)
            let composed = try WatermarkRenderer.compose(base: previewBase, logo: logo, spec: spec)
            previewImage = nsImage(from: composed)
            previewError = nil
        } catch {
            previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        previewIsStale = false
    }

    private func nsImage(from image: CIImage) -> NSImage? {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1,
              let cgImage = previewContext.createCGImage(image, from: extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: extent.size)
    }

    func stepPreview(by delta: Int) {
        guard !sourceFiles.isEmpty else { return }
        let count = sourceFiles.count
        previewIndex = ((previewIndex + delta) % count + count) % count
    }

    // MARK: - Preset

    func reloadPresets() {
        presets = presetStore.list().map(\.preset)
    }

    func apply(_ preset: Preset) {
        watermark = preset.watermark
        output = preset.output
        statusMessage = "Preset «\(preset.name)» applicato"
    }

    func savePreset(named name: String, description: String?) {
        do {
            let preset = Preset(name: name, description: description,
                                watermark: watermark, output: output)
            let url = try presetStore.save(preset)
            reloadPresets()
            statusMessage = "Preset salvato in \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Drive

    func refreshRemotes() {
        rcloneInstalled = RcloneUploader.locateExecutable() != nil
        guard rcloneInstalled else { return }
        Task.detached(priority: .utility) {
            let remotes = RcloneUploader.configuredRemotes()
            await MainActor.run {
                self.availableRemotes = remotes
                if self.driveRemote.isEmpty { self.driveRemote = remotes.first ?? "" }
            }
        }
    }

    var driveTarget: RemoteTarget? {
        guard driveEnabled, !driveRemote.isEmpty else { return nil }
        let path = drivePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return RemoteTarget(path.isEmpty ? "\(driveRemote):" : "\(driveRemote):\(path)")
    }

    // MARK: - Esecuzione

    func run() {
        guard canRun, let destinationFolder else { return }
        let files = sourceFiles
        let inputRoot = sourceFolder

        isRunning = true
        completed = 0
        failed = 0
        totalToProcess = files.count
        throughput = ""
        statusMessage = nil
        errorMessage = nil

        let watermark = self.watermark
        let output = self.output
        let precision = self.precision
        let blendSpace = self.blendSpace
        let jobs = self.jobsOverride
        let target = self.driveTarget
        let streaming = self.driveStreaming

        runTask = Task { [weak self] in
            do {
                let validatedWatermark = try watermark.validated()
                let validatedOutput = try output.validated()
                let pool = try GPUContextPool(count: max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 3)),
                                              precision: precision, blendSpace: blendSpace)
                let logo = try LogoAsset.load(URL(fileURLWithPath: validatedWatermark.logoPath))
                let config = JobConfiguration(watermark: validatedWatermark,
                                              output: validatedOutput,
                                              outputRoot: destinationFolder,
                                              inputRoot: inputRoot)
                let processor = BatchProcessor(pool: pool, logo: logo, config: config)

                var uploader: RcloneUploader?
                if let target, streaming {
                    uploader = try RcloneUploader(target: target,
                                                  localRoot: destinationFolder,
                                                  preserveTree: validatedOutput.preserveTree)
                }
                let sink = uploader

                let concurrency = jobs ?? BatchProcessor.recommendedConcurrency(for: files, precision: precision)
                let summary = await processor.run(
                    files: files,
                    concurrency: concurrency,
                    onEvent: { event in
                        Task { @MainActor in self?.handle(event) }
                    },
                    onProduced: sink.map { uploader in { @Sendable url in uploader.enqueue(url) } })

                var uploadNote = ""
                if let uploader {
                    let stats = await uploader.finish()
                    uploadNote = stats.failed > 0
                        ? " · Drive: \(stats.uploaded) caricate, \(stats.failed) fallite"
                        : " · Drive: \(stats.uploaded) caricate"
                } else if let target, summary.succeeded > 0 {
                    let bulk = try RcloneUploader(target: target,
                                                  localRoot: destinationFolder,
                                                  preserveTree: validatedOutput.preserveTree)
                    try bulk.copyAll(transfers: 8, showProgress: false)
                    uploadNote = " · Drive: \(summary.succeeded) caricate"
                }

                await MainActor.run {
                    guard let self else { return }
                    self.isRunning = false
                    self.throughput = String(format: "%.1f img/s · %.0f MP/s",
                                             summary.imagesPerSecond, summary.megapixelsPerSecond)
                    var message = "\(summary.succeeded) foto completate in \(Self.duration(summary.elapsed))"
                    if summary.skipped > 0 { message += " · \(summary.skipped) saltate" }
                    if summary.failed > 0 { message += " · \(summary.failed) fallite" }
                    self.statusMessage = message + uploadNote
                }
            } catch {
                await MainActor.run {
                    self?.isRunning = false
                    self?.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        isRunning = false
        statusMessage = "Interrotto"
    }

    private func handle(_ event: BatchEvent) {
        switch event {
        case .start: break
        case .success: completed += 1
        case .failure(let url, let message):
            failed += 1
            errorMessage = "\(url.lastPathComponent): \(message)"
        case .skipped: completed += 1
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60 ? String(format: "%.1f s", seconds)
                     : String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

/// Tiene in vita l'ultimo logo caricato: l'anteprima lo richiede a ogni ritocco
/// di uno slider, e rileggerlo dal disco ogni volta renderebbe l'interfaccia scattosa.
final class LogoCache: @unchecked Sendable {
    static let shared = LogoCache()
    private let lock = NSLock()
    private var cachedPath: String?
    private var cached: LogoAsset?

    func asset(for url: URL) throws -> LogoAsset {
        lock.lock(); defer { lock.unlock() }
        if let cached, cachedPath == url.path { return cached }
        let asset = try LogoAsset.load(url)
        cached = asset
        cachedPath = url.path
        return asset
    }

    func invalidate() {
        lock.lock(); cached = nil; cachedPath = nil; lock.unlock()
    }
}
