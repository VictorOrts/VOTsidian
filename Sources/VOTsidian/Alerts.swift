import Foundation

struct Alert: Identifiable, Equatable {
    enum Level: Int { case urgent = 0, soon = 1, info = 2 }
    /// Lo que se puede resolver desde el propio aviso, sin ir a la pantalla.
    enum Action: Equatable {
        case markPaid(month: String, line: Int, name: String)
        case createBudget(String)
        case injectToday
        /// Marca como hecha hoy la toma de un medicamento (por nombre).
        case take(String)

        var title: String {
            switch self {
            case .take: "Tomada"
            case .markPaid: "Pagado"
            case .createBudget: "Crear"
            case .injectToday: "Me pinché hoy"
            }
        }
    }
    var level: Level
    var icon: String
    var text: String
    var screen: Screen
    var action: Action? = nil
    /// Estable entre recálculos: SwiftUI no vuelve a pintar la lista entera cada vez que se piden los avisos.
    var id: String { "\(screen.rawValue)|\(text)" }
}

extension Store {
    /// Cosas que piden atención, de más a menos urgente.
    /// Lo mismo que `computeAlerts`, guardado hasta que cambie algo que lo afecte: la barra lateral, Inicio, Avisos y la barra de
    /// menús lo piden en cada cambio, y entre dos cambios de las notas el resultado es el mismo.
    func alerts(today: Date = DayKey.today()) -> [Alert] {
        let backupReady = dailyBackupDay == nil || backupJob.wait(timeout: .now()) == .success
        let key = "\(revision)|\(DayKey.string(today))|\(hiddenModules.map(\.rawValue).sorted())|\(backupFailure ?? "")|\(dailyBackupDay ?? "")|\(backupReady)|\(daysSinceLastBackup(today: today) ?? -1)"
        if let c = alertsCache, c.key == key { return c.alerts }
        let result = computeAlerts(today: today)
        alertsCache = (key, result)
        return result
    }

    /// Cosas que piden atención, de más a menos urgente.
    func computeAlerts(today: Date = DayKey.today()) -> [Alert] {
        var out: [Alert] = []

        // Lo periódico avisa antes y al ir tarde; lo diario, si hoy falta alguna toma.
        let main = medicacion.main
        for m in medicacion.active(on: today) where !m.asNeeded && m.every > 1 {
            guard let d = medicacion.daysUntil(m, today: today), medicacion.taken(m, on: today) == 0 else { continue }
            let action: Alert.Action = m == main ? .injectToday : .take(m.name)
            let act = m.isInjection ? "Pinchazo" : "Toma"
            if d < 0 { out.append(Alert(level: .urgent, icon: m.icon, text: "\(act) de \(m.name) con \(-d) \(-d == 1 ? "día" : "días") de retraso", screen: .medicacion, action: action)) }
            else if d == 0 { out.append(Alert(level: .urgent, icon: m.icon, text: "Hoy toca \(m.isInjection ? "el pinchazo" : "la toma") de \(m.name)", screen: .medicacion, action: action)) }
            else if d <= 2 { out.append(Alert(level: .soon, icon: m.icon, text: "\(act) de \(m.name) \(relativeDays(d))", screen: .medicacion)) }
        }
        let daily = medicacion.pending(today: today).filter { $0.med.every == 1 }
        if daily.count == 1, let p = daily.first {
            out.append(Alert(level: .info, icon: p.med.icon, text: "Hoy falta tomar \(p.med.name)" + (p.left > 1 ? " (\(p.left) tomas)" : ""), screen: .medicacion, action: .take(p.med.name)))
        } else if daily.count > 1 {
            out.append(Alert(level: .info, icon: "pills", text: "Hoy falta tomar: \(daily.map(\.med.name).joined(separator: ", "))", screen: .medicacion))
        }
        if let l = weight.last {
            let days = DayKey.days(from: l.date, to: today)
            if days > 31 { out.append(Alert(level: .soon, icon: "scalemass", text: "Hace \(days) días que no registras el peso", screen: .peso)) }
        }
        let overdue = tasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) }
        if !overdue.isEmpty { out.append(Alert(level: .urgent, icon: "checklist", text: "\(overdue.count) \(overdue.count == 1 ? "tarea vencida" : "tareas vencidas")", screen: .tareas)) }
        let dueToday = tasks.filter { !$0.done && $0.due == today }
        if !dueToday.isEmpty { out.append(Alert(level: .soon, icon: "checklist", text: "\(dueToday.count) \(dueToday.count == 1 ? "tarea" : "tareas") para hoy", screen: .tareas)) }

        for t in tasks where !t.done && t.file == VaultPath.medico {
            guard let due = t.due else { continue }
            let n = DayKey.days(from: today, to: due)
            if n >= 0, n <= 7 { out.append(Alert(level: n <= 1 ? .urgent : .soon, icon: "cross.case", text: "\(t.text) \(relativeDays(n))" + (t.time.map { " a las \(TimeOfDay.text($0))" } ?? ""), screen: .salud)) }
        }
        for d in documents {
            let n = DayKey.days(from: today, to: d.date)
            if n < 0 { out.append(Alert(level: .urgent, icon: "doc.on.doc", text: "\(d.name) caducó el \(DayKey.dmy(d.date))", screen: .documentos)) }
            else if n <= 30 { out.append(Alert(level: .soon, icon: "doc.on.doc", text: "\(d.name) caduca \(relativeDays(n))", screen: .documentos)) }
        }
        for p in people {
            if let b = p.nextBirthday(from: today) {
                let n = DayKey.days(from: today, to: b.date)
                if n <= 7 { out.append(Alert(level: n == 0 ? .urgent : .info, icon: "gift", text: "Cumpleaños de \(p.name) \(relativeDays(n))" + (b.age.map { " (\($0) años)" } ?? ""), screen: .personas)) }
            }
        }
        for o in mascota.overdue { out.append(Alert(level: .soon, icon: "pawprint", text: "\(mascota.name): \(o.title) vencida el \(DayKey.dmy(o.date))", screen: .mascota)) }
        for u in mascota.upcoming.prefix(2) {
            let n = DayKey.days(from: today, to: u.date)
            if n <= 14 { out.append(Alert(level: .info, icon: "pawprint", text: "\(mascota.name): \(u.title) \(relativeDays(n))", screen: .mascota)) }
        }
        out += vehiculoAlerts(today: today) + suscripcionAlerts(today: today) + prestamoAlerts(today: today) + viajeAlerts(today: today) + tramiteAlerts(today: today)
        for e in events {
            let n = DayKey.days(from: today, to: e.date)
            if n >= 0, n <= 14, noteMeta[e.path]?["estado"] != "pagado" {
                out.append(Alert(level: .info, icon: "party.popper", text: "\(e.name) \(relativeDays(n))", screen: .finanzas))
            }
        }
        out += budgetAlerts(today: today)
        // Solo en la app (la que hace copias al abrir): un fallo de hoy o una copia demasiado vieja.
        if let f = backupFailure {
            out.append(Alert(level: .urgent, icon: "externaldrive.badge.exclamationmark", text: f, screen: .ajustes))
        } else if dailyBackupDay != nil, backupJob.wait(timeout: .now()) == .success, let days = daysSinceLastBackup(today: today), days > 2 {
            out.append(Alert(level: .soon, icon: "externaldrive.badge.exclamationmark", text: "La última copia de seguridad es de hace \(days) días", screen: .ajustes))
        }
        if !pendingDownloads.isEmpty { out.append(Alert(level: .soon, icon: "icloud.and.arrow.down", text: "\(pendingDownloads.count) archivos de iCloud sin descargar en este Mac (no entran en las copias)", screen: .ajustes)) }
        if !unreadableFiles.isEmpty { out.append(Alert(level: .soon, icon: "exclamationmark.triangle", text: "\(unreadableFiles.count) \(unreadableFiles.count == 1 ? "nota no se puede leer" : "notas no se pueden leer"): \(unreadableFiles.prefix(2).joined(separator: ", "))", screen: .ajustes)) }
        let conflicts = conflictCopies
        if !conflicts.isEmpty {
            out.append(Alert(level: .soon, icon: "exclamationmark.triangle", text: "\(conflicts.count) \(conflicts.count == 1 ? "posible copia en conflicto" : "posibles copias en conflicto") de iCloud: \(conflicts.prefix(2).map(\.name).joined(separator: ", "))", screen: .notas))
        }
        // Revisión mensual: los dos últimos días del mes y los tres primeros del siguiente, mientras siga vacía.
        let cal = DayKey.calendar()
        let dayOfMonth = cal.component(.day, from: today), monthDays = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        if let month = dayOfMonth >= monthDays - 1 ? today : dayOfMonth <= 3 ? DayKey.adding(days: -dayOfMonth, to: today) : nil {
            let key = Budget.monthKey(month)
            let r = monthReview(key)
            if (r?.logros ?? "").isEmpty, (r?.noSalio ?? "").isEmpty {
                out.append(Alert(level: .info, icon: "calendar.badge.clock", text: "Revisión mensual de \(Budget.title(key).lowercased()) sin hacer", screen: .mes))
            }
        }
        let wk = DayKey.weekKey(today)
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: today)
        if let r = reviews[wk], r.totalDone == 0, weekday == 1 || weekday >= 5 {
            out.append(Alert(level: .info, icon: "calendar.badge.checkmark", text: "Sin hábitos marcados en la semana \(wk.suffix(3))", screen: .semana))
        }
        // Dos avisos iguales (mismo texto y pantalla) son uno: además comparten id. Los de módulos ocultos no salen.
        var seen = Set<String>()
        return out.filter { isVisible($0.screen) && seen.insert($0.id).inserted }.sorted { $0.level.rawValue < $1.level.rawValue }
    }
}

extension Store {
    /// Lo que vence del vehículo (ITV, seguro…) y los mantenimientos a los que les toca o les falta poco.
    func vehiculoAlerts(today: Date = DayKey.today()) -> [Alert] {
        let v = vehiculo
        var out: [Alert] = []
        for d in v.dues {
            let n = DayKey.days(from: today, to: d.date)
            if n < 0 { out.append(Alert(level: .urgent, icon: "car", text: "\(v.name): \(d.name) venció el \(DayKey.dmy(d.date))", screen: .vehiculo)) }
            else if n <= 30 { out.append(Alert(level: .soon, icon: "car", text: "\(v.name): \(d.name) vence \(relativeDays(n))", screen: .vehiculo)) }
        }
        for s in v.nextServices(today: today) where s.isDue || s.isSoon {
            out.append(Alert(level: s.isDue ? .urgent : .soon, icon: "wrench.and.screwdriver", text: "\(v.name): \(s.what) \(Vehiculo.dueText(s))", screen: .vehiculo))
        }
        return out
    }
}

extension Store {
    /// Notas que iCloud duplicó al detectar dos versiones: «Nota 2.md» junto a «Nota.md» (o «… copia en conflicto»).
    var conflictCopies: [NoteFile] {
        let existing = Set(notes.map(\.path))
        return notes.filter { Store.isConflictCopy($0.path, existing: existing) }
    }

    static func isConflictCopy(_ path: String, existing: Set<String>) -> Bool {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let dir = (path as NSString).deletingLastPathComponent
        func sibling(_ n: String) -> String { (dir.isEmpty ? "" : dir + "/") + n + ".md" }
        let folded = MD.fold(name)
        if folded.contains("conflicted copy") || folded.contains("copia en conflicto") { return true }
        guard let space = name.lastIndex(of: " "), let n = Int(name[name.index(after: space)...]), n >= 2 else { return false }
        return existing.contains(sibling(String(name[..<space])))
    }
}

extension Store {
    /// Números de la barra lateral. Se calculan una vez por recarga, no en cada pintado.
    func sidebarCounts(today: Date = DayKey.today()) -> [Screen: Int] {
        var out: [Screen: Int] = [:]
        out[.tareas] = tasks.filter { !$0.done && ($0.due.map { $0 <= today } ?? false) }.count
        out[.compra] = shoppingItems.filter { !$0.done }.count
        out[.avisos] = alerts(today: today).filter { $0.level != .info }.count
        out[.enlaces] = brokenLinkCount
        if let d = medicacion.daysUntilNext, d <= 0 { out[.medicacion] = 1 }
        return out.filter { $0.value > 0 }
    }

    /// Cuántos enlaces no llevan a nada. Versión barata de `brokenLinks()`: usa los enlaces ya analizados y no busca sugerencias.
    var brokenLinkCount: Int {
        if let c = brokenCountCache, c.revision == revision { return c.count }
        let n = countBrokenLinks()
        brokenCountCache = (revision, n)
        return n
    }

    private func countBrokenLinks() -> Int {
        var n = 0
        for note in notes {
            let names = fileCache[note.path]?.parsed.links ?? Links.extract(noteTexts[note.path] ?? "")
            n += Set(names).filter { resolve($0) == nil && attachmentURL($0) == nil && screenAlias($0) == nil }.count
        }
        return n
    }
}

extension Store {
    /// Pagos del mes en curso: los que tocaban y no están marcados, los de hoy y mañana, y si el mes va a cerrar en negativo.
    func budgetAlerts(today: Date = DayKey.today()) -> [Alert] {
        let month = Budget.monthKey(today)
        guard let b = budget(month) else {
            // Hay presupuestos pero no el de este mes: se avisa una vez entrado el mes.
            if let last = budgetMonths.last, last < month, DayKey.calendar().component(.day, from: today) >= 2 {
                return [Alert(level: .info, icon: "creditcard", text: "Crea el presupuesto de \(Budget.title(month).lowercased())", screen: .gastos, action: .createBudget(month))]
            }
            return []
        }
        var out: [Alert] = []
        let day = DayKey.calendar().component(.day, from: today)
        for l in b.lines where !l.isDiscretionary && l.isDue(month) && !l.paid && b.real(l) == 0 && l.planned > 0 {
            guard let d = l.day else { continue }
            let paid = Alert.Action.markPaid(month: month, line: l.line, name: l.name)
            if d < day { out.append(Alert(level: .soon, icon: "creditcard", text: "\(l.name) (\(Money.format(l.planned)), día \(d)) sin marcar como pagado", screen: .gastos, action: paid)) }
            else if d == day { out.append(Alert(level: .soon, icon: "creditcard", text: "Hoy se paga \(l.name) (\(Money.format(l.planned)))", screen: .gastos, action: paid)) }
            else if d == day + 1 { out.append(Alert(level: .info, icon: "creditcard", text: "Mañana se paga \(l.name) (\(Money.format(l.planned)))", screen: .gastos, action: paid)) }
        }
        let s = BudgetStatus(b, today: today)
        if s.day >= 5, s.endLeft < -20 {
            out.append(Alert(level: .soon, icon: "creditcard", text: "A este ritmo el mes acabará en \(Money.format(s.endLeft))", screen: .gastos))
        }
        return out
    }
}

extension Store {
    /// Hace lo que propone un aviso. Devuelve `false` si ya no se puede (la nota cambió).
    @discardableResult
    func perform(_ action: Alert.Action) -> Bool {
        switch action {
        case .markPaid(let month, let line, let name):
            guard let b = budget(month), b.lines.contains(where: { $0.line == line && $0.name == name }) else { return false }
            setBudgetCell(b, section: "Partidas", line: line, name: name, column: "Pagado", value: "✅")
        case .createBudget(let month): return createBudget(month)
        case .injectToday: injectToday()
        case .take(let name):
            guard let m = medicacion.meds.first(where: { $0.name == name }) else { return false }
            take(m)
        }
        return true
    }

    /// Pagos fijos con día del mes en curso y del siguiente que aún no están pagados, para Calendar y las notificaciones.
    func upcomingPayments(today: Date = DayKey.today()) -> [(name: String, date: Date, amount: Double, saving: Bool)] {
        guard let m = BudgetLine.monthIndex(Budget.monthKey(today)) else { return [] }
        var out: [(name: String, date: Date, amount: Double, saving: Bool)] = []
        for month in [BudgetLine.month(m), BudgetLine.month(m + 1)] {
            // El mes que viene puede no tener nota aún: se usan las partidas de este, con sus frecuencias.
            guard let b = budget(month) ?? budget(BudgetLine.month(m)).map({ Parse.budget(Edit.budgetNote(month: month, from: $0), month: month, path: "") }),
                  let first = Budget.firstDay(month), let days = DayKey.calendar().range(of: .day, in: .month, for: first)?.count else { continue }
            for l in b.lines where !l.isDiscretionary && l.isDue(month) && !l.paid && b.real(l) == 0 && l.planned > 0 {
                guard let d = l.day, let date = DayKey.make(DayKey.calendar().component(.year, from: first), DayKey.calendar().component(.month, from: first), min(d, days)),
                      date >= today else { continue }
                out.append((l.name, date, l.planned, l.kind == .ahorro))
            }
        }
        return out.sorted { $0.date < $1.date }
    }
}
