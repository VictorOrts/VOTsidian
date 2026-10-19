import AppKit
import Foundation
import SwiftUI

// Datos derivados, copias manuales y acciones sobre archivos del vault.
extension Store {
    // MARK: Datos derivados

    func reminderSources() -> ReminderSources {
        var casaDates: [(name: String, date: Date)] = []
        for t in [casa.reformas, casa.compras] {
            for r in t.rows {
                if let d = DayKey.date(t.value(r, "Cuándo")), let n = r.cells.first, !n.isEmpty { casaDates.append((n, d)) }
            }
        }
        for t in Parse.tables(read(VaultPath.moda)) where MD.fold(t.title).contains("por comprar") {
            for r in t.rows where !MD.fold(t.value(r, "estado")).contains("comprado") && !MD.fold(t.value(r, "estado")).contains("descartado") {
                if let d = DayKey.date(t.value(r, "fecha objetivo")), let n = r.cells.first, !n.isEmpty { casaDates.append(("Comprar: " + n, d)) }
            }
        }
        return ReminderSources(mounjaro: mounjaro, tasks: tasks, nala: nala, people: people,
                               documents: documents.map { ($0.name, $0.date) },
                               events: events.map { ($0.name, $0.date) } + casaDates)
    }

    /// Abre un enlace `votsidian://note/Nombre`: salta a la nota o abre el adjunto con su programa.
    func open(link url: URL) -> OpenURLAction.Result {
        guard url.scheme == "votsidian", let target = url.lastPathComponent.removingPercentEncoding else { return .systemAction }
        if let p = fuzzyResolve(target) {
            // Las notas que tienen pantalla propia abren esa pantalla; el resto, el lector de notas.
            let screens: [String: Screen] = [VaultPath.peso: .peso, VaultPath.mounjaro: .mounjaro, VaultPath.plan: .nutricion, VaultPath.casa: .casa,
                                             VaultPath.nala: .nala, VaultPath.moda: .moda, VaultPath.medico: .salud, VaultPath.inbox: .tareas,
                                             "Organización/Personas.md": .personas, "Organización/Documentos.md": .documentos,
                                             "Organización/Objetivos.md": .objetivos, "Finanzas/Finanzas.md": .finanzas]
            if let sc = screens[p] { screen = sc } else { pendingNote = p }
        } else if let a = attachmentURL(target) { NSWorkspace.shared.open(a) }
        else if let sc = screenAlias(target) { screen = sc }
        return .handled
    }

    func attachmentURL(_ name: String) -> URL? {
        attachments[MD.fold((name as NSString).lastPathComponent)].map { url($0) }
    }

    func addWeight(date: Date, kg: Double, note: String) {
        edit(VaultPath.peso) { Edit.addWeight($0, date: date, kg: kg, note: note) }
    }

    func addDose(date: Date, dose: Double, site: String, note: String) {
        edit(VaultPath.mounjaro) { Edit.addDose($0, date: date, dose: dose, site: site, note: note) }
    }

    func addNalaVisit(date: Date, tipo: String, detalle: String, proxima: Date?, coste: String) {
        edit(VaultPath.nala) { Edit.addNalaVisit($0, date: date, tipo: tipo, detalle: detalle, proxima: proxima, coste: coste) }
    }

    func setTask(_ task: TaskItem, done: Bool) {
        if done, task.recurrence != nil {
            edit(task.file) { Edit.completeRecurring($0, task: task) }
        } else {
            edit(task.file) { Edit.setTask($0, task: task, done: done) }
        }
    }

    func addTask(_ text: String, due: Date?, recurrence: String? = nil, priority: Int = 0) {
        edit(VaultPath.inbox) { Edit.addInboxTask($0, task: text, due: due, recurrence: recurrence, priority: priority) }
    }

    /// Registra el pinchazo de hoy con la última dosis y el lado contrario al anterior.
    func injectToday() {
        addDose(date: DayKey.today(), dose: mounjaro.last?.mg ?? 7.5, site: mounjaro.suggestedSite, note: "")
    }

    /// Modo "añadir fila" detrás de la fila `last` de una tabla.
    func addMode(file: String, afterRowLine last: Int) -> RowSpec.Mode {
        let lines = MD.lines(read(file))
        let h = last < lines.count ? MD.tableHeaderLine(lines, containing: last) : last
        return .add(afterLine: last, headerLine: h)
    }

    /// Añade varias tareas al Inbox en un solo cambio; omite las que ya existen.
    func addTasks(_ items: [(String, Date?)]) {
        edit(VaultPath.inbox) { text in
            var out: String? = text
            for (t, due) in items where !text.contains("- [ ] \(t)") { out = out.flatMap { Edit.addInboxTask($0, task: t, due: due) } }
            return out
        }
    }

    func addIdea(_ text: String) {
        edit(VaultPath.inbox) { Edit.appendToSection($0, section: "Ideas", line: "- \(text)") }
    }

    /// Copia manual, con hora en el nombre. No se borra sola.
    @discardableResult
    func backupNow() -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let dest = backupsFolder.appendingPathComponent("\(vaultName)-manual-\(Store.stamp("yyyy-MM-dd-HHmm"))")
        do { try fm.copyItem(at: root, to: dest); message = nil; return dest }
        catch { message = "No se pudo crear la copia: \(error.localizedDescription)"; return nil }
    }

    func allBackups() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func addCasaRow(section: String, cells: [String]) {
        edit(VaultPath.casa) { Edit.addRow($0, section: section, cells: cells) }
    }

    func setCasaCell(section: String, row: TableRow, column: String, value: String) {
        edit(VaultPath.casa) { Edit.setSectionCell($0, section: section, line: row.line, expectFirst: row.cells.first ?? "", column: column, value: value) }
    }
}
