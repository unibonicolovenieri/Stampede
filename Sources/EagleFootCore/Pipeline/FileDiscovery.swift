import Foundation

/// Espande gli argomenti di input (file, cartelle, glob) nell'elenco di foto da lavorare.
public enum FileDiscovery {

    public struct Plan: Sendable {
        public let files: [URL]
        /// Cartella comune agli input: serve a ricostruire l'albero nella destinazione.
        public let root: URL?
        public let skippedUnsupported: Int
    }

    public static func plan(inputs: [String], recursive: Bool) throws -> Plan {
        var files: [URL] = []
        var skipped = 0
        var explicitRoots: [URL] = []

        for input in inputs {
            let url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                Log.warn("percorso inesistente, lo salto: \(url.path)")
                continue
            }
            if isDirectory.boolValue {
                explicitRoots.append(url)
                let (found, ignored) = scan(directory: url, recursive: recursive)
                files.append(contentsOf: found)
                skipped += ignored
            } else if ImageLoader.isSupported(url) {
                explicitRoots.append(url.deletingLastPathComponent())
                files.append(url)
            } else {
                skipped += 1
            }
        }

        // Deduplica mantenendo un ordine stabile e prevedibile.
        var seen = Set<String>()
        let unique = files.filter { seen.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        return Plan(files: unique, root: commonRoot(of: explicitRoots), skippedUnsupported: skipped)
    }

    public static func scan(directory: URL, recursive: Bool) -> (files: [URL], skipped: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }

        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: options)
        else { return ([], 0) }

        var files: [URL] = []
        var skipped = 0
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if ImageLoader.isSupported(url) {
                files.append(url.standardizedFileURL)
            } else {
                skipped += 1
            }
        }
        return (files, skipped)
    }

    /// La cartella più profonda che contiene tutti gli input.
    static func commonRoot(of urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        guard urls.count > 1 else { return first }
        var common = first.standardizedFileURL.pathComponents
        for url in urls.dropFirst() {
            let components = url.standardizedFileURL.pathComponents
            var shared = 0
            while shared < min(common.count, components.count), common[shared] == components[shared] {
                shared += 1
            }
            common = Array(common.prefix(shared))
        }
        guard common.count > 1 else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: common))
    }
}
