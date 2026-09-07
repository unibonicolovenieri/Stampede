import ArgumentParser
import StampedeCore
import Foundation

/// Mette insieme preset, opzioni CLI, GPU e uploader, e fa girare un batch.
/// Condiviso fra `apply` e `watch` così i due comandi non possono divergere.
struct JobRunner {
    let watermark: WatermarkSpec
    let output: OutputSpec
    let outputRoot: URL
    let pool: GPUContextPool
    let logo: LogoAsset
    let concurrencyOverride: Int?
    let precision: WorkingPrecision
    let driveTarget: RemoteTarget?
    let driveParallel: Int
    let driveAfterBatch: Bool

    struct Assembled {
        let runner: JobRunner
        let preset: Preset
    }

    /// Risolve tutte le opzioni e prepara GPU e logo. Fallisce presto e con messaggi chiari:
    /// meglio scoprire ora che il logo non si apre, che a metà di 800 foto.
    static func assemble(watermarkOptions: WatermarkOptions,
                         outputOptions: OutputOptions,
                         engineOptions: EngineOptions,
                         driveOptions: DriveOptions) throws -> Assembled {
        let store = PresetStore()
        var base = Preset(name: "cli")
        if let name = watermarkOptions.preset {
            base = try store.load(name)
            Log.debug("preset `\(base.name)` caricato")
        }

        let watermark = try watermarkOptions.resolve(base: base.watermark)
        let output = try outputOptions.resolve(base: base.output)

        guard let outputPath = outputOptions.output else {
            throw ValidationError("Manca la cartella di destinazione: usa -o / --output.")
        }
        let outputRoot = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            .standardizedFileURL

        let logoURL = URL(fileURLWithPath: watermark.logoPath).standardizedFileURL
        let logo = try LogoAsset.load(logoURL)
        Log.debug("logo \(logoURL.lastPathComponent): \(logo.kind == .vector ? "vettoriale" : "raster") "
            + "\(Int(logo.nativeSize.width))×\(Int(logo.nativeSize.height))")

        let contexts = engineOptions.gpuContexts
            ?? max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 3))
        let pool = try GPUContextPool(count: contexts,
                                      precision: engineOptions.precision,
                                      blendSpace: engineOptions.blendSpace)
        Log.debug("GPU \(pool.deviceName) — \(pool.size) contesti Core Image, precisione \(engineOptions.precision.rawValue)")

        let target = try driveOptions.makeTarget()
        if target != nil, RcloneUploader.locateExecutable() == nil {
            throw StampedeError.rcloneMissing
        }

        var resolved = base
        resolved.watermark = watermark
        resolved.output = output

        let runner = JobRunner(watermark: watermark,
                               output: output,
                               outputRoot: outputRoot,
                               pool: pool,
                               logo: logo,
                               concurrencyOverride: engineOptions.jobs,
                               precision: engineOptions.precision,
                               driveTarget: target,
                               driveParallel: driveOptions.driveParallel,
                               driveAfterBatch: driveOptions.driveAfterBatch)
        return Assembled(runner: runner, preset: resolved)
    }

    struct RunReport: Codable {
        var processed: Int
        var succeeded: Int
        var failed: Int
        var skipped: Int
        var elapsedSeconds: Double
        var imagesPerSecond: Double
        var megapixelsPerSecond: Double
        var bytesWritten: Int
        var uploaded: Int?
        var uploadFailed: Int?
        var outputDirectory: String
    }

    func run(files: [URL],
             inputRoot: URL?,
             dryRun: Bool,
             showProgress: Bool) async throws -> RunReport {
        let concurrency = concurrencyOverride
            ?? BatchProcessor.recommendedConcurrency(for: files, precision: precision)

        let config = JobConfiguration(watermark: watermark,
                                      output: output,
                                      outputRoot: outputRoot,
                                      inputRoot: inputRoot,
                                      dryRun: dryRun)
        let processor = BatchProcessor(pool: pool, logo: logo, config: config)

        var uploader: RcloneUploader?
        if let driveTarget, !dryRun, !driveAfterBatch {
            uploader = try RcloneUploader(target: driveTarget,
                                          localRoot: outputRoot,
                                          preserveTree: output.preserveTree,
                                          parallelUploads: driveParallel)
            Log.info("upload in streaming verso \(driveTarget.spec)")
        }

        Log.info("\(files.count) foto · \(concurrency) in parallelo · GPU \(pool.deviceName)")
        let progress = ProgressReporter(total: files.count, enabled: showProgress)
        let sink = uploader

        let summary = await processor.run(
            files: files,
            concurrency: concurrency,
            onEvent: { event in
                switch event {
                case .start: break
                case .success(let outcome):
                    progress.advance(failed: false)
                    Log.debug("\(outcome.source.lastPathComponent) → \(outcome.destination.path) "
                        + "(\(Format.duration(outcome.duration)))")
                case .failure(let source, let message):
                    progress.advance(failed: true)
                    Log.error("\(source.lastPathComponent): \(message)")
                case .skipped(let source, let reason):
                    progress.advance(failed: false)
                    Log.debug("salto \(source.lastPathComponent): \(reason)")
                }
            },
            onProduced: sink.map { uploader in { @Sendable url in uploader.enqueue(url) } }
        )
        progress.finish()

        var report = RunReport(processed: summary.total,
                               succeeded: summary.succeeded,
                               failed: summary.failed,
                               skipped: summary.skipped,
                               elapsedSeconds: summary.elapsed,
                               imagesPerSecond: summary.imagesPerSecond,
                               megapixelsPerSecond: summary.megapixelsPerSecond,
                               bytesWritten: summary.bytesWritten,
                               uploaded: nil,
                               uploadFailed: nil,
                               outputDirectory: outputRoot.path)

        if let uploader {
            Log.info("attendo la fine degli upload…")
            let stats = await uploader.finish()
            report.uploaded = stats.uploaded
            report.uploadFailed = stats.failed
        } else if let driveTarget, !dryRun, driveAfterBatch, summary.succeeded > 0 {
            Log.info("sincronizzo \(outputRoot.lastPathComponent) → \(driveTarget.spec)")
            let bulk = try RcloneUploader(target: driveTarget,
                                          localRoot: outputRoot,
                                          preserveTree: output.preserveTree,
                                          parallelUploads: driveParallel)
            try bulk.copyAll(transfers: max(4, driveParallel), showProgress: showProgress)
            report.uploaded = summary.succeeded
            report.uploadFailed = 0
        }
        return report
    }
}
