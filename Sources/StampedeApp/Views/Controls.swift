import AppKit
import StampedeCore
import SwiftUI
import UniformTypeIdentifiers

/// Riga con slider e valore leggibile a destra.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var displayScale: Double = 1

    var body: some View {
        // Etichetta e valore sopra, slider a tutta larghezza sotto: in una colonna
        // da 380 pt, mettere tutto su una riga lascerebbe allo slider una trentina
        // di pixel, inutilizzabili.
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value * displayScale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
        .padding(.vertical, 1)
    }
}

/// Misura esprimibile in percentuale della foto oppure in pixel assoluti.
///
/// La percentuale è quasi sempre la scelta giusta: lo stesso preset dà un logo
/// proporzionato sia su un file da 12 MP sia su uno da 60.
struct MeasureControl: View {
    let title: String
    @Binding var value: Double
    @Binding var unit: SizeUnit
    let fractionRange: ClosedRange<Double>
    let pixelRange: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                Text(unit == .fraction
                     ? String(format: "%.1f%%", value * 100)
                     : String(format: "%.0f px", value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Picker("", selection: $unit) {
                    Text("%").tag(SizeUnit.fraction)
                    Text("px").tag(SizeUnit.pixels)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 62)
                .controlSize(.small)
                .onChange(of: unit) { old, new in convert(from: old, to: new) }
            }
            Slider(value: $value, in: unit == .fraction ? fractionRange : pixelRange)
        }
        .padding(.vertical, 1)
    }

    /// Cambiando unità si conserva l'ordine di grandezza, così lo slider non salta
    /// da "18%" a "18 pixel" lasciando il logo invisibile.
    private func convert(from old: SizeUnit, to new: SizeUnit) {
        guard old != new else { return }
        switch new {
        case .pixels: value = (value * 4000).rounded().clamped(to: pixelRange)
        case .fraction: value = (value / 4000).clamped(to: fractionRange)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// La griglia 3×3 dentro una riga di Form.
struct AncherGridRow: View {
    @Binding var anchor: Anchor

    var body: some View {
        HStack(spacing: 10) {
            AnchorGrid(anchor: $anchor)
            Text(Self.label(anchor))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func label(_ anchor: Anchor) -> String {
        switch anchor {
        case .topLeft: "In alto a sinistra"
        case .topCenter: "In alto al centro"
        case .topRight: "In alto a destra"
        case .middleLeft: "Al centro a sinistra"
        case .center: "Al centro"
        case .middleRight: "Al centro a destra"
        case .bottomLeft: "In basso a sinistra"
        case .bottomCenter: "In basso al centro"
        case .bottomRight: "In basso a destra"
        }
    }
}

/// Scelta del file del logo, con anteprima e indicazione se è raster o vettoriale.
struct LogoPicker: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                logoThumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.logoURL?.lastPathComponent ?? "Nessun logo scelto")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let kind = logoKind {
                        Text(kind)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Scegli…", action: choose)
                    .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: isTargeted ? 1.5 : 1))
            .dropDestination(for: URL.self) { items, _ in
                guard let file = items.first else { return false }
                setLogo(file)
                return true
            } isTargeted: { isTargeted = $0 }

            Text("PNG o TIFF con trasparenza. PDF e SVG restano nitidi a qualunque risoluzione.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var logoThumbnail: some View {
        ZStack {
            // Scacchiera come in Photoshop: quasi tutti i logo sono bianchi su
            // trasparente, e su fondo chiaro il riquadro sembrerebbe vuoto.
            Checkerboard()
            if let url = model.logoURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: "signature")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 52, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private var logoKind: String? {
        guard let url = model.logoURL else { return nil }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" || ext == "svg" { return "Vettoriale — ridisegnato per ogni foto" }
        if ext == "jpg" || ext == "jpeg" { return "JPEG: senza trasparenza, avrà un riquadro di sfondo" }
        return "Raster"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .tiff, .pdf, .svg, .jpeg, .heic]
        panel.message = "Scegli il file del logo"
        panel.prompt = "Usa questo logo"
        if panel.runModal() == .OK, let url = panel.url { setLogo(url) }
    }

    private func setLogo(_ url: URL) {
        LogoCache.shared.invalidate()
        model.watermark.logoPath = url.path
    }
}


/// Scacchiera grigia che rende visibile la trasparenza.
struct Checkerboard: View {
    var square: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(white: 0.82)))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : square
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: square, height: square)),
                                 with: .color(Color(white: 0.66)))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
