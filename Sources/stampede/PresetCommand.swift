import ArgumentParser
import StampedeCore
import Foundation

struct PresetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preset",
        abstract: "Gestisce i profili di lavorazione riutilizzabili.",
        discussion: """
        I preset vengono cercati prima in ./presets del progetto, poi in
        ~/.config/stampede/presets. Sono normali file JSON: puoi versionarli,
        condividerli con il resto dello studio o modificarli a mano.
        """,
        subcommands: [List.self, Show.self, Save.self, Delete.self, Path.self],
        defaultSubcommand: List.self)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Elenca i preset disponibili.")

        func run() throws {
            let entries = PresetStore().list()
            guard !entries.isEmpty else {
                print("Nessun preset. Creane uno con: stampede apply … --save-preset <nome>")
                return
            }
            for (preset, url) in entries {
                let layout = preset.watermark.layout == .tile ? "mosaico" : preset.watermark.single.anchor.cliName
                let scale = preset.watermark.scale.unit == .pixels
                    ? "\(Int(preset.watermark.scale.value))px"
                    : "\(Int(preset.watermark.scale.value * 100))%"
                print("\(preset.name.padding(toLength: max(18, preset.name.count + 2), withPad: " ", startingAt: 0))"
                    + "\(layout) · \(scale) · opacità \(Int(preset.watermark.opacity * 100))%"
                    + " · \(preset.output.format.cliName)")
                if let description = preset.description { print("  \(description)") }
                Log.debug(url.path)
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stampa un preset come JSON.")

        @Argument(help: "Nome del preset.")
        var name: String

        func run() throws {
            let preset = try PresetStore().load(name)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(preset), as: UTF8.self))
        }
    }

    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Crea un preset dalle opzioni passate qui.")

        @Argument(help: "Nome del preset.")
        var name: String

        @Option(help: "Descrizione libera mostrata da `preset list`.")
        var description: String?

        @Flag(name: .customLong("project"), help: "Salva in ./presets invece che in ~/.config/stampede/presets.")
        var project: Bool = false

        @OptionGroup(title: "Watermark")
        var watermarkOptions: WatermarkOptions

        @OptionGroup(title: "Output")
        var outputOptions: OutputOptions

        func run() throws {
            let store = PresetStore()
            let base = watermarkOptions.preset.flatMap { try? store.load($0) } ?? Preset(name: name)
            let preset = Preset(name: name,
                                description: description,
                                watermark: try watermarkOptions.resolve(base: base.watermark),
                                output: try outputOptions.resolve(base: base.output))
            let url = try store.save(preset, to: project ? PresetStore.projectDirectory : nil)
            Log.success("preset `\(name)` salvato in \(url.path)")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Elimina un preset.")

        @Argument(help: "Nome del preset.")
        var name: String

        func run() throws {
            try PresetStore().delete(name)
            Log.success("preset `\(name)` eliminato")
        }
    }

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra dove vengono cercati i preset.")

        func run() {
            for directory in PresetStore.searchPaths {
                let exists = FileManager.default.fileExists(atPath: directory.path)
                print("\(exists ? "✓" : "·") \(directory.path)")
            }
        }
    }
}
