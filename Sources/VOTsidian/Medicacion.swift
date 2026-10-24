import Foundation

// MARK: - Medicación: varios medicamentos, cada uno con su forma y su frecuencia
//
// La nota tiene dos tablas: «## Medicamentos» (qué se toma, cuánto y cada cuánto) y «## Registro» (cada toma o
// pinchazo). Sirve para una pastilla diaria (una o varias veces al día), una inyección semanal o cada N días y lo que
// se toma solo cuando hace falta.
//
// Las notas de la primera versión solo tenían el registro de un medicamento inyectable (Fecha | Dosis | Zona | Notas)
// con «cada_dias» en el encabezado: se leen como un único medicamento, y al añadir otro la nota pasa al formato nuevo.

struct Medication: Identifiable, Equatable {
    var name: String
    var dose = ""
    /// Pastilla, cápsula, inyección, gotas… Texto libre; las inyecciones llevan zona y la alternan.
    var form = ""
    /// Días entre tomas: 1 = cada día, 7 = cada semana; 0 = solo cuando hace falta.
    var every = 1
    /// Horas de las tomas («09:00», «21:00»): tantas tomas al día como horas. Sin horas, una.
    var times: [String] = []
    var start: Date?
    var end: Date?
    var note = ""
    /// Fila en la tabla de medicamentos; -1 en una nota de antes, que no la tiene.
    var line = -1
    var id: String { "\(line)|\(name)" }

    var isInjection: Bool {
        let f = MD.fold(form)
        return f.contains("inyec") || f.contains("pinch") || f.contains("pluma") || f.contains("jeringa")
    }
    var asNeeded: Bool { every <= 0 }
    var perDay: Int { max(times.count, 1) }
    /// «pinchazo» o «toma», para los textos.
    var act: String { isInjection ? "pinchazo" : "toma" }
    var icon: String {
        let f = MD.fold(form)
        if isInjection { return "syringe" }
        if f.contains("gota") || f.contains("jarabe") { return "drop" }
        if f.contains("inhal") { return "lungs" }
        if f.contains("crema") || f.contains("pomada") || f.contains("parche") { return "bandage" }
        return "pills"
    }

    func isActive(on day: Date) -> Bool { (start.map { $0 <= day } ?? true) && (end.map { day <= $0 } ?? true) }

    var frequencyText: String {
        if asNeeded { return "Cuando haga falta" }
        let base = every == 1 ? "Cada día" : every == 7 ? "Cada semana" : every == 14 ? "Cada dos semanas" : "Cada \(every) días"
        return times.isEmpty ? base : "\(base) · \(times.joined(separator: ", "))"
    }

    /// Columna «Cada»: «1», «diaria», «7 días», «semanal», «cada 2 semanas»… → días; vacío o «si hace falta» → 0.
    static func every(_ text: String) -> Int {
        let t = MD.fold(text)
        if t.isEmpty || t.contains("falta") || t.contains("necesi") || t.contains("demanda") { return 0 }
        if let n = MD.number(t) {
            let v = max(MD.int(n) ?? 0, 0)
            if t.contains("seman") { return max(v, 1) * 7 }
            if t.contains("mes") { return max(v, 1) * 30 }
            return v
        }
        if t.contains("quincen") { return 14 }
        if t.contains("seman") { return 7 }
        if t.contains("mes") || t.contains("mensual") { return 30 }
        if t.contains("dia") || t.contains("diari") { return 1 }
        return 0
    }

    static func everyText(_ days: Int) -> String { days <= 0 ? "Si hace falta" : String(days) }

    /// Columna «Horas»: «09:00, 21:00», «9:00 y 21:00»…
    static func times(_ text: String) -> [String] {
        text.replacingOccurrences(of: " y ", with: ",").split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Minutos desde medianoche de «09:00» o «9.30»; `nil` si no es una hora.
    static func minutes(_ time: String) -> Int? {
        guard let m = time.firstMatch(of: /^(\d{1,2})[:.](\d{2})$/), let h = Int(m.1), let mi = Int(m.2), h < 24, mi < 60 else { return nil }
        return h * 60 + mi
    }

    static let forms = ["Pastilla", "Cápsula", "Inyección", "Sobre", "Gotas", "Jarabe", "Inhalador", "Crema", "Parche", "Otra"]
}

struct MedicacionData: Equatable {
    /// Nombre de la pantalla: «Medicación», o el de su único medicamento en una nota de una sola tabla («nombre:»).
    var name = "Medicación"
    var meds: [Medication] = []
    /// Todas las tomas, de la más vieja a la más nueva.
    var intakes: [Dose] = []
    /// Nota de una sola tabla: un solo medicamento, sin tabla de medicamentos ni columna «Medicamento».
    var singleTable = false

    func active(on day: Date = DayKey.today()) -> [Medication] { meds.filter { $0.isActive(on: day) } }

    /// Tomas por medicamento (nombre plegado), agrupadas al leer la nota: «próxima toma», «tomadas hoy» o «última dosis» se
    /// piden muchas veces en cada pintado, y antes recorrían todo el registro cada vez.
    var intakeIndex: [String: [Dose]] = [:]

    func intakes(of m: Medication) -> [Dose] {
        let k = MD.fold(m.name)
        if intakeIndex.isEmpty && !intakes.isEmpty { return intakes.filter { MD.fold($0.med) == k } }
        return intakeIndex[k] ?? []
    }
    func last(of m: Medication) -> Dose? { intakes(of: m).last }

    /// Cuándo toca la siguiente de un medicamento que no es diario ni «cuando haga falta».
    func next(of m: Medication) -> Date? {
        guard !m.asNeeded else { return nil }
        if let l = last(of: m) { return DayKey.adding(days: m.every, to: l.date) }
        return m.start
    }
    func daysUntil(_ m: Medication, today: Date = DayKey.today()) -> Int? { next(of: m).map { DayKey.days(from: today, to: $0) } }
    func taken(_ m: Medication, on day: Date) -> Int { intakes(of: m).filter { $0.date == day }.count }

    /// Lo que toca hoy y aún no está: tomas diarias pendientes y lo periódico que toca hoy o va tarde.
    func pending(today: Date = DayKey.today()) -> [(med: Medication, left: Int)] {
        active(on: today).compactMap { m in
            if m.asNeeded { return nil }
            if m.every == 1 {
                let left = m.perDay - taken(m, on: today)
                return left > 0 ? (m, left) : nil
            }
            guard let d = daysUntil(m, today: today), d <= 0, taken(m, on: today) == 0 else { return nil }
            return (m, 1)
        }
    }

    /// Días con todas las tomas hechas, de los últimos `days` (sin contar hoy, que aún no ha acabado). Solo diarios.
    func adherence(_ m: Medication, days: Int = 30, today: Date = DayKey.today()) -> (done: Int, total: Int)? {
        guard m.every == 1 else { return nil }
        let first = [DayKey.adding(days: -days, to: today), m.start ?? intakes(of: m).first?.date ?? today].max()!
        let total = DayKey.days(from: first, to: today)
        guard total > 0 else { return nil }
        var counts: [Date: Int] = [:]
        for i in intakes(of: m) { counts[i.date, default: 0] += 1 }
        let done = (0..<total).filter { counts[DayKey.adding(days: $0, to: first), default: 0] >= m.perDay }.count
        return (done, total)
    }

    // MARK: El medicamento periódico principal
    //
    // Inicio, la barra de menús, «Me pinché hoy», la gráfica de dosis y el peso por dosis siguen al medicamento
    // periódico (normalmente un inyectable semanal). Sin ninguno, estas partes no salen.

    var main: Medication? {
        let periodic = active().filter { !$0.asNeeded && $0.every > 1 }
        return periodic.first(where: \.isInjection) ?? periodic.first ?? (singleTable ? meds.first : nil)
    }
    var everyDays: Int { main?.every ?? 9 }
    var doses: [Dose] { main.map(intakes(of:)) ?? [] }
    var last: Dose? { doses.last }
    var next: Date? { main.flatMap(next(of:)) }
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

// MARK: - Leer

extension Parse {
    /// Las dos tablas de la nota: la lista de medicamentos y el registro de tomas.
    static func medicationTables(_ text: String) -> (list: NamedTable?, log: NamedTable?) {
        let tables = Parse.tables(text)
        let list = tables.first { $0.col("medicamento") != nil && ($0.col("cada") != nil || $0.col("forma") != nil) }
        let others = tables.filter { $0.headerLine != list?.headerLine }
        let log = others.first { $0.col("fecha") != nil } ?? others.first { t in t.rows.contains { DayKey.date($0.cells.first ?? "") != nil } }
        return (list, log)
    }

    static func medicacion(_ text: String) -> MedicacionData {
        var d = MedicacionData()
        guard !text.isEmpty else { return d }
        let fm = MD.frontmatter(text)
        let lines = MD.lines(text)
        let (list, log) = medicationTables(text)
        d.singleTable = list == nil
        let singleName = fm["nombre"].flatMap { $0.isEmpty ? nil : $0 } ?? d.name
        if d.singleTable { d.name = singleName }
        if let list {
            for r in list.rows {
                let name = list.value(r, "medicamento").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                func date(_ col: String) -> Date? { let v = list.value(r, col); return DayKey.date(v) ?? DayKey.dmyDate(v) }
                d.meds.append(Medication(name: name, dose: list.value(r, "dosis"), form: list.value(r, "forma"),
                                         every: Medication.every(list.value(r, "cada")), times: Medication.times(list.value(r, "hora")),
                                         start: date("desde"), end: date("hasta"), note: list.value(r, "nota"), line: r.line))
            }
        }
        if let log {
            let medCol = log.col("medicamento"), dateCol = log.col("fecha") ?? 0
            for r in log.rows {
                let c = r.cells
                func cell(_ i: Int?) -> String { i.map { $0 < c.count ? c[$0] : "" } ?? "" }
                guard let date = DayKey.date(cell(dateCol)) ?? DayKey.dmyDate(cell(dateCol)) else { continue }
                // En las notas de antes las columnas iban por posición: fecha, dosis, zona, notas.
                func named(_ name: String, _ position: Int) -> String { log.col(name).map { cell($0) } ?? (medCol == nil ? cell(position) : "") }
                d.intakes.append(Dose(date: date, dose: named("dosis", 1), site: named("zona", 2), note: named("nota", 3), line: r.line,
                                      med: medCol.map { cell($0) } ?? singleName, raw: r.line < lines.count ? lines[r.line] : ""))
            }
        }
        d.intakes.sort { ($0.date, $0.line) < ($1.date, $1.line) }
        if d.singleTable {
            d.meds = [Medication(name: singleName, dose: d.intakes.last?.dose ?? "", form: "Inyección",
                                 every: fm["cada_dias"].flatMap { Int($0) } ?? 9)]
        }
        for i in d.intakes { d.intakeIndex[MD.fold(i.med), default: []].append(i) }
        return d
    }
}

// MARK: - Escribir

extension Edit {
    /// Apunta una toma en el registro, con las columnas que tenga (en las notas de antes, por posición).
    /// Con `replaceSameDay`, una toma del mismo medicamento ese día se sustituye en vez de repetirse.
    static func addIntake(_ text: String, date: Date, med: String, dose: String, site: String, note: String, replaceSameDay: Bool) -> String? {
        guard let log = Parse.medicationTables(text).log else { return nil }
        var lines = MD.lines(text)
        let medCol = log.col("medicamento"), dateCol = log.col("fecha") ?? 0
        var cells: [String]
        if medCol == nil, log.col("dosis") == nil {
            cells = [DayKey.string(date), dose, site, note]
            while cells.count < log.header.count { cells.append("") }
        } else {
            cells = log.header.map { h in
                let f = MD.fold(h)
                if f.contains("fecha") { return DayKey.string(date) }
                if f.contains("medicamento") { return med }
                if f.contains("dosis") { return dose }
                if f.contains("zona") { return site }
                if f.contains("nota") { return note }
                return ""
            }
        }
        let row = rowString(cells)
        func cell(_ r: TableRow, _ i: Int) -> String { i < r.cells.count ? r.cells[i] : "" }
        func day(_ r: TableRow) -> Date? { DayKey.date(cell(r, dateCol)) ?? DayKey.dmyDate(cell(r, dateCol)) }
        func sameMed(_ r: TableRow) -> Bool { medCol.map { MD.fold(cell(r, $0)) == MD.fold(med) } ?? true }
        if replaceSameDay, let same = log.rows.first(where: { day($0) == date && sameMed($0) }) {
            lines[same.line] = row
            return lines.joined(separator: "\n")
        }
        // Detrás de la última fila con fecha; en un registro vacío, bajo la cabecera.
        let after = log.rows.last(where: { day($0) != nil })?.line ?? (log.headerLine + 1)
        lines.insertClamped(row, at: min(after + 1, lines.count))   // una tabla que es solo la cabecera, al final del archivo
        return lines.joined(separator: "\n")
    }

    static let medicationHeader = ["Medicamento", "Dosis", "Forma", "Cada", "Horas", "Desde", "Hasta", "Notas"]
    static let intakeHeader = ["Fecha", "Medicamento", "Dosis", "Zona", "Notas"]

    static func medicationRow(_ m: Medication, header: [String] = medicationHeader) -> String {
        rowString(header.map { h in
            let f = MD.fold(h)
            if f.contains("medicamento") { return m.name }
            if f.contains("dosis") { return m.dose }
            if f.contains("forma") { return m.form }
            if f.contains("cada") { return Medication.everyText(m.every) }
            if f.contains("hora") { return m.times.joined(separator: ", ") }
            if f.contains("desde") { return m.start.map(DayKey.string) ?? "" }
            if f.contains("hasta") { return m.end.map(DayKey.string) ?? "" }
            if f.contains("nota") { return m.note }
            return ""
        })
    }

    /// Pasa una nota de antes al formato de varios medicamentos: lista con el que había y columna «Medicamento» en el
    /// registro, rellena con su nombre. El resto de la nota no cambia.
    static func upgradeMedicationNote(_ text: String, current: Medication) -> String {
        let (list, log) = Parse.medicationTables(text)
        guard list == nil else { return text }
        var lines = MD.lines(text)
        let listLines = ["## Medicamentos", "", rowString(medicationHeader), rowString(medicationHeader.map { _ in "---" }),
                         medicationRow(current), ""]
        guard let log else {
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += [""] + listLines + ["## Registro", "", rowString(intakeHeader), rowString(intakeHeader.map { _ in "---" }), ""]
            return lines.joined(separator: "\n")
        }
        if log.col("medicamento") == nil {
            let at = (log.col("fecha") ?? 0) + 1
            for i in log.headerLine...log.lastLine where i < lines.count && MD.isTable(lines[i]) {
                var c = MD.cells(lines[i])
                let value = i == log.headerLine ? "Medicamento" : i == log.headerLine + 1 ? "---"
                    : (DayKey.date(c.first ?? "") ?? DayKey.dmyDate(c.first ?? "")) != nil ? current.name : ""
                c.insert(value, at: min(at, c.count))
                lines[i] = rowString(c)
            }
        }
        // La lista va antes del registro, y antes de su título si lo tiene; si no lo tiene, se le pone.
        let heading = (0..<log.headerLine).last { lines[$0].hasPrefix("#") }
        let onlyGap = heading.map { h in ((h + 1)..<log.headerLine).allSatisfy { let t = lines[$0].trimmingCharacters(in: .whitespaces); return t.isEmpty || t.hasPrefix(">") } } ?? false
        if let h = heading, onlyGap { lines.insertClamped(contentsOf: listLines, at: h) }
        else { lines.insertClamped(contentsOf: listLines + ["## Registro", ""], at: log.headerLine) }
        return lines.joined(separator: "\n")
    }

    /// Añade un medicamento a la lista (pasando antes la nota al formato nuevo si hace falta).
    static func addMedication(_ text: String, _ m: Medication, current: Medication?) -> String? {
        var t = text
        if Parse.medicationTables(t).list == nil {
            guard let current else { return nil }
            t = upgradeMedicationNote(t, current: current)
        }
        guard let list = Parse.medicationTables(t).list else { return nil }
        guard !list.rows.contains(where: { MD.fold(list.value($0, "medicamento")) == MD.fold(m.name) }) else { return nil }
        var lines = MD.lines(t)
        let after = list.rows.last(where: { !($0.cells.first ?? "").isEmpty })?.line ?? (list.headerLine + 1)
        lines.insertClamped(medicationRow(m, header: list.header), at: after + 1)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Store

extension Store {
    /// Apunta una toma de `m` (por defecto hoy y con su dosis). Las inyecciones y lo que se toma una vez al día no se
    /// repiten el mismo día: se corrige la fila.
    func take(_ m: Medication, date: Date = DayKey.today(), dose: String? = nil, site: String = "", note: String = "") {
        edit(VaultPath.medicacion) {
            Edit.addIntake($0, date: date, med: m.name, dose: dose ?? (m.dose.isEmpty ? medicacion.last(of: m)?.dose ?? "" : m.dose),
                           site: site, note: note, replaceSameDay: m.isInjection || m.perDay == 1)
        }
    }

    /// Quita la última toma de `m` de ese día (desmarcar).
    func untake(_ m: Medication, on day: Date = DayKey.today()) {
        guard let d = medicacion.intakes(of: m).last(where: { $0.date == day }) else { return }
        edit(VaultPath.medicacion) { Edit.deleteLine($0, raw: d.raw, hint: d.line) }
    }

    func addMedication(_ m: Medication) {
        let current = medicacion.singleTable ? medicacion.meds.first : nil
        guard edit(VaultPath.medicacion, { Edit.addMedication($0, m, current: current) }) else {
            if medicacion.meds.contains(where: { MD.fold($0.name) == MD.fold(m.name) }) { message = "Ya hay un medicamento llamado «\(m.name)»." }
            return
        }
    }

    /// Cambia cada cuántos días toca. En una nota de antes es «cada_dias» del encabezado.
    func setEvery(_ m: Medication, days: Int) {
        if m.line < 0 { setProperty(VaultPath.medicacion, key: "cada_dias", value: String(days)); return }
        edit(VaultPath.medicacion) { Edit.setSectionCell($0, section: "Medicamentos", line: m.line, expectFirst: m.name, column: "Cada", value: Medication.everyText(days)) }
    }
}
