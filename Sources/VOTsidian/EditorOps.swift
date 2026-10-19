import Foundation

/// Operaciones de edición sobre texto con posiciones en caracteres (puras, para poder probarlas).
enum EditorOps {
    struct Result: Equatable {
        var text: String
        var caret: Int
    }

    private static func idx(_ s: String, _ offset: Int) -> String.Index { s.index(s.startIndex, offsetBy: min(max(offset, 0), s.count)) }

    /// Rodea la selección con `pre` y `post`. Sin selección inserta el par y deja el cursor en medio.
    static func wrap(_ text: String, selection: Range<Int>?, pre: String, post: String) -> Result {
        guard let sel = selection else { return Result(text: text + pre + post, caret: text.count + pre.count) }
        let a = idx(text, sel.lowerBound), b = idx(text, sel.upperBound)
        let chosen = String(text[a..<b])
        var out = text
        out.replaceSubrange(a..<b, with: pre + chosen + post)
        let caret = sel.lowerBound + pre.count + chosen.count + (chosen.isEmpty ? 0 : post.count)
        return Result(text: out, caret: caret)
    }

    /// Sustituye la selección (o inserta en el cursor) y deja el cursor detrás.
    static func insert(_ text: String, selection: Range<Int>?, _ new: String) -> Result {
        guard let sel = selection else { return Result(text: text + new, caret: text.count + new.count) }
        var out = text
        out.replaceSubrange(idx(text, sel.lowerBound)..<idx(text, sel.upperBound), with: new)
        return Result(text: out, caret: sel.lowerBound + new.count)
    }

    /// Pone o quita un prefijo (`- `, `## `…) al principio de la línea del cursor.
    static func linePrefix(_ text: String, caret: Int?, prefix: String) -> Result {
        guard let c = caret else {
            let sep = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
            return Result(text: text + sep + prefix, caret: text.count + sep.count + prefix.count)
        }
        let chars = Array(text)
        var start = min(c, chars.count)
        while start > 0, chars[start - 1] != "\n" { start -= 1 }
        let lineHasPrefix = String(chars[start...]).hasPrefix(prefix)
        var out = chars
        if lineHasPrefix {
            out.removeSubrange(start..<(start + prefix.count))
            return Result(text: String(out), caret: max(c - prefix.count, start))
        }
        out.insert(contentsOf: Array(prefix), at: start)
        return Result(text: String(out), caret: c + prefix.count)
    }

    /// Sustituye lo escrito (`[[abc` o `#abc`) por la sugerencia elegida; si ya había `]]` detrás, los reutiliza.
    static func accept(_ text: String, match m: EditorCompletion.Match, insert new: String) -> Result {
        var end = m.end
        if m.kind == .link {
            let after = String(Array(text)[min(m.end, text.count)...])
            if after.hasPrefix("]]") { end += 2 }
        }
        var out = text
        out.replaceSubrange(idx(text, m.start)..<idx(text, end), with: new)
        return Result(text: out, caret: m.start + new.count)
    }
}

/// Qué pestañas quedan y cuál está activa al abrir, cerrar o cambiar (puro, para poder probarlo).
enum TabLogic {
    /// Abre `path`: si ya está, no cambia nada; en pestaña nueva se añade al final; si no, sustituye la activa.
    static func open(_ tabs: [String], active: String?, path: String, newTab: Bool) -> [String] {
        var t = tabs
        if t.contains(path) { return t }
        if newTab || t.isEmpty { t.append(path) }
        else if let a = active, let i = t.firstIndex(of: a) { t[i] = path }
        else { t.append(path) }
        return t
    }

    /// Cierra una pestaña. Devuelve las que quedan y la que pasa a estar activa.
    static func close(_ tabs: [String], active: String?, path: String) -> (tabs: [String], active: String?) {
        guard let i = tabs.firstIndex(of: path) else { return (tabs, active) }
        var t = tabs
        t.remove(at: i)
        if path != active { return (t, active) }
        return (t, t.isEmpty ? nil : t[min(i, t.count - 1)])
    }

    /// Pestaña siguiente (+1) o anterior (-1), dando la vuelta.
    static func cycle(_ tabs: [String], active: String?, by delta: Int) -> String? {
        guard tabs.count > 1, let a = active, let i = tabs.firstIndex(of: a) else { return active }
        return tabs[(i + delta + tabs.count) % tabs.count]
    }
}
