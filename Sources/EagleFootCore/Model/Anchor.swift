import CoreGraphics
import Foundation

/// Le 9 ancore classiche di posizionamento del watermark.
public enum Anchor: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    /// Nome usato da CLI e preset JSON: `top-left`, `bottom-right`, ...
    public var cliName: String {
        switch self {
        case .topLeft: "top-left"
        case .topCenter: "top-center"
        case .topRight: "top-right"
        case .middleLeft: "middle-left"
        case .center: "center"
        case .middleRight: "middle-right"
        case .bottomLeft: "bottom-left"
        case .bottomCenter: "bottom-center"
        case .bottomRight: "bottom-right"
        }
    }

    public init?(cliName: String) {
        let normalized = cliName.lowercased().replacingOccurrences(of: "_", with: "-")
        guard let match = Anchor.allCases.first(where: { $0.cliName == normalized }) else { return nil }
        self = match
    }

    public static var allCLINames: [String] { allCases.map(\.cliName) }

    /// Frazione (0…1) del riquadro contenitore su cui si aggancia l'ancora.
    /// (0,0) = in basso a sinistra, coerente con lo spazio di coordinate di Core Image.
    var unitPoint: CGPoint {
        switch self {
        case .topLeft: CGPoint(x: 0, y: 1)
        case .topCenter: CGPoint(x: 0.5, y: 1)
        case .topRight: CGPoint(x: 1, y: 1)
        case .middleLeft: CGPoint(x: 0, y: 0.5)
        case .center: CGPoint(x: 0.5, y: 0.5)
        case .middleRight: CGPoint(x: 1, y: 0.5)
        case .bottomLeft: CGPoint(x: 0, y: 0)
        case .bottomCenter: CGPoint(x: 0.5, y: 0)
        case .bottomRight: CGPoint(x: 1, y: 0)
        }
    }

    /// Direzione verso cui il margine spinge il watermark (verso l'interno dell'immagine).
    var marginDirection: CGVector {
        switch self {
        case .topLeft: CGVector(dx: 1, dy: -1)
        case .topCenter: CGVector(dx: 0, dy: -1)
        case .topRight: CGVector(dx: -1, dy: -1)
        case .middleLeft: CGVector(dx: 1, dy: 0)
        case .center: CGVector(dx: 0, dy: 0)
        case .middleRight: CGVector(dx: -1, dy: 0)
        case .bottomLeft: CGVector(dx: 1, dy: 1)
        case .bottomCenter: CGVector(dx: 0, dy: 1)
        case .bottomRight: CGVector(dx: -1, dy: 1)
        }
    }
}
