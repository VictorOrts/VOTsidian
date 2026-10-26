import Foundation

// MARK: - Tablas con nombre (para pantallas genéricas)

struct NamedTable: Identifiable, Equatable {
    var title: String
    var headerLine: Int
    var header: [String]
    var rows: [TableRow]
    var id: Int { headerLine }
    var lastLine: Int { rows.last?.line ?? headerLine + 1 }

    func col(_ name: String) -> Int? { header.firstIndex { MD.fold($0).contains(MD.fold(name)) } }
    func value(_ row: TableRow, _ name: String) -> String { col(name).flatMap { $0 < row.cells.count ? row.cells[$0] : nil } ?? "" }
}

extension Parse {
    /// Todas las tablas de una nota, con el título del encabezado que las precede.
    static func tables(_ text: String) -> [NamedTable] {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var out: [NamedTable] = []
        var title = ""
        var i = 0
        while i < lines.count {
            let l = lines[i]
            if fence.contains(i) { i += 1; continue }
            if l.hasPrefix("#") {
                title = l.drop(while: { $0 == "#" || $0 == " " }).drop(while: { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
                i += 1; continue
            }
            if MD.isTable(l) {
                let headerLine = i
                let header = MD.cells(l)
                var rows: [TableRow] = []
                i += 1
                while i < lines.count, MD.isTable(lines[i]), !fence.contains(i) {
                    let c = MD.cells(lines[i])
                    let isSeparator = c.allSatisfy { $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }
                    if !isSeparator { rows.append(TableRow(line: i, cells: c)) }
                    i += 1
                }
                out.append(NamedTable(title: title, headerLine: headerLine, header: header, rows: rows))
                continue
            }
            i += 1
        }
        return out
    }
}

// MARK: - Personas

struct Person: Identifiable, Equatable {
    var name: String
    var relation: String
    var birthday: String        // "1990-10-17" o "10-17"
    var lastContact: Date?
    var line: Int
    var id: Int { line }

    /// Año de nacimiento, si la fecha lo trae.
    var birthYear: Int? {
        let p = birthday.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? p[0] : nil
    }

    /// El cumpleaños en el año `year`, o `nil` si la fecha no existe («02-30»). Quien nació un 29 de febrero lo celebra el 28 los
    /// años que no son bisiestos (el calendario lo pasaba al 1 de marzo sin avisar).
    func birthday(in year: Int) -> Date? {
        let p = birthday.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 || p.count == 3 else { return nil }
        let (month, day) = p.count == 3 ? (p[1], p[2]) : (p[0], p[1])
        return DayKey.make(year, month, day) ?? (month == 2 && day == 29 ? DayKey.make(year, 2, 28) : nil)
    }

    /// Próxima fecha de cumpleaños desde `today`.
    func nextBirthday(from today: Date = DayKey.today()) -> (date: Date, age: Int?)? {
        let cal = DayKey.calendar()
        let year = cal.component(.year, from: today)
        guard var d = birthday(in: year) else { return nil }
        if d < today { d = birthday(in: year + 1) ?? d }
        return (d, birthYear.map { cal.component(.year, from: d) - $0 })
    }
}

extension Parse {
    static func people(_ text: String) -> (table: NamedTable?, people: [Person]) {
        guard let t = tables(text).first(where: { $0.col("persona") != nil }) else { return (nil, []) }
        let people = t.rows.compactMap { r -> Person? in
            let n = t.value(r, "persona")
            guard !n.isEmpty else { return nil }
            return Person(name: n, relation: t.value(r, "relaci"), birthday: t.value(r, "cumple"), lastContact: DayKey.date(t.value(r, "ultima vez")), line: r.line)
        }
        return (t, people)
    }
}

// MARK: - Análisis por dosis

struct DosePeriod: Identifiable, Equatable {
    var mg: Double
    var start: Date
    var end: Date
    var count: Int
    var startKg: Double?
    var endKg: Double?
    var id: Date { start }

    var lostKg: Double? { zip(startKg, endKg).map { $0 - $1 } }
    var months: Double { max(Double(DayKey.days(from: start, to: end)) / 30.4, 0) }
    var kgPerMonth: Double? { months >= 0.5 ? lostKg.map { $0 / months } : nil }
}

private func zip(_ a: Double?, _ b: Double?) -> (Double, Double)? { a.flatMap { x in b.map { (x, $0) } } }

extension MedicacionData {
    /// Tramos consecutivos con la misma dosis y el peso al inicio y al final de cada uno.
    func periods(weights: [WeightRecord]) -> [DosePeriod] {
        var groups: [[Dose]] = []
        for d in doses {
            guard let mg = d.mg else { continue }
            if let last = groups.last?.last, last.mg == mg { groups[groups.count - 1].append(d) } else { groups.append([d]) }
        }
        func weight(at date: Date) -> Double? {
            weights.last(where: { $0.date <= date })?.kg ?? weights.first?.kg
        }
        let lastWeightDate = weights.last?.date
        return groups.enumerated().compactMap { i, g in
            guard let first = g.first, let lastDose = g.last, let mg = first.mg else { return nil }
            let start = first.date
            let next = i + 1 < groups.count ? groups[i + 1].first?.date : nil
            let end = next ?? max(lastDose.date, lastWeightDate ?? lastDose.date)
            return DosePeriod(mg: mg, start: start, end: end, count: g.count, startKg: weight(at: start), endKg: weight(at: end))
        }
    }
}


// MARK: - Listas de una sección

struct ListItem: Identifiable, Equatable {
    var line: Int
    var raw: String
    var text: String
    var id: Int { line }
}

extension Parse {
    /// Elementos `- texto` (no tareas) de una sección.
    static func listItems(_ text: String, section: String) -> [ListItem] {
        let lines = MD.lines(text)
        guard let r = MD.section(lines, containing: section) else { return [] }
        return r.compactMap { i in
            let l = lines[i]
            guard l.hasPrefix("- "), !l.hasPrefix("- [") else { return nil }
            let t = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : ListItem(line: i, raw: l, text: t)
        }
    }
}


// MARK: - Tareas que se repiten

enum Recurrence {
    /// Separa «month on the 31st» en la regla base («month») y el día fijo del mes (31; -1 = el último).
    /// `🔁 every …` hasta el siguiente campo de la tarea (fechas, prioridad, `[completion::]`, y las marcas propias ⏰ ⏱ 🔕).
    static let pattern = #"🔁\s*every\s+[^📅⏳🛫➕✅⏫🔼🔽⏰⏱🔕\[]+"#

    /// El trozo `🔁 every …` de una línea. Con `NSString`, como `TaskDuration.find`: la búsqueda de `String` no paraba ante un
    /// «⏱️» con selector de variación y la regla se quedaba con la duración («week ⏱️ 30m»).
    static func find(in line: String) -> String? {
        let ns = line as NSString
        let r = ns.range(of: pattern, options: .regularExpression)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }

    /// «every week when done» (Obsidian Tasks): la siguiente se cuenta desde el día en que se completa, no desde la fecha.
    static func isWhenDone(_ rule: String) -> Bool { rule.lowercased().contains("when done") }

    static func split(_ rule: String) -> (base: String, day: Int?) {
        let r = rule.lowercased().replacingOccurrences(of: "when done", with: "")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard let on = r.range(of: " on the ") else { return (r, nil) }
        let spec = r[on.upperBound...].trimmingCharacters(in: .whitespaces)
        let day = spec.hasPrefix("last") ? -1 : spec.firstMatch(of: /^([0-9]{1,2})/).flatMap { Int($0.1) }.flatMap { (1...31).contains($0) ? $0 : nil }
        return (String(r[..<on.lowerBound]).trimmingCharacters(in: .whitespaces), day)
    }

    static func isWeekday(_ rule: String) -> Bool { split(rule).base == "weekday" }

    /// Intervalo de una regla como "week", "2 weeks", "month", "3 days", "year". «weekday» no tiene intervalo fijo: nil.
    static func component(_ rule: String) -> (Calendar.Component, Int)? {
        let base = split(rule).base
        guard base != "weekday" else { return nil }
        let parts = base.split(separator: " ").map(String.init)
        guard let unit = parts.last else { return nil }
        let n = parts.count > 1 ? Int(parts[0]) ?? 1 : 1
        if unit.hasPrefix("day") { return (.day, n) }
        if unit.hasPrefix("week") { return (.weekOfYear, n) }
        if unit.hasPrefix("month") { return (.month, n) }
        if unit.hasPrefix("year") { return (.year, n) }
        return nil
    }

    /// Siguiente fecha futura de la serie a partir de `due` (o de hoy si no tenía).
    /// Se cuenta siempre desde `due` (n, 2n, 3n…), no saltando de fecha en fecha: así el 31 de enero + 3 meses es el 30 de abril, no el 28.
    static func next(after due: Date?, rule: String, today: Date = DayKey.today()) -> Date? {
        let cal = DayKey.calendar()
        let anchor = isWhenDone(rule) ? today : due ?? today
        if isWeekday(rule) {
            var d = anchor
            repeat { d = DayKey.adding(days: 1, to: d) } while d < today || cal.isDateInWeekend(d)
            return d
        }
        guard let (unit, n) = component(rule), n > 0 else { return nil }
        let fixedDay = unit == .month ? split(rule).day : nil
        for k in 1...100_000 {
            guard var d = cal.date(byAdding: unit, value: n * k, to: anchor) else { return nil }
            if let fixedDay, let days = cal.range(of: .day, in: .month, for: d)?.count {
                d = cal.date(bySetting: .day, value: fixedDay < 0 ? days : min(fixedDay, days), of: cal.dateInterval(of: .month, for: d)!.start) ?? d
            }
            if d >= today { return d }
        }
        return nil
    }

    /// Para una serie mensual que vence el 29, 30 o 31 fija ese día («month on the 31st»): si no, tras febrero se quedaría en el 28.
    static func pinningDay(_ rule: String, due: Date?) -> String {
        guard let due, component(rule)?.0 == .month, split(rule).day == nil else { return rule }
        let day = DayKey.calendar().component(.day, from: due)
        guard day >= 29 else { return rule }
        return "\(rule) on the \(day)\(day == 31 ? "st" : "th")"
    }

    static func describe(_ rule: String) -> String {
        if isWeekday(rule) { return "cada día laborable" }
        guard let (unit, n) = component(rule) else { return rule }
        let names: [Calendar.Component: (String, String)] = [.day: ("día", "días"), .weekOfYear: ("semana", "semanas"), .month: ("mes", "meses"), .year: ("año", "años")]
        let (one, many) = names[unit] ?? ("", "")
        var out = n == 1 ? "cada \(one)" : "cada \(n) \(many)"
        if unit == .month, let d = split(rule).day { out += d < 0 ? ", el último día" : ", el día \(d)" }
        return out
    }
}
