import AppKit
import StampedeCore
import SwiftUI

/// Salva le impostazioni correnti come preset, negli stessi file JSON che legge la CLI.
struct SavePresetSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Salva come preset")
                .font(.headline)

            Form {
                TextField("Nome", text: $name, prompt: Text("matrimoni"))
                TextField("Descrizione", text: $description, prompt: Text("facoltativa"))
            }
            .formStyle(.grouped)

            Text("Finisce in ~/.config/stampede/presets e sarà utilizzabile anche da terminale "
                 + "con `stampede apply --preset \(cleanName.isEmpty ? "nome" : cleanName)`.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salva") {
                    model.savePreset(named: cleanName,
                                     description: description.isEmpty ? nil : description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleanName.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    /// I nomi diventano nomi di file: niente spazi né barre.
    private var cleanName: String {
        name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}

/// Mostra il comando da terminale equivalente alle impostazioni correnti,
/// per chi vuole poi metterlo in uno script o in un Automator.
struct CommandSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Comando equivalente")
                .font(.headline)

            ScrollView {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 180)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

            Text("Stesse impostazioni, stesso motore: la GUI e la riga di comando usano "
                 + "la medesima libreria.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(copied ? "Copiato" : "Copia") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private var command: String { CommandBuilder.build(from: model) }
}

/// Traduce lo stato dell'app nella riga di comando corrispondente.
@MainActor
enum CommandBuilder {
    static func build(from model: AppModel) -> String {
        var parts = ["stampede apply"]

        parts.append(quote(model.sourceFolder?.path ?? "<cartella-origine>"))
        parts.append("-o " + quote(model.destinationFolder?.path ?? "<cartella-destinazione>"))
        if model.recursive { parts.append("-r") }

        let watermark = model.watermark
        parts.append("--logo " + quote(watermark.logoPath.isEmpty ? "<logo.png>" : watermark.logoPath))

        if watermark.scale.unit == .pixels {
            parts.append("--scale \(Int(watermark.scale.value))px")
        } else {
            parts.append("--scale \(percent(watermark.scale.value))%")
            if watermark.scale.reference != .width {
                parts.append("--scale-ref \(watermark.scale.reference.rawValue)")
            }
        }

        if watermark.layout == .tile {
            parts.append("--layout tile")
            parts.append("--tile-angle \(Int(watermark.tile.angle))")
            if watermark.tile.spacingX == watermark.tile.spacingY {
                parts.append("--tile-spacing \(trim(watermark.tile.spacingX))")
            } else {
                parts.append("--tile-spacing-x \(trim(watermark.tile.spacingX))")
                parts.append("--tile-spacing-y \(trim(watermark.tile.spacingY))")
            }
            if !watermark.tile.stagger { parts.append("--no-stagger") }
        } else {
            parts.append("--anchor \(watermark.single.anchor.cliName)")
            let unit = watermark.single.marginUnit
            let x = unit == .pixels ? "\(Int(watermark.single.marginX))px" : "\(percent(watermark.single.marginX))%"
            let y = unit == .pixels ? "\(Int(watermark.single.marginY))px" : "\(percent(watermark.single.marginY))%"
            if x == y { parts.append("--margin \(x)") } else {
                parts.append("--margin-x \(x)")
                parts.append("--margin-y \(y)")
            }
        }

        parts.append("--opacity \(trim(watermark.opacity))")
        if watermark.rotation != 0 { parts.append("--rotate \(Int(watermark.rotation))") }
        if watermark.blend != .normal { parts.append("--blend \(watermark.blend.cliName)") }
        if let shadow = watermark.shadow {
            parts.append("--shadow")
            if shadow.radius != 6 { parts.append("--shadow-radius \(Int(shadow.radius))") }
            if shadow.opacity != 0.45 { parts.append("--shadow-opacity \(trim(shadow.opacity))") }
        }

        let output = model.output
        if output.format != .keep { parts.append("--format \(output.format.cliName)") }
        if !output.format.isLossless { parts.append("--quality \(trim(output.quality))") }
        if output.bitDepth != .eight { parts.append("--bit-depth 16") }
        if output.colorSpace != .source { parts.append("--color-space \(output.colorSpace.cliName)") }
        if let resize = output.resize {
            switch resize.mode {
            case .longest: parts.append("--resize-longest \(Int(resize.value))")
            case .width: parts.append("--resize-width \(Int(resize.value))")
            case .height: parts.append("--resize-height \(Int(resize.value))")
            case .percent: parts.append("--resize-percent \(Int(resize.value))")
            }
            if resize.allowUpscale { parts.append("--allow-upscale") }
        }
        if output.filenameTemplate != "{name}{ext}" {
            parts.append("--name-template " + quote(output.filenameTemplate))
        }
        if !output.preserveMetadata { parts.append("--no-metadata") }
        if output.stripGPS { parts.append("--strip-gps") }
        if output.overwrite { parts.append("--overwrite") }
        if !output.preserveTree { parts.append("--flatten") }

        if model.precision != .balanced { parts.append("--precision \(model.precision.rawValue)") }
        if model.blendSpace != .srgb { parts.append("--blend-space \(model.blendSpace.rawValue)") }
        if let jobs = model.jobsOverride { parts.append("--jobs \(jobs)") }

        if let target = model.driveTarget {
            parts.append("--drive " + quote(target.spec))
            if !model.driveStreaming { parts.append("--drive-after-batch") }
        }

        // Spezziamo in righe da ~76 colonne: un comando lungo su una riga sola
        // è illeggibile appena lo si incolla in uno script.
        var lines: [String] = []
        var current = ""
        for part in parts {
            if current.isEmpty {
                current = part
            } else if current.count + part.count + 1 > 76 {
                lines.append(current + " \\")
                current = "    " + part
            } else {
                current += " " + part
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }

    private static func quote(_ value: String) -> String {
        value.contains(where: { $0 == " " || $0 == "'" }) ? "\"\(value)\"" : value
    }

    private static func percent(_ value: Double) -> String {
        let scaled = value * 100
        return scaled == scaled.rounded() ? String(Int(scaled)) : String(format: "%.1f", scaled)
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
