import StampedeCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var capture = WindowCapture.requested()
    @State private var showingSavePreset = false
    @State private var showingCommand = false

    var body: some View {
        VStack(spacing: 0) {
            folderBar
            Divider()
            HSplitView {
                PreviewPane()
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                // Un solo `frame`: incatenandone due (uno fisso e uno con i limiti)
                // l'HSplitView non riempiva la finestra e restava una fascia scoperta.
                InspectorPane()
                    .frame(minWidth: 360, idealWidth: 384, maxWidth: 460, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            RunBar()
        }
        // Sfondo esplicito: senza, le aree non coperte dai pannelli restano nere.
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbarContent }
        .onAppear {
            if let capture { WindowCapture.perform(capture, model: model) }
        }
        .sheet(isPresented: $showingSavePreset) { SavePresetSheet() }
        .sheet(isPresented: $showingCommand) { CommandSheet() }
        .alert("Qualcosa non ha funzionato",
               isPresented: .init(get: { model.errorMessage != nil },
                                  set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var folderBar: some View {
        HStack(spacing: 12) {
            FolderField(title: "Cartella di origine",
                        systemImage: "photo.on.rectangle.angled",
                        placeholder: "Trascina qui una cartella",
                        url: $model.sourceFolder)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12, weight: .semibold))
            FolderField(title: "Cartella di destinazione",
                        systemImage: "folder",
                        placeholder: "Dove salvare le foto firmate",
                        url: $model.destinationFolder)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                if model.presets.isEmpty {
                    Text("Nessun preset salvato")
                } else {
                    ForEach(model.presets, id: \.name) { preset in
                        Button(preset.name) { model.apply(preset) }
                    }
                }
                Divider()
                Button("Salva impostazioni come preset…") { showingSavePreset = true }
                Button("Ricarica dal disco") { model.reloadPresets() }
            } label: {
                Label("Preset", systemImage: "slider.horizontal.3")
            }
            .help("Applica o salva un profilo di lavorazione")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showingCommand = true
            } label: {
                Label("Comando", systemImage: "terminal")
            }
            .help("Mostra il comando da terminale equivalente")
        }
    }
}
