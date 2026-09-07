import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Compone il watermark sopra la foto costruendo un grafo di filtri Core Image.
///
/// Qui non viene renderizzato nulla: si restituisce una `CIImage`, cioè una ricetta.
/// Il calcolo vero avviene una volta sola, sulla GPU, quando `ImageWriter` chiede il
/// bitmap finale — così ridimensionamento, fusione e codifica sono un solo passaggio.
public enum WatermarkRenderer {

    /// Applica il watermark a `base` e restituisce l'immagine composta, già ritagliata.
    public static func compose(base: CIImage,
                               logo: LogoAsset,
                               spec: WatermarkSpec,
                               resize: ResizeSpec? = nil) throws -> CIImage {
        let canvas = normalize(resized(base, with: resize))
        let size = canvas.extent.size
        guard size.width > 0, size.height > 0 else { return canvas }

        guard spec.opacity > 0 else { return canvas }

        let logoWidth = spec.scale.targetWidth(imageSize: size)
        guard logoWidth >= 1 else {
            throw StampedeError.invalidConfiguration(
                "il logo risulterebbe largo \(Int(logoWidth)) px: aumenta --scale")
        }

        var stamp = try logo.image(atWidth: logoWidth)
        stamp = rotated(stamp, degrees: spec.rotation)
        if let shadow = spec.shadow, shadow.opacity > 0, shadow.radius > 0 {
            stamp = applyShadow(to: stamp, shadow: shadow)
        }
        stamp = faded(stamp, opacity: spec.opacity)

        let overlay: CIImage = switch spec.layout {
        case .single: placeSingle(stamp, in: size, placement: spec.single)
        case .tile: placeTiled(stamp, in: canvas.extent, placement: spec.tile)
        }

        return blend(overlay: overlay, over: canvas, mode: spec.blend)
            .cropped(to: canvas.extent)
    }

    // MARK: - Ridimensionamento

    public static func resized(_ image: CIImage, with resize: ResizeSpec?) -> CIImage {
        guard let resize, let factor = resize.scaleFactor(for: image.extent.size) else { return image }
        if factor < 1 {
            // Lanczos: il downscale è il caso normale e merita il filtro migliore.
            return image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: factor,
                kCIInputAspectRatioKey: 1.0,
            ])
        }
        return image.applyingFilter("CIBicubicScaleTransform", parameters: [
            kCIInputScaleKey: factor,
            kCIInputAspectRatioKey: 1.0,
        ])
    }

    /// Riporta l'origine dell'extent a (0,0): i filtri di scala la spostano di frazioni di pixel.
    public static func normalize(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.origin != .zero else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .cropped(to: CGRect(origin: .zero, size: extent.size))
    }

    // MARK: - Trasformazioni sul logo

    public static func rotated(_ image: CIImage, degrees: Double) -> CIImage {
        guard abs(degrees.truncatingRemainder(dividingBy: 360)) > 0.001 else { return image }
        let radians = CGFloat(degrees * .pi / 180)
        let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: radians)
            .translatedBy(x: -center.x, y: -center.y)
        return normalize(image.transformed(by: transform))
    }

    /// Sfuma il logo scalando **solo** il canale alfa.
    ///
    /// `CIColorMatrix` lavora su valori non premoltiplicati: scalare anche R, G e B
    /// applicherebbe l'opacità due volte (0.5 diventerebbe 0.25) e il watermark
    /// risulterebbe molto più trasparente di quanto chiesto. Verificato da `stampede selftest`.
    public static func faded(_ image: CIImage, opacity: Double) -> CIImage {
        guard opacity < 0.999 else { return image }
        let f = CGFloat(max(0, opacity))
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: f),
        ])
    }

    public static func applyShadow(to image: CIImage, shadow: ShadowSpec) -> CIImage {
        // La sagoma dell'ombra è il logo tutto nero, con l'alfa del logo.
        let silhouette = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(shadow.opacity)),
        ])
        let blurred = silhouette
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: shadow.radius])
            .cropped(to: image.extent.insetBy(dx: -shadow.radius * 3, dy: -shadow.radius * 3))
            .transformed(by: CGAffineTransform(translationX: CGFloat(shadow.offsetX),
                                               y: CGFloat(shadow.offsetY)))
        return normalize(image.composited(over: blurred))
    }

    // MARK: - Posizionamento

    public static func placeSingle(_ stamp: CIImage, in size: CGSize, placement: SinglePlacement) -> CIImage {
        let unit = placement.anchor.unitPoint
        let direction = placement.anchor.marginDirection
        let margin = placement.marginPoints(imageSize: size)

        let anchorX = size.width * unit.x + margin.x * direction.dx
        let anchorY = size.height * unit.y + margin.y * direction.dy

        let box = stamp.extent
        let targetX = anchorX - box.width * unit.x
        let targetY = anchorY - box.height * unit.y

        return stamp.transformed(by: CGAffineTransform(translationX: (targetX - box.origin.x).rounded(),
                                                        y: (targetY - box.origin.y).rounded()))
    }

    public static func placeTiled(_ stamp: CIImage, in bounds: CGRect, placement: TilePlacement) -> CIImage {
        let box = stamp.extent
        let cellWidth = max(1, box.width * CGFloat(1 + placement.spacingX))
        let cellHeight = max(1, box.height * CGFloat(1 + placement.spacingY))

        // La cella di base contiene una copia centrata. Con `stagger` la cella è alta
        // il doppio e la seconda riga è sfalsata di mezza cella: tassellandola nasce
        // il classico reticolo a mattoni, molto più difficile da rimuovere in post.
        let cellRect = CGRect(x: 0, y: 0,
                              width: cellWidth,
                              height: placement.stagger ? cellHeight * 2 : cellHeight)
        // `CIImage.empty()` ha extent nullo: ritagliarlo non produce una tela, resta vuoto.
        // Serve un colore trasparente a estensione infinita da ritagliare sulla cella,
        // altrimenti la cella coincide con il logo e la spaziatura sparisce.
        var cell = CIImage(color: .clear).cropped(to: cellRect)

        func stamped(centeredAt point: CGPoint) -> CIImage {
            stamp.transformed(by: CGAffineTransform(
                translationX: point.x - box.midX,
                y: point.y - box.midY))
        }

        cell = stamped(centeredAt: CGPoint(x: cellWidth / 2, y: cellHeight / 2)).composited(over: cell)
        if placement.stagger {
            // Le due metà ai bordi si ricompongono in un logo intero quando la cella si ripete.
            cell = stamped(centeredAt: CGPoint(x: 0, y: cellHeight * 1.5)).composited(over: cell)
            cell = stamped(centeredAt: CGPoint(x: cellWidth, y: cellHeight * 1.5)).composited(over: cell)
        }
        cell = cell.cropped(to: cellRect)

        let tiled = cell.applyingFilter("CIAffineTile", parameters: [
            kCIInputTransformKey: CGAffineTransform.identity,
        ])

        guard abs(placement.angle.truncatingRemainder(dividingBy: 360)) > 0.001 else {
            return tiled.cropped(to: bounds)
        }
        // Ruotiamo il reticolo attorno al centro della foto, poi ritagliamo:
        // il piano tassellato è infinito, quindi non restano angoli scoperti.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rotation = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(placement.angle * .pi / 180))
            .translatedBy(x: -center.x, y: -center.y)
        return tiled.transformed(by: rotation).cropped(to: bounds)
    }

    // MARK: - Fusione

    public static func blend(overlay: CIImage, over base: CIImage, mode: BlendMode) -> CIImage {
        if mode == .normal {
            return overlay.composited(over: base)
        }
        guard let filter = CIFilter(name: mode.ciFilterName) else {
            return overlay.composited(over: base)
        }
        filter.setValue(base, forKey: kCIInputBackgroundImageKey)
        filter.setValue(overlay, forKey: kCIInputImageKey)
        return filter.outputImage ?? overlay.composited(over: base)
    }
}
