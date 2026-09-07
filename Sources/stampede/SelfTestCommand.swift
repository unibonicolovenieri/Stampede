import ArgumentParser
import CoreImage
import StampedeCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Verifica che il motore si comporti come promesso su *questa* macchina.
///
/// Esiste come comando e non solo come test unitario perché `swift test` richiede
/// Xcode completo, mentre questo gira ovunque giri il binario — anche dopo un
/// aggiornamento di macOS, che è esattamente quando serve saperlo.
struct SelfTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "selftest",
        abstract: "Controlla che rendering, metadati e qualità siano corretti.")

    @Flag(name: [.short, .long], help: "Mostra ogni singolo controllo, anche quelli passati.")
    var verbose: Bool = false

    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .workingFormat: CIFormat.RGBAh,
    ])

    func run() async throws {
        var checker = Checker(verbose: verbose)

        checkBlending(&checker)
        checkPlacement(&checker)
        checkTiling(&checker)
        checkSizing(&checker)
        checkNaming(&checker)
        checkRemotePaths(&checker)
        try checkRoundTrip(&checker)

        checker.report()
        if checker.failures > 0 { throw ExitCode(1) }
    }

    // MARK: - Fusione e opacità

    private func checkBlending(_ c: inout Checker) {
        c.section("Fusione e opacità")

        // Un logo rosso pieno al 50% su nero deve dare 128, non 255. È il controllo che
        // smaschera la premoltiplicazione sbagliata: scalando il solo canale alfa il
        // colore resterebbe saturo e il watermark sembrerebbe quasi opaco.
        let size = CGSize(width: 8, height: 8)
        let red = solid(CIColor(red: 1, green: 0, blue: 0, alpha: 1), size)
        let half = sample(WatermarkRenderer.faded(red, opacity: 0.5).composited(over: solid(.black, size)))
        c.near("rosso al 50% su nero → ~128", half.r, 128, tolerance: 3)
        c.near("i canali non toccati restano a 0", half.g, 0, tolerance: 2)

        let full = sample(WatermarkRenderer.faded(red, opacity: 1).composited(over: solid(.black, size)))
        c.near("opacità 1 non altera i pixel", full.r, 255, tolerance: 1)

        // Un PNG già semitrasparente sfumato di un altro 50% → 25% effettivo.
        let translucent = solid(CIColor(red: 1, green: 1, blue: 1, alpha: 0.5), size)
        let compounded = sample(WatermarkRenderer.faded(translucent, opacity: 0.5).composited(over: solid(.black, size)))
        c.near("alfa del PNG e --opacity si moltiplicano", compounded.r, 64, tolerance: 4)
    }

    // MARK: - Posizionamento

    private func checkPlacement(_ c: inout Checker) {
        c.section("Posizionamento")
        let canvas = CGSize(width: 200, height: 100)
        let stamp = solid(.white, CGSize(width: 20, height: 10))

        let corners: [(Anchor, CGPoint)] = [
            (.bottomLeft, CGPoint(x: 0, y: 0)),
            (.bottomRight, CGPoint(x: 180, y: 0)),
            (.topLeft, CGPoint(x: 0, y: 90)),
            (.topRight, CGPoint(x: 180, y: 90)),
            (.center, CGPoint(x: 90, y: 45)),
            (.topCenter, CGPoint(x: 90, y: 90)),
            (.middleLeft, CGPoint(x: 0, y: 45)),
            (.bottomCenter, CGPoint(x: 90, y: 0)),
            (.middleRight, CGPoint(x: 180, y: 45)),
        ]
        for (anchor, expected) in corners {
            let placed = WatermarkRenderer.placeSingle(
                stamp, in: canvas,
                placement: SinglePlacement(anchor: anchor, marginUnit: .pixels, marginX: 0, marginY: 0))
            c.near("ancora \(anchor.cliName)", Double(placed.extent.origin.x), Double(expected.x), tolerance: 0.5)
            c.near("ancora \(anchor.cliName) (Y)", Double(placed.extent.origin.y), Double(expected.y), tolerance: 0.5)
        }

        // Il margine deve spingere verso l'interno da tutti e quattro gli angoli:
        // un segno sbagliato manderebbe il logo fuori immagine solo su due di essi.
        let topRight = WatermarkRenderer.placeSingle(
            stamp, in: canvas,
            placement: SinglePlacement(anchor: .topRight, marginUnit: .pixels, marginX: 10, marginY: 5))
        c.near("margine da top-right rientra in X", Double(topRight.extent.origin.x), 170, tolerance: 0.5)
        c.near("margine da top-right rientra in Y", Double(topRight.extent.maxY), 95, tolerance: 0.5)

        let bottomLeft = WatermarkRenderer.placeSingle(
            stamp, in: canvas,
            placement: SinglePlacement(anchor: .bottomLeft, marginUnit: .pixels, marginX: 10, marginY: 5))
        c.near("margine da bottom-left rientra in X", Double(bottomLeft.extent.origin.x), 10, tolerance: 0.5)
        c.near("margine da bottom-left rientra in Y", Double(bottomLeft.extent.origin.y), 5, tolerance: 0.5)

        let margin = SinglePlacement(anchor: .bottomRight, marginUnit: .fraction, marginX: 0.05, marginY: 0.1)
            .marginPoints(imageSize: CGSize(width: 1000, height: 500))
        c.near("margine in % scala con la foto", Double(margin.x), 50, tolerance: 0.001)

        let rotated = WatermarkRenderer.rotated(solid(.white, CGSize(width: 100, height: 40)), degrees: 45)
        let placedRotated = WatermarkRenderer.placeSingle(
            rotated, in: CGSize(width: 400, height: 300),
            placement: SinglePlacement(anchor: .bottomRight, marginUnit: .pixels, marginX: 10, marginY: 10))
        c.assert("il logo ruotato resta dentro l'immagine",
                 placedRotated.extent.maxX <= 390.5 && placedRotated.extent.minY >= 9.5)

        // Il riquadro di un rettangolo 100×40 ruotato di 30° è calcolabile a mano:
        // se non torna, la rotazione sta applicando un angolo diverso da quello chiesto.
        let angle = 30.0 * .pi / 180
        let box = WatermarkRenderer.rotated(solid(.white, CGSize(width: 100, height: 40)), degrees: 30).extent
        c.near("--rotate 30 produce il riquadro atteso (larghezza)",
               Double(box.width), 100 * cos(angle) + 40 * sin(angle), tolerance: 1.5)
        c.near("--rotate 30 produce il riquadro atteso (altezza)",
               Double(box.height), 100 * sin(angle) + 40 * cos(angle), tolerance: 1.5)
    }

    // MARK: - Mosaico

    private func checkTiling(_ c: inout Checker) {
        c.section("Mosaico")
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let stamp = solid(.white, CGSize(width: 40, height: 20))

        let tiled = WatermarkRenderer.placeTiled(
            stamp, in: bounds, placement: TilePlacement(angle: -30, spacingX: 0.2, spacingY: 0.2, stagger: true))
        c.assert("il mosaico ruotato è ritagliato sulla foto", tiled.extent == bounds)
        c.assert("il mosaico ruotato copre anche gli angoli", coverage(tiled, in: bounds) > 40)

        for stagger in [true, false] {
            let extent = WatermarkRenderer.placeTiled(
                stamp, in: bounds,
                placement: TilePlacement(angle: 0, spacingX: 1, spacingY: 1, stagger: stagger)).extent
            c.assert("stagger=\(stagger) non cambia il ritaglio", extent == bounds)
        }

        // Più spazio fra le copie ⇒ meno inchiostro. Se il rapporto si invertisse,
        // --tile-spacing farebbe l'opposto di quel che promette.
        func inked(_ spacing: Double) -> Int {
            coverage(WatermarkRenderer.placeTiled(
                stamp, in: bounds,
                placement: TilePlacement(angle: 0, spacingX: spacing, spacingY: spacing, stagger: false)),
                     in: bounds)
        }
        c.assert("più spaziatura = meno copertura", inked(0.2) > inked(2.0))

        // L'angolo dev'essere davvero quello chiesto, non una frazione: si verifica
        // ruotando di 90° un reticolo di barre orizzontali e controllando che
        // diventino verticali. Un errore di scala nella rotazione salterebbe fuori qui.
        let bar = solid(.white, CGSize(width: 60, height: 6))
        let square = CGRect(x: 0, y: 0, width: 240, height: 240)
        func stripes(angle: Double) -> CIImage {
            WatermarkRenderer.placeTiled(bar, in: square,
                                         placement: TilePlacement(angle: angle, spacingX: 0,
                                                                  spacingY: 5, stagger: false))
        }
        // Una fascia sottile e orizzontale al centro: con barre orizzontali la incrocia
        // di rado, con barre verticali la attraversa in continuazione.
        let probe = CGRect(x: 20, y: 118, width: 200, height: 4)
        let horizontal = coverage(stripes(angle: 0), in: probe, over: square)
        let vertical = coverage(stripes(angle: 90), in: probe, over: square)
        c.assert("--tile-angle 90 ruota davvero il reticolo di 90° "
            + "(orizzontale \(horizontal), verticale \(vertical))", vertical > horizontal + 15)

        // Un reticolo ruotato di 180° è indistinguibile da uno non ruotato: è una
        // simmetria vera del mosaico, quindi un buon controllo che la rotazione non
        // introduca derive di posizione o ritagli storti.
        let halfTurn = coverage(stripes(angle: 180), in: probe, over: square)
        c.near("--tile-angle 180 equivale a 0° (simmetria del reticolo)",
               halfTurn, horizontal, tolerance: 6)
        c.assert("--tile-angle 45 cambia effettivamente il reticolo",
                 abs(coverage(stripes(angle: 45), in: probe, over: square) - horizontal) > 5)
    }

    // MARK: - Scala, resize, nomi

    private func checkSizing(_ c: inout Checker) {
        c.section("Scala e ridimensionamento")
        let size = CGSize(width: 4000, height: 3000)
        c.near("scala 25% sulla larghezza", Double(ScaleSpec(unit: .fraction, value: 0.25, reference: .width).targetWidth(imageSize: size)), 1000, tolerance: 0.01)
        c.near("scala 25% sull'altezza", Double(ScaleSpec(unit: .fraction, value: 0.25, reference: .height).targetWidth(imageSize: size)), 750, tolerance: 0.01)
        c.near("scala 25% sul lato lungo", Double(ScaleSpec(unit: .fraction, value: 0.25, reference: .longest).targetWidth(imageSize: size)), 1000, tolerance: 0.01)
        c.near("scala 10% sulla diagonale", Double(ScaleSpec(unit: .fraction, value: 0.1, reference: .diagonal).targetWidth(imageSize: size)), 500, tolerance: 0.01)
        c.near("scala in pixel assoluti", Double(ScaleSpec(unit: .pixels, value: 640).targetWidth(imageSize: size)), 640, tolerance: 0.01)

        let small = CGSize(width: 800, height: 600)
        c.assert("senza --allow-upscale non si ingrandisce", ResizeSpec(mode: .longest, value: 2000).scaleFactor(for: small) == nil)
        c.near("con --allow-upscale si ingrandisce", ResizeSpec(mode: .longest, value: 2000, allowUpscale: true).scaleFactor(for: small) ?? 0, 2.5, tolerance: 0.001)
        c.near("il downscale calcola il fattore giusto", ResizeSpec(mode: .longest, value: 400).scaleFactor(for: small) ?? 0, 0.5, tolerance: 0.001)
        c.assert("resize al 100% non tocca nulla", ResizeSpec(mode: .percent, value: 100).scaleFactor(for: small) == nil)
    }

    private func checkNaming(_ c: inout Checker) {
        c.section("Nomi dei file")
        let source = URL(fileURLWithPath: "/Servizi/Matrimonio/DSC_0042.NEF")
        var output = OutputSpec(format: .jpeg)
        c.assert("estensione allineata al formato",
                 output.outputFilename(source: source, index: 7) == "DSC_0042.jpg")
        output.filenameTemplate = "{name}_wm{ext}"
        c.assert("suffisso applicato",
                 output.outputFilename(source: source, index: 7) == "DSC_0042_wm.jpg")
        output.filenameTemplate = "{parent}-{index}"
        c.assert("estensione aggiunta anche senza {ext}",
                 output.outputFilename(source: source, index: 7) == "Matrimonio-0007.jpg")
    }

    private func checkRemotePaths(_ c: inout Checker) {
        c.section("Percorsi Google Drive")
        c.assert("remote:cartella viene interpretato", RemoteTarget("gdrive:Foto/2026")?.spec == "gdrive:Foto/2026")
        c.assert("remote senza cartella", RemoteTarget("gdrive:")?.spec == "gdrive:")
        c.assert("slash di troppo rimossi", RemoteTarget("gdrive:/Foto/")?.spec == "gdrive:Foto")
        c.assert("stringa vuota rifiutata", RemoteTarget("") == nil)

        // Regressione: `/tmp` è un link a `/private/tmp`, quindi due URL dello stesso
        // file possono avere testo diverso. Se il confronto tornasse a essere testuale,
        // l'albero di cartelle finirebbe appiattito su Drive.
        let viaLink = URL(fileURLWithPath: "/tmp/servizio/Sposi/a.jpg")
        let viaReal = URL(fileURLWithPath: "/private/tmp/servizio")
        c.assert("l'albero sopravvive ai link simbolici (/tmp ↔ /private/tmp)",
                 PathUtilities.relativeComponents(of: viaLink, under: viaReal) == ["Sposi", "a.jpg"])
        c.assert("le sottocartelle sono estratte senza il nome file",
                 PathUtilities.relativeDirectories(of: viaLink, under: viaReal) == ["Sposi"])
        c.assert("un file fuori dalla radice non è relativo",
                 PathUtilities.relativeComponents(
                     of: URL(fileURLWithPath: "/altrove/a.jpg"),
                     under: URL(fileURLWithPath: "/tmp")) == nil)
        c.assert("lo stesso file per due strade è riconosciuto",
                 PathUtilities.sameFile(URL(fileURLWithPath: "/tmp/x.jpg"),
                                        URL(fileURLWithPath: "/private/tmp/./x.jpg")))
        c.assert("file diversi non vengono confusi",
                 !PathUtilities.sameFile(URL(fileURLWithPath: "/tmp/x.jpg"),
                                         URL(fileURLWithPath: "/tmp/y.jpg")))
    }

    // MARK: - Prova completa su file veri

    private func checkRoundTrip(_ c: inout Checker) throws {
        c.section("Prova completa su file")
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stampede-selftest-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let photoSize = CGSize(width: 1200, height: 800)
        let photo = try makePhotoWithMetadata(size: photoSize, into: workspace)
        let logo = try SampleGenerator.generateLogo(into: workspace)

        let pool = try GPUContextPool(count: 2, precision: .balanced, blendSpace: .srgb)
        let asset = try LogoAsset.load(logo)
        let watermark = WatermarkSpec(logoPath: logo.path, opacity: 0.9,
                                      scale: ScaleSpec(unit: .fraction, value: 0.3),
                                      single: SinglePlacement(anchor: .bottomRight,
                                                              marginUnit: .fraction,
                                                              marginX: 0.02, marginY: 0.02))
        let loaded = try ImageLoader.load(photo)
        c.assert("le dimensioni lette corrispondono all'originale", loaded.pixelSize == photoSize)

        let composed = try WatermarkRenderer.compose(base: loaded.image, logo: asset, spec: watermark)
        let destination = workspace.appendingPathComponent("out.jpg")
        let written = try ImageWriter.write(composed, to: destination, context: pool.next(),
                                            source: loaded, output: OutputSpec(format: .jpeg, quality: 0.95))

        c.assert("l'output ha la stessa risoluzione dell'originale", written.pixelSize == photoSize)
        c.assert("il file è stato scritto", written.bytes > 0)
        c.assert("nessun file temporaneo lasciato in giro",
                 (try? FileManager.default.contentsOfDirectory(atPath: workspace.path))?
                     .contains(where: { $0.hasSuffix(".stampede-part") }) == false)

        guard let source = CGImageSourceCreateWithURL(destination as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            c.assert("l'output è rileggibile", false)
            return
        }

        c.assert("larghezza nel file corretta", properties[kCGImagePropertyPixelWidth] as? Int == 1200)
        c.assert("altezza nel file corretta", properties[kCGImagePropertyPixelHeight] as? Int == 800)
        c.assert("orientamento azzerato (già applicato ai pixel)",
                 (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        c.assert("EXIF preservato: modello di fotocamera",
                 (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String == "Stampede Test Cam")
        c.assert("EXIF preservato: data di scatto",
                 exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:07 12:00:00")
        c.assert("EXIF aggiornato: dimensioni coerenti",
                 exif?[kCGImagePropertyExifPixelXDimension] as? Int == 1200)
        c.assert("profilo colore presente nell'output", properties[kCGImagePropertyProfileName] != nil)

        // Il watermark deve aver cambiato l'angolo in basso a destra e lasciato intatto
        // quello opposto. Si confrontano le medie di due riquadri e non due singoli
        // pixel: un logo è in gran parte trasparente, e un pixel preso nel punto
        // sbagliato direbbe "nessuna differenza" anche con il watermark al posto giusto.
        guard let outputImage = CIImage(contentsOf: destination),
              let originalImage = CIImage(contentsOf: photo) else {
            c.assert("l'output è decodificabile", false)
            return
        }
        // Logo largo il 30% di 1200 px = 360, alto 108, con margine del 2%.
        let logoBox = CGRect(x: 1200 - 24 - 360, y: 16, width: 360, height: 108)
        let quietBox = CGRect(x: 40, y: 620, width: 360, height: 108)

        let stampedDelta = meanDifference(outputImage, originalImage, in: logoBox)
        let quietDelta = meanDifference(outputImage, originalImage, in: quietBox)

        c.assert("il riquadro del logo è cambiato (delta \(stampedDelta))", stampedDelta > 10)
        c.assert("l'angolo opposto è rimasto invariato (delta \(quietDelta))", quietDelta <= 3)
        c.assert("il logo si vede più del resto della foto", stampedDelta > quietDelta * 3)

        // Con --no-metadata l'EXIF deve sparire davvero.
        let stripped = workspace.appendingPathComponent("stripped.jpg")
        _ = try ImageWriter.write(composed, to: stripped, context: pool.next(), source: loaded,
                                  output: OutputSpec(format: .jpeg, preserveMetadata: false))
        if let strippedSource = CGImageSourceCreateWithURL(stripped as CFURL, nil),
           let strippedProperties = CGImageSourceCopyPropertiesAtIndex(strippedSource, 0, nil) as? [CFString: Any] {
            let model = (strippedProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel]
            c.assert("--no-metadata rimuove davvero l'EXIF", model == nil)
        }

        // Il ridimensionamento deve produrre esattamente il lato lungo richiesto.
        let resizedOutput = workspace.appendingPathComponent("resized.jpg")
        let resizeSpec = ResizeSpec(mode: .longest, value: 600)
        let resizedImage = try WatermarkRenderer.compose(base: loaded.image, logo: asset,
                                                         spec: watermark, resize: resizeSpec)
        let resizedResult = try ImageWriter.write(resizedImage, to: resizedOutput, context: pool.next(),
                                                  source: loaded, output: OutputSpec(format: .jpeg, resize: resizeSpec))
        c.near("--resize-longest 600 produce il lato lungo esatto",
               Double(resizedResult.pixelSize.width), 600, tolerance: 1)
        c.near("il ridimensionamento conserva le proporzioni",
               Double(resizedResult.pixelSize.height), 400, tolerance: 1)
    }

    // MARK: - Utilità

    private func makePhotoWithMetadata(size: CGSize, into directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("photo.jpg")
        let gradient = CIFilter(name: "CILinearGradient")!
        gradient.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        gradient.setValue(CIVector(x: size.width, y: size.height), forKey: "inputPoint1")
        gradient.setValue(CIColor(red: 0.15, green: 0.25, blue: 0.45), forKey: "inputColor0")
        gradient.setValue(CIColor(red: 0.85, green: 0.55, blue: 0.25), forKey: "inputColor1")
        let image = gradient.outputImage!.cropped(to: CGRect(origin: .zero, size: size))

        guard let cgImage = Self.context.createCGImage(image, from: CGRect(origin: .zero, size: size),
                                                       format: .RGBA8,
                                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        else { throw StampedeError.renderFailed(url) }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw StampedeError.cannotCreateDestination(url) }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.98,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Lumika",
                kCGImagePropertyTIFFModel: "Stampede Test Cam",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:07 12:00:00",
                kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifFNumber: 2.8,
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StampedeError.encodingFailed(url) }
        return url
    }

    private func solid(_ color: CIColor, _ size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func sample(_ image: CIImage, at point: CGPoint = .zero) -> (r: Int, g: Int, b: Int, a: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        Self.context.render(image, toBitmap: &pixel, rowBytes: 4,
                            bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]), Int(pixel[3]))
    }

    /// Scarto medio fra due immagini dentro un riquadro, in livelli su 255.
    private func meanDifference(_ a: CIImage, _ b: CIImage, in rect: CGRect) -> Int {
        let difference = a.applyingFilter("CIDifferenceBlendMode", parameters: [
            kCIInputBackgroundImageKey: b,
        ])
        let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: difference,
            kCIInputExtentKey: CIVector(cgRect: rect),
        ])!.outputImage!
        let pixel = sample(average)
        return (pixel.r + pixel.g + pixel.b) / 3
    }

    /// Luminosità media del reticolo composto su nero: quanta foto viene coperta.
    /// `probe` può essere una porzione di `canvas`, per misurare una sola fascia.
    private func coverage(_ overlay: CIImage, in probe: CGRect, over canvas: CGRect? = nil) -> Int {
        let base = canvas ?? probe
        let composed = overlay.composited(over: solid(.black, base.size))
        let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: composed,
            kCIInputExtentKey: CIVector(cgRect: probe),
        ])!.outputImage!
        return sample(average).r
    }
}

/// Raccoglie l'esito dei controlli e stampa un rapporto leggibile.
private struct Checker {
    let verbose: Bool
    var passed = 0
    var failures = 0
    private var currentSection = ""

    init(verbose: Bool) { self.verbose = verbose }

    mutating func section(_ title: String) {
        currentSection = title
        print("\n\u{001B}[1m\(title)\u{001B}[0m")
    }

    mutating func assert(_ description: String, _ condition: Bool) {
        if condition {
            passed += 1
            if verbose { print("  \u{001B}[32m✓\u{001B}[0m \(description)") }
        } else {
            failures += 1
            print("  \u{001B}[31m✗ \(description)\u{001B}[0m")
        }
    }

    mutating func near(_ description: String, _ actual: some BinaryFloatingPoint,
                       _ expected: some BinaryFloatingPoint, tolerance: Double) {
        let ok = abs(Double(actual) - Double(expected)) <= tolerance
        assert(ok ? description : "\(description) — atteso \(Double(expected)), ottenuto \(Double(actual))", ok)
    }

    mutating func near(_ description: String, _ actual: Int, _ expected: Int, tolerance: Int) {
        let ok = abs(actual - expected) <= tolerance
        assert(ok ? description : "\(description) — atteso \(expected), ottenuto \(actual)", ok)
    }

    func report() {
        print("")
        if failures == 0 {
            print("\u{001B}[32m✓ \(passed) controlli superati\u{001B}[0m")
        } else {
            print("\u{001B}[31m✗ \(failures) controlli falliti\u{001B}[0m (\(passed) superati)")
        }
    }
}
