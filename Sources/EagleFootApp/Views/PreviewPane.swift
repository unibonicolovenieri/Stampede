import EagleFootCore
import SwiftUI

/// Anteprima dal vivo: la stessa foto che verrà consegnata, in piccolo.
///
/// Usa lo stesso `WatermarkRenderer` del batch, quindi ciò che si vede qui è
/// letteralmente quello che finirà sul file — non un'approssimazione.
struct PreviewPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .underPageBackgroundColor))

                if let image = model.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(20)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                        .opacity(model.previewIsStale ? 0.75 : 1)
                        .animation(.easeOut(duration: 0.12), value: model.previewIsStale)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            filmstrip
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: model.previewError != nil ? "exclamationmark.triangle" : "photo")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(placeholderText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    private var placeholderText: String {
        if let error = model.previewError { return error }
        if model.sourceFolder == nil { return "Scegli una cartella di origine per vedere l'anteprima" }
        if model.sourceFiles.isEmpty { return "Nessuna foto trovata in questa cartella" }
        return "Carico l'anteprima…"
    }

    private var filmstrip: some View {
        HStack(spacing: 10) {
            Button {
                model.stepPreview(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.sourceFiles.count < 2)

            Button {
                model.stepPreview(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.sourceFiles.count < 2)

            if model.sourceFiles.isEmpty {
                Text("Nessuna foto")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.sourceFiles[min(model.previewIndex, model.sourceFiles.count - 1)].lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.previewIndex + 1) di \(model.sourceFiles.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Toggle("Sottocartelle", isOn: $model.recursive)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
