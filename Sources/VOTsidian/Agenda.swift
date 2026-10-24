import SwiftUI

struct AgendaItem: Identifiable {
    enum Kind: String {
        case task, done, appointment, dose, doseNext, weight, birthday, document, mascota, vehiculo, suscripcion, prestamo, viaje, lectura, tramite, event, shopping, diary
        var icon: String {
            switch self {
            case .task: "circle"
            case .done: "checkmark.circle.fill"
            case .appointment: "cross.case"
            case .dose, .doseNext: "syringe"
            case .weight: "scalemass"
            case .birthday: "gift"
            case .document: "doc.on.doc"
            case .mascota: "pawprint"
            case .vehiculo: "car"
            case .suscripcion: "repeat"
            case .prestamo: "creditcard.and.123"
            case .viaje: "airplane"
            case .lectura: "book"
            case .tramite: "building.columns"
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
            case .mascota: Brand.clay
            case .vehiculo: Brand.sky
            case .suscripcion: Brand.violet
            case .prestamo: Brand.slate
            case .viaje: Brand.rose
            case .lectura: Brand.lime
            case .tramite: Brand.amber
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
    /// Hora, si la tiene (minutos desde medianoche). Lo de todo el día va primero; lo que tiene hora, después y en orden.
    var minutes: Int? = nil
    var timeText: String? { minutes.map(TimeOfDay.text) }
}

extension Store {
    static func diaryPath(_ day: Date) -> String { "Diario/\(DayKey.string(day)).md" }

    /// Todo lo que cae en cada día del rango: tareas, citas, pinchazos, pesajes, cumpleaños, caducidades…
    func agenda(from start: Date, to end: Date) -> [String: [AgendaItem]] {
        // Aunque la caché acierte, quien pinta la agenda depende de todo lo que sale en ella (cada uno solo avisa si cambia).
        _ = (tasks, weight, medicacion, mascota, people, documents, events, noteMeta, notes, casa, hiddenModules)
        _ = (vehiculo, suscripciones, prestamos, lecturas, viajes, tramites)
        touch(VaultPath.moda)
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
                add(AgendaItem(id: "t\(t.id)", kind: isMedical ? .appointment : .task, title: t.text, detail: t.noteName, date: d, task: t, screen: isMedical ? .salud : nil, minutes: t.time))
            } else if let s = t.scheduled {
                add(AgendaItem(id: "s\(t.id)", kind: .task, title: t.text, detail: "planeada · \(t.noteName)", date: s, task: t))
            }
        }
        // Lo periódico (un pinchazo semanal…) sale en el calendario; lo diario llenaría cada día.
        for m in medicacion.meds where !m.asNeeded && m.every > 1 {
            let what = m.isInjection ? "Pinchazo" : "Toma"
            for d in medicacion.intakes(of: m) {
                add(AgendaItem(id: "dose\(d.line)", kind: .dose, title: "\(what) \(m.name) \(d.dose)", detail: d.site, date: d.date, screen: .medicacion))
            }
            guard m.isActive(on: DayKey.today()), var next = medicacion.next(of: m) else { continue }
            var guardCount = 0
            while next <= end, guardCount < 80, m.end.map({ next <= $0 }) ?? true {
                if next >= DayKey.today() {
                    add(AgendaItem(id: "next\(m.line)|\(DayKey.string(next))", kind: .doseNext, title: "Toca \(m.act) de \(m.name)", detail: m.frequencyText.lowercased(), date: next, screen: .medicacion))
                }
                next = DayKey.adding(days: m.every, to: next)
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
        for v in mascota.visits {
            add(AgendaItem(id: "nv\(v.line)", kind: .mascota, title: "\(mascota.name): \(v.tipo)", detail: v.detalle, date: v.date, screen: .mascota))
            if let p = v.proxima { add(AgendaItem(id: "np\(v.line)", kind: .mascota, title: "\(mascota.name): \(v.tipo.isEmpty ? "revisión" : v.tipo)", detail: "próxima", date: p, screen: .mascota)) }
        }
        for d in vehiculo.dues { add(AgendaItem(id: "vd\(d.line)", kind: .vehiculo, title: "\(vehiculo.name): vence \(d.name)", date: d.date, screen: .vehiculo)) }
        for s in vehiculo.services { add(AgendaItem(id: "vs\(s.line)", kind: .vehiculo, title: "\(vehiculo.name): \(s.what)", detail: s.shop, date: s.date, screen: .vehiculo)) }
        for s in vehiculo.nextServices() {
            if let d = s.date { add(AgendaItem(id: "vn\(s.what)", kind: .vehiculo, title: "\(vehiculo.name): toca \(s.what)", detail: "próximo", date: d, screen: .vehiculo)) }
        }
        for i in suscripciones.items {
            if i.status == .trial { add(AgendaItem(id: "sp\(i.line)", kind: .suscripcion, title: "Acaba la prueba de \(i.name)", detail: Money.exact(i.amount), date: i.anchor, screen: .suscripciones)) }
            for d in i.occurrences(from: start, to: end) {
                add(AgendaItem(id: "su\(i.line)|\(DayKey.string(d))", kind: .suscripcion, title: "Se renueva \(i.name)", detail: Money.exact(i.amount), date: d, screen: .suscripciones))
            }
        }
        for p in prestamos.payments { add(AgendaItem(id: "pp\(p.line)", kind: .prestamo, title: "Cuota de \(p.loan)", detail: Money.exact(p.amount), date: p.date, screen: .prestamos)) }
        for s in prestamos.statuses() {
            for d in prestamos.dueDates(s, upTo: end) { add(AgendaItem(id: "pd\(s.loan.line)|\(DayKey.string(d))", kind: .prestamo, title: "Toca la cuota de \(s.loan.name)", detail: Money.exact(s.loan.installment), date: d, screen: .prestamos)) }
        }
        for t in viajes.trips where !t.isClosed {
            if let s = t.start { add(AgendaItem(id: "vj\(t.line)", kind: .viaje, title: "Viaje a \(t.name)", detail: t.end.map { "hasta el \(DayKey.dmy($0))" } ?? "", date: s, screen: .viajes)) }
            if let e = t.end, e != t.start { add(AgendaItem(id: "vv\(t.line)", kind: .viaje, title: "Vuelta de \(t.name)", date: e, screen: .viajes)) }
        }
        for b in lecturas.books where b.status == .finished {
            if let f = b.finished { add(AgendaItem(id: "lb\(b.line)", kind: .lectura, title: "Terminado: \(b.title)", detail: b.author, date: f, screen: .lecturas)) }
        }
        for (p, due) in tramites.pendingProcedures {
            add(AgendaItem(id: "tp\(p.line)", kind: .tramite, title: "Plazo: \(p.name)", detail: p.amount.map(Money.exact) ?? "", date: due, screen: .tramites))
        }
        for p in tramites.procedures { if let d = p.done { add(AgendaItem(id: "th\(p.line)", kind: .tramite, title: "Hecho: \(p.name)", date: d, screen: .tramites)) } }
        for i in tramites.insurances {
            for d in i.renewals(from: start, to: end) {
                add(AgendaItem(id: "ts\(i.line)|\(DayKey.string(d))", kind: .tramite, title: "Renueva el seguro de \(i.name)", detail: i.premium > 0 ? Money.exact(i.premium) : "", date: d, screen: .tramites))
            }
        }
        for e in events { add(AgendaItem(id: "e\(e.path)", kind: .event, title: e.name, date: e.date, path: e.path)) }
        for (path, m) in noteMeta where m["tipo"] == "cita_medica" {
            if let d = m["fecha"].flatMap(DayKey.date) {
                add(AgendaItem(id: "c\(path)", kind: .appointment, title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, detail: m["especialidad"] ?? "", date: d, path: path,
                               minutes: m["hora"].flatMap(TimeOfDay.parse)))
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
        // Como los avisos: lo de los módulos ocultos no sale en el calendario ni en «Hoy».
        // Orden estable: primero lo de todo el día (como se añadió) y después lo que tiene hora, de más temprano a más tarde.
        return out.mapValues { items in
            items.filter { $0.screen.map(isVisible) ?? true }.enumerated()
                .sorted { ($0.element.minutes ?? -1, $0.offset) < ($1.element.minutes ?? -1, $1.offset) }.map(\.element)
        }.filter { !$0.value.isEmpty }
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
        "calendario": .calendario, "mi dia": .dia, "agenda": .dia, "grafo": .grafo, "ajustes": .ajustes, "avisos": .avisos, "salud": .salud,
        "medicos": .salud, "analiticas": .salud, "analisis": .salud, "medico": .salud, "doctor": .salud, "inicio": .inicio,
        "enlaces rotos": .enlaces, "gastos": .gastos, "presupuesto": .gastos, "coche": .vehiculo, "vehiculo": .vehiculo, "suscripciones": .suscripciones, "prestamos": .prestamos, "deudas": .prestamos,
        "lecturas": .lecturas, "libros": .lecturas, "viajes": .viajes, "tramites": .tramites, "seguros": .tramites, "impuestos": .tramites,
    ]

    func screenAlias(_ name: String) -> Screen? { Store.screenAliases[MD.fold((name as NSString).lastPathComponent)] }

    /// Como `resolve`, pero tolera plurales y pequeñas diferencias ("Medicos" → "Médico").
    func fuzzyResolve(_ name: String) -> String? {
        if let p = resolve(name) { return p }
        let stems = noteKeys.stems
        let key = Store.stem(MD.fold((name as NSString).lastPathComponent))
        if let i = stems.firstIndex(of: key) { return notes[i].path }
        guard key.count >= 4 else { return nil }
        let candidates = stems.indices.filter { stems[$0].hasPrefix(key) || key.hasPrefix(stems[$0]) }
        return candidates.count == 1 ? notes[candidates[0]].path : nil
    }

    /// Quita el plural a un nombre ya plegado ("medicos" → "medico").
    nonisolated static func stem(_ folded: String) -> String {
        var t = folded
        if t.hasSuffix("es"), t.count > 4 { t.removeLast(2) } else if t.hasSuffix("s"), t.count > 3 { t.removeLast() }
        return t
    }

    /// Nombres de nota plegados, en el orden de `notes`, para comparar con todos los enlaces que no resuelven.
    struct NameKeys {
        var folded: [String]
        /// Sin plural, para `fuzzyResolve`.
        var stems: [String]
        /// En escalares y no en letras: ya sin tildes dan la misma distancia de edición, y compararlos es mucho más rápido.
        var scalars: [[Unicode.Scalar]]
        /// La primera nota de cada nombre plegado: las repetidas no dan otra sugerencia.
        var unique: [Int]
    }

    /// `nameKeys`, calculados la primera vez que hacen falta tras cada recarga.
    var noteKeys: NameKeys {
        if let k = nameKeys { return k }
        let folded = notes.map { MD.fold($0.name) }
        var seen = Set<String>()
        let k = NameKeys(folded: folded, stems: folded.map(Store.stem), scalars: folded.map { Array($0.unicodeScalars) },
                         unique: folded.indices.filter { seen.insert(folded[$0]).inserted })
        nameKeys = k
        return k
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
            // Los enlaces ya están analizados en la caché: volver a sacarlos con regex de cada nota costaba ~0,4 s con 1500 notas.
            for name in fileCache[n.path]?.parsed.links ?? Links.extract(noteTexts[n.path] ?? read(n.path)) where seen.insert(name).inserted {
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
        let folded = MD.fold(name)
        let key = Array(folded.unicodeScalars)
        guard !key.isEmpty else { return [] }
        var scored: [(name: String, score: Double)] = []
        let keys = noteKeys
        for i in keys.unique {
            let f = keys.folded[i], other = keys.scalars[i]
            let longest = max(key.count, other.count)
            let gap = abs(key.count - other.count)
            guard gap <= max(3, longest / 2) else { continue }
            let contains = other.count >= 3 && (MD.contains(folded, f) || MD.contains(f, folded))
            // La distancia nunca baja de la diferencia de longitud: si eso ya pasa del 0,4, no hace falta calcularla.
            guard contains || 5 * gap <= 2 * longest else { continue }
            let score = contains ? 0.2 : Double(Store.editDistance(key, other, limit: 2 * longest / 5)) / Double(longest)
            if score <= 0.4 { scored.append((notes[i].name, score)) }
        }
        return scored.sorted { ($0.score, $0.name) < ($1.score, $1.name) }.prefix(limit).map(\.name)
    }

    /// Distancia de Levenshtein. Con `limit`, en cuanto se sabe que pasa de ahí devuelve `limit + 1` sin terminar la cuenta.
    nonisolated static func editDistance<T: Equatable>(_ a: [T], _ b: [T], limit: Int = .max) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        let w = b.count + 1
        // Las dos filas van en la pila: se compara con cada nota, y reservar memoria en cada llamada era lo que más costaba.
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: 2 * w) { buf in
            var prev = buf.baseAddress!, cur = prev + w
            for j in 0..<w { prev[j] = j }
            for i in 1...a.count {
                cur[0] = i
                var best = i
                for j in 1...b.count {
                    cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                    best = min(best, cur[j])
                }
                if best > limit { return limit + 1 }   // ninguna fila siguiente baja de este mínimo
                swap(&prev, &cur)
            }
            return prev[b.count]
        }
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
