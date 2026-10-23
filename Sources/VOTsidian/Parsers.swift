import Foundation

// MARK: - Parsers

enum Parse {
    static func weight(_ text: String) -> WeightData {
        let fm = MD.frontmatter(text)
        var d = WeightData()
        d.initialKg = fm["peso_inicial_kg"].flatMap(MD.number) ?? 0
        d.goalKg = fm["objetivo_peso_kg"].flatMap(MD.number) ?? 0
        d.start = fm["fecha_inicio"].flatMap(DayKey.dmyDate)
        for (i, c) in MD.tableRows(MD.lines(text)) where c.count >= 2 {
            guard let date = DayKey.dmyDate(c[0]), let kg = MD.number(c[1]) else { continue }
            d.records.append(WeightRecord(date: date, kg: kg, note: c.count > 2 ? c[2] : "", line: i))
        }
        d.records.sort { $0.date < $1.date }
        // Sin `peso_inicial_kg`, el punto de partida es el primer pesaje.
        if d.initialKg == 0, let first = d.records.first { d.initialKg = first.kg }
        return d
    }

    static func mascota(_ text: String) -> MascotaData {
        let fm = MD.frontmatter(text)
        var d = MascotaData()
        d.name = fm["nombre"].flatMap { $0.isEmpty ? nil : $0 } ?? d.name
        d.birth = fm["nacimiento"].flatMap(DayKey.dmyDate)
        d.food = fm["comida"] ?? ""
        for (line, c) in MD.tableRows(MD.lines(text)) where c.count >= 2 {
            guard let date = DayKey.date(c[0]) else { continue }
            func at(_ i: Int) -> String { i < c.count ? c[i] : "" }
            d.visits.append(MascotaVisit(date: date, tipo: at(1), detalle: at(2), proxima: DayKey.date(at(3)), coste: at(4), line: line))
        }
        d.visits.sort { $0.date < $1.date }
        return d
    }

    static func tasks(_ text: String, file: String) -> [TaskItem] {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var out: [TaskItem] = []
        for (i, line) in lines.enumerated() where !fence.contains(i) {
            guard let m = line.firstMatch(of: /^\s*(?:[-*+]|\d+\.)\s+\[([ xX])\]\s+(.*)$/) else { continue }
            let body = String(m.2)
            func date(_ emoji: String) -> Date? {
                guard let r = body.range(of: "\(emoji)\\s*\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) else { return nil }
                return DayKey.date(String(body[r].suffix(10)))
            }
            var clean = body
            let priority = body.contains("⏫") ? 3 : body.contains("🔼") ? 2 : body.contains("🔽") ? 1 : 0
            var recurrence: String?
            if let r = body.range(of: Recurrence.pattern, options: .regularExpression) {
                recurrence = String(body[r]).replacingOccurrences(of: "🔁", with: "").replacingOccurrences(of: "every", with: "").trimmingCharacters(in: .whitespaces)
            }
            for pattern in [#"[📅⏳🛫➕✅]\s*\d{4}-\d{2}-\d{2}"#, #"\[completion::[^\]]*\]"#, Recurrence.pattern, "⏫", "🔼", "🔽"] {
                clean = clean.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            clean = clean.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }
            var completed: Date?
            if let r = body.range(of: #"\[completion::\s*\d{4}-\d{2}-\d{2}\]"#, options: .regularExpression) {
                completed = DayKey.date(String(body[r].dropLast().suffix(10)))
            } else if let r = body.range(of: #"✅\s*\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
                completed = DayKey.date(String(body[r].suffix(10)))
            }
            out.append(TaskItem(file: file, line: i, raw: line, text: clean, due: date("📅"), scheduled: date("⏳"),
                                done: m.1 != " ", completed: completed, recurrence: recurrence, priority: priority))
        }
        return out
    }

    static func week(_ text: String, key: String) -> WeekReview {
        var r = WeekReview(key: key, exists: true)
        let lines = MD.lines(text)
        if let h = lines.firstIndex(where: { MD.fold($0).hasPrefix("| habito") }) {
            let critCol = MD.cells(lines[h]).firstIndex { MD.fold($0) == "criterio" }
            var j = h + 2
            while j < lines.count, MD.isTable(lines[j]) {
                let c = MD.cells(lines[j])
                let days = (1...7).map { $0 < c.count && c[$0].contains("✅") }
                let crit = critCol.flatMap { $0 < c.count ? c[$0] : nil } ?? ""
                if !c[0].isEmpty { r.habits.append(HabitWeek(name: c[0], days: days, criterion: crit)) }
                j += 1
            }
        }
        func value(after marker: String) -> String {
            guard let l = lines.first(where: { $0.contains(marker) }), let r = l.range(of: marker) else { return "" }
            return String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        r.logros = value(after: "**Logros:**")
        r.noSalio = value(after: "**Lo que no salió:**")
        if let o = lines.firstIndex(where: { $0.contains("**Tres objetivos:**") }) {
            var n = 0
            var j = o + 1
            while j < lines.count, n < 3 {
                if let m = lines[j].firstMatch(of: /^\s*\d\.\s?(.*)$/) { r.objetivos[n] = String(m.1).trimmingCharacters(in: .whitespaces); n += 1 }
                else if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { break }
                j += 1
            }
        }
        if let f = lines.firstIndex(where: { $0.contains("**Fechas importantes:**") }) {
            var j = f + 1
            while j < lines.count, lines[j].hasPrefix("- ") {
                r.fechas.append(String(lines[j].dropFirst(2)))
                j += 1
            }
        }
        return r
    }

    static func plan(_ text: String) -> PlanData {
        let fm = MD.frontmatter(text)
        var p = PlanData()
        p.kcal = fm["kcal_objetivo"].flatMap(MD.number) ?? 0
        p.protein = fm["proteina_g"].flatMap(MD.number) ?? 0
        p.carbs = fm["carbohidratos_g"].flatMap(MD.number) ?? 0
        p.fat = fm["grasas_g"].flatMap(MD.number) ?? 0
        let lines = MD.lines(text)
        if let r = MD.section(lines, containing: "Reparto del dia") {
            let rows = r.filter { MD.isTable(lines[$0]) }.map { ($0, MD.cells(lines[$0]).map { $0.replacingOccurrences(of: "**", with: "") }) }
                .filter { !($0.1.first ?? "").hasPrefix(":") && !($0.1.first ?? "").hasPrefix("-") }
            p.meals = rows.map(\.1)
            p.mealLines = rows.map(\.0)
        }
        return p
    }

    static func milestones(_ text: String) -> [Milestone] {
        let lines = MD.lines(text)
        guard let r = MD.section(lines, containing: "Hitos") else { return [] }
        return r.filter { MD.isTable(lines[$0]) }.compactMap { i in
            let c = MD.cells(lines[i])
            guard c.count >= 3, let kg = MD.number(c[1]), !c[0].hasPrefix(":"), !c[0].hasPrefix("-") else { return nil }
            return Milestone(name: c[0], kg: kg, markedDone: c[2].contains("✅"), line: i)
        }
    }
}
