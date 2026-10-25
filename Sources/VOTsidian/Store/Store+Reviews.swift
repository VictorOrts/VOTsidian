import AppKit
import Foundation
import SwiftUI

// Revisiones mensual y semanal.
extension Store {
    // MARK: Revisión mensual

    func monthReviewFile(_ key: String) -> String { "\(VaultPath.revisiones)/Revisión mensual \(key).md" }

    func monthReview(_ key: String) -> WeekReview? {
        FileManager.default.fileExists(atPath: url(monthReviewFile(key)).path) ? Parse.week(read(monthReviewFile(key)), key: key) : nil
    }

    func createMonthReview(key: String, monthStart: Date) {
        let rel = monthReviewFile(key)
        guard !FileManager.default.fileExists(atPath: url(rel).path) else { return }
        // Se crea sola al abrir la pantalla: sin el aviso de «Guardado», que parecía un cambio hecho por el usuario.
        writeNote(rel, text: Template.month(key: key, monthStart: monthStart), quiet: true)
    }

    func saveMonthText(key: String, _ r: WeekReview, quiet: Bool = false) {
        edit(monthReviewFile(key), quiet: quiet) { text in
            var t: String? = text
            t = t.flatMap { Edit.setValue($0, after: "**Logros:**", value: r.logros) }
            t = t.flatMap { Edit.setValue($0, after: "**Lo que no salió:**", value: r.noSalio) }
            for i in 0..<3 { t = t.flatMap { Edit.setObjective($0, index: i, value: r.objetivos[i]) } }
            return t
        }
    }

    // MARK: Revisión semanal

    func reviewFile(_ key: String) -> String { "\(VaultPath.revisiones)/Revisión semanal \(key).md" }

    func createReview(key: String, monday: Date) {
        let rel = reviewFile(key)
        guard !FileManager.default.fileExists(atPath: url(rel).path) else { return }
        ensureBackup()
        do {
            try FileManager.default.createDirectory(at: url(VaultPath.revisiones), withIntermediateDirectories: true)
            try Template.week(key: key, monday: monday, habits: habitDefs).write(to: url(rel), atomically: true, encoding: .utf8)
        } catch { message = "No se pudo crear la revisión: \(error.localizedDescription)"; return }
        reload()
        connectWeek(key: key, monday: monday)
    }

    /// Enlaza la revisión nueva con la semana anterior (y viceversa) y con la revisión del mes, que se crea si falta.
    func connectWeek(key: String, monday: Date) {
        let name = "Revisión semanal \(key)"
        var related: [String] = []
        let prevKey = DayKey.weekKey(DayKey.adding(days: -7, to: monday))
        if reviews[prevKey] != nil {
            related.append("Revisión semanal \(prevKey)")
            edit(reviewFile(prevKey), quiet: true) { Edit.addRelated($0, links: [name]) }
        }
        let first = DayKey.calendar().dateInterval(of: .month, for: monday)!.start
        let month = String(DayKey.string(first).prefix(7))
        createMonthReview(key: month, monthStart: first)
        if monthReview(month) != nil {
            related.append("Revisión mensual \(month)")
            edit(monthReviewFile(month), quiet: true) { Edit.addRelated($0, links: [name]) }
        }
        if !related.isEmpty { edit(reviewFile(key), quiet: true) { Edit.addRelated($0, links: related) } }
    }

    /// Una nota del día nueva se enlaza con la revisión de su semana, o con el Inbox si aún no existe.
    func connectDiary(_ day: Date) {
        let key = DayKey.weekKey(day)
        let link = reviews[key] != nil ? "Revisión semanal \(key)" : "Inbox"
        edit(Store.diaryPath(day), quiet: true) { Edit.addRelated($0, links: [link]) }
    }

    /// Notas que no enlazan a ninguna ni reciben enlaces.
    func isolatedNotes() -> [NoteFile] {
        notes.filter { (outLinks[$0.path] ?? []).isEmpty && (backLinks[$0.path] ?? []).isEmpty }
    }

    func linkRelated(_ rel: String, to names: [String]) {
        edit(rel, quiet: true) { Edit.addRelated($0, links: names) }
    }

    func toggleHabit(key: String, habit: String, day: Int) {
        edit(reviewFile(key)) { Edit.toggleHabit($0, habit: habit, day: day) }
    }

    func saveReviewText(key: String, _ r: WeekReview, quiet: Bool = false) {
        edit(reviewFile(key), quiet: quiet) { text in
            var t: String? = text
            t = t.flatMap { Edit.setValue($0, after: "**Logros:**", value: r.logros) }
            t = t.flatMap { Edit.setValue($0, after: "**Lo que no salió:**", value: r.noSalio) }
            for i in 0..<3 { t = t.flatMap { Edit.setObjective($0, index: i, value: r.objetivos[i]) } }
            t = t.flatMap { Edit.setDates($0, items: r.fechas) }
            return t
        }
    }
}
