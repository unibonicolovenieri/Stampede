import AppKit
import CoreGraphics
import CoreImage
import Foundation
import UniformTypeIdentifiers

/// Il logo da stampare sulle foto, caricato una volta sola e riusato da tutto il batch.
///
/// I formati vettoriali (PDF, SVG) non vengono rasterizzati a una risoluzione fissa:
/// li ridisegniamo alla larghezza esatta richiesta da ogni foto, così il logo resta
/// nitido anche su un file da 60 megapixel. Le rasterizzazioni sono in cache per larghezza.
public final class LogoAsset: @unchecked Sendable {
    public enum Kind: Sendable {
        case raster
        case vector
    }

    public let url: URL
    public let kind: Kind
    /// Rapporto altezza/larghezza del logo.
    public let aspectRatio: CGFloat
    /// Dimensione nativa in pixel (per i vettoriali: la dimensione del box del documento).
    public let nativeSize: CGSize

    private let baseImage: CIImage?
    private let vectorRenderer: (@Sendable (CGFloat) -> CIImage?)?
    private let cacheLock = NSLock()
    private var vectorCache: [Int: CIImage] = [:]

    public static func load(_ url: URL) throws -> LogoAsset {
        let ext = url.pathExtension.lowercased()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StampedeError.cannotDecodeLogo(url)
        }
        switch ext {
        case "pdf": return try LogoAsset(pdf: url)
        case "svg": return try LogoAsset(svg: url)
        case "png", "tif", "tiff", "webp", "heic", "heif", "jpg", "jpeg", "gif", "bmp":
            return try LogoAsset(raster: url)
        default:
            throw StampedeError.unsupportedLogoFormat(ext)
        }
    }

    // MARK: - Raster

    private init(raster url: URL) throws {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              image.extent.width > 0, image.extent.height > 0
        else { throw StampedeError.cannotDecodeLogo(url) }
        self.url = url
        self.kind = .raster
        self.baseImage = image
        self.vectorRenderer = nil
        self.nativeSize = image.extent.size
        self.aspectRatio = image.extent.height / image.extent.width
        if url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" {
            Log.warn("il logo \(url.lastPathComponent) è un JPEG: senza canale alfa il watermark avrà un rettangolo di sfondo. Usa un PNG.")
        }
    }

    // MARK: - PDF vettoriale

    private init(pdf url: URL) throws {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else {
            throw StampedeError.cannotDecodeLogo(url)
        }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { throw StampedeError.cannotDecodeLogo(url) }
        self.url = url
        self.kind = .vector
        self.baseImage = nil
        self.nativeSize = box.size
        self.aspectRatio = box.height / box.width
        self.vectorRenderer = { width in
            let height = (width * box.height / box.width).rounded()
            guard let bitmap = LogoAsset.makeBitmapContext(width: width, height: height) else { return nil }
            bitmap.scaleBy(x: width / box.width, y: height / box.height)
            bitmap.translateBy(x: -box.origin.x, y: -box.origin.y)
            bitmap.interpolationQuality = .high
            bitmap.drawPDFPage(page)
            return bitmap.makeImage().map { CIImage(cgImage: $0) }
        }
    }

    // MARK: - SVG vettoriale

    private init(svg url: URL) throws {
        guard let nsImage = NSImage(contentsOf: url), nsImage.size.width > 0 else {
            throw StampedeError.invalidConfiguration(
                "questo sistema non sa leggere \(url.lastPathComponent). Converti l'SVG in PDF o PNG "
                + "(es. apri con Anteprima ed esporta in PDF) e ripassalo a --logo.")
        }
        let box = CGRect(origin: .zero, size: nsImage.size)
        self.url = url
        self.kind = .vector
        self.baseImage = nil
        self.nativeSize = nsImage.size
        self.aspectRatio = nsImage.size.height / nsImage.size.width
        self.vectorRenderer = { width in
            let height = (width * box.height / box.width).rounded()
            guard let bitmap = LogoAsset.makeBitmapContext(width: width, height: height) else { return nil }
            bitmap.interpolationQuality = .high
            let graphicsContext = NSGraphicsContext(cgContext: bitmap, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            nsImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height),
                         from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.makeImage().map { CIImage(cgImage: $0) }
        }
    }

    private static func makeBitmapContext(width: CGFloat, height: CGFloat) -> CGContext? {
        let w = max(1, Int(width.rounded()))
        let h = max(1, Int(height.rounded()))
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: - Uso

    /// Il logo alla larghezza richiesta, pronto per essere composto.
    /// I raster vengono riscalati con Lanczos; i vettoriali ridisegnati alla risoluzione esatta.
    public func image(atWidth width: CGFloat) throws -> CIImage {
        let width = max(1, width.rounded())
        if let vectorRenderer {
            // Arrotondiamo a 8 px: un batch di foto della stessa dimensione riusa lo stesso raster.
            let key = Int((width / 8).rounded()) * 8
            cacheLock.lock()
            if let cached = vectorCache[key] { cacheLock.unlock(); return cached }
            cacheLock.unlock()

            guard let rendered = vectorRenderer(CGFloat(key)) else {
                throw StampedeError.cannotDecodeLogo(url)
            }
            cacheLock.lock()
            vectorCache[key] = rendered
            cacheLock.unlock()
            return rendered
        }

        guard let baseImage else { throw StampedeError.cannotDecodeLogo(url) }
        let factor = width / baseImage.extent.width
        if abs(factor - 1) < 0.002 { return baseImage }
        // Lanczos per il downscale (il caso normale: logo grande su foto), bilineare
        // per l'upscale, dove Lanczos introdurrebbe solo ringing.
        let scaled: CIImage
        if factor < 1 {
            scaled = baseImage.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: factor,
                kCIInputAspectRatioKey: 1.0,
            ])
        } else {
            scaled = baseImage.transformed(by: CGAffineTransform(scaleX: factor, y: factor),
                                           highQualityDownsample: true)
        }
        // Riportiamo l'origine a zero: i filtri di scala possono spostare l'extent.
        return scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x,
                                                        y: -scaled.extent.origin.y))
    }
}
