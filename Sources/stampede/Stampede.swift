import ArgumentParser
import StampedeCore
import Foundation

@main
struct Stampede: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stampede",
        abstract: "Watermarking di massa accelerato dalla GPU.",
        discussion: """
        Stampede stampa il tuo logo su intere cartelle di foto usando Core Image e Metal,
        mantenendo risoluzione, profilo colore e metadati EXIF dell'originale.

        Esempi
          stampede apply ~/Scatti -o ~/Consegna --logo ~/logo.png --scale 15% --anchor bottom-right
          stampede apply ~/Scatti -o ~/Consegna --preset social --drive gdrive:Foto/2026
          stampede watch ~/Ingest -o ~/Consegna --preset consegna --drive gdrive:Consegne
          stampede doctor
        """,
        version: "0.2.0",
        subcommands: [Apply.self, Watch.self, PresetCommand.self, Doctor.self, SelfTest.self],
        defaultSubcommand: Apply.self)
}
