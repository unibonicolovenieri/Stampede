import ArgumentParser
import StampedeCore
import Foundation

// MARK: - Enum accettati da riga di comando

extension Anchor: ExpressibleByArgument {
    public init?(argument: String) { self.init(cliName: argument) }
    public static var allValueStrings: [String] { allCLINames }
}

extension BlendMode: ExpressibleByArgument {
    public init?(argument: String) { self.init(cliName: argument) }
    public static var allValueStrings: [String] { allCLINames }
}

extension OutputFormat: ExpressibleByArgument {
    public init?(argument: String) { self.init(cliName: argument) }
    public static var allValueStrings: [String] { allCLINames }
}

extension ColorSpacePolicy: ExpressibleByArgument {
    public init?(argument: String) { self.init(cliName: argument) }
    public static var allValueStrings: [String] { allCLINames }
}

extension WatermarkLayout: ExpressibleByArgument {}
extension ScaleReference: ExpressibleByArgument {}
extension WorkingPrecision: ExpressibleByArgument {}
extension BlendSpace: ExpressibleByArgument {}

// MARK: - Misure relative o assolute

/// Accetta `18%`, `0.18`, `240px` o `240`.
///
/// Un numero nudo ≤ 1 è una frazione, > 1 è una percentuale: `--scale 0.18` e
/// `--scale 18` significano la stessa cosa, che è quasi sempre ciò che ci si aspetta.
struct RelativeSize: ExpressibleByArgument, Sendable {
    let unit: SizeUnit
    let value: Double

    init?(argument: String) {
        let raw = argument.trimmingCharacters(in: .whitespaces).lowercased()
        if raw.hasSuffix("px") {
            guard let n = Double(raw.dropLast(2)), n > 0 else { return nil }
            unit = .pixels
            value = n
        } else if raw.hasSuffix("%") {
            guard let n = Double(raw.dropLast()) else { return nil }
            unit = .fraction
            value = n / 100
        } else if let n = Double(raw) {
            unit = .fraction
            value = n > 1 ? n / 100 : n
        } else {
            return nil
        }
    }

    static var defaultValueDescription: String { "18% | 0.18 | 240px" }
}

// MARK: - Gruppi di opzioni riusati da più comandi

struct WatermarkOptions: ParsableArguments {
    @Option(name: [.short, .long], help: ArgumentHelp(
        "Logo da stampare: PNG/TIFF con canale alfa, oppure PDF/SVG (ridisegnati come vettoriale).",
        valueName: "file"))
    var logo: String?

    @Option(help: ArgumentHelp("Preset da cui partire; le altre opzioni lo sovrascrivono.", valueName: "nome"))
    var preset: String?

    @Option(help: "Disposizione: una sola istanza ancorata (single) o mosaico ripetuto (tile).")
    var layout: WatermarkLayout?

    @Option(help: ArgumentHelp("Posizione del logo.", valueName: "ancora"))
    var anchor: Anchor?

    @Option(help: ArgumentHelp("Dimensione del logo rispetto alla foto.", valueName: "misura"))
    var scale: RelativeSize?

    @Option(name: .customLong("scale-ref"), help: "Dimensione della foto su cui si calcola --scale.")
    var scaleReference: ScaleReference?

    @Option(help: ArgumentHelp("Distanza dal bordo (vale per entrambi gli assi).", valueName: "misura"))
    var margin: RelativeSize?

    @Option(name: .customLong("margin-x"), help: ArgumentHelp("Margine orizzontale, se diverso da --margin.", valueName: "misura"))
    var marginX: RelativeSize?

    @Option(name: .customLong("margin-y"), help: ArgumentHelp("Margine verticale, se diverso da --margin.", valueName: "misura"))
    var marginY: RelativeSize?

    @Option(help: ArgumentHelp("Opacità del watermark, 0…1.", valueName: "n"))
    var opacity: Double?

    @Option(name: .customLong("rotate"), parsing: .unconditional,
            help: ArgumentHelp("Rotazione del logo in gradi (accetta valori negativi).", valueName: "gradi"))
    var rotation: Double?

    @Option(help: "Modo di fusione del logo sulla foto.")
    var blend: BlendMode?

    @Flag(name: .customLong("shadow"), help: "Aggiunge un'ombra sfumata dietro al logo (utile su sfondi chiari).")
    var shadow: Bool = false

    @Flag(name: .customLong("no-shadow"), help: "Toglie l'ombra ereditata da un preset.")
    var noShadow: Bool = false

    @Option(name: .customLong("shadow-radius"), parsing: .unconditional,
            help: ArgumentHelp("Raggio di sfocatura dell'ombra, in px.", valueName: "px"))
    var shadowRadius: Double = 6

    @Option(name: .customLong("shadow-opacity"), help: ArgumentHelp("Opacità dell'ombra, 0…1.", valueName: "n"))
    var shadowOpacity: Double = 0.45

    @Option(name: .customLong("tile-angle"), parsing: .unconditional,
            help: ArgumentHelp("Inclinazione del mosaico in gradi (accetta valori negativi).", valueName: "gradi"))
    var tileAngle: Double?

    @Option(name: .customLong("tile-spacing"), help: ArgumentHelp(
        "Spazio fra le copie del mosaico, come frazione del logo (0.6 = 60% in più).", valueName: "n"))
    var tileSpacing: Double?

    @Option(name: .customLong("tile-spacing-x"), help: ArgumentHelp("Spaziatura orizzontale del mosaico.", valueName: "n"))
    var tileSpacingX: Double?

    @Option(name: .customLong("tile-spacing-y"), help: ArgumentHelp("Spaziatura verticale del mosaico.", valueName: "n"))
    var tileSpacingY: Double?

    @Flag(name: .customLong("no-stagger"), help: "Allinea le righe del mosaico invece di sfalsarle a mattoni.")
    var noStagger: Bool = false

    /// Fonde preset, opzioni e default in una specifica completa.
    func resolve(base: WatermarkSpec) throws -> WatermarkSpec {
        var spec = base
        if let logo { spec.logoPath = (logo as NSString).expandingTildeInPath }
        if let layout { spec.layout = layout }
        if let anchor { spec.single.anchor = anchor }
        if let scale {
            spec.scale.unit = scale.unit
            spec.scale.value = scale.value
        }
        if let scaleReference { spec.scale.reference = scaleReference }
        if let margin {
            spec.single.marginUnit = margin.unit
            spec.single.marginX = margin.value
            spec.single.marginY = margin.value
        }
        if let marginX {
            spec.single.marginUnit = marginX.unit
            spec.single.marginX = marginX.value
        }
        if let marginY {
            spec.single.marginUnit = marginY.unit
            spec.single.marginY = marginY.value
        }
        if let opacity { spec.opacity = opacity }
        if let rotation { spec.rotation = rotation }
        if let blend { spec.blend = blend }
        if let tileAngle { spec.tile.angle = tileAngle }
        if let tileSpacing {
            spec.tile.spacingX = tileSpacing
            spec.tile.spacingY = tileSpacing
        }
        if let tileSpacingX { spec.tile.spacingX = tileSpacingX }
        if let tileSpacingY { spec.tile.spacingY = tileSpacingY }
        if noStagger { spec.tile.stagger = false }
        if noShadow {
            spec.shadow = nil
        } else if shadow || spec.shadow != nil {
            // `--shadow-radius` e `--shadow-opacity` raffinano l'ombra del preset
            // anche senza ripetere `--shadow`.
            spec.shadow = ShadowSpec(radius: shadowRadius, opacity: shadowOpacity)
        }

        if marginX != nil, marginY != nil, marginX!.unit != marginY!.unit {
            throw ValidationError("--margin-x e --margin-y devono usare la stessa unità (entrambi in % o entrambi in px).")
        }
        return try spec.validated()
    }
}

struct OutputOptions: ParsableArguments {
    @Option(name: [.short, .long], help: ArgumentHelp("Cartella di destinazione.", valueName: "cartella"))
    var output: String?

    @Option(help: "Formato di uscita. `keep` mantiene quello del sorgente.")
    var format: OutputFormat?

    // Niente forma corta: `-q` è per `--quiet`, come in ogni altra CLI.
    @Option(help: ArgumentHelp("Qualità 0…1 per JPEG/HEIC/WebP.", valueName: "n"))
    var quality: Double?

    @Option(name: .customLong("resize-longest"), help: ArgumentHelp("Porta il lato lungo a N pixel.", valueName: "px"))
    var resizeLongest: Double?

    @Option(name: .customLong("resize-width"), help: ArgumentHelp("Porta la larghezza a N pixel.", valueName: "px"))
    var resizeWidth: Double?

    @Option(name: .customLong("resize-height"), help: ArgumentHelp("Porta l'altezza a N pixel.", valueName: "px"))
    var resizeHeight: Double?

    @Option(name: .customLong("resize-percent"), help: ArgumentHelp("Scala percentuale (100 = invariata).", valueName: "n"))
    var resizePercent: Double?

    @Flag(name: .customLong("allow-upscale"), help: "Permette di ingrandire le foto più piccole del target.")
    var allowUpscale: Bool = false

    @Option(name: .customLong("bit-depth"), help: ArgumentHelp("Bit per canale in uscita: 8 o 16 (solo png/tiff).", valueName: "n"))
    var bitDepth: Int?

    @Option(name: .customLong("color-space"), help: "Profilo colore di uscita.")
    var colorSpace: ColorSpacePolicy?

    @Flag(name: .customLong("no-metadata"), help: "Non copiare EXIF/IPTC/XMP dal sorgente.")
    var noMetadata: Bool = false

    @Flag(name: .customLong("strip-gps"), help: "Rimuove le coordinate GPS mantenendo il resto dei metadati.")
    var stripGPS: Bool = false

    @Option(parsing: .unconditional,
            help: ArgumentHelp("Suffisso aggiunto al nome file, es. `_wm` o `-web`.", valueName: "testo"))
    var suffix: String?

    @Option(name: .customLong("name-template"), help: ArgumentHelp(
        "Template del nome. Placeholder: {name} {ext} {parent} {index} {date}", valueName: "testo"))
    var nameTemplate: String?

    @Flag(help: "Sovrascrive i file già presenti in destinazione.")
    var overwrite: Bool = false

    @Flag(help: "Scrive tutto in una cartella sola invece di ricreare l'albero degli input.")
    var flatten: Bool = false

    func resolve(base: OutputSpec) throws -> OutputSpec {
        var spec = base
        if let format { spec.format = format }
        if let quality { spec.quality = quality }
        if let colorSpace { spec.colorSpace = colorSpace }
        if let bitDepth {
            guard let depth = BitDepth(rawValue: bitDepth) else {
                throw ValidationError("--bit-depth accetta solo 8 o 16.")
            }
            spec.bitDepth = depth
        }
        if noMetadata { spec.preserveMetadata = false }
        if stripGPS { spec.stripGPS = true }
        if overwrite { spec.overwrite = true }
        if flatten { spec.preserveTree = false }

        let resizeFlags = [resizeLongest, resizeWidth, resizeHeight, resizePercent].compactMap { $0 }
        guard resizeFlags.count <= 1 else {
            throw ValidationError("Usa una sola opzione di ridimensionamento alla volta.")
        }
        if let value = resizeLongest {
            spec.resize = ResizeSpec(mode: .longest, value: value, allowUpscale: allowUpscale)
        } else if let value = resizeWidth {
            spec.resize = ResizeSpec(mode: .width, value: value, allowUpscale: allowUpscale)
        } else if let value = resizeHeight {
            spec.resize = ResizeSpec(mode: .height, value: value, allowUpscale: allowUpscale)
        } else if let value = resizePercent {
            spec.resize = ResizeSpec(mode: .percent, value: value, allowUpscale: allowUpscale)
        }

        if let nameTemplate {
            spec.filenameTemplate = nameTemplate
        } else if let suffix {
            spec.filenameTemplate = "{name}\(suffix){ext}"
        }
        return try spec.validated()
    }
}

struct EngineOptions: ParsableArguments {
    @Option(name: [.short, .long], help: ArgumentHelp(
        "Quante foto tenere in lavorazione insieme. Di default è calcolato su core e memoria.",
        valueName: "n"))
    var jobs: Int?

    @Option(help: "Precisione dei pixel intermedi sulla GPU.")
    var precision: WorkingPrecision = .balanced

    @Option(name: .customLong("blend-space"), help:
        "Spazio in cui avviene la fusione: `srgb` come Photoshop/uMark, `linear` fisicamente corretto.")
    var blendSpace: BlendSpace = .srgb

    @Option(name: .customLong("gpu-contexts"), help: ArgumentHelp(
        "Contesti Core Image in rotazione sulla GPU.", valueName: "n"))
    var gpuContexts: Int?
}

struct DriveOptions: ParsableArguments {
    @Option(name: .customLong("drive"), help: ArgumentHelp(
        "Destinazione rclone, es. `gdrive:Foto/2026/Servizio`. Richiede rclone configurato.",
        valueName: "remote:path"))
    var drive: String?

    @Option(name: .customLong("drive-parallel"), help: ArgumentHelp("Upload simultanei.", valueName: "n"))
    var driveParallel: Int = 4

    @Flag(name: .customLong("drive-after-batch"), help:
        "Carica tutto in blocco alla fine invece che foto per foto durante l'elaborazione.")
    var driveAfterBatch: Bool = false

    func makeTarget() throws -> RemoteTarget? {
        guard let drive else { return nil }
        guard let target = RemoteTarget(drive) else {
            throw ValidationError("Destinazione Drive non valida: `\(drive)`. Formato atteso: `remote:cartella`.")
        }
        return target
    }
}

struct VerbosityOptions: ParsableArguments {
    @Flag(name: [.short, .long], help: "Mostra ogni file lavorato.")
    var verbose: Bool = false

    @Flag(name: [.short, .long], help: "Stampa solo gli errori.")
    var quiet: Bool = false

    func apply() {
        Log.level = quiet ? .error : (verbose ? .debug : .info)
    }
}
