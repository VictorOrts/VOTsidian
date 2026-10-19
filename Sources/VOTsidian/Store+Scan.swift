import Foundation

// Leer la carpeta: no toca el estado de la app, así puede hacerse en segundo plano.
extension Store {
    /// Resultado de leer la carpeta: se calcula sin tocar el estado de la app, así puede hacerse en segundo plano.
    struct Scan: Sendable {
        var files: [NoteFile] = []
        var texts: [String: String] = [:]
        var metas: [String: [String: String]] = [:]
        var attachments: [String: String] = [:]
        var tags: [String: [String]] = [:]
        var snippets: [String: String] = [:]
        var modified: [String: Date] = [:]
        var aliases: [String: String] = [:]
        var cache: [String: CachedFile] = [:]
        var links: [String: [String]] = [:]
        var pending: [String] = []
        var unreadable: [String] = []
        var tasks: [TaskItem] = []
        /// `false` si no hay ningún archivo nuevo, borrado ni modificado respecto a la caché con que se empezó.
        var changed = true
    }

    nonisolated static func scan(root: URL, cache: [String: CachedFile]) -> Scan {
        var out = Scan()
        let skip = ["Plantillas", ".obsidian"]
        let base = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var reused = 0
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) {
            for case let u as URL in en {
                let rel = String(u.standardizedFileURL.path.dropFirst(base.count + 1))
                let comps = rel.split(separator: "/").map(String.init)
                let last = u.lastPathComponent
                if last.hasPrefix(".") {
                    if last.hasSuffix(".icloud") { out.pending.append((comps.dropLast().joined(separator: "/") + "/" + String(last.dropFirst().dropLast(7))).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
                    if u.hasDirectoryPath { en.skipDescendants() }
                    continue
                }
                if comps.contains(where: { skip.contains($0) }) || rel.hasSuffix(".excalidraw.md") { continue }
                guard u.pathExtension == "md" else {
                    if !u.hasDirectoryPath, !u.lastPathComponent.hasPrefix(".") { out.attachments[MD.fold(u.lastPathComponent)] = rel }
                    continue
                }
                let v = try? u.resourceValues(forKeys: Set(keys))
                let mtime = v?.contentModificationDate ?? .distantPast
                let size = v?.fileSize ?? 0
                let entry: CachedFile
                if let c = cache[rel], c.mtime == mtime, c.size == size {
                    entry = c   // sin cambios: no se vuelve a leer ni a analizar
                    reused += 1
                } else if let text = try? String(contentsOf: u, encoding: .utf8) {
                    entry = CachedFile(mtime: mtime, size: size, text: text, parsed: ParsedNote(
                        tasks: Parse.tasks(text, file: rel), meta: MD.frontmatter(text), tags: NoteInfo.tags(text),
                        snippet: NoteInfo.snippet(text), aliases: NoteInfo.aliases(text), links: Links.extract(text)))
                } else { out.unreadable.append(rel); continue }   // existe pero no es UTF-8 o no se puede leer
                out.cache[rel] = entry
                out.files.append(NoteFile(path: rel))
                out.texts[rel] = entry.text
                out.links[rel] = entry.parsed.links
                if entry.parsed.meta["tipo"] != "compra" { out.tasks += entry.parsed.tasks }   // la lista de la compra no son tareas
                out.metas[rel] = entry.parsed.meta
                out.tags[rel] = entry.parsed.tags
                out.snippets[rel] = entry.parsed.snippet
                out.modified[rel] = mtime
                for a in entry.parsed.aliases { out.aliases[MD.fold(a)] = rel }
            }
        }
        out.changed = reused != out.cache.count || out.cache.count != cache.count
        return out
    }
}
