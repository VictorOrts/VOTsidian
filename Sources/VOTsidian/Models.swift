import Foundation

// MARK: - Peso

struct WeightRecord: Identifiable, Equatable {
    var date: Date
    var kg: Double
    var note: String
    var line = -1
    var id: Date { date }
}

struct WeightData: Equatable {
    var initialKg = 0.0
    var goalKg = 0.0
    var start: Date?
    var records: [WeightRecord] = []

    var last: WeightRecord? { records.last }
    var previous: WeightRecord? { records.count > 1 ? records[records.count - 2] : nil }
    var lostKg: Double? { last.map { initialKg - $0.kg } }
    var remainingKg: Double? { last.map { max(0, $0.kg - goalKg) } }
    var progress: Double {
        guard let l = last, initialKg > goalKg else { return 0 }
        return min(1, max(0, (initialKg - l.kg) / (initialKg - goalKg)))
    }

    /// kg por mes entre el primer registro dentro de `window` días y el último.
    func ratePerMonth(window days: Int? = nil) -> Double? {
        guard let l = last else { return nil }
        let pool = days.map { d in records.filter { DayKey.days(from: $0.date, to: l.date) <= d } } ?? records
        guard let f = pool.first, pool.count > 1 else { return nil }
        let span = Double(DayKey.days(from: f.date, to: l.date))
        return span > 0 ? (l.kg - f.kg) / span * 30.4 : nil
    }

    /// Media móvil exponencial por tiempo: cada registro pesa según los días desde el anterior.
    /// Con pesajes espaciados (mensuales) un solo valor atípico no mueve tanto la tendencia.
    func smoothed(halfLifeDays: Double = 30) -> [WeightRecord] {
        guard var cur = records.first?.kg else { return [] }
        var out: [WeightRecord] = []
        for (i, r) in records.enumerated() {
            if i > 0 {
                let gap = Double(max(1, DayKey.days(from: records[i - 1].date, to: r.date)))
                let a = 1 - pow(0.5, gap / halfLifeDays)
                cur += a * (r.kg - cur)
            }
            var s = r
            s.kg = cur
            out.append(s)
        }
        return out
    }

    func projectedGoalDate(window days: Int? = 120) -> Date? {
        guard let l = last, let r = ratePerMonth(window: days), r < 0, l.kg > goalKg else { return nil }
        return DayKey.adding(days: Int((l.kg - goalKg) / -r * 30.4), to: l.date)
    }
}

// MARK: - Mounjaro

struct Dose: Identifiable, Equatable {
    var date: Date
    var dose: String
    var site: String
    var note: String
    var line = -1
    var id: Date { date }
    var mg: Double? { MD.number(dose) }
}

struct MounjaroData: Equatable {
    var everyDays = 9
    var doses: [Dose] = []

    var last: Dose? { doses.last }
    var next: Date? { last.map { DayKey.adding(days: everyDays, to: $0.date) } }
    /// Positivo: faltan días. Negativo: atrasado.
    var daysUntilNext: Int? { next.map { DayKey.days(from: DayKey.today(), to: $0) } }

    /// Lado opuesto al de la última inyección, si se anotó.
    var suggestedSite: String {
        let s = MD.fold(last?.site ?? "")
        if s.contains("izq") { return "Abdomen derecho" }
        if s.contains("der") { return "Abdomen izquierdo" }
        return "Abdomen izquierdo"
    }
}

// MARK: - Nala

struct NalaVisit: Identifiable, Equatable {
    var date: Date
    var tipo: String
    var detalle: String
    var proxima: Date?
    var coste: String
    var line = -1
    var id: String { DayKey.string(date) + tipo + String(line) }
}

struct NalaData: Equatable {
    var name = "Nala"
    var birth: Date?
    var food = ""
    var visits: [NalaVisit] = []

    var upcoming: [(date: Date, title: String)] {
        visits.compactMap { v in v.proxima.map { ($0, v.tipo.isEmpty ? (v.detalle.isEmpty ? "Revisión" : v.detalle) : v.tipo) } }
            .filter { $0.0 >= DayKey.today() }.sorted { $0.0 < $1.0 }
    }

    var overdue: [(date: Date, title: String)] {
        visits.compactMap { v -> (Date, String)? in
            guard let p = v.proxima, p < DayKey.today() else { return nil }
            let done = visits.contains { $0.tipo == v.tipo && $0.date >= p }
            return done ? nil : (p, v.tipo.isEmpty ? "Revisión" : v.tipo)
        }
    }

    var ageText: String? {
        guard let b = birth else { return nil }
        let c = DayKey.calendar().dateComponents([.year, .month], from: b, to: Date())
        return "\(c.year ?? 0) años y \(c.month ?? 0) meses"
    }
}

// MARK: - Tareas

struct TaskItem: Identifiable, Equatable {
    var file: String
    var line: Int
    var raw: String
    var text: String
    var due: Date?
    var scheduled: Date?
    var done: Bool
    var completed: Date? = nil
    var recurrence: String? = nil
    var priority = 0   // 3 alta ⏫ · 2 media 🔼 · 1 baja 🔽
    var id: String { "\(file):\(line)" }
    var noteName: String { (file as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "") }
}

// MARK: - Revisión semanal

struct HabitDef: Equatable, Identifiable {
    var name: String
    var criterion = ""
    var id: String { name }
}

struct HabitWeek: Equatable {
    var name: String
    var days: [Bool]
    var criterion = ""
    var count: Int { days.filter { $0 }.count }
}

struct WeekReview: Equatable {
    var key: String
    var exists = false
    var habits: [HabitWeek] = []
    var logros = ""
    var noSalio = ""
    var objetivos = ["", "", ""]
    var fechas: [String] = []

    var totalDone: Int { habits.reduce(0) { $0 + $1.count } }
    var totalPossible: Int { habits.count * 7 }
}

// MARK: - Plan nutricional y proyecto

struct PlanData: Equatable {
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
    var meals: [[String]] = []
    var mealLines: [Int] = []
}

struct Milestone: Identifiable, Equatable {
    var name: String
    var kg: Double
    var markedDone: Bool
    var line = -1
    var id: String { name }
}

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
        return d
    }

    static func mounjaro(_ text: String) -> MounjaroData {
        var d = MounjaroData()
        d.everyDays = MD.frontmatter(text)["cada_dias"].flatMap { Int($0) } ?? 9
        for (i, c) in MD.tableRows(MD.lines(text)) where c.count >= 3 {
            guard let date = DayKey.date(c[0]) else { continue }
            d.doses.append(Dose(date: date, dose: c[1], site: c[2], note: c.count > 3 ? c[3] : "", line: i))
        }
        d.doses.sort { $0.date < $1.date }
        return d
    }

    static func nala(_ text: String) -> NalaData {
        let fm = MD.frontmatter(text)
        var d = NalaData()
        d.name = fm["nombre"] ?? "Nala"
        d.birth = fm["nacimiento"].flatMap(DayKey.dmyDate)
        d.food = fm["comida"] ?? ""
        for (line, c) in MD.tableRows(MD.lines(text)) where c.count >= 2 {
            guard let date = DayKey.date(c[0]) else { continue }
            func at(_ i: Int) -> String { i < c.count ? c[i] : "" }
            d.visits.append(NalaVisit(date: date, tipo: at(1), detalle: at(2), proxima: DayKey.date(at(3)), coste: at(4), line: line))
        }
        d.visits.sort { $0.date < $1.date }
        return d
    }

    static func tasks(_ text: String, file: String) -> [TaskItem] {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var out: [TaskItem] = []
        for (i, line) in lines.enumerated() where !fence.contains(i) {
            guard let m = line.firstMatch(of: /^\s*- \[([ xX])\] (.*)$/) else { continue }
            let body = String(m.2)
            func date(_ emoji: String) -> Date? {
                guard let r = body.range(of: "\(emoji)\\s*\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) else { return nil }
                return DayKey.date(String(body[r].suffix(10)))
            }
            var clean = body
            let priority = body.contains("⏫") ? 3 : body.contains("🔼") ? 2 : body.contains("🔽") ? 1 : 0
            var recurrence: String?
            if let r = body.range(of: #"🔁\s*every\s+[^📅⏳\[]+"#, options: .regularExpression) {
                recurrence = String(body[r]).replacingOccurrences(of: "🔁", with: "").replacingOccurrences(of: "every", with: "").trimmingCharacters(in: .whitespaces)
            }
            for pattern in [#"📅\s*\d{4}-\d{2}-\d{2}"#, #"⏳\s*\d{4}-\d{2}-\d{2}"#, #"\[completion::[^\]]*\]"#, #"🔁\s*every\s+[^📅⏳\[]+"#, "⏫", "🔼", "🔽"] {
                clean = clean.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            clean = clean.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }
            var completed: Date?
            if let r = body.range(of: #"\[completion::\s*\d{4}-\d{2}-\d{2}\]"#, options: .regularExpression) {
                completed = DayKey.date(String(body[r].dropLast().suffix(10)))
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

// MARK: - Casa

struct TableRow: Identifiable, Equatable {
    var line: Int
    var cells: [String]
    var id: Int { line }
}

struct SectionTable: Equatable {
    var title: String
    var header: [String] = []
    var rows: [TableRow] = []

    func col(_ name: String) -> Int? { header.firstIndex { MD.fold($0) == MD.fold(name) } }
    func value(_ row: TableRow, _ name: String) -> String { col(name).flatMap { $0 < row.cells.count ? row.cells[$0] : nil } ?? "" }
}

struct CasaData: Equatable {
    var reformas = SectionTable(title: "Reformas")
    var compras = SectionTable(title: "Compras")
    var electros = SectionTable(title: "Electrodomésticos")
    var small = SectionTable(title: "Pequeños electrodomésticos")
}

enum Money {
    /// Igual que la nota Casa: quita €, usa coma decimal y punto de millares.
    static func parse(_ s: String) -> Double {
        var t = s.replacingOccurrences(of: "€", with: "").filter { !$0.isWhitespace }
        if t.isEmpty { return 0 }
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else if t.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil { t = t.replacingOccurrences(of: ".", with: "") }
        return Double(t) ?? 0
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "es_ES")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v)) €"
    }
}

extension Parse {
    static func sectionTable(_ text: String, title: String) -> SectionTable {
        var t = SectionTable(title: title)
        let lines = MD.lines(text)
        guard let range = MD.section(lines, containing: title) else { return t }
        let rows = MD.tableRows(Array(lines)).filter { range.contains($0.index) }
        guard let head = rows.first else { return t }
        t.header = head.cells
        for r in rows.dropFirst() {
            if r.cells.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil || $0.isEmpty }) && r.cells.contains(where: { !$0.isEmpty }) { continue }
            t.rows.append(TableRow(line: r.index, cells: r.cells))
        }
        return t
    }

    static func casa(_ text: String) -> CasaData {
        CasaData(reformas: sectionTable(text, title: "Reformas"), compras: sectionTable(text, title: "Compras"),
                 electros: sectionTable(text, title: "Electrodomésticos"), small: sectionTable(text, title: "Pequeños electrodomésticos"))
    }
}

// MARK: - Enlaces entre notas

enum Links {
    /// Nombres de nota enlazados con `[[Nota]]`, `[[Nota|alias]]` o `[[Nota#sección]]`, fuera de bloques de código.
    static func extract(_ text: String) -> [String] {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var out: [String] = []
        for (i, l) in lines.enumerated() where !fence.contains(i) {
            for m in l.matches(of: /\[\[([^\]]+)\]\]/) {
                var name = String(m.1)
                if let r = name.range(of: #"\\?\|"#, options: .regularExpression) { name = String(name[..<r.lowerBound]) }
                if let h = name.firstIndex(of: "#") { name = String(name[..<h]) }
                name = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { out.append(name) }
            }
        }
        return out
    }
}

enum GraphLayout {
    /// Disposición de fuerzas (Fruchterman-Reingold). Devuelve posiciones en [0,1]².
    static func compute(count n: Int, edges: [(Int, Int)], iterations: Int = 320) -> [CGPoint] {
        guard n > 0 else { return [] }
        if n == 1 { return [CGPoint(x: 0.5, y: 0.5)] }
        var pos = (0..<n).map { i -> CGPoint in
            let angle = 2 * Double.pi * Double(i) / Double(n)
            let jitter = abs(sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let r = 0.3 + 0.15 * jitter
            return CGPoint(x: 0.5 + r * cos(angle), y: 0.5 + r * sin(angle))
        }
        let k = 0.9 * (1.0 / Double(n)).squareRoot()
        var temp = 0.1
        for _ in 0..<iterations {
            var disp = [CGVector](repeating: .zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    let d = max((dx * dx + dy * dy).squareRoot(), 0.001)
                    let f = k * k / d
                    disp[i].dx += dx / d * f; disp[i].dy += dy / d * f
                    disp[j].dx -= dx / d * f; disp[j].dy -= dy / d * f
                }
            }
            for (a, b) in edges where a != b {
                let dx = pos[a].x - pos[b].x, dy = pos[a].y - pos[b].y
                let d = max((dx * dx + dy * dy).squareRoot(), 0.001)
                let f = d * d / k
                disp[a].dx -= dx / d * f; disp[a].dy -= dy / d * f
                disp[b].dx += dx / d * f; disp[b].dy += dy / d * f
            }
            for i in 0..<n {
                disp[i].dx -= (pos[i].x - 0.5) * k * 2
                disp[i].dy -= (pos[i].y - 0.5) * k * 2
                let len = max((disp[i].dx * disp[i].dx + disp[i].dy * disp[i].dy).squareRoot(), 0.0001)
                let step = min(len, temp)
                pos[i].x += disp[i].dx / len * step
                pos[i].y += disp[i].dy / len * step
            }
            temp *= 0.985
        }
        let xs = pos.map(\.x), ys = pos.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let span = max(maxX - minX, maxY - minY, 0.0001)
        return pos.map { CGPoint(x: 0.5 + ($0.x - (minX + maxX) / 2) / span * 0.9, y: 0.5 + ($0.y - (minY + maxY) / 2) / span * 0.9) }
    }
}


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

    /// Próxima fecha de cumpleaños desde `today`.
    func nextBirthday(from today: Date = DayKey.today()) -> (date: Date, age: Int?)? {
        let p = birthday.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 || p.count == 3 else { return nil }
        let (month, day) = p.count == 3 ? (p[1], p[2]) : (p[0], p[1])
        let cal = DayKey.calendar()
        let year = cal.component(.year, from: today)
        guard var d = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        if d < today { d = cal.date(from: DateComponents(year: year + 1, month: month, day: day)) ?? d }
        return (d, p.count == 3 ? cal.component(.year, from: d) - p[0] : nil)
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

extension MounjaroData {
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
    /// Intervalo de una regla como "week", "2 weeks", "month", "3 days", "year".
    static func component(_ rule: String) -> (Calendar.Component, Int)? {
        let parts = rule.lowercased().split(separator: " ").map(String.init)
        guard let unit = parts.last else { return nil }
        let n = parts.count > 1 ? Int(parts[0]) ?? 1 : 1
        if unit.hasPrefix("day") { return (.day, n) }
        if unit.hasPrefix("week") { return (.weekOfYear, n) }
        if unit.hasPrefix("month") { return (.month, n) }
        if unit.hasPrefix("year") { return (.year, n) }
        return nil
    }

    /// Siguiente fecha futura de la serie a partir de `due` (o de hoy si no tenía).
    static func next(after due: Date?, rule: String, today: Date = DayKey.today()) -> Date? {
        guard let (unit, n) = component(rule), n > 0 else { return nil }
        let cal = DayKey.calendar()
        var d = due ?? today
        repeat { guard let nx = cal.date(byAdding: unit, value: n, to: d) else { return nil }; d = nx } while d < today
        return d
    }

    static func describe(_ rule: String) -> String {
        guard let (unit, n) = component(rule) else { return rule }
        let names: [Calendar.Component: (String, String)] = [.day: ("día", "días"), .weekOfYear: ("semana", "semanas"), .month: ("mes", "meses"), .year: ("año", "años")]
        let (one, many) = names[unit] ?? ("", "")
        return n == 1 ? "cada \(one)" : "cada \(n) \(many)"
    }
}

// MARK: - Medidas corporales

struct MeasureRecord: Identifiable, Equatable {
    var date: Date
    var values: [String: Double]
    var note: String
    var line: Int
    var id: Int { line }
}

enum Measures {
    static let file = "Cambio físico/Medidas.md"
    static let fields = ["Cintura", "Cadera", "Pecho", "Brazo", "Muslo", "Grasa"]
    static let units = ["Cintura": "cm", "Cadera": "cm", "Pecho": "cm", "Brazo": "cm", "Muslo": "cm", "Grasa": "%"]

    static func parse(_ text: String) -> (table: NamedTable?, records: [MeasureRecord]) {
        guard let t = Parse.tables(text).first(where: { $0.col("cintura") != nil }) else { return (nil, []) }
        let recs = t.rows.compactMap { r -> MeasureRecord? in
            guard let d = DayKey.dmyDate(r.cells.first ?? "") ?? DayKey.date(r.cells.first ?? "") else { return nil }
            var v: [String: Double] = [:]
            for f in fields { if let n = MD.number(t.value(r, f)), !t.value(r, f).isEmpty { v[f] = n } }
            return MeasureRecord(date: d, values: v, note: t.value(r, "notas"), line: r.line)
        }.sorted { $0.date < $1.date }
        return (t, recs)
    }

    static var template: String {
        """
        ---
        tipo: medidas
        tags:
          - salud
          - medidas
        ---

        # Medidas corporales

        > Mídete una vez al mes, en ayunas y con la cinta sin apretar, en los mismos puntos.

        | Fecha | Cintura (cm) | Cadera (cm) | Pecho (cm) | Brazo (cm) | Muslo (cm) | Grasa (%) | Notas |
        | :---- | -----------: | ----------: | ---------: | ---------: | ---------: | --------: | :---- |

        ---
        [[Peso]]
        """
    }
}


// MARK: - Etiquetas, resumen y menciones (estilo Bear / Obsidian)

enum NoteInfo {
    /// Etiquetas de una nota: la lista `tags:` del encabezado y los `#etiqueta` del texto (fuera de código).
    static func tags(_ text: String) -> [String] {
        var out: [String] = MD.frontmatterList(text, key: "tags").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#\"' ")) }
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var start = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        for (i, l) in lines.enumerated() where i >= start && !fence.contains(i) {
            for m in l.matches(of: /(?:^|\s)#([\p{L}][\p{L}\p{N}_\/-]*)/) { out.append(String(m.1)) }
        }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert(MD.fold($0)).inserted }
    }

    /// Primera línea con texto (sin encabezados, listas ni formato) para mostrar como vista previa.
    static func snippet(_ text: String) -> String {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var start = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        for (i, raw) in lines.enumerated() where i >= start && !fence.contains(i) {
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("|") || l == "---" { continue }
            l = l.replacingOccurrences(of: #"^(>\s*(\[![^\]]*\]\s*)?|[-*]\s+(\[[ xX]\]\s+)?|\d+\.\s+)"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"\[\[([^\]|]*\|)?([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            if !l.isEmpty { return String(l.prefix(120)) }
        }
        return ""
    }

    static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }

    static func aliases(_ text: String) -> [String] { MD.frontmatterList(text, key: "aliases") }
}
