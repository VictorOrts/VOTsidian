import SwiftUI

struct AgendaItem: Identifiable {
    enum Kind: String {
        case task, done, appointment, dose, doseNext, weight, birthday, document, nala, event, shopping, diary
        var icon: String {
            switch self {
            case .task: "circle"
            case .done: "checkmark.circle.fill"
            case .appointment: "cross.case"
            case .dose, .doseNext: "syringe"
            case .weight: "scalemass"
            case .birthday: "gift"
            case .document: "doc.on.doc"
            case .nala: "cat"
            case .event: "party.popper"
            case .shopping: "bag"
            case .diary: "note.text"
            }
        }
        var color: Color {
            switch self {
            case .task: Brand.accent
            case .done: .gray
            case .appointment: Brand.bad
            case .dose, .doseNext: Brand.violet
            case .weight: Brand.amber
            case .birthday: Brand.sky
            case .document: Brand.slate
            case .nala: Brand.clay
            case .event: Brand.rose
            case .shopping: Brand.lime
            case .diary: Brand.info
            }
        }
    }

    var id: String
    var kind: Kind
    var title: String
    var detail = ""
    var date: Date
    var task: TaskItem? = nil
    var screen: Screen? = nil
    var path: String? = nil
}

extension Store {
    static func diaryPath(_ day: Date) -> String { "Diario/\(DayKey.string(day)).md" }

    /// Todo lo que cae en cada día del rango: tareas, citas, pinchazos, pesajes, cumpleaños, caducidades…
    func agenda(from start: Date, to end: Date) -> [String: [AgendaItem]] {
        let cacheKey = "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        if let hit = agendaCache[cacheKey] { return hit }
        let result = buildAgenda(from: start, to: end)
        agendaCache[cacheKey] = result
        return result
    }

    private func buildAgenda(from start: Date, to end: Date) -> [String: [AgendaItem]] {
        var out: [String: [AgendaItem]] = [:]
        func add(_ item: AgendaItem) {
            guard item.date >= start, item.date <= end else { return }
            out[DayKey.string(item.date), default: []].append(item)
        }

        for t in tasks {
            let isMedical = t.file == VaultPath.medico
            if t.done {
                if let c = t.completed { add(AgendaItem(id: "d\(t.id)", kind: .done, title: t.text, detail: t.noteName, date: c, task: t)) }
            } else if let d = t.due {
                add(AgendaItem(id: "t\(t.id)", kind: isMedical ? .appointment : .task, title: t.text, detail: t.noteName, date: d, task: t, screen: isMedical ? .salud : nil))
            } else if let s = t.scheduled {
                add(AgendaItem(id: "s\(t.id)", kind: .task, title: t.text, detail: "planeada · \(t.noteName)", date: s, task: t))
            }
        }
        for d in mounjaro.doses { add(AgendaItem(id: "dose\(d.line)", kind: .dose, title: "Pinchazo \(d.dose)", detail: d.site, date: d.date, screen: .mounjaro)) }
        if let last = mounjaro.last {
            var next = DayKey.adding(days: mounjaro.everyDays, to: last.date)
            var guardCount = 0
            while next <= end, guardCount < 80 {
                if next >= DayKey.today() { add(AgendaItem(id: "next\(DayKey.string(next))", kind: .doseNext, title: "Toca pinchazo", detail: "cada \(mounjaro.everyDays) días", date: next, screen: .mounjaro)) }
                next = DayKey.adding(days: mounjaro.everyDays, to: next)
                guardCount += 1
            }
        }
        for w in weight.records { add(AgendaItem(id: "w\(w.line)", kind: .weight, title: "Peso \(fmt(w.kg)) kg", detail: w.note, date: w.date, screen: .peso)) }
        let cal = DayKey.calendar()
        let years = Set([cal.component(.year, from: start), cal.component(.year, from: end)])
        for p in people {
            let parts = p.birthday.split(separator: "-").compactMap { Int($0) }
            guard parts.count >= 2 else { continue }
            let (m, d) = parts.count == 3 ? (parts[1], parts[2]) : (parts[0], parts[1])
            for y in years {
                if let date = cal.date(from: DateComponents(year: y, month: m, day: d)) {
                    add(AgendaItem(id: "b\(p.name)\(y)", kind: .birthday, title: "Cumpleaños de \(p.name)", detail: parts.count == 3 ? "\(y - parts[0]) años" : "", date: date, screen: .personas))
                }
            }
        }
        for d in documents { add(AgendaItem(id: "doc\(d.name)", kind: .document, title: "Caduca: \(d.name)", detail: d.section, date: d.date, screen: .documentos)) }
        for v in nala.visits {
            add(AgendaItem(id: "nv\(v.line)", kind: .nala, title: "\(nala.name): \(v.tipo)", detail: v.detalle, date: v.date, screen: .nala))
            if let p = v.proxima { add(AgendaItem(id: "np\(v.line)", kind: .nala, title: "\(nala.name): \(v.tipo.isEmpty ? "revisión" : v.tipo)", detail: "próxima", date: p, screen: .nala)) }
        }
        for e in events { add(AgendaItem(id: "e\(e.path)", kind: .event, title: e.name, date: e.date, path: e.path)) }
        for (path, m) in noteMeta where m["tipo"] == "cita_medica" {
            if let d = m["fecha"].flatMap(DayKey.date) {
                add(AgendaItem(id: "c\(path)", kind: .appointment, title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, detail: m["especialidad"] ?? "", date: d, path: path))
            }
        }
        for t in Parse.tables(read(VaultPath.moda)) where MD.fold(t.title).contains("por comprar") {
            for r in t.rows {
                let e = MD.fold(t.value(r, "estado"))
                if !e.contains("comprado"), !e.contains("descartado"), let d = DayKey.date(t.value(r, "fecha objetivo")), let n = r.cells.first, !n.isEmpty {
                    add(AgendaItem(id: "m\(r.line)", kind: .shopping, title: "Comprar: \(n)", detail: t.value(r, "modelo"), date: d, screen: .moda))
                }
            }
        }
        for t in [casa.reformas, casa.compras] {
            for r in t.rows {
                if let d = DayKey.date(t.value(r, "Cuándo")), let n = r.cells.first, !n.isEmpty {
                    add(AgendaItem(id: "c\(t.title)\(r.line)", kind: .shopping, title: n, detail: t.title, date: d, screen: .casa))
                }
            }
        }
        for n in notes where n.path.hasPrefix("Diario/") {
            if let d = DayKey.date(n.name) { add(AgendaItem(id: "n\(n.path)", kind: .diary, title: "Nota del día", date: d, path: n.path)) }
        }
        return out
    }

    /// Añade un punto a la nota del día (`Diario/AAAA-MM-DD.md`), que se crea con la fecha ya puesta.
    func appendToDiary(_ day: Date, text: String) {
        let rel = Store.diaryPath(day)
        let line = "- \(Store.stamp("HH:mm")) \(text)"
        if FileManager.default.fileExists(atPath: url(rel).path) {
            edit(rel) { $0.hasSuffix("\n") ? $0 + line + "\n" : $0 + "\n" + line + "\n" }
        } else {
            writeNote(rel, text: Store.diaryTemplate(day) + line + "\n")
            connectDiary(day)
        }
    }

    static func diaryTemplate(_ day: Date) -> String {
        let title = DayKey.esLong(day, .dateTime.weekday(.wide).day().month(.wide).year())
        return "---\ntipo: diario\nfecha: \(DayKey.string(day))\n---\n\n# \(capitalizedFirst(title))\n\n"
    }

    func reschedule(_ t: TaskItem, to date: Date) {
        edit(t.file) { Edit.updateTask($0, task: t, newText: t.text, due: date) }
    }

    // MARK: Enlaces

    static let screenAliases: [String: Screen] = [
        "tareas": .tareas, "proyectos": .proyectos, "habitos": .semana, "revision semanal": .semana, "revision mensual": .mes, "revisiones": .semana,
        "calendario": .calendario, "grafo": .grafo, "ajustes": .ajustes, "avisos": .avisos, "salud": .salud,
        "medicos": .salud, "analiticas": .salud, "analisis": .salud, "medico": .salud, "doctor": .salud, "inicio": .inicio,
        "enlaces rotos": .enlaces, "gastos": .gastos, "presupuesto": .gastos,
    ]

    func screenAlias(_ name: String) -> Screen? { Store.screenAliases[MD.fold((name as NSString).lastPathComponent)] }

    /// Como `resolve`, pero tolera plurales y pequeñas diferencias ("Medicos" → "Médico").
    func fuzzyResolve(_ name: String) -> String? {
        if let p = resolve(name) { return p }
        func stem(_ s: String) -> String {
            var t = MD.fold((s as NSString).lastPathComponent)
            if t.hasSuffix("es"), t.count > 4 { t.removeLast(2) } else if t.hasSuffix("s"), t.count > 3 { t.removeLast() }
            return t
        }
        let key = stem(name)
        if let n = notes.first(where: { stem($0.name) == key }) { return n.path }
        guard key.count >= 4 else { return nil }
        let candidates = notes.filter { stem($0.name).hasPrefix(key) || key.hasPrefix(stem($0.name)) }
        return candidates.count == 1 ? candidates[0].path : nil
    }

    struct BrokenLink: Identifiable {
        var id: String { path + "\u{0}" + target }
        var path: String
        var target: String
        var suggestion: String?   // nombre de la nota que probablemente quería
        var candidates: [String] = []   // notas de nombre parecido, para elegir a mano
    }

    func brokenLinks() -> [BrokenLink] {
        var out: [BrokenLink] = []
        for n in notes {
            var seen = Set<String>()
            for name in Links.extract(noteTexts[n.path] ?? read(n.path)) where seen.insert(name).inserted {
                if resolve(name) != nil || attachmentURL(name) != nil { continue }
                let sug = fuzzyResolve(name).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                if sug == nil, screenAlias(name) != nil { continue }
                var candidates = similarNotes(name)
                if let sug { candidates.removeAll { $0 == sug }; candidates.insert(sug, at: 0) }
                out.append(BrokenLink(path: n.path, target: name, suggestion: sug, candidates: Array(candidates.prefix(3))))
            }
        }
        return out
    }

    /// Hasta `limit` nombres de nota parecidos a `name` (distancia de edición sin tildes ni mayúsculas), del más al menos parecido.
    func similarNotes(_ name: String, limit: Int = 3) -> [String] {
        let key = Array(MD.fold(name))
        guard !key.isEmpty else { return [] }
        var scored: [(name: String, score: Double)] = []
        var seen = Set<String>()
        for n in notes where seen.insert(MD.fold(n.name)).inserted {
            let other = Array(MD.fold(n.name))
            let longest = max(key.count, other.count)
            guard abs(key.count - other.count) <= max(3, longest / 2) else { continue }
            let contains = other.count >= 3 && (String(key).contains(String(other)) || String(other).contains(String(key)))
            let score = contains ? 0.2 : Double(Store.editDistance(key, other)) / Double(longest)
            if score <= 0.4 { scored.append((n.name, score)) }
        }
        return scored.sorted { ($0.score, $0.name) < ($1.score, $1.name) }.prefix(limit).map(\.name)
    }

    nonisolated static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Corrige los enlaces rotos que tienen una sugerencia clara. Devuelve cuántos cambió.
    @discardableResult
    func repairLinks() -> Int {
        var fixed = 0
        for b in brokenLinks() {
            guard let s = b.suggestion else { continue }
            fixLink(b, to: s)
            fixed += 1
        }
        return fixed
    }

    /// Cambia en su nota el enlace roto por uno a `name`.
    func fixLink(_ b: BrokenLink, to name: String) {
        edit(b.path) { Edit.renameLinks($0, old: b.target, new: name) }
    }

    /// Crea la nota que falta, en la misma carpeta que la nota que la enlaza.
    @discardableResult
    func createMissingNote(_ b: BrokenLink) -> String? {
        let folder = (b.path as NSString).deletingLastPathComponent
        return createNote(folder: folder, name: b.target, template: "En blanco")
    }
}

// MARK: - Nota de hoy y estado de ánimo (diario)

extension Store {
    /// Crea (si falta) y abre la nota del día en el editor.
    func openToday() {
        let day = DayKey.today()
        let rel = Store.diaryPath(day)
        if !FileManager.default.fileExists(atPath: url(rel).path) {
            writeNote(rel, text: Store.diaryTemplate(day) + "- ")
            connectDiary(day)
        }
        pendingNote = rel
    }

    /// Valor de ánimo (1 a 5), horas de sueño o energía de un día.
    func diaryValue(_ day: Date, _ key: String) -> Double? {
        noteMeta[Store.diaryPath(day)]?[key].flatMap { MD.number($0) }
    }

    func setDiaryValue(_ day: Date, _ key: String, _ value: Double?) {
        let rel = Store.diaryPath(day)
        if !FileManager.default.fileExists(atPath: url(rel).path) {
            guard value != nil else { return }
            writeNote(rel, text: Store.diaryTemplate(day))
            connectDiary(day)
        }
        setProperty(rel, key: key, value: value.map { MD.formatNumber($0) } ?? "", quiet: true)
    }

    /// Valores diarios dentro de un rango, para medias y gráficas.
    func diarySeries(_ key: String, from: Date, to: Date) -> [(Date, Double)] {
        var out: [(Date, Double)] = []
        var d = from
        while d <= to {
            if let v = diaryValue(d, key) { out.append((d, v)) }
            d = DayKey.adding(days: 1, to: d)
        }
        return out
    }
}
