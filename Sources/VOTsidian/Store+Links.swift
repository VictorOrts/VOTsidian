import Foundation

// Etiquetas, fijadas y menciones sin enlazar.
extension Store {
    /// Etiquetas de todo el vault con el número de notas que las usan.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: (String, Int)] = [:]
        for tags in noteTags.values { for t in tags { counts[MD.fold(t), default: (t, 0)].1 += 1 } }
        return counts.values.map { (tag: $0.0, count: $0.1) }.sorted { ($1.count, $0.tag) < ($0.count, $1.tag) }
    }

    func notes(withTag tag: String) -> Set<String> {
        Set(noteTags.filter { $0.value.contains { MD.fold($0) == MD.fold(tag) } }.map(\.key))
    }

    func togglePin(_ path: String) {
        if let i = pinned.firstIndex(of: path) { pinned.remove(at: i) } else { pinned.insert(path, at: 0) }
    }

    /// Notas que nombran a esta en texto plano pero no la enlazan.
    func unlinkedMentions(of path: String) -> [NoteFile] {
        guard let me = notes.first(where: { $0.path == path }), me.name.count >= 4 else { return [] }
        let key = MD.fold(me.name)
        let linked = Set(backLinks[path] ?? [])
        return notes.filter { n in
            guard n.path != path, !linked.contains(n.path) else { return false }
            let t = noteTexts[n.path] ?? read(n.path)
            let folded: String
            if let f = foldedTexts[n.path] { folded = f } else { folded = MD.fold(t); foldedTexts[n.path] = folded }   // se pliega una vez por recarga, no por consulta
            return folded.contains(key) && Edit.linkMention(t, name: me.name) != nil
        }
    }

    func linkMention(in path: String, to name: String) {
        edit(path) { Edit.linkMention($0, name: name) }
    }
}
