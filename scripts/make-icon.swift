// Genera l'icona di Stampede: un timbro che scende, con le linee di velocità.
// Vive come codice e non come binario, così si modifica leggendola.
// Eseguito da build-app.sh.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                         radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size s: CGFloat) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setShouldAntialias(true)

    // Il "squircle" di macOS: il grafico occupa circa l'82% della tela, il resto
    // è margine, altrimenti l'icona sembra più grande delle altre nel Dock.
    let pad = s * 0.09
    let plate = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: s * 0.2237, cornerHeight: s * 0.2237,
                       transform: nil))
    ctx.clip()

    // Ambra calda in alto a sinistra verso vermiglio in basso a destra: il colore
    // della corsa, e si distingue dalle icone blu che affollano il Dock.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [CGColor(red: 1.00, green: 0.78, blue: 0.28, alpha: 1),
                                       CGColor(red: 0.94, green: 0.45, blue: 0.18, alpha: 1),
                                       CGColor(red: 0.80, green: 0.24, blue: 0.20, alpha: 1)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    ctx.restoreGState()

    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    // Linee di velocità a sinistra: spariscono da sole alle dimensioni minime,
    // dove servirebbero solo a sporcare.
    if s >= 64 {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
        // Allineate alla base del timbro, l'elemento più pesante: è quello che
        // deve sembrare in corsa. E si fermano prima di toccarla.
        let lines: [(y: CGFloat, length: CGFloat)] = [
            (0.436, 0.105), (0.487, 0.165), (0.538, 0.105),
        ]
        for line in lines {
            ctx.addPath(roundedRect(s * (0.248 - line.length), s * line.y,
                                    s * line.length, s * 0.031, radius: s * 0.0155))
            ctx.fillPath()
        }
    }

    // Il timbro: impugnatura, collo, base.
    ctx.setFillColor(white)
    ctx.addPath(roundedRect(s * 0.365, s * 0.625, s * 0.27, s * 0.135, radius: s * 0.055))
    ctx.fillPath()
    ctx.addPath(roundedRect(s * 0.445, s * 0.545, s * 0.11, s * 0.10, radius: s * 0.018))
    ctx.fillPath()
    ctx.addPath(roundedRect(s * 0.275, s * 0.435, s * 0.45, s * 0.12, radius: s * 0.035))
    ctx.fillPath()

    // L'impronta lasciata sul foglio, staccata dalla base: è ciò che rende
    // l'oggetto un timbro e non un martello.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
    ctx.addPath(roundedRect(s * 0.315, s * 0.285, s * 0.37, s * 0.075, radius: s * 0.0375))
    ctx.fillPath()

    return ctx.makeImage()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

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
