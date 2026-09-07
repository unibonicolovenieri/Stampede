import CoreImage
import Foundation
import Metal

/// Come Core Image esegue le fusioni: in luce lineare (fisicamente corretto)
/// o in sRGB con gamma (identico a Photoshop / uMark).
public enum BlendSpace: String, Codable, CaseIterable, Sendable {
    case srgb, linear

    var colorSpace: CGColorSpace? {
        switch self {
        case .srgb: CGColorSpace(name: CGColorSpace.sRGB)
        case .linear: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        }
    }
}

/// Precisione con cui la GPU tiene i pixel intermedi.
public enum WorkingPrecision: String, Codable, CaseIterable, Sendable {
    /// 8 bit per canale: il più veloce e leggero, adatto a JPEG 8 bit.
    case fast
    /// half-float 16 bit: default, nessun banding percepibile, ottimo su Apple Silicon.
    case balanced
    /// float 32 bit: massima precisione, ~2x memoria rispetto a balanced.
    case maximum

    var ciFormat: CIFormat {
        switch self {
        case .fast: .RGBA8
        case .balanced: .RGBAh
        case .maximum: .RGBAf
        }
    }

    public static var allCLINames: [String] { allCases.map(\.rawValue) }
}

/// Pool di `CIContext` che condividono un solo `MTLDevice`.
///
/// Un singolo `CIContext` è thread-safe ma serializza parte del lavoro di
/// preparazione dei command buffer: tenerne alcuni in rotazione permette a più
/// immagini di essere in volo sulla GPU contemporaneamente.
public final class GPUContextPool: @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let contexts: [CIContext]
    private let lock = NSLock()
    private var cursor = 0

    public var size: Int { contexts.count }
    public var deviceName: String { device.name }
    public var hasUnifiedMemory: Bool { device.hasUnifiedMemory }
    public var recommendedWorkingSetSize: UInt64 { device.recommendedMaxWorkingSetSize }

    public init(count: Int, precision: WorkingPrecision = .balanced, blendSpace: BlendSpace = .srgb) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw EagleFootError.metalUnavailable
        }
        self.device = device
        self.commandQueue = queue

        var options: [CIContextOption: Any] = [
            .workingFormat: precision.ciFormat,
            // Il batch tocca ogni pixel una volta sola: la cache intermedia
            // farebbe solo crescere la memoria senza mai essere riusata.
            .cacheIntermediates: false,
            .highQualityDownsample: true,
            .allowLowPower: false,
        ]
        if let workingSpace = blendSpace.colorSpace {
            options[.workingColorSpace] = workingSpace
        }
        self.contexts = (0..<max(1, count)).map { _ in
            CIContext(mtlCommandQueue: queue, options: options)
        }
    }

    /// Restituisce il prossimo contesto in round-robin.
    public func next() -> CIContext {
        lock.lock(); defer { lock.unlock() }
        let context = contexts[cursor % contexts.count]
        cursor &+= 1
        return context
    }

    /// Libera le cache GPU accumulate: da chiamare fra un batch e l'altro.
    public func clearCaches() {
        for context in contexts { context.clearCaches() }
    }
}
