import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Selettore di cartella: si può cliccare "Scegli…" oppure trascinarci sopra
/// una cartella dal Finder.
struct FolderField: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var url: URL?

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(url == nil ? .secondary : Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(url?.lastPathComponent ?? placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(url == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url?.path ?? placeholder)
            }

            Spacer(minLength: 4)

            if url != nil {
                Button {
                    url = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Rimuovi")
            }

            Button("Scegli…", action: choose)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: isTargeted ? 1.5 : 1)
        )
        .dropDestination(for: URL.self) { items, _ in
            guard let dropped = items.first(where: \.hasDirectoryPath) ?? items.first else { return false }
            url = dropped.hasDirectoryPath ? dropped : dropped.deletingLastPathComponent()
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scegli"
        panel.message = title
        panel.directoryURL = url
        if panel.runModal() == .OK { url = panel.url }
    }
}
