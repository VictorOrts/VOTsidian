import Foundation

/// Autocompletado del editor: `[[` sugiere notas y `#` sugiere etiquetas. Lógica pura, con posiciones en caracteres.
enum EditorCompletion {
    enum Kind: Equatable { case link, tag }

    struct Match: Equatable {
        var kind: Kind
        var start: Int   // donde empieza `[[` o `#`
        var end: Int     // el cursor
        var query: String
    }

    struct Suggestion: Identifiable, Equatable {
        var id: String { insert + (create ?? "") }
        var title: String
        var subtitle = ""
        var insert: String
        var create: String? = nil   // nombre de la nota que hay que crear antes de insertar
    }

    /// ¿Está el cursor escribiendo un enlace (`[[abc`) o una etiqueta (`#abc`)?
    static func detect(_ text: String, caret: Int) -> Match? {
        let chars = Array(text)
        let c = min(max(caret, 0), chars.count)
        var lineStart = c
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        let seg = Array(chars[lineStart..<c])

        // enlace: último «[[» de la línea sin «]» ni «[» después
        if seg.count >= 2 {
            var i = seg.count - 2
            while i >= 0 {
                if seg[i] == "[", seg[i + 1] == "[" {
                    let q = Array(seg[(i + 2)...])
                    if !q.contains("]"), !q.contains("["), q.count <= 40 { return Match(kind: .link, start: lineStart + i, end: c, query: String(q)) }
                    break
                }
                i -= 1
            }
        }
        // etiqueta: «#» al principio o tras un espacio, seguido de al menos una letra
        if let h = seg.lastIndex(of: "#") {
            let q = Array(seg[(h + 1)...])
            let prevOK = h == 0 ? false : seg[h - 1] == " " || seg[h - 1] == "\t"
            let heading = h == 0 // «# Título»
            if prevOK, !heading, !q.isEmpty, q.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "/" || $0 == "-" }) {
                return Match(kind: .tag, start: lineStart + h, end: c, query: String(q))
            }
        }
        return nil
    }

    static func fold(_ s: String) -> String { MD.fold(s) }

    /// Notas que encajan con lo escrito: primero las que empiezan igual, luego las que lo contienen.
    static func noteSuggestions(query: String, notes: [(name: String, folder: String, aliases: [String])], current: String, recent: [String], limit: Int = 8) -> [Suggestion] {
        let q = fold(query)
        let pool = notes.filter { $0.name != current }
        var out: [Suggestion]
        if q.isEmpty {
            let order = recent.compactMap { r in pool.first { $0.name == r } }
            let rest = pool.filter { n in !order.contains { $0.name == n.name } }.sorted { fold($0.name) < fold($1.name) }
            out = (order + rest).prefix(limit).map { Suggestion(title: $0.name, subtitle: $0.folder, insert: "[[\($0.name)]]") }
        } else {
            func score(_ n: (name: String, folder: String, aliases: [String])) -> Int? {
                let f = fold(n.name)
                if f == q { return 0 }
                if f.hasPrefix(q) { return 1 }
                if n.aliases.contains(where: { fold($0).hasPrefix(q) }) { return 2 }
                if f.contains(q) { return 3 }
                if n.aliases.contains(where: { fold($0).contains(q) }) { return 4 }
                return nil
            }
            out = pool.compactMap { n in score(n).map { (n, $0) } }
                .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : fold($0.0.name) < fold($1.0.name) }
                .prefix(limit).map { Suggestion(title: $0.0.name, subtitle: $0.0.folder, insert: "[[\($0.0.name)]]") }
            let exact = pool.contains { fold($0.name) == q } || fold(current) == q
            if !exact, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let name = query.trimmingCharacters(in: .whitespaces)
                out.append(Suggestion(title: "Crear nota «\(name)»", subtitle: "se crea y se enlaza", insert: "[[\(name)]]", create: name))
            }
        }
        return out
    }

    static func tagSuggestions(query: String, tags: [(tag: String, count: Int)], limit: Int = 8) -> [Suggestion] {
        let q = fold(query)
        return tags.filter { fold($0.tag).hasPrefix(q) || fold($0.tag).contains(q) }
            .sorted { (fold($0.tag).hasPrefix(q) ? 0 : 1, -$0.count) < (fold($1.tag).hasPrefix(q) ? 0 : 1, -$1.count) }
            .prefix(limit).map { Suggestion(title: "#\($0.tag)", subtitle: "\($0.count) \($0.count == 1 ? "nota" : "notas")", insert: "#\($0.tag) ") }
    }
}
