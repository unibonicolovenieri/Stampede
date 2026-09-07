import Foundation

/// Confronti fra percorsi che reggono i link simbolici.
///
/// Su macOS `/tmp` è un link a `/private/tmp` (come `/var`, e come qualunque cartella
/// che l'utente abbia alias-ato in `~` o sotto `/Volumes`). Due URL che indicano lo
/// stesso file possono quindi avere testo diverso, e un confronto per stringa direbbe
/// che uno non sta dentro l'altro. Qui si normalizza sempre prima di confrontare.
public enum PathUtilities {

    /// I firmlink di macOS: `/tmp`, `/var` e `/etc` puntano dentro `/private`.
    /// Foundation li normalizza solo quando il percorso esiste già sul disco, quindi
    /// la stessa cartella prima e dopo essere stata creata otterrebbe due forme diverse.
    /// Qui il taglio del prefisso è incondizionato, e perciò sempre coerente.
    private static let privatePrefixes = ["/private/tmp", "/private/var", "/private/etc"]

    /// Percorso in forma canonica: `.`/`..` risolti, link simbolici seguiti,
    /// prefisso `/private` normalizzato via.
    public static func canonical(_ url: URL) -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = resolved.path
        for prefix in privatePrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return URL(fileURLWithPath: String(path.dropFirst("/private".count)))
        }
        return resolved
    }

    /// I componenti di `file` relativi a `root`, oppure `nil` se non vi è contenuto.
    ///
    /// Per `/foto/2026/Sposi/a.jpg` sotto `/foto` restituisce `["2026", "Sposi", "a.jpg"]`.
    public static func relativeComponents(of file: URL, under root: URL) -> [String]? {
        let rootComponents = canonical(root).pathComponents
        let fileComponents = canonical(file).pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    /// Le sole sottocartelle fra `root` e il file (senza il nome del file).
    public static func relativeDirectories(of file: URL, under root: URL) -> [String] {
        guard let components = relativeComponents(of: file, under: root) else { return [] }
        return Array(components.dropLast())
    }

    /// Vero se i due URL indicano lo stesso file, anche per strade diverse.
    public static func sameFile(_ a: URL, _ b: URL) -> Bool {
        canonical(a).path == canonical(b).path
    }
}
