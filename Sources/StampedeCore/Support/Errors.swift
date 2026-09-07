import Foundation

public enum StampedeError: LocalizedError {
    case metalUnavailable
    case cannotReadImage(URL)
    case cannotDecodeLogo(URL)
    case unsupportedLogoFormat(String)
    case cannotCreateDestination(URL)
    case encodingFailed(URL)
    case renderFailed(URL)
    case noInputsFound(URL)
    case presetNotFound(String)
    case invalidConfiguration(String)
    case rcloneMissing
    case rcloneFailed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Nessun dispositivo Metal disponibile su questa macchina."
        case .cannotReadImage(let url):
            return "Impossibile leggere l'immagine: \(url.path)"
        case .cannotDecodeLogo(let url):
            return "Impossibile decodificare il logo: \(url.path)"
        case .unsupportedLogoFormat(let ext):
            return "Formato logo non supportato: .\(ext) (usa PNG, TIFF, SVG o PDF)"
        case .cannotCreateDestination(let url):
            return "Impossibile creare il file di destinazione: \(url.path)"
        case .encodingFailed(let url):
            return "Encoding fallito per: \(url.path)"
        case .renderFailed(let url):
            return "Rendering GPU fallito per: \(url.path)"
        case .noInputsFound(let url):
            return "Nessuna immagine trovata in: \(url.path)"
        case .presetNotFound(let name):
            return "Preset non trovato: \(name)"
        case .invalidConfiguration(let msg):
            return "Configurazione non valida: \(msg)"
        case .rcloneMissing:
            return "rclone non trovato nel PATH. Installalo con: brew install rclone"
        case .rcloneFailed(let code, let stderr):
            return "rclone ha restituito codice \(code): \(stderr)"
        }
    }
}
