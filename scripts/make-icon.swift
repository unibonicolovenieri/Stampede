// Genera l'icona dell'app: un otturatore stilizzato con la "firma" del watermark.
// Eseguito da build-app.sh, così l'icona vive nel repo come codice e non come binario.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func drawIcon(size: CGFloat) -> CGImage? {
    let s = size
    guard let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // Fondo: quadrato con angoli arrotondati alla maniera di macOS (circa 22% del lato).
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [CGColor(red: 0.16, green: 0.22, blue: 0.36, alpha: 1),
                                       CGColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Anello dell'otturatore.
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(s * 0.055)
    let ring = CGRect(x: s * 0.26, y: s * 0.26, width: s * 0.48, height: s * 0.48)
    ctx.strokeEllipse(in: ring)

    // Triangolo interno: richiama il segno del logo di esempio.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.move(to: CGPoint(x: s * 0.40, y: s * 0.43))
    ctx.addLine(to: CGPoint(x: s * 0.50, y: s * 0.60))
    ctx.addLine(to: CGPoint(x: s * 0.60, y: s * 0.43))
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Le dimensioni richieste da iconutil per un .icns completo.
let sizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    guard let image = drawIcon(size: pixels) else { continue }
    let url = output.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { continue }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("iconset generato in \(output.path)")
