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
    /// Cómo se ve la base: tabla, calendario por una propiedad de fecha o tablero por una propiedad de pocos valores.
    enum Layout: String, Codable, CaseIterable { case tabla = "Tabla", calendario = "Calendario", tablero = "Tablero" }

    var name: String
    var text = ""
    var sortKey = "Nota"
    var ascending = true
    var conditions: [BaseCondition] = []
    var layout: Layout = .tabla
    /// Propiedad de fecha del calendario y de agrupación del tablero; vacías, la app propone una.
    var dateKey = ""
    var groupKey = ""
    var id: String { name }

    init(name: String) { self.name = name }

    /// Las vistas guardadas antes no tenían disposición ni propiedades: se abren como tabla.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sortKey = try c.decodeIfPresent(String.self, forKey: .sortKey) ?? "Nota"
        ascending = try c.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
        conditions = try c.decodeIfPresent([BaseCondition].self, forKey: .conditions) ?? []
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .tabla
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        groupKey = try c.decodeIfPresent(String.self, forKey: .groupKey) ?? ""
    }
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

// MARK: Calendario y tablero

extension BaseQuery {
    /// Fecha de una propiedad: `2026-10-24` o `24/10/2026`.
    static func date(_ value: String) -> Date? { DayKey.date(value) ?? DayKey.dmyDate(value) }

    /// La fecha escrita como estaba la anterior (si era `DD/MM/AAAA`, sigue así); si no había, en `AAAA-MM-DD`.
    static func format(_ date: Date, like previous: String?) -> String {
        if let previous, DayKey.dmyDate(previous) != nil { return DayKey.dmy(date) }
        return DayKey.string(date)
    }

    /// Propiedades que sirven para el calendario: las que tienen fecha en al menos la mitad de las notas donde aparecen.
    /// Las más usadas primero.
    static func dateKeys(paths: [String], meta: [String: [String: String]]) -> [String] {
        var filled: [String: Int] = [:], dated: [String: Int] = [:]
        for p in paths {
            for (k, v) in meta[p] ?? [:] where !v.isEmpty && !["tipo", "tags", "aliases"].contains(k) {
                filled[k, default: 0] += 1
                if date(v) != nil { dated[k, default: 0] += 1 }
            }
        }
        return dated.filter { $0.value * 2 >= filled[$0.key, default: 1] }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    }

    /// Propiedades que sirven para el tablero: de 2 a 12 valores distintos, que no son fechas ni números sueltos.
    static func groupKeys(paths: [String], meta: [String: [String: String]]) -> [String] {
        var values: [String: Set<String>] = [:], count: [String: Int] = [:]
        for p in paths {
            for (k, v) in meta[p] ?? [:] where !v.isEmpty && !["tipo", "tags", "aliases"].contains(k) && date(v) == nil && Double(v.replacingOccurrences(of: ",", with: ".")) == nil {
                values[k, default: []].insert(MD.fold(v))
                count[k, default: 0] += 1
            }
        }
        // Las de estado primero, que es para lo que más se usa un tablero.
        func rank(_ k: String) -> Int { ["estado", "status", "fase", "prioridad"].firstIndex(of: MD.fold(k)) ?? 9 }
        return values.filter { (2...12).contains($0.value.count) }.keys.sorted { (rank($0), -count[$0, default: 0], $0) < (rank($1), -count[$1, default: 0], $1) }
    }

    /// Notas por día (`AAAA-MM-DD`) según `key`, y las que no tienen fecha.
    static func byDay(paths: [String], meta: [String: [String: String]], key: String) -> (days: [String: [String]], undated: [String]) {
        var days: [String: [String]] = [:], undated: [String] = []
        for p in paths {
            if let d = meta[p]?[key].flatMap(date) { days[DayKey.string(d), default: []].append(p) } else { undated.append(p) }
        }
        return (days, undated)
    }

    /// Columnas del tablero: cada valor de `key` (con la forma más usada) y, al final, «Sin valor» si hay notas sin él.
    /// Los estados conocidos van en su orden natural (idea → pendiente → en curso → hecho); el resto, por orden alfabético.
    static func columns(paths: [String], meta: [String: [String: String]], key: String) -> [(value: String, paths: [String])] {
        var groups: [String: [String]] = [:], spelling: [String: [String: Int]] = [:]
        var blank: [String] = []
        for p in paths {
            let v = (meta[p]?[key] ?? "").trimmingCharacters(in: .whitespaces)
            if v.isEmpty { blank.append(p); continue }
            groups[MD.fold(v), default: []].append(p)
            spelling[MD.fold(v), default: [:]][v, default: 0] += 1
        }
        let natural = ["idea", "pendiente", "planeando", "por hacer", "activo", "en curso", "en marcha", "esperando", "pausado", "reservado", "hecho", "terminado", "completado", "cancelado", "alta", "media", "baja"]
        func rank(_ k: String) -> Int { natural.firstIndex(of: k) ?? natural.count }
        var out = groups.keys.sorted { (rank($0), $0) < (rank($1), $1) }.map { k in
            (value: spelling[k]?.max { $0.value < $1.value }?.key ?? k, paths: groups[k] ?? [])
        }
        if !blank.isEmpty { out.append((value: "", paths: blank)) }
        return out
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
