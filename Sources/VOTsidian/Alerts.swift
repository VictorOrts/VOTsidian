import Foundation

struct Alert: Identifiable {
    enum Level: Int { case urgent = 0, soon = 1, info = 2 }
    var id = UUID()
    var level: Level
    var icon: String
    var text: String
    var screen: Screen
}

extension Store {
    /// Cosas que piden atención, de más a menos urgente.
    func alerts(today: Date = DayKey.today()) -> [Alert] {
        var out: [Alert] = []

        if let d = mounjaro.daysUntilNext {
            if d < 0 { out.append(Alert(level: .urgent, icon: "syringe", text: "Pinchazo de Mounjaro con \(-d) \(-d == 1 ? "día" : "días") de retraso", screen: .mounjaro)) }
            else if d == 0 { out.append(Alert(level: .urgent, icon: "syringe", text: "Hoy toca el pinchazo de Mounjaro", screen: .mounjaro)) }
            else if d <= 2 { out.append(Alert(level: .soon, icon: "syringe", text: "Pinchazo de Mounjaro \(relativeDays(d))", screen: .mounjaro)) }
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
            if n >= 0, n <= 7 { out.append(Alert(level: n <= 1 ? .urgent : .soon, icon: "cross.case", text: "\(t.text) \(relativeDays(n))", screen: .salud)) }
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
        for o in nala.overdue { out.append(Alert(level: .soon, icon: "cat", text: "\(nala.name): \(o.title) vencida el \(DayKey.dmy(o.date))", screen: .nala)) }
        for u in nala.upcoming.prefix(2) {
            let n = DayKey.days(from: today, to: u.date)
            if n <= 14 { out.append(Alert(level: .info, icon: "cat", text: "\(nala.name): \(u.title) \(relativeDays(n))", screen: .nala)) }
        }
        for e in events {
            let n = DayKey.days(from: today, to: e.date)
            if n >= 0, n <= 14, noteMeta[e.path]?["estado"] != "pagado" {
                out.append(Alert(level: .info, icon: "party.popper", text: "\(e.name) \(relativeDays(n))", screen: .finanzas))
            }
        }
        if !pendingDownloads.isEmpty { out.append(Alert(level: .soon, icon: "icloud.and.arrow.down", text: "\(pendingDownloads.count) archivos de iCloud sin descargar en este Mac (no entran en las copias)", screen: .ajustes)) }
        if !unreadableFiles.isEmpty { out.append(Alert(level: .soon, icon: "exclamationmark.triangle", text: "\(unreadableFiles.count) \(unreadableFiles.count == 1 ? "nota no se puede leer" : "notas no se pueden leer"): \(unreadableFiles.prefix(2).joined(separator: ", "))", screen: .ajustes)) }
        let conflicts = conflictCopies
        if !conflicts.isEmpty {
            out.append(Alert(level: .soon, icon: "exclamationmark.triangle", text: "\(conflicts.count) \(conflicts.count == 1 ? "posible copia en conflicto" : "posibles copias en conflicto") de iCloud: \(conflicts.prefix(2).map(\.name).joined(separator: ", "))", screen: .notas))
        }
        let wk = DayKey.weekKey(today)
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: today)
        if let r = reviews[wk], r.totalDone == 0, weekday == 1 || weekday >= 5 {
            out.append(Alert(level: .info, icon: "calendar.badge.checkmark", text: "Sin hábitos marcados en la semana \(wk.suffix(3))", screen: .semana))
        }
        return out.sorted { $0.level.rawValue < $1.level.rawValue }
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
