import ArgumentParser
import EagleFootCore
import Foundation

@main
struct EagleFoot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eaglefoot",
        abstract: "Watermarking di massa accelerato dalla GPU.",
        discussion: """
        EagleFoot stampa il tuo logo su intere cartelle di foto usando Core Image e Metal,
        mantenendo risoluzione, profilo colore e metadati EXIF dell'originale.

        Esempi
          eaglefoot apply ~/Scatti -o ~/Consegna --logo ~/logo.png --scale 15% --anchor bottom-right
          eaglefoot apply ~/Scatti -o ~/Consegna --preset social --drive gdrive:Foto/2026
          eaglefoot watch ~/Ingest -o ~/Consegna --preset consegna --drive gdrive:Consegne
          eaglefoot doctor
        """,
        version: "0.1.0",
        subcommands: [Apply.self, Watch.self, PresetCommand.self, Doctor.self, SelfTest.self],
        defaultSubcommand: Apply.self)
}
