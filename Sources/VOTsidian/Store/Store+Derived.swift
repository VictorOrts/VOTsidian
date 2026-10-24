import AppKit
import Foundation
import SwiftUI

// Datos derivados, copias manuales y acciones sobre archivos del vault.
extension Store {
    // MARK: Datos derivados

    /// Lo que puede avisar en Calendar y en las notificaciones. Los módulos ocultos no avisan.
    func reminderSources() -> ReminderSources {
        var casaDates: [(name: String, date: Date)] = []
        for t in isVisible(.casa) ? [casa.reformas, casa.compras] : [] {
            for r in t.rows {
                if let d = DayKey.date(t.value(r, "Cuándo")), let n = r.cells.first, !n.isEmpty { casaDates.append((n, d)) }
            }
        }
        for t in isVisible(.moda) ? Parse.tables(read(VaultPath.moda)) : [] where MD.fold(t.title).contains("por comprar") {
            for r in t.rows where !MD.fold(t.value(r, "estado")).contains("comprado") && !MD.fold(t.value(r, "estado")).contains("descartado") {
                if let d = DayKey.date(t.value(r, "fecha objetivo")), let n = r.cells.first, !n.isEmpty { casaDates.append(("Comprar: " + n, d)) }
            }
        }
        return ReminderSources(medicacion: isVisible(.medicacion) ? medicacion : MedicacionData(), tasks: tasks,
                               mascota: isVisible(.mascota) ? mascota : MascotaData(), vehiculo: isVisible(.vehiculo) ? vehiculo : VehiculoData(),
                               suscripciones: isVisible(.suscripciones) ? suscripciones : SuscripcionesData(),
                               prestamos: isVisible(.prestamos) ? prestamos : PrestamosData(),
                               viajes: isVisible(.viajes) ? viajes : ViajesData(),
                               tramites: isVisible(.tramites) ? tramites : TramitesData(), people: isVisible(.personas) ? people : [],
                               documents: isVisible(.documentos) ? documents.map { ($0.name, $0.date) } : [],
                               events: (isVisible(.finanzas) ? events.map { ($0.name, $0.date) } : []) + casaDates,
                               payments: isVisible(.gastos) ? upcomingPayments() : [])
    }

    /// El plan de avisos sin lo de los módulos ocultos que no depende de sus notas (el pesaje mensual).
    func reminderPlan(_ plan: ReminderPlan = .stored) -> ReminderPlan {
        var p = plan
        if !isVisible(.peso) { p.monthlyWeight = false }
        return p
    }

    /// Abre un enlace `votsidian://note/Nombre`: salta a la nota o abre el adjunto con su programa.
    func open(link url: URL) -> OpenURLAction.Result {
        guard url.scheme == "votsidian", let target = url.lastPathComponent.removingPercentEncoding else { return .systemAction }
        if let p = fuzzyResolve(target) {
            // Las notas que tienen pantalla propia abren esa pantalla; el resto, el lector de notas.
            let screens: [String: Screen] = [VaultPath.peso: .peso, VaultPath.medicacion: .medicacion, VaultPath.plan: .nutricion, VaultPath.casa: .casa,
                                             VaultPath.mascota: .mascota, VaultPath.vehiculo: .vehiculo, VaultPath.suscripciones: .suscripciones, VaultPath.prestamos: .prestamos,
                                             VaultPath.lecturas: .lecturas, VaultPath.viajes: .viajes, VaultPath.tramites: .tramites, VaultPath.moda: .moda, VaultPath.medico: .salud, VaultPath.inbox: .tareas,
                                             VaultPath.personas: .personas, VaultPath.documentos: .documentos,
                                             VaultPath.objetivos: .objetivos, VaultPath.finanzas: .finanzas]
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
        edit(VaultPath.medicacion) { Edit.addDose($0, date: date, dose: dose, site: site, note: note, med: medicacion.main?.name ?? "") }
    }

    func addMascotaVisit(date: Date, tipo: String, detalle: String, proxima: Date?, coste: String) {
        edit(VaultPath.mascota) { Edit.addMascotaVisit($0, date: date, tipo: tipo, detalle: detalle, proxima: proxima, coste: coste) }
    }

    func setTask(_ task: TaskItem, done: Bool) {
        if done, task.recurrence != nil {
            edit(task.file) { Edit.completeRecurring($0, task: task) }
        } else {
            edit(task.file) { Edit.setTask($0, task: task, done: done) }
        }
    }

    /// En una carpeta nueva el Inbox no existe: se crea antes de la primera tarea o idea.
    private func ensureInbox() {
        guard !FileManager.default.fileExists(atPath: url(VaultPath.inbox).path) else { return }
        writeNote(VaultPath.inbox, text: "# Inbox\n\n## Pendiente de clasificar\n\n## Ideas\n")
    }

    func addTask(_ text: String, due: Date?, recurrence: String? = nil, priority: Int = 0, time: Int? = nil, muted: Bool = false, duration: Int? = nil) {
        ensureInbox()
        edit(VaultPath.inbox) { Edit.addInboxTask($0, task: text, due: due, recurrence: recurrence, priority: priority, time: time, muted: muted, duration: duration) }
    }

    /// Guarda una tarea escrita en lenguaje natural con todo lo que se entendió: fecha (o `defaultDue`), hora, repetición,
    /// prioridad y «sin aviso». Devuelve el mensaje de confirmación. Todas las entradas rápidas pasan por aquí, para que
    /// ninguna se deje la hora por el camino.
    @discardableResult
    func addTask(_ p: NaturalDate.ParsedTask, defaultDue: Date? = nil) -> String {
        // Solo con hora («llamar a Ana a las 18:00») es para hoy.
        let due = p.date ?? defaultDue ?? (p.time != nil ? DayKey.today() : nil)
        addTask(p.text, due: due, recurrence: p.recurrence, priority: p.priority, time: due == nil ? nil : p.time, muted: p.muted, duration: p.duration)
        return (due.map { "Añadida para \(longDate($0))" } ?? "Añadida al Inbox") + (due != nil ? p.time.map { " a las \(TimeOfDay.text($0))" } ?? "" : "")
            + (p.duration.map { " · \(TaskDuration.human($0))" } ?? "") + (p.recurrence.map { " · \(Recurrence.describe($0))" } ?? "") + (p.muted ? " · sin aviso" : "")
    }

    /// Una cita médica en «Próximas citas» de Médico, con hora si se sabe. Desde Salud, el Calendario y ⌘K.
    func addAppointment(_ text: String, date: Date, time: Int? = nil) {
        edit(VaultPath.medico) { Edit.appendToSection($0, section: "Próximas citas", line: Edit.taskLine(text, due: date, time: time)) }
    }

    /// Registra la toma de hoy del medicamento periódico, con su última dosis y, si es inyección, el lado contrario al anterior.
    func injectToday(date: Date = DayKey.today(), note: String = "") {
        guard let m = medicacion.main else { message = "No hay ningún medicamento periódico en \(VaultPath.medicacion)."; return }
        take(m, date: date, dose: medicacion.last?.dose ?? m.dose, site: m.isInjection ? medicacion.suggestedSite : "", note: note)
    }

    /// Modo "añadir fila" detrás de la fila `last` de una tabla.
    func addMode(file: String, afterRowLine last: Int) -> RowSpec.Mode {
        let lines = MD.lines(read(file))
        let h = last < lines.count ? MD.tableHeaderLine(lines, containing: last) : last
        return .add(afterLine: last, headerLine: h)
    }

    /// Añade varias tareas al Inbox en un solo cambio; omite las que ya existen.
    func addTasks(_ items: [(String, Date?)]) {
        ensureInbox()
        edit(VaultPath.inbox) { text in
            var out: String? = text
            // Se mira el texto que se va formando: así tampoco se repiten las que vienen dos veces en `items`.
            for (t, due) in items {
                guard let cur = out, !cur.contains("- [ ] \(t)") else { continue }
                out = Edit.addInboxTask(cur, task: t, due: due)
            }
            return out
        }
    }

    func addIdea(_ text: String) {
        ensureInbox()
        edit(VaultPath.inbox) { Edit.appendToSection($0, section: "Ideas", line: "- \(text)") ?? Edit.appendToSectionCreating($0, section: "Ideas", lines: ["- \(text)"]) }
    }

    /// Copia manual, con hora en el nombre. No se borra sola.
    @discardableResult
    func backupNow() -> URL? {
        try? FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let name = "\(vaultName)-manual-\(Store.stamp("yyyy-MM-dd-HHmm"))"
        let password = backupPassword
        let dest = backupsFolder.appendingPathComponent(password == nil ? name : "\(name).\(EncryptedBackup.ext)")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return dest }
        let src = root
        message = nil
        // La copia (y el cifrado) corren fuera del hilo principal; la carpeta o el .dmg aparece al terminar.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = Store.makeBackup(from: src, to: dest, password: password)
            DispatchQueue.main.async { if !ok { self?.message = "No se pudo crear la copia." }; self?.backupsStamp += 1 }
        }
        return dest
    }

    func allBackups() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ($0.hasDirectoryPath || $0.pathExtension == EncryptedBackup.ext) && !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func addCasaRow(section: String, cells: [String]) {
        edit(VaultPath.casa) { Edit.addRow($0, section: section, cells: cells) }
    }

    func setCasaCell(section: String, row: TableRow, column: String, value: String) {
        edit(VaultPath.casa) { Edit.setSectionCell($0, section: section, line: row.line, expectFirst: row.cells.first ?? "", column: column, value: value) }
    }
}
