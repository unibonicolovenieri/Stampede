import ArgumentParser
import EagleFootCore
import Foundation

struct Apply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Applica il watermark a file e cartelle, in parallelo sulla GPU.")

    @Argument(help: ArgumentHelp("File o cartelle da lavorare.", valueName: "input"))
    var inputs: [String] = []

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

    @Flag(name: [.short, .long], help: "Scendi nelle sottocartelle.")
    var recursive: Bool = false

    @Flag(name: .customLong("dry-run"), help: "Mostra cosa verrebbe scritto senza toccare il disco.")
    var dryRun: Bool = false

    @Flag(help: "Stampa il riepilogo come JSON su stdout (per scriptare).")
    var json: Bool = false

    @Option(name: .customLong("save-preset"), help: ArgumentHelp(
        "Salva queste impostazioni come preset riutilizzabile.", valueName: "nome"))
    var savePreset: String?

    func run() async throws {
        verbosity.apply()
        if json { Log.level = max(Log.level, .warn) }

        guard !inputs.isEmpty else {
            throw ValidationError("Indica almeno un file o una cartella da lavorare.")
        }

        let plan = try FileDiscovery.plan(inputs: inputs, recursive: recursive)
        guard !plan.files.isEmpty else {
            throw EagleFootError.noInputsFound(URL(fileURLWithPath: inputs[0]))
        }
        if plan.skippedUnsupported > 0 {
            Log.debug("\(plan.skippedUnsupported) file ignorati perché non sono immagini supportate")
        }

        let assembled = try JobRunner.assemble(watermarkOptions: watermarkOptions,
                                               outputOptions: outputOptions,
                                               engineOptions: engineOptions,
                                               driveOptions: driveOptions)

        if let savePreset {
            var preset = assembled.preset
            preset.name = savePreset
            let url = try PresetStore().save(preset)
            Log.success("preset `\(savePreset)` salvato in \(url.path)")
        }

        if dryRun { Log.warn("dry-run: nessun file verrà scritto") }

        let report = try await assembled.runner.run(files: plan.files,
                                                    inputRoot: plan.root,
                                                    dryRun: dryRun,
                                                    showProgress: !json && !verbosity.quiet)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            Summary.print(report, dryRun: dryRun)
        }

        if report.failed > 0 { throw ExitCode(1) }
    }
}

enum Summary {
    static func print(_ report: JobRunner.RunReport, dryRun: Bool) {
        let verb = dryRun ? "da scrivere" : "scritte"
        Log.success("\(report.succeeded) foto \(verb) in \(Format.duration(report.elapsedSeconds))"
            + " · \(String(format: "%.1f", report.imagesPerSecond)) img/s"
            + " · \(String(format: "%.0f", report.megapixelsPerSecond)) MP/s")
        if report.bytesWritten > 0 {
            Log.info("output: \(report.outputDirectory) (\(Format.bytes(report.bytesWritten)))")
        }
        if report.skipped > 0 { Log.warn("\(report.skipped) saltate (già presenti in destinazione)") }
        if report.failed > 0 { Log.error("\(report.failed) fallite") }
        if let uploaded = report.uploaded {
            let failed = report.uploadFailed ?? 0
            if failed > 0 {
                Log.error("Drive: \(uploaded) caricate, \(failed) fallite")
            } else {
                Log.success("Drive: \(uploaded) foto caricate")
            }
        }
    }
}
