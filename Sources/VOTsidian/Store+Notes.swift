import AppKit
import Foundation
import SwiftUI

// Notas y plantillas del usuario: crear, borrar, renombrar.
extension Store {
    // MARK: Notas

    /// Guarda el texto completo de una nota (editor).
    @discardableResult
    func writeNote(_ rel: String, text: String, quiet: Bool = false) -> Bool {
        let u = url(rel)
        // Si el archivo existe pero no se puede leer, no se sobrescribe: no sabríamos qué se pierde ni cómo deshacerlo.
        let exists = FileManager.default.fileExists(atPath: u.path)
        let previous = exists ? readOptional(rel) : nil
        if exists, previous == nil { message = "No pude leer \(rel). No se modificó."; return false }
        ensureBackup()
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
            message = nil
            record(rel, previous: previous, written: text, quiet: quiet)
        } catch { message = "No se pudo guardar \(rel): \(error.localizedDescription)"; return false }
        if exists { reload(changed: [rel]) } else { reload() }
        return true
    }

    // MARK: Plantillas del usuario (carpeta Plantillas)

    static let templatesFolder = "Plantillas"

    func userTemplates() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url(Store.templatesFolder), includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".") }
            .map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    struct TemplateQuestion: Identifiable, Equatable {
        var label: String
        var defaultValue: String
        var id: String { label }
    }

    /// Preguntas de una plantilla: `{{?Con quién}}` o `{{?Estado|pendiente}}` (con valor por defecto), sin repetir.
    func templateQuestions(_ name: String) -> [TemplateQuestion] {
        guard let raw = try? String(contentsOf: url("\(Store.templatesFolder)/\(name).md"), encoding: .utf8) else { return [] }
        var seen = Set<String>()
        return raw.matches(of: /\{\{\?([^}|]+)(?:\|([^}]*))?\}\}/).compactMap { m in
            let label = String(m.1).trimmingCharacters(in: .whitespaces)
            guard seen.insert(label).inserted else { return nil }
            return TemplateQuestion(label: label, defaultValue: m.2.map(String.init) ?? "")
        }
    }

    /// Texto de una plantilla del usuario con sus variables resueltas y su carpeta sugerida.
    func userTemplate(_ name: String, title: String, answers: [String: String] = [:]) -> (body: String, folder: String)? {
        guard var raw = try? String(contentsOf: url("\(Store.templatesFolder)/\(name).md"), encoding: .utf8) else { return nil }
        for m in raw.matches(of: /\{\{\?([^}|]+)(?:\|([^}]*))?\}\}/).reversed() {
            let label = String(m.1).trimmingCharacters(in: .whitespaces)
            let value = answers[label].flatMap { $0.isEmpty ? nil : $0 } ?? m.2.map(String.init) ?? ""
            raw.replaceSubrange(m.range, with: value)
        }
        let now = Date()
        var body = raw.replacingOccurrences(of: "{{titulo}}", with: title)
            .replacingOccurrences(of: "{{fecha}}", with: DayKey.string(now))
            .replacingOccurrences(of: "{{hora}}", with: Store.stamp("HH:mm"))
            .replacingOccurrences(of: "{{dia}}", with: DayKey.esLong(now, .dateTime.weekday(.wide)))
            .replacingOccurrences(of: "{{semana}}", with: DayKey.weekKey(now))
        var folder = ""
        var lines = MD.lines(body)
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for i in stride(from: end - 1, through: 1, by: -1) where lines[i].hasPrefix("plantilla_carpeta:") {
                folder = lines[i].dropFirst("plantilla_carpeta:".count).trimmingCharacters(in: .whitespaces)
                lines.remove(at: i)
            }
            body = lines.joined(separator: "\n")
        }
        return (body, folder)
    }

    func createSampleTemplates() {
        let samples: [(String, String)] = [
            ("Reunión", "---\nplantilla_carpeta: Proyectos\ntipo: reunion\nfecha: {{fecha}}\ntags:\n  - reunion\n---\n\n# {{titulo}}\n\n**Fecha:** {{fecha}} {{hora}}\n**Con:** {{?Con quién}}\n\n## Temas\n- \n\n## Decisiones\n- \n\n## Tareas\n- [ ] \n"),
            ("Lectura", "---\ntipo: lectura\nautor: {{?Autor}}\nestado: {{?Estado|pendiente}}\nvaloracion: \ntags:\n  - lectura\n---\n\n# {{titulo}}\n\n## Por qué quiero leerlo\n\n## Notas\n- \n\n## Frases\n> \n"),
            ("Idea", "---\ntipo: idea\nfecha: {{fecha}}\ntags:\n  - idea\n---\n\n# {{titulo}}\n\n## La idea\n\n## Para qué sirve\n\n## Primer paso\n- [ ] \n"),
            ("Viaje", "---\nplantilla_carpeta: Proyectos\ntipo: viaje\nestado: idea\nfecha_inicio: {{?Fecha de salida (AAAA-MM-DD)}}\nfecha_fin: {{?Fecha de vuelta (AAAA-MM-DD)}}\ntags:\n  - viaje\n---\n\n# {{titulo}}\n\n**Destino:** {{?Destino}}\n\n## Plan\n- \n\n## Reservas\n- [ ] Alojamiento\n- [ ] Transporte\n\n## Presupuesto\n| Concepto | Importe |\n| :--- | ---: |\n|  |  |\n"),
        ]
        do {
            try FileManager.default.createDirectory(at: url(Store.templatesFolder), withIntermediateDirectories: true)
            for (n, t) in samples where !FileManager.default.fileExists(atPath: url("\(Store.templatesFolder)/\(n).md").path) {
                try t.write(to: url("\(Store.templatesFolder)/\(n).md"), atomically: true, encoding: .utf8)
            }
        } catch { message = "No se pudieron crear las plantillas: \(error.localizedDescription)" }
        reload()
    }

    func createNote(folder: String, name: String, template: String, answers: [String: String] = [:]) -> String? {
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let rel = (folder.isEmpty ? "" : folder + "/") + clean + ".md"
        guard !FileManager.default.fileExists(atPath: url(rel).path) else { message = "Ya existe una nota llamada \(clean) en esa carpeta."; return nil }
        let body = NoteTemplates.names.contains(template) ? NoteTemplates.body(template, title: clean) : (userTemplate(template, title: clean, answers: answers)?.body ?? NoteTemplates.body("En blanco", title: clean))
        return writeNote(rel, text: body) ? rel : nil
    }

    /// Mueve la nota a la papelera y convierte en texto los enlaces que apuntaban a ella.
    func trashNote(_ rel: String) {
        ensureBackup()
        let name = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
        pinned.removeAll { $0 == rel }
        fileCache.removeAll()
        var trashed: NSURL?
        do { try FileManager.default.trashItem(at: url(rel), resultingItemURL: &trashed); message = nil }
        catch { message = "No se pudo mover a la papelera: \(error.localizedDescription)"; return }
        // Si queda otra nota con el mismo nombre, los enlaces por nombre pasan a ser suyos: no se quitan.
        let homonym = notes.contains { $0.path != rel && MD.fold($0.name) == MD.fold(name) }
        var links: [(rel: String, previous: String)] = [], failed: [String] = []
        if !homonym { (links, failed) = rewriteLinks { Edit.unlink($0, name: name) } }
        if let t = trashed as URL? { push(.trash(rel: rel, trashed: t, links: links)) }
        if !failed.isEmpty { message = "La nota se movió, pero no se pudieron actualizar los enlaces en: \(failed.joined(separator: ", "))." }
        lastChange = Change(file: rel, undoable: trashed != nil)
        reload()
    }

    /// Reescribe las demás notas con `transform`. Devuelve el texto previo de las que cambió (para deshacer) y las que fallaron.
    func rewriteLinks(except skip: String? = nil, _ transform: (String) -> String) -> (changed: [(rel: String, previous: String)], failed: [String]) {
        var changed: [(rel: String, previous: String)] = []
        var failed: [String] = []
        for n in notes where n.path != skip {
            let u = url(n.path)
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let updated = transform(text)
            guard updated != text else { continue }
            do { try updated.write(to: u, atomically: true, encoding: .utf8); changed.append((n.path, text)) }
            catch { failed.append(n.path) }
        }
        return (changed, failed)
    }

    /// Renombra la nota y actualiza los enlaces [[...]] de las demás.
    func renameNote(_ rel: String, to newName: String) -> String? {
        let clean = newName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        let dir = (rel as NSString).deletingLastPathComponent
        let newRel = (dir.isEmpty ? "" : dir + "/") + clean + ".md"
        let oldName = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !clean.isEmpty, clean != oldName else { return nil }
        // En un disco que no distingue mayúsculas, «nota» → «Nota» es el mismo archivo: no es un choque.
        let caseOnly = newRel.lowercased() == rel.lowercased()
        guard caseOnly || !FileManager.default.fileExists(atPath: url(newRel).path) else { message = "Ya existe una nota llamada \(clean)."; return nil }
        ensureBackup()
        do { try FileManager.default.moveItem(at: url(rel), to: url(newRel)) }
        catch { message = "No se pudo renombrar: \(error.localizedDescription)"; return nil }
        pinned = pinned.map { $0 == rel ? newRel : $0 }
        fileCache.removeAll()
        let (links, failed) = rewriteLinks(except: rel) { Edit.renameLinks($0, old: oldName, new: clean, folder: dir) }
        push(.rename(old: rel, new: newRel, links: links))
        if !failed.isEmpty { message = "Se renombró, pero no se pudieron actualizar los enlaces en: \(failed.joined(separator: ", "))." }
        lastChange = Change(file: newRel, undoable: true)
        reload()
        return newRel
    }

    func setProperty(_ rel: String, key: String, value: String, quiet: Bool = false) {
        edit(rel, quiet: quiet) { Edit.setFrontmatter($0, key: key, value: value) }
    }

    func toggleLine(_ rel: String, line: Int, raw: String? = nil) {
        edit(rel) { Edit.toggleCheckbox($0, line: line, expect: raw) }
    }

    /// Encabezado y celdas actuales de una fila de tabla, leídos del disco.
    func rowCells(file: String, line: Int) -> (header: [String], cells: [String])? {
        let lines = MD.lines(read(file))
        guard line >= 0, line < lines.count, MD.isTable(lines[line]) else { return nil }
        let h = MD.tableHeaderLine(lines, containing: line)
        return (MD.cells(lines[h]), MD.cells(lines[line]))
    }

    func tableHeader(file: String, headerLine: Int) -> [String] {
        let lines = MD.lines(read(file))
        return headerLine < lines.count ? MD.cells(lines[headerLine]) : []
    }

    func updateRow(file: String, line: Int, expectFirst: String, cells: [String]) {
        edit(file) { Edit.updateRow($0, line: line, expectFirst: expectFirst, cells: cells) }
    }

    func deleteRow(file: String, line: Int, expectFirst: String) {
        edit(file) { Edit.deleteRow($0, line: line, expectFirst: expectFirst) }
    }

    func insertRow(file: String, afterLine: Int, cells: [String]) {
        edit(file) { Edit.insertTableRow($0, afterLine: afterLine, cells: cells) }
    }

    func updateTask(_ t: TaskItem, text: String, due: Date?, priority: Int = -1) {
        edit(t.file) { Edit.updateTask($0, task: t, newText: text, due: due, priority: priority) }
    }

    func deleteTask(_ t: TaskItem) {
        edit(t.file) { Edit.deleteLine($0, raw: t.raw, hint: t.line) }
    }

    /// Guarda los hábitos (nombre y criterio) en la revisión de esta semana, que la crea si falta. Las nuevas revisiones copian esa lista.
    func saveHabits(_ defs: [HabitDef]) {
        let today = Date()
        let key = DayKey.weekKey(today)
        if reviews[key] == nil { createReview(key: key, monday: DayKey.weekStart(today)) }
        edit(reviewFile(key)) { Edit.setHabitTable($0, defs: defs) }
    }
}
