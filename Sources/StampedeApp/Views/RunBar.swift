import StampedeCore
import SwiftUI

/// Barra inferiore: stato, avanzamento e il pulsante che fa partire tutto.
struct RunBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(model.isRunning ? .primary : .secondary)
                    .lineLimit(1)

                if model.isRunning {
                    ProgressView(value: model.progressFraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 340)
                }
            }

            Spacer()

            if model.isRunning {
                Button("Interrompi", role: .destructive) { model.cancel() }
            }

            Button {
                model.run()
            } label: {
                Label(model.isRunning ? "In corso…" : "Applica watermark",
                      systemImage: "wand.and.stars")
                    .frame(minWidth: 130)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canRun)
            .help(model.canRun ? "⌘↩" : blockedReason)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusText: String {
        if model.isRunning {
            let done = model.completed + model.failed
            return "\(done) di \(model.totalToProcess)"
                + (model.failed > 0 ? " · \(model.failed) errori" : "")
        }
        if let message = model.statusMessage {
            return model.throughput.isEmpty ? message : "\(message) · \(model.throughput)"
        }
        if model.sourceFiles.isEmpty { return "Pronto" }
        return "\(model.sourceFiles.count) foto pronte"
    }

    /// Spiega *cosa* manca invece di lasciare il pulsante grigio senza motivo.
    private var blockedReason: String {
        if model.sourceFolder == nil { return "Scegli la cartella di origine" }
        if model.sourceFiles.isEmpty { return "Nessuna foto nella cartella di origine" }
        if model.destinationFolder == nil { return "Scegli la cartella di destinazione" }
        if model.watermark.logoPath.isEmpty { return "Scegli il file del logo" }
        return ""
    }
}
