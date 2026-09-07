import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Formato del file di output.
public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    /// Mantiene il container del file sorgente (JPEG resta JPEG, TIFF resta TIFF...).
    case keep, jpeg, png, tiff, heic, webp

    public var cliName: String { rawValue }

    public init?(cliName: String) {
        let n = cliName.lowercased()
        let alias = ["jpg": "jpeg", "tif": "tiff", "heif": "heic", "same": "keep", "original": "keep"]
        guard let match = OutputFormat(rawValue: alias[n] ?? n) else { return nil }
        self = match
    }

    public static var allCLINames: [String] { allCases.map(\.cliName) }

    var utType: UTType? {
        switch self {
        case .keep: nil
        case .jpeg: .jpeg
        case .png: .png
        case .tiff: .tiff
        case .heic: .heic
        case .webp: .webP
        }
    }

    var fileExtension: String? {
        switch self {
        case .keep: nil
        case .jpeg: "jpg"
        case .png: "png"
        case .tiff: "tif"
        case .heic: "heic"
        case .webp: "webp"
        }
    }

    /// Formati che ignorano il parametro qualità perché senza perdita.
    public var isLossless: Bool { self == .png || self == .tiff }

    /// I formati a 16 bit per canale che sappiamo scrivere.
    var supportsDeepColor: Bool { self == .png || self == .tiff }

    /// Verifica a runtime che ImageIO sappia scrivere questo formato su questa versione di macOS.
    public func isWritable() -> Bool {
        guard let type = utType else { return true }
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(type.identifier)
    }
}

public enum BitDepth: Int, Codable, CaseIterable, Sendable {
    case eight = 8
    case sixteen = 16
}

/// Politica di gestione del profilo colore in uscita.
public enum ColorSpacePolicy: String, Codable, CaseIterable, Sendable {
    /// Riusa il profilo ICC del file sorgente (default: nessuna conversione percepibile).
    case source
    case srgb
    case displayP3
    case adobeRGB

    public var cliName: String {
        switch self {
        case .source: "source"
        case .srgb: "srgb"
        case .displayP3: "display-p3"
        case .adobeRGB: "adobe-rgb"
        }
    }

    public init?(cliName: String) {
        let n = cliName.lowercased().replacingOccurrences(of: "-", with: "")
        switch n {
        case "source", "keep", "original": self = .source
        case "srgb": self = .srgb
        case "displayp3", "p3": self = .displayP3
        case "adobergb", "argb": self = .adobeRGB
        default: return nil
        }
    }

    public static var allCLINames: [String] { allCases.map(\.cliName) }

    func resolve(source: CGColorSpace?) -> CGColorSpace {
        switch self {
        case .source:
            if let source, source.supportsOutput, source.model == .rgb { return source }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .srgb: return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: return CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        }
    }
}

public enum ResizeMode: String, Codable, CaseIterable, Sendable {
    case longest, width, height, percent

    public static var allCLINames: [String] { allCases.map(\.rawValue) }
}

/// Ridimensionamento opzionale applicato prima del watermark.
public struct ResizeSpec: Codable, Sendable, Equatable {
    public var mode: ResizeMode
    /// Pixel per longest/width/height, percentuale (100 = invariato) per `.percent`.
    public var value: Double
    public var allowUpscale: Bool

    public init(mode: ResizeMode, value: Double, allowUpscale: Bool = false) {
        self.mode = mode
        self.value = value
        self.allowUpscale = allowUpscale
    }

    /// Fattore di scala da applicare, oppure `nil` se l'immagine va lasciata com'è.
    public func scaleFactor(for size: CGSize) -> CGFloat? {
        guard size.width > 0, size.height > 0 else { return nil }
        let factor: CGFloat = switch mode {
        case .longest: CGFloat(value) / max(size.width, size.height)
        case .width: CGFloat(value) / size.width
        case .height: CGFloat(value) / size.height
        case .percent: CGFloat(value) / 100.0
        }
        guard factor.isFinite, factor > 0 else { return nil }
        if factor > 1, !allowUpscale { return nil }
        if abs(factor - 1) < 0.0005 { return nil }
        return factor
    }
}

/// Come vengono scritti i file risultanti.
public struct OutputSpec: Codable, Sendable, Equatable {
    public var format: OutputFormat
    /// 0…1. Usata da JPEG/HEIC/WebP; ignorata dai formati lossless.
    public var quality: Double
    public var resize: ResizeSpec?
    public var bitDepth: BitDepth
    public var colorSpace: ColorSpacePolicy
    /// Copia EXIF/IPTC/GPS/XMP dal sorgente all'output.
    public var preserveMetadata: Bool
    /// Rimuove le coordinate GPS anche quando i metadati sono preservati.
    public var stripGPS: Bool
    /// Template del nome file. Placeholder: {name} {ext} {parent} {index} {date}
    public var filenameTemplate: String
    public var overwrite: Bool
    /// Ricrea la gerarchia di sottocartelle dell'input dentro la cartella di output.
    public var preserveTree: Bool

    public init(format: OutputFormat = .keep,
                quality: Double = 0.95,
                resize: ResizeSpec? = nil,
                bitDepth: BitDepth = .eight,
                colorSpace: ColorSpacePolicy = .source,
                preserveMetadata: Bool = true,
                stripGPS: Bool = false,
                filenameTemplate: String = "{name}{ext}",
                overwrite: Bool = false,
                preserveTree: Bool = true) {
        self.format = format
        self.quality = quality
        self.resize = resize
        self.bitDepth = bitDepth
        self.colorSpace = colorSpace
        self.preserveMetadata = preserveMetadata
        self.stripGPS = stripGPS
        self.filenameTemplate = filenameTemplate
        self.overwrite = overwrite
        self.preserveTree = preserveTree
    }

    public func validated() throws -> OutputSpec {
        guard (0...1).contains(quality) else {
            throw EagleFootError.invalidConfiguration("quality deve essere fra 0 e 1 (valore: \(quality))")
        }
        if !format.isWritable() {
            throw EagleFootError.invalidConfiguration(
                "questo macOS non sa codificare \(format.rawValue); prova jpeg, png, tiff o heic")
        }
        if bitDepth == .sixteen, format != .keep, !format.supportsDeepColor {
            throw EagleFootError.invalidConfiguration(
                "16 bit per canale sono supportati solo da png e tiff (formato richiesto: \(format.rawValue))")
        }
        return self
    }

    /// Costruisce il nome del file di output a partire dal sorgente.
    public func outputFilename(source: URL, index: Int, date: Date = Date()) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = format.fileExtension ?? (source.pathExtension.isEmpty ? "jpg" : source.pathExtension)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let replacements: [String: String] = [
            "{name}": base,
            "{ext}": ".\(ext)",
            "{parent}": source.deletingLastPathComponent().lastPathComponent,
            "{index}": String(format: "%04d", index),
            "{date}": formatter.string(from: date),
        ]
        var result = filenameTemplate
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        // Se il template non contiene {ext}, aggiungiamo comunque l'estensione corretta.
        if !filenameTemplate.contains("{ext}") {
            result += ".\(ext)"
        }
        return result
    }
}
