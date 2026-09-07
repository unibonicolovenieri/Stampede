import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Un'immagine sorgente aperta, con tutto ciò che serve per riscriverla identica.
public struct LoadedImage {
    /// Immagine con l'orientamento EXIF già applicato: l'estensione è quella "vista".
    public let image: CIImage
    /// Dizionario completo delle proprietà ImageIO del sorgente (EXIF, IPTC, GPS, TIFF...).
    public let properties: [String: Any]
    /// Container XMP del sorgente, se presente.
    public let metadata: CGImageMetadata?
    public let colorSpace: CGColorSpace?
    public let sourceType: UTType?
    public let url: URL
    public let isRAW: Bool

    public var pixelSize: CGSize { image.extent.size }
    public var megapixels: Double { Double(pixelSize.width * pixelSize.height) / 1_000_000 }
}

public enum ImageLoader {
    /// Estensioni RAW che passiamo dal demosaicing di Core Image.
    static let rawExtensions: Set<String> = [
        "arw", "cr2", "cr3", "crw", "dng", "erf", "nef", "nrw", "orf",
        "pef", "raf", "raw", "rw2", "sr2", "srf", "srw", "3fr", "fff", "iiq",
    ]

    /// Estensioni che accettiamo in input quando si scandisce una cartella.
    public static let supportedExtensions: Set<String> = {
        var set: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif", "webp", "bmp", "gif", "avif"]
        set.formUnion(rawExtensions)
        return set
    }()

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func load(_ url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            throw StampedeError.cannotReadImage(url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let isRAW = rawExtensions.contains(url.pathExtension.lowercased())

        let image: CIImage
        if isRAW, let raw = CIRAWFilter(imageURL: url), let output = raw.outputImage {
            // Il RAW arriva già demosaicizzato e orientato da CIRAWFilter.
            image = output
        } else if let loaded = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
            image = loaded
        } else {
            throw StampedeError.cannotReadImage(url)
        }

        return LoadedImage(
            image: image,
            properties: properties,
            metadata: metadata,
            colorSpace: image.colorSpace,
            sourceType: sourceType,
            url: url,
            isRAW: isRAW
        )
    }

    /// Legge solo le dimensioni in pixel senza decodificare i pixel: usato per le stime a monte del batch.
    public static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = props[kCGImagePropertyPixelWidth as String] as? Double,
              let height = props[kCGImagePropertyPixelHeight as String] as? Double
        else { return nil }
        let orientation = props[kCGImagePropertyOrientation as String] as? Int ?? 1
        // Gli orientamenti 5…8 scambiano larghezza e altezza.
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}
