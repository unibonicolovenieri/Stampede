import Foundation

/// Un profilo di lavorazione riutilizzabile: watermark + regole di output.
public struct Preset: Codable, Sendable, Equatable {
    public var name: String
    public var description: String?
    public var watermark: WatermarkSpec
    public var output: OutputSpec

    public init(name: String,
                description: String? = nil,
                watermark: WatermarkSpec = WatermarkSpec(),
                output: OutputSpec = OutputSpec()) {
        self.name = name
        self.description = description
        self.watermark = watermark
        self.output = output
    }
}

/// Legge e scrive i preset su disco, cercandoli in più posizioni.
public struct PresetStore: Sendable {
    /// `~/.config/stampede/presets` — dove finiscono i preset salvati dall'utente.
    public static var userDirectory: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("stampede/presets", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/stampede/presets", isDirectory: true)
    }

    /// `./presets` nella cartella di lavoro corrente — utile per preset versionati nel repo.
    public static var projectDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("presets", isDirectory: true)
    }

    public static var searchPaths: [URL] { [projectDirectory, userDirectory] }

    public init() {}

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Risolve `nameOrPath`: prima come percorso esplicito a un .json, poi per nome nelle cartelle note.
    public func load(_ nameOrPath: String) throws -> Preset {
        let direct = URL(fileURLWithPath: (nameOrPath as NSString).expandingTildeInPath)
        if nameOrPath.hasSuffix(".json"), FileManager.default.fileExists(atPath: direct.path) {
            return try decode(at: direct)
        }
        let filename = nameOrPath.hasSuffix(".json") ? nameOrPath : "\(nameOrPath).json"
        for dir in Self.searchPaths {
            let candidate = dir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try decode(at: candidate)
            }
        }
        throw StampedeError.presetNotFound(nameOrPath)
    }

    private func decode(at url: URL) throws -> Preset {
        let data = try Data(contentsOf: url)
        var preset: Preset
        do {
            preset = try JSONDecoder().decode(Preset.self, from: data)
        } catch {
            throw StampedeError.invalidConfiguration("preset illeggibile \(url.lastPathComponent): \(error.localizedDescription)")
        }
        // Un logo indicato con percorso relativo si risolve rispetto al preset, non
        // alla cartella corrente: così un preset versionato nel repo insieme al logo
        // funziona da qualunque directory venga lanciato il comando.
        let logoPath = preset.watermark.logoPath
        if !logoPath.isEmpty, !logoPath.hasPrefix("/"), !logoPath.hasPrefix("~") {
            preset.watermark.logoPath = url.deletingLastPathComponent()
                .appendingPathComponent(logoPath).standardizedFileURL.path
        } else if logoPath.hasPrefix("~") {
            preset.watermark.logoPath = (logoPath as NSString).expandingTildeInPath
        }
        return preset
    }

    @discardableResult
    public func save(_ preset: Preset, to directory: URL? = nil) throws -> URL {
        let dir = directory ?? Self.userDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(preset.name).json")
        try Self.encoder.encode(preset).write(to: url, options: .atomic)
        return url
    }

    public func delete(_ name: String) throws {
        let filename = name.hasSuffix(".json") ? name : "\(name).json"
        for dir in Self.searchPaths {
            let candidate = dir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.removeItem(at: candidate)
                return
            }
        }
        throw StampedeError.presetNotFound(name)
    }

    /// Tutti i preset trovati, deduplicati per nome (il progetto ha la precedenza sull'utente).
    public func list() -> [(preset: Preset, url: URL)] {
        var seen = Set<String>()
        var results: [(Preset, URL)] = []
        for dir in Self.searchPaths {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where file.pathExtension.lowercased() == "json" {
                guard let preset = try? decode(at: file), !seen.contains(preset.name) else { continue }
                seen.insert(preset.name)
                results.append((preset, file))
            }
        }
        return results
    }
}
