import Foundation

/// Consulta guardada sobre una base: filtros por propiedad, texto y orden.
struct BaseCondition: Codable, Equatable, Identifiable {
    enum Op: String, Codable, CaseIterable {
        case contains = "contiene", equals = "es", notEquals = "no es", empty = "vacía", filled = "con valor"
        var needsValue: Bool { self == .contains || self == .equals || self == .notEquals }
    }
    var id = UUID()
    var key: String
    var op: Op = .contains
    var value = ""
}

struct BaseView: Codable, Equatable, Identifiable {
    var name: String
    var text = ""
    var sortKey = "Nota"
    var ascending = true
    var conditions: [BaseCondition] = []
    var id: String { name }
}

enum BaseQuery {
    static let nameKey = "Nota", modifiedKey = "Modificada"

    static func matches(_ c: BaseCondition, meta: [String: String]) -> Bool {
        let v = MD.fold(meta[c.key] ?? "")
        let target = MD.fold(c.value)
        switch c.op {
        case .contains: return target.isEmpty || v.contains(target)
        case .equals: return v == target
        case .notEquals: return v != target
        case .empty: return v.isEmpty
        case .filled: return !v.isEmpty
        }
    }

    /// Filtra y ordena las notas de una base. Los números se comparan como números, el resto sin acentos ni mayúsculas.
    static func apply(_ view: BaseView, paths: [String], meta: [String: [String: String]], modified: [String: Date]) -> [String] {
        func title(_ p: String) -> String { ((p as NSString).lastPathComponent as NSString).deletingPathExtension }
        let q = MD.fold(view.text)
        let kept = paths.filter { p in
            (q.isEmpty || MD.fold(title(p)).contains(q)) && view.conditions.allSatisfy { matches($0, meta: meta[p] ?? [:]) }
        }
        let key = view.sortKey
        func order(_ list: [String], _ less: (String, String) -> Bool) -> [String] {
            let sorted = list.sorted(by: less)
            return view.ascending ? sorted : sorted.reversed()
        }
        switch key {
        case nameKey: return order(kept) { MD.fold(title($0)) < MD.fold(title($1)) }
        case modifiedKey: return order(kept) { (modified[$0] ?? .distantPast) < (modified[$1] ?? .distantPast) }
        default:
            // Las notas sin valor van siempre al final, también al invertir el orden.
            func value(_ p: String) -> String { meta[p]?[key] ?? "" }
            let filled = kept.filter { !value($0).isEmpty }, blank = kept.filter { value($0).isEmpty }
            return order(filled) { a, b in
                if let n = MD.number(value(a)), let m = MD.number(value(b)) { return n < m }
                return MD.fold(value(a)) < MD.fold(value(b))
            } + blank.sorted { MD.fold(title($0)) < MD.fold(title($1)) }
        }
    }
}

enum BaseViewStore {
    private static let key = "basesViews"

    static func load(_ type: String) -> [BaseView] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: [BaseView]].self, from: data) else { return [] }
        return all[type] ?? []
    }

    static func save(_ views: [BaseView], for type: String) {
        var all: [String: [BaseView]] = [:]
        if let data = UserDefaults.standard.data(forKey: key), let old = try? JSONDecoder().decode([String: [BaseView]].self, from: data) { all = old }
        all[type] = views
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}
