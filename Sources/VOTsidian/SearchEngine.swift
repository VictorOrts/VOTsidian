import Foundation

/// Consulta de búsqueda: palabras sueltas, `#etiqueta`, `carpeta:x`, `tipo:x` y fechas en lenguaje natural («viernes», «25/11»).
struct SearchQuery: Equatable {
    var tokens: [String] = []        // palabras sin tildes ni mayúsculas
    var tags: [String] = []
    var folder: String?
    var type: String?
    var date: Date?

    var isEmpty: Bool { tokens.isEmpty && tags.isEmpty && folder == nil && type == nil && date == nil }

    static func parse(_ raw: String, today: Date = DayKey.today()) -> SearchQuery {
        var q = SearchQuery()
        var words: [String] = []
        for part in raw.split(separator: " ").map(String.init) {
            let f = MD.fold(part)
            if f.hasPrefix("#"), f.count > 1 { q.tags.append(String(f.dropFirst())); continue }
            if let r = f.range(of: ":"), r.lowerBound != f.startIndex {
                let key = String(f[..<r.lowerBound]), value = String(f[r.upperBound...])
                if !value.isEmpty {
                    if ["carpeta", "en", "folder"].contains(key) { q.folder = value; continue }
                    if ["tipo", "type"].contains(key) { q.type = value; continue }
                }
            }
            words.append(part)
        }
        // fecha: solo si la expresión de fecha ocupa la frase entera o va sola (evita convertir «el 5» de una frase normal en filtro)
        let joined = words.joined(separator: " ")
        let parsed = NaturalDate.extract(joined, today: today)
        if let d = parsed.date {
            q.date = d
            words = parsed.text.split(separator: " ").map(String.init)
        }
        q.tokens = words.map { MD.fold($0) }.filter { !$0.isEmpty }
        return q
    }
}

enum Synonyms {
    static let groups: [[String]] = [
        ["medico", "doctor", "consulta", "cita", "endocrino"], ["peso", "bascula", "kilos", "kg"],
        ["pinchazo", "inyeccion", "mounjaro", "tirzepatida"], ["casa", "hogar", "vivienda", "piso"],
        ["reforma", "obra", "obras"], ["compra", "comprar", "adquirir"], ["tarea", "pendiente"],
        ["habito", "rutina"], ["gato", "nala", "mascota"], ["dinero", "finanzas", "ahorro", "gasto", "pago"],
        ["analisis", "analitica", "pruebas", "resultados"], ["ropa", "armario", "moda", "vestuario"],
        ["revision", "repaso", "balance"], ["nutricion", "dieta", "comida", "alimentacion", "menu"],
        ["objetivo", "meta"], ["cumpleanos", "cumple", "aniversario"], ["documento", "papeles", "caducidad"],
    ]

    private static func stem(_ s: String) -> String {
        if s.hasSuffix("es"), s.count > 4 { return String(s.dropLast(2)) }
        if s.hasSuffix("s"), s.count > 3 { return String(s.dropLast()) }
        return s
    }

    /// La palabra y sus equivalentes («doctor» → médico, consulta, cita…).
    static func expand(_ token: String) -> [String] {
        let t = stem(token)
        for g in groups where g.contains(where: { stem($0) == t }) { return Array(Set(g + [token])) }
        return [token]
    }
}

enum SearchEngine {
    /// ¿El texto (ya sin tildes ni mayúsculas) contiene todas las palabras, o algún sinónimo de cada una?
    static func matches(_ folded: String, _ q: SearchQuery, useSynonyms: Bool = true) -> Bool {
        for t in q.tokens {
            let options = useSynonyms ? Synonyms.expand(t) : [t]
            if !options.contains(where: { folded.contains($0) }) { return false }
        }
        return true
    }

    /// Nota que encaja con etiquetas, carpeta y tipo del filtro.
    static func passesFilters(path: String, folder: String, type: String?, tags: [String], _ q: SearchQuery) -> Bool {
        if let f = q.folder, !MD.fold(folder).contains(f) { return false }
        if let t = q.type, MD.fold(type ?? "") != t { return false }
        for tag in q.tags where !tags.contains(where: { MD.fold($0).hasPrefix(tag) }) { return false }
        return true
    }

    /// La línea que mejor encaja (más palabras distintas) y sus palabras a resaltar.
    static func bestLine(in text: String, _ q: SearchQuery) -> String? {
        guard !q.tokens.isEmpty else { return nil }
        var best: (String, Int)?
        for raw in MD.lines(text) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("---") || l.hasPrefix("```") { continue }
            let f = MD.fold(l)
            // coincidencia literal vale 2 y por sinónimo 1
            let hits = q.tokens.reduce(0) { sum, t in f.contains(t) ? sum + 2 : (Synonyms.expand(t).contains { f.contains($0) } ? sum + 1 : sum) }
            if hits > 0, hits > (best?.1 ?? 0) { best = (l, hits) }
        }
        return best.map { String($0.0.prefix(140)) }
    }

    /// Texto con las palabras encontradas en negrita (ignora tildes y mayúsculas).
    static func highlight(_ line: String, _ q: SearchQuery) -> AttributedString {
        var out = AttributedString(line)
        let folded = String(line.map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first ?? $0 })
        let ns = folded as NSString
        var ranges: [NSRange] = []
        for t in q.tokens {
            for word in Synonyms.expand(t) {
                var from = 0
                while from < ns.length {
                    let r = ns.range(of: word, options: [], range: NSRange(location: from, length: ns.length - from))
                    if r.location == NSNotFound { break }
                    ranges.append(r); from = r.location + max(r.length, 1)
                }
            }
        }
        for r in ranges {
            guard let sr = Range(r, in: line), let lo = AttributedString.Index(sr.lowerBound, within: out), let hi = AttributedString.Index(sr.upperBound, within: out) else { continue }
            out[lo..<hi].font = .body.bold()
            out[lo..<hi].foregroundColor = .accentColor
        }
        return out
    }
}
