import AppKit
import EagleFootCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Salva la finestra dell'app in un PNG, disegnandola da sé.
///
/// Serve a produrre gli screenshot della documentazione in modo riproducibile,
/// senza dipendere dal permesso "Registrazione schermo" e senza che qualcuno
/// debba ricordarsi di rifarli a mano a ogni modifica dell'interfaccia.
///
/// Si attiva solo con `--capture <file.png>`; in uso normale non esiste.
@MainActor
enum WindowCapture {

    struct Request {
        let destination: URL
        let source: URL?
        let logo: URL?
        let tab: String?
        /// Esegue davvero la lavorazione prima di scattare: serve a verificare
        /// che il pulsante "Applica watermark" faccia il suo mestiere.
        let run: Bool
    }

    static func requested() -> Request? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--capture"),
              index + 1 < arguments.count
        else { return nil }

        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        return Request(destination: URL(fileURLWithPath: arguments[index + 1]),
                       source: value("--capture-source").map { URL(fileURLWithPath: $0) },
                       logo: value("--capture-logo").map { URL(fileURLWithPath: $0) },
                       tab: value("--capture-tab"),
                       run: arguments.contains("--capture-run"))
    }

    /// Prepara il modello con dati d'esempio, aspetta che l'anteprima sia pronta,
    /// scatta e chiude.
    /// La scheda dell'ispettore chiesta da `--capture-tab`, se c'è.
    static var requestedTab: InspectorPane.Tab? {
        guard let name = requested()?.tab else { return nil }
        return InspectorPane.Tab(rawValue: name)
    }

    static func perform(_ request: Request, model: AppModel) {
        if let logo = request.logo { model.watermark.logoPath = logo.path }
        if let source = request.source {
            model.sourceFolder = source
            model.destinationFolder = source.deletingLastPathComponent()
                .appendingPathComponent("Consegna")
        }

        Task {
            // Diamo tempo alla scansione della cartella e al primo rendering
            // dell'anteprima: catturare prima mostrerebbe una finestra vuota.
            try? await Task.sleep(nanoseconds: 2_500_000_000)

            if request.run {
                guard model.canRun else {
                    FileHandle.standardError.write(Data("impossibile avviare: manca qualcosa\n".utf8))
                    NSApp.terminate(nil)
                    return
                }
                model.run()
                while model.isRunning {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                FileHandle.standardError.write(
                    Data("esito: \(model.statusMessage ?? "nessuno")\n".utf8))
            }

            capture(to: request.destination)
            NSApp.terminate(nil)
        }
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView
        else {
            FileHandle.standardError.write(Data("nessuna finestra da catturare\n".utf8))
            return
        }

        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)

        guard let cgImage = rep.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        FileHandle.standardError.write(Data("catturato \(url.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))\n".utf8))
    }
}
