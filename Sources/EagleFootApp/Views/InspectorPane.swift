import AppKit
import EagleFootCore
import SwiftUI
import UniformTypeIdentifiers

/// Tutte le opzioni disponibili da riga di comando, divise in tre schede perché
/// una colonna sola con quaranta controlli non si leggerebbe.
struct InspectorPane: View {
    enum Tab: String, CaseIterable, Identifiable {
        case watermark = "Watermark"
        case output = "Output"
        case advanced = "Avanzate"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    // Letto dagli argomenti invece che da una variabile impostata altrove: così non
    // conta l'ordine in cui vista e modalità di cattura vengono inizializzate.
    @State private var tab: Tab = WindowCapture.requestedTab ?? .watermark

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Niente ScrollView attorno: un Form `.grouped` scorre già per conto suo,
            // e annidarlo gli fa perdere lo sfondo di sistema.
            switch tab {
            case .watermark: WatermarkSettings()
            case .output: OutputSettings()
            case .advanced: AdvancedSettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Scheda Watermark

private struct WatermarkSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Logo") {
                LogoPicker()
            }

            Section("Disposizione") {
                Picker("Tipo", selection: $model.watermark.layout) {
                    Text("Singolo").tag(WatermarkLayout.single)
                    Text("Mosaico").tag(WatermarkLayout.tile)
                }
                .pickerStyle(.segmented)

                if model.watermark.layout == .single {
                    LabeledContent("Posizione") {
                        AncherGridRow(anchor: $model.watermark.single.anchor)
                    }
                    MeasureControl(title: "Margine ↔",
                                   value: $model.watermark.single.marginX,
                                   unit: $model.watermark.single.marginUnit,
                                   fractionRange: 0...0.25, pixelRange: 0...600)
                    MeasureControl(title: "Margine ↕",
                                   value: $model.watermark.single.marginY,
                                   unit: $model.watermark.single.marginUnit,
                                   fractionRange: 0...0.25, pixelRange: 0...600)
                } else {
                    SliderRow(title: "Inclinazione", value: $model.watermark.tile.angle,
                              range: -90...90, format: "%.0f°")
                    SliderRow(title: "Spaziatura ↔", value: $model.watermark.tile.spacingX,
                              range: 0...3, format: "%.2f×")
                    SliderRow(title: "Spaziatura ↕", value: $model.watermark.tile.spacingY,
                              range: 0...3, format: "%.2f×")
                    Toggle("Righe sfalsate a mattoni", isOn: $model.watermark.tile.stagger)
                    Text("Il reticolo sfalsato e inclinato è più difficile da rimuovere in post.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Aspetto") {
                MeasureControl(title: "Dimensione",
                               value: $model.watermark.scale.value,
                               unit: $model.watermark.scale.unit,
                               fractionRange: 0.01...1, pixelRange: 20...4000)
                Picker("Rispetto a", selection: $model.watermark.scale.reference) {
                    Text("Larghezza").tag(ScaleReference.width)
                    Text("Altezza").tag(ScaleReference.height)
                    Text("Lato lungo").tag(ScaleReference.longest)
                    Text("Lato corto").tag(ScaleReference.shortest)
                    Text("Diagonale").tag(ScaleReference.diagonal)
                }
                .disabled(model.watermark.scale.unit == .pixels)

                SliderRow(title: "Opacità", value: $model.watermark.opacity,
                          range: 0...1, format: "%.0f%%", displayScale: 100)
                SliderRow(title: "Rotazione", value: $model.watermark.rotation,
                          range: -180...180, format: "%.0f°")

                Picker("Fusione", selection: $model.watermark.blend) {
                    ForEach(BlendMode.allCases, id: \.self) { mode in
                        Text(Self.blendLabel(mode)).tag(mode)
                    }
                }
            }

            Section("Ombra") {
                Toggle("Ombra dietro al logo", isOn: shadowEnabled)
                if let shadow = model.watermark.shadow {
                    SliderRow(title: "Sfocatura",
                              value: Binding(get: { shadow.radius },
                                             set: { model.watermark.shadow?.radius = $0 }),
                              range: 0...40, format: "%.0f px")
                    SliderRow(title: "Intensità",
                              value: Binding(get: { shadow.opacity },
                                             set: { model.watermark.shadow?.opacity = $0 }),
                              range: 0...1, format: "%.0f%%", displayScale: 100)
                }
                Text("Utile quando il logo è chiaro e finisce su cieli o abiti bianchi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shadowEnabled: Binding<Bool> {
        Binding(get: { model.watermark.shadow != nil },
                set: { model.watermark.shadow = $0 ? ShadowSpec() : nil })
    }

    static func blendLabel(_ mode: BlendMode) -> String {
        switch mode {
        case .normal: "Normale"
        case .multiply: "Moltiplica"
        case .screen: "Scolora"
        case .overlay: "Sovrapponi"
        case .softLight: "Luce soffusa"
        case .hardLight: "Luce intensa"
        case .darken: "Scurisci"
        case .lighten: "Schiarisci"
        case .difference: "Differenza"
        case .luminosity: "Luminosità"
        }
    }
}

// MARK: - Scheda Output

private struct OutputSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var resizeMode: ResizeChoice = .none

    enum ResizeChoice: String, CaseIterable, Identifiable {
        case none, longest, width, height, percent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "Nessuno"
            case .longest: "Lato lungo"
            case .width: "Larghezza"
            case .height: "Altezza"
            case .percent: "Percentuale"
            }
        }
    }

    var body: some View {
        Form {
            Section("Formato") {
                Picker("Formato", selection: $model.output.format) {
                    Text("Come l'originale").tag(OutputFormat.keep)
                    Text("JPEG").tag(OutputFormat.jpeg)
                    Text("PNG").tag(OutputFormat.png)
                    Text("TIFF").tag(OutputFormat.tiff)
                    Text("HEIC").tag(OutputFormat.heic)
                    if OutputFormat.webp.isWritable() {
                        Text("WebP").tag(OutputFormat.webp)
                    }
                }

                if !model.output.format.isLossless {
                    SliderRow(title: "Qualità", value: $model.output.quality,
                              range: 0.5...1, format: "%.0f%%", displayScale: 100)
                }

                Picker("Profondità", selection: $model.output.bitDepth) {
                    Text("8 bit per canale").tag(BitDepth.eight)
                    Text("16 bit per canale").tag(BitDepth.sixteen)
                }
                .disabled(!supportsDeepColor)
                if !supportsDeepColor {
                    Text("I 16 bit sono disponibili solo con PNG o TIFF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Profilo colore", selection: $model.output.colorSpace) {
                    Text("Come l'originale").tag(ColorSpacePolicy.source)
                    Text("sRGB").tag(ColorSpacePolicy.srgb)
                    Text("Display P3").tag(ColorSpacePolicy.displayP3)
                    Text("Adobe RGB").tag(ColorSpacePolicy.adobeRGB)
                }
            }

            Section("Dimensioni") {
                Picker("Ridimensiona", selection: $resizeMode) {
                    ForEach(ResizeChoice.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: resizeMode) { _, _ in applyResize() }

                if resizeMode != .none {
                    LabeledContent(resizeMode == .percent ? "Percentuale" : "Pixel") {
                        TextField("", value: resizeValue, format: .number)
                            .labelsHidden()
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Permetti l'ingrandimento", isOn: Binding(
                        get: { model.output.resize?.allowUpscale ?? false },
                        set: { model.output.resize?.allowUpscale = $0 }))
                    Text("Senza questa opzione le foto già più piccole del target restano intatte.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("File") {
                LabeledContent("Nome") {
                    TextField("", text: $model.output.filenameTemplate,
                              prompt: Text("{name}{ext}"))
                        .labelsHidden()
                        .frame(maxWidth: 190)
                }
                Text("Segnaposto: {name} {ext} {parent} {index} {date}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Ricrea l'albero delle sottocartelle", isOn: $model.output.preserveTree)
                Toggle("Sovrascrivi i file già presenti", isOn: $model.output.overwrite)
            }

            Section("Metadati") {
                Toggle("Conserva EXIF, IPTC e XMP", isOn: $model.output.preserveMetadata)
                Toggle("Rimuovi le coordinate GPS", isOn: $model.output.stripGPS)
                    .disabled(!model.output.preserveMetadata)
                Text("L'orientamento EXIF viene sempre applicato ai pixel e azzerato nel file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { syncResizeMode() }
    }

    private var supportsDeepColor: Bool {
        model.output.format == .png || model.output.format == .tiff || model.output.format == .keep
    }

    private var resizeValue: Binding<Double> {
        Binding(get: { model.output.resize?.value ?? 0 },
                set: { model.output.resize?.value = $0 })
    }

    private func syncResizeMode() {
        resizeMode = switch model.output.resize?.mode {
        case .none: .none
        case .some(.longest): .longest
        case .some(.width): .width
        case .some(.height): .height
        case .some(.percent): .percent
        }
    }

    private func applyResize() {
        let upscale = model.output.resize?.allowUpscale ?? false
        switch resizeMode {
        case .none:
            model.output.resize = nil
        case .longest:
            model.output.resize = ResizeSpec(mode: .longest, value: 2048, allowUpscale: upscale)
        case .width:
            model.output.resize = ResizeSpec(mode: .width, value: 2048, allowUpscale: upscale)
        case .height:
            model.output.resize = ResizeSpec(mode: .height, value: 1365, allowUpscale: upscale)
        case .percent:
            model.output.resize = ResizeSpec(mode: .percent, value: 50, allowUpscale: upscale)
        }
    }
}

// MARK: - Scheda Avanzate

private struct AdvancedSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Google Drive") {
                if model.rcloneInstalled {
                    Toggle("Carica su Drive a fine lavorazione", isOn: $model.driveEnabled)

                    if model.driveEnabled {
                        if model.availableRemotes.isEmpty {
                            Text("Nessun remote configurato. Lancia `./scripts/setup-drive.sh` dal Terminale.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Account", selection: $model.driveRemote) {
                                ForEach(model.availableRemotes, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        LabeledContent("Cartella") {
                            TextField("", text: $model.drivePath,
                                      prompt: Text("Consegne/2026"))
                                .labelsHidden()
                                .frame(maxWidth: 190)
                        }
                        Picker("Momento", selection: $model.driveStreaming) {
                            Text("Durante l'elaborazione").tag(true)
                            Text("Tutto alla fine").tag(false)
                        }
                        Text(model.driveStreaming
                             ? "Ogni foto parte appena è pronta: quando la GPU finisce, gran parte è già caricata."
                             : "Un solo trasferimento in blocco: più efficiente su molti file piccoli.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("rclone") { Text("non installato").foregroundStyle(.secondary) }
                    Text("Serve per l'upload su Drive. Installalo con `brew install rclone`, poi riapri l'app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Ricontrolla") { model.refreshRemotes() }
                }
            }

            Section("Motore") {
                Picker("Precisione", selection: $model.precision) {
                    Text("Veloce (8 bit)").tag(WorkingPrecision.fast)
                    Text("Bilanciata (16 bit)").tag(WorkingPrecision.balanced)
                    Text("Massima (32 bit)").tag(WorkingPrecision.maximum)
                }
                Picker("Spazio di fusione", selection: $model.blendSpace) {
                    Text("sRGB (come Photoshop)").tag(BlendSpace.srgb)
                    Text("Lineare (fisicamente corretto)").tag(BlendSpace.linear)
                }

                Toggle("Scegli io quante foto in parallelo", isOn: Binding(
                    get: { model.jobsOverride != nil },
                    set: { model.jobsOverride = $0 ? ProcessInfo.processInfo.activeProcessorCount : nil }))

                if let jobs = model.jobsOverride {
                    LabeledContent("In parallelo") {
                        Stepper("\(jobs)", value: Binding(
                            get: { jobs },
                            set: { model.jobsOverride = $0 }), in: 1...24)
                    }
                }
                Text("Di default il numero è calcolato su core e memoria: una foto da 45 MP occupa "
                     + "circa 360 MB mentre viene lavorata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
