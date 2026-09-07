import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renderizza sulla GPU e scrive il file finale, conservando profilo colore e metadati.
public enum ImageWriter {

    public struct Result: Sendable {
        public let url: URL
        public let bytes: Int
        public let pixelSize: CGSize
    }

    /// Esegue il rendering di `image` e lo scrive in `url`.
    ///
    /// La scrittura è atomica: si passa da un file temporaneo nella stessa cartella,
    /// così un batch interrotto non lascia mai un JPEG mezzo scritto — cosa che conta
    /// parecchio quando la cartella di output è sotto watch o sincronizzata su Drive.
    @discardableResult
    public static func write(_ image: CIImage,
                             to url: URL,
                             context: CIContext,
                             source: LoadedImage,
                             output: OutputSpec) throws -> Result {
        let type = resolveType(output: output, source: source)
        let colorSpace = output.colorSpace.resolve(source: source.colorSpace)
        let format: CIFormat = output.bitDepth == .sixteen ? .RGBA16 : .RGBA8
        let extent = image.extent.integral

        guard extent.width >= 1, extent.height >= 1 else {
            throw StampedeError.renderFailed(source.url)
        }

        // Qui parte il lavoro vero: l'intero grafo (resize + watermark + fusione)
        // viene eseguito in un solo passaggio sulla GPU.
        guard let cgImage = context.createCGImage(image,
                                                  from: extent,
                                                  format: format,
                                                  colorSpace: colorSpace,
                                                  deferred: false)
        else { throw StampedeError.renderFailed(source.url) }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).stampede-part")
        defer { try? FileManager.default.removeItem(at: temporary) }

        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL,
                                                                type.identifier as CFString, 1, nil)
        else { throw StampedeError.cannotCreateDestination(url) }

        let properties = buildProperties(source: source, output: output, type: type, size: extent.size)

        var wroteWithMetadata = false
        if output.preserveMetadata, let metadata = adjustedMetadata(from: source, size: extent.size, output: output) {
            CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, properties as CFDictionary)
            wroteWithMetadata = true
        }
        if !wroteWithMetadata {
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw StampedeError.encodingFailed(url)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }

        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        return Result(url: url, bytes: bytes, pixelSize: extent.size)
    }

    // MARK: - Tipo di file

    static func resolveType(output: OutputSpec, source: LoadedImage) -> UTType {
        if let explicit = output.format.utType { return explicit }
        // format == .keep
        if source.isRAW {
            // Un RAW non si riscrive: dopo il watermark non è più dato grezzo.
            return output.bitDepth == .sixteen ? .tiff : .jpeg
        }
        guard let sourceType = source.sourceType, sourceType.conforms(to: .image) else { return .jpeg }
        // Se il container di partenza non è scrivibile su questo sistema, ripieghiamo.
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard writable.contains(sourceType.identifier) else { return .jpeg }
        if output.bitDepth == .sixteen, sourceType != .png, sourceType != .tiff { return .tiff }
        return sourceType
    }

    // MARK: - Proprietà (EXIF / IPTC / GPS / TIFF)

    static func buildProperties(source: LoadedImage,
                                output: OutputSpec,
                                type: UTType,
                                size: CGSize) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]

        if output.preserveMetadata {
            for (key, value) in source.properties {
                properties[key as CFString] = value
            }
            // Chiavi che descrivono il *sorgente* e mentirebbero sull'output.
            for stale in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
                          kCGImagePropertyDepth, kCGImagePropertyIsFloat,
                          kCGImagePropertyProfileName, kCGImagePropertyThumbnailImages,
                          kCGImagePropertyFileSize] {
                properties.removeValue(forKey: stale)
            }
            properties.removeValue(forKey: "PixelWidth" as CFString)
            properties.removeValue(forKey: "PixelHeight" as CFString)

            if output.stripGPS {
                properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
            }

            // L'orientamento EXIF è già stato applicato ai pixel in fase di lettura:
            // lasciarlo nel file farebbe ruotare l'immagine una seconda volta.
            properties[kCGImagePropertyOrientation] = 1
            if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
            if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = Int(size.width)
                exif[kCGImagePropertyExifPixelYDimension] = Int(size.height)
                properties[kCGImagePropertyExifDictionary] = exif
            }
        } else {
            properties[kCGImagePropertyOrientation] = 1
        }

        if !output.format.isLossless, type != .png, type != .tiff {
            properties[kCGImageDestinationLossyCompressionQuality] = output.quality
        }
        if type == .jpeg {
            properties[kCGImagePropertyHasAlpha] = false
        }
        return properties
    }

    /// Copia il contenitore XMP del sorgente correggendo orientamento e dimensioni.
    static func adjustedMetadata(from source: LoadedImage,
                                 size: CGSize,
                                 output: OutputSpec) -> CGImageMetadata? {
        guard let original = source.metadata,
              let mutable = CGImageMetadataCreateMutableCopy(original)
        else { return nil }

        CGImageMetadataSetValueMatchingImageProperty(
            mutable, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber)
        CGImageMetadataSetValueMatchingImageProperty(
            mutable, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension,
            Int(size.width) as CFNumber)
        CGImageMetadataSetValueMatchingImageProperty(
            mutable, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension,
            Int(size.height) as CFNumber)

        if output.stripGPS {
            CGImageMetadataEnumerateTagsUsingBlock(mutable, nil, nil) { path, _ in
                if (path as String).lowercased().hasPrefix("exif:gps")
                    || (path as String).lowercased().hasPrefix("gps") {
                    CGImageMetadataRemoveTagWithPath(mutable, nil, path)
                }
                return true
            }
        }
        return mutable
    }
}
