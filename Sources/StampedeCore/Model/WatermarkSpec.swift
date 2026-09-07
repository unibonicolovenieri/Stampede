import CoreImage
import Foundation

/// Unità di misura per scale e margini.
public enum SizeUnit: String, Codable, Sendable {
    /// Frazione della dimensione di riferimento dell'immagine (0.15 = 15%).
    case fraction
    /// Pixel assoluti sull'immagine di output.
    case pixels
}

/// Dimensione dell'immagine base rispetto a cui viene calcolata la scala del logo.
public enum ScaleReference: String, Codable, CaseIterable, Sendable {
    case width, height, longest, shortest, diagonal

    func measure(of size: CGSize) -> CGFloat {
        switch self {
        case .width: size.width
        case .height: size.height
        case .longest: max(size.width, size.height)
        case .shortest: min(size.width, size.height)
        case .diagonal: (size.width * size.width + size.height * size.height).squareRoot()
        }
    }
}

/// Modalità di composizione del watermark sopra la foto.
public enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, softLight, hardLight, darken, lighten, difference, luminosity

    var ciFilterName: String {
        switch self {
        case .normal: "CISourceOverCompositing"
        case .multiply: "CIMultiplyBlendMode"
        case .screen: "CIScreenBlendMode"
        case .overlay: "CIOverlayBlendMode"
        case .softLight: "CISoftLightBlendMode"
        case .hardLight: "CIHardLightBlendMode"
        case .darken: "CIDarkenBlendMode"
        case .lighten: "CILightenBlendMode"
        case .difference: "CIDifferenceBlendMode"
        case .luminosity: "CILuminosityBlendMode"
        }
    }

    public var cliName: String {
        self == .softLight ? "soft-light" : (self == .hardLight ? "hard-light" : rawValue)
    }

    public init?(cliName: String) {
        let normalized = cliName.lowercased().replacingOccurrences(of: "-", with: "")
        guard let match = BlendMode.allCases.first(where: { $0.rawValue.lowercased() == normalized }) else {
            return nil
        }
        self = match
    }

    public static var allCLINames: [String] { allCases.map(\.cliName) }
}

/// Come viene disposto il watermark: una singola istanza ancorata, oppure a mosaico.
public enum WatermarkLayout: String, Codable, CaseIterable, Sendable {
    case single, tile
}

/// Dimensione del logo rispetto alla foto.
public struct ScaleSpec: Codable, Sendable, Equatable {
    public var unit: SizeUnit
    /// Con `.fraction` è la frazione della dimensione di riferimento; con `.pixels` è la larghezza in px.
    public var value: Double
    public var reference: ScaleReference

    public init(unit: SizeUnit = .fraction, value: Double = 0.18, reference: ScaleReference = .width) {
        self.unit = unit
        self.value = value
        self.reference = reference
    }

    /// Larghezza in pixel che il logo deve avere sull'immagine data.
    public func targetWidth(imageSize: CGSize) -> CGFloat {
        switch unit {
        case .pixels: CGFloat(value)
        case .fraction: reference.measure(of: imageSize) * CGFloat(value)
        }
    }
}

/// Posizionamento di una singola istanza del watermark.
public struct SinglePlacement: Codable, Sendable, Equatable {
    public var anchor: Anchor
    public var marginUnit: SizeUnit
    public var marginX: Double
    public var marginY: Double

    public init(anchor: Anchor = .bottomRight, marginUnit: SizeUnit = .fraction,
                marginX: Double = 0.03, marginY: Double = 0.03) {
        self.anchor = anchor
        self.marginUnit = marginUnit
        self.marginX = marginX
        self.marginY = marginY
    }

    public func marginPoints(imageSize: CGSize) -> CGPoint {
        switch marginUnit {
        case .pixels:
            return CGPoint(x: marginX, y: marginY)
        case .fraction:
            return CGPoint(x: imageSize.width * CGFloat(marginX),
                           y: imageSize.height * CGFloat(marginY))
        }
    }
}

/// Parametri del mosaico anti-furto.
public struct TilePlacement: Codable, Sendable, Equatable {
    /// Rotazione dell'intero reticolo, in gradi.
    public var angle: Double
    /// Spazio fra le copie, espresso come frazione della larghezza/altezza del logo.
    public var spacingX: Double
    public var spacingY: Double
    /// Sfalsa le righe alterne di mezza cella (effetto "mattoni").
    public var stagger: Bool

    public init(angle: Double = -30, spacingX: Double = 0.6, spacingY: Double = 0.9, stagger: Bool = true) {
        self.angle = angle
        self.spacingX = spacingX
        self.spacingY = spacingY
        self.stagger = stagger
    }
}

/// Ombra sfumata dietro al logo, per staccarlo dagli sfondi chiari.
public struct ShadowSpec: Codable, Sendable, Equatable {
    public var radius: Double
    public var opacity: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(radius: Double = 6, opacity: Double = 0.45, offsetX: Double = 0, offsetY: Double = -3) {
        self.radius = radius
        self.opacity = opacity
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

/// Descrizione completa del watermark da applicare.
public struct WatermarkSpec: Codable, Sendable, Equatable {
    public var logoPath: String
    public var layout: WatermarkLayout
    public var opacity: Double
    /// Rotazione della singola istanza del logo, in gradi.
    public var rotation: Double
    public var blend: BlendMode
    public var scale: ScaleSpec
    public var single: SinglePlacement
    public var tile: TilePlacement
    public var shadow: ShadowSpec?

    public init(logoPath: String = "",
                layout: WatermarkLayout = .single,
                opacity: Double = 0.85,
                rotation: Double = 0,
                blend: BlendMode = .normal,
                scale: ScaleSpec = ScaleSpec(),
                single: SinglePlacement = SinglePlacement(),
                tile: TilePlacement = TilePlacement(),
                shadow: ShadowSpec? = nil) {
        self.logoPath = logoPath
        self.layout = layout
        self.opacity = opacity
        self.rotation = rotation
        self.blend = blend
        self.scale = scale
        self.single = single
        self.tile = tile
        self.shadow = shadow
    }

    /// La stessa specifica adattata a un'immagine ridotta di `factor` (0.25 = un quarto).
    ///
    /// Le misure in frazione sono già indipendenti dalla risoluzione e restano intatte;
    /// quelle in pixel vanno riscalate, altrimenti l'anteprima mostrerebbe un logo
    /// enorme rispetto a quello che finirà davvero sulla foto a piena risoluzione.
    public func scaled(by factor: Double) -> WatermarkSpec {
        guard factor > 0, factor != 1 else { return self }
        var copy = self
        if copy.scale.unit == .pixels { copy.scale.value *= factor }
        if copy.single.marginUnit == .pixels {
            copy.single.marginX *= factor
            copy.single.marginY *= factor
        }
        if var shadow = copy.shadow {
            shadow.radius *= factor
            shadow.offsetX *= factor
            shadow.offsetY *= factor
            copy.shadow = shadow
        }
        return copy
    }

    public func validated() throws -> WatermarkSpec {
        guard !logoPath.isEmpty else {
            throw StampedeError.invalidConfiguration("nessun logo specificato (usa --logo o un preset)")
        }
        guard (0...1).contains(opacity) else {
            throw StampedeError.invalidConfiguration("opacity deve essere fra 0 e 1 (valore: \(opacity))")
        }
        guard scale.value > 0 else {
            throw StampedeError.invalidConfiguration("la scala del logo deve essere > 0")
        }
        if layout == .tile {
            guard tile.spacingX > -0.99, tile.spacingY > -0.99 else {
                throw StampedeError.invalidConfiguration("spacing del mosaico troppo negativo")
            }
        }
        return self
    }
}
