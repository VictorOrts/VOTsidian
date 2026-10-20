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

    /// Analiza el texto de una nota. No toca el estado de la app, así puede correr en varios hilos a la vez.
    nonisolated static func makeEntry(text: String, rel: String, mtime: Date, size: Int) -> CachedFile {
        CachedFile(mtime: mtime, size: size, text: text, parsed: ParsedNote(
            tasks: Parse.tasks(text, file: rel), meta: MD.frontmatter(text), tags: NoteInfo.tags(text),
            snippet: NoteInfo.snippet(text), aliases: NoteInfo.aliases(text), links: Links.extract(text)))
    }

    nonisolated static func ingest(_ entry: CachedFile, rel: String, into out: inout Scan) {
        out.cache[rel] = entry
        out.files.append(NoteFile(path: rel))
        out.texts[rel] = entry.text
        out.links[rel] = entry.parsed.links
        if entry.parsed.meta["tipo"] != "compra" { out.tasks += entry.parsed.tasks }   // la lista de la compra no son tareas
        out.metas[rel] = entry.parsed.meta
        out.tags[rel] = entry.parsed.tags
        out.snippets[rel] = entry.parsed.snippet
        out.modified[rel] = entry.mtime
        for a in entry.parsed.aliases { out.aliases[MD.fold(a)] = rel }
    }

    /// Reparte las notas nuevas o modificadas entre los núcleos. Cada hilo escribe solo en su hueco.
    private final class Slots: @unchecked Sendable {
        let n: Int
        let ptr: UnsafeMutablePointer<CachedFile?>
        init(_ n: Int) { self.n = n; ptr = .allocate(capacity: max(n, 1)); ptr.initialize(repeating: nil, count: max(n, 1)) }
        deinit { ptr.deinitialize(count: max(n, 1)); ptr.deallocate() }
        func set(_ i: Int, _ v: CachedFile?) { ptr[i] = v }
        func get(_ i: Int) -> CachedFile? { ptr[i] }
    }

    nonisolated static func scan(root: URL, cache: [String: CachedFile]) -> Scan {
        var out = Scan()
        let skip = ["Plantillas", ".obsidian"]
        let base = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        // Primera fase (secuencial, barata): recorrer la carpeta y separar lo que está en caché de lo que hay que leer.
        struct Item: Sendable { var rel: String; var url: URL; var mtime: Date; var size: Int; var cached: CachedFile? }
        var items: [Item] = []
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
                let hit = cache[rel].flatMap { $0.mtime == mtime && $0.size == size ? $0 : nil }   // sin cambios: no se vuelve a leer ni a analizar
                items.append(Item(rel: rel, url: u, mtime: mtime, size: size, cached: hit))
            }
        }
        // Segunda fase: leer y analizar en paralelo lo que cambió.
        let frozen = items
        let misses = frozen.indices.filter { frozen[$0].cached == nil }
        let slots = Slots(misses.count)
        let work: @Sendable (Int) -> Void = { k in
            let it = frozen[misses[k]]
            if let text = try? String(contentsOf: it.url, encoding: .utf8) {
                slots.set(k, makeEntry(text: text, rel: it.rel, mtime: it.mtime, size: it.size))
            }
        }
        if misses.count > 16 { DispatchQueue.concurrentPerform(iterations: misses.count, execute: work) }
        else { for k in 0..<misses.count { work(k) } }
        var fresh: [Int: CachedFile] = [:]
        for (k, i) in misses.enumerated() { if let e = slots.get(k) { fresh[i] = e } }
        // Tercera fase: juntar en el orden original.
        var reused = 0
        for (i, it) in items.enumerated() {
            if let c = it.cached { reused += 1; ingest(c, rel: it.rel, into: &out) }
            else if let e = fresh[i] { ingest(e, rel: it.rel, into: &out) }
            else { out.unreadable.append(it.rel) }   // existe pero no es UTF-8 o no se puede leer
        }
        out.changed = reused != out.cache.count || out.cache.count != cache.count
        return out
    }
}
