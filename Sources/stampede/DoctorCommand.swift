import ArgumentParser
import CoreImage
import StampedeCore
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Verifica GPU, formati supportati e configurazione di Drive.")

    @Flag(help: "Esegue anche un benchmark reale su immagini sintetiche.")
    var bench: Bool = false

    @Option(help: ArgumentHelp("Quante immagini generare per il benchmark.", valueName: "n"))
    var benchCount: Int = 16

    @Option(name: .customLong("bench-megapixels"), help: ArgumentHelp(
        "Dimensione delle immagini di prova, in megapixel.", valueName: "mp"))
    var benchMegapixels: Double = 24

    func run() async throws {
        section("Macchina")
        let info = ProcessInfo.processInfo
        line("CPU", "\(info.activeProcessorCount) core attivi")
        line("RAM", Format.bytes(Int(info.physicalMemory)))

        section("GPU")
        if let device = MTLCreateSystemDefaultDevice() {
            line("Dispositivo", device.name)
            line("Memoria unificata", device.hasUnifiedMemory ? "sì" : "no")
            line("Working set consigliato", Format.bytes(Int(device.recommendedMaxWorkingSetSize)))
            let workingSpace = CIContext(mtlDevice: device).workingColorSpace?.name as String?
            line("Spazio di lavoro CI", workingSpace ?? "sRGB")
        } else {
            fail("Nessun dispositivo Metal disponibile.")
        }

        section("Formati scrivibili")
        for format in OutputFormat.allCases where format != .keep {
            let writable = format.isWritable()
            line(format.cliName, writable ? "sì" : "no — non disponibile su questo macOS", ok: writable)
        }

        section("Preset")
        for directory in PresetStore.searchPaths {
            let exists = FileManager.default.fileExists(atPath: directory.path)
            line(exists ? "trovata" : "assente", directory.path, ok: true)
        }
        let presets = PresetStore().list()
        line("Preset disponibili", presets.isEmpty ? "nessuno" : presets.map(\.preset.name).joined(separator: ", "))

        section("Google Drive (rclone)")
        if let executable = RcloneUploader.locateExecutable() {
            line("rclone", executable.path)
            let remotes = RcloneUploader.configuredRemotes()
            if remotes.isEmpty {
                line("remote configurati", "nessuno — lancia `rclone config` e crea un remote Drive", ok: false)
            } else {
                line("remote configurati", remotes.joined(separator: ", "))
            }
        } else {
            line("rclone", "non installato — `brew install rclone` (serve solo per --drive)", ok: false)
        }

        if bench { try await runBenchmark() }
    }

    // MARK: - Benchmark

    private func runBenchmark() async throws {
        section("Benchmark")
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stampede-bench-\(UUID().uuidString.prefix(8))")
        let inputDirectory = workspace.appendingPathComponent("in")
        let outputDirectory = workspace.appendingPathComponent("out")
        defer { try? FileManager.default.removeItem(at: workspace) }

        Log.info("genero \(benchCount) immagini da \(Int(benchMegapixels)) MP…")
        let side = (benchMegapixels * 1_000_000 * 4 / 3).squareRoot()
        let size = CGSize(width: (side).rounded(), height: (side * 3 / 4).rounded())
        let files = try SampleGenerator.generate(count: benchCount, size: size, into: inputDirectory)
        let logoURL = try SampleGenerator.generateLogo(into: workspace)

        let pool = try GPUContextPool(count: 4, precision: .balanced, blendSpace: .srgb)
        let logo = try LogoAsset.load(logoURL)
        let watermark = WatermarkSpec(logoPath: logoURL.path, opacity: 0.8)
        let config = JobConfiguration(watermark: watermark,
                                      output: OutputSpec(format: .jpeg, quality: 0.95, overwrite: true),
                                      outputRoot: outputDirectory,
                                      inputRoot: inputDirectory)
        let concurrency = BatchProcessor.recommendedConcurrency(for: files)
        let processor = BatchProcessor(pool: pool, logo: logo, config: config)

        Log.info("elaboro con \(concurrency) immagini in parallelo…")
        let summary = await processor.run(files: files, concurrency: concurrency, onEvent: { event in
            if case .failure(let source, let message) = event {
                Log.error("\(source.lastPathComponent): \(message)")
            }
        })

        line("Immagini", "\(summary.succeeded)/\(summary.total)")
        line("Tempo", Format.duration(summary.elapsed))
        line("Velocità", String(format: "%.1f img/s · %.0f MP/s",
                                summary.imagesPerSecond, summary.megapixelsPerSecond))
        line("Parallelismo", "\(concurrency) foto in volo, \(pool.size) contesti GPU")
        if summary.failed > 0 { fail("\(summary.failed) immagini fallite") }
    }

    // MARK: - Stampa

    private func section(_ title: String) {
        print("\n\u{001B}[1m\(title)\u{001B}[0m")
    }

    private func line(_ key: String, _ value: String, ok: Bool = true) {
        let mark = ok ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[33m!\u{001B}[0m"
        print("  \(mark) \(key.padding(toLength: max(24, key.count + 1), withPad: " ", startingAt: 0))\(value)")
    }

    private func fail(_ message: String) {
        print("  \u{001B}[31m✗\u{001B}[0m \(message)")
    }
}

/// Genera foto e logo sintetici per il benchmark: nessuna dipendenza da file dell'utente.
enum SampleGenerator {
    static func generate(count: Int, size: CGSize, into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = CIContext(options: [.workingFormat: CIFormat.RGBA8, .cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var urls: [URL] = []

        for index in 0..<count {
            let hue = Double(index) / Double(max(1, count))
            let gradient = CIFilter(name: "CILinearGradient")!
            gradient.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            gradient.setValue(CIVector(x: size.width, y: size.height), forKey: "inputPoint1")
            gradient.setValue(CIColor(red: hue, green: 0.35, blue: 1 - hue), forKey: "inputColor0")
            gradient.setValue(CIColor(red: 1 - hue, green: 0.8, blue: hue), forKey: "inputColor1")

            // Un po' di rumore rende il JPEG realisticamente incomprimibile,
            // altrimenti il benchmark misurerebbe una codifica troppo facile.
            let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.12, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.12, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.12, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])

            let rect = CGRect(origin: .zero, size: size)
            let image = noise.applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: gradient.outputImage!.cropped(to: rect),
            ]).cropped(to: rect)

            let url = directory.appendingPathComponent(String(format: "sample-%03d.jpg", index))
            try context.writeJPEGRepresentation(of: image, to: url, colorSpace: colorSpace,
                                                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9])
            urls.append(url)
        }
        return urls
    }

    static func generateLogo(into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = CGSize(width: 800, height: 240)
        let rect = CGRect(origin: .zero, size: size)
        guard let bitmap = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw StampedeError.invalidConfiguration("impossibile creare il logo di prova") }

        bitmap.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        bitmap.setLineWidth(24)
        bitmap.stroke(rect.insetBy(dx: 24, dy: 24))
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        bitmap.fillEllipse(in: CGRect(x: 90, y: 60, width: 120, height: 120))

        guard let cgImage = bitmap.makeImage() else {
            throw StampedeError.invalidConfiguration("impossibile creare il logo di prova")
        }
        let url = directory.appendingPathComponent("bench-logo.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw StampedeError.cannotCreateDestination(url) }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw StampedeError.encodingFailed(url) }
        return url
    }
}
