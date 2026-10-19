import AppKit
import Foundation
import SwiftUI

// Escritura segura: copias de seguridad, edición con deshacer.
extension Store {
    // MARK: Escritura

    static func stamp(_ format: String) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        return f.string(from: Date())
    }

    /// Copia de seguridad del vault antes del primer cambio de cada día, en la carpeta de copias.
    /// Después borra las automáticas más viejas y deja solo las últimas `keepAutoBackups`.
    /// Normalmente ya la hizo `startDailyBackup` al abrir; aquí solo espera a esa o la hace si falta.
    func ensureBackup() {
        let day = Store.stamp("yyyy-MM-dd")
        guard lastBackupDay != day else { return }
        lastBackupDay = day
        backupJob.wait()
        let dest = autoBackupURL(day)
        if !FileManager.default.fileExists(atPath: dest.path) { Store.copyVault(from: root, to: dest) }
        pruneAutoBackups()
    }

    /// Hace la copia de hoy en segundo plano nada más abrir, para que el primer cambio no espere a copiar toda la carpeta.
    func startDailyBackup() {
        let day = Store.stamp("yyyy-MM-dd")
        let dest = autoBackupURL(day)
        guard !FileManager.default.fileExists(atPath: dest.path) else { lastBackupDay = day; return }
        let src = root
        let job = backupJob
        job.enter()
        DispatchQueue.global(qos: .utility).async {
            Store.copyVault(from: src, to: dest)
            job.leave()
        }
    }

    func autoBackupURL(_ day: String) -> URL {
        backupsFolder.appendingPathComponent("\(vaultName)-auto-\(day)")
    }

    /// Copia a una carpeta temporal y la renombra al final, para que una copia a medias no pase por completa.
    nonisolated static func copyVault(from src: URL, to dest: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: dest.path) else { return }
        let partial = dest.deletingLastPathComponent().appendingPathComponent(".\(dest.lastPathComponent).partial")
        try? fm.removeItem(at: partial)
        do {
            try fm.copyItem(at: src, to: partial)
            try fm.moveItem(at: partial, to: dest)
        } catch { try? fm.removeItem(at: partial) }
    }

    /// Las copias automáticas se llaman `<vault>-auto-AAAA-MM-DD`; las manuales y cualquier otra carpeta no se tocan.
    func autoBackups() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.range(of: #"-auto-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func pruneAutoBackups(keep: Int = Store.keepAutoBackups) {
        let all = autoBackups()
        guard all.count > keep else { return }
        for u in all.prefix(all.count - keep) { try? FileManager.default.removeItem(at: u) }
    }

    /// Mueve a la carpeta de copias las que se hicieron antes sueltas en Documentos.
    func moveLooseBackups() {
        let fm = FileManager.default
        let docs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let items = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        let loose = items.filter { $0.lastPathComponent.contains("-backup-") && $0.hasDirectoryPath }
        guard !loose.isEmpty else { return }
        try? fm.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        for u in loose { try? fm.moveItem(at: u, to: backupsFolder.appendingPathComponent(u.lastPathComponent)) }
    }

    /// Lee el archivo recién del disco, aplica el cambio y lo guarda. Así no se pisan cambios hechos desde otro programa.
    func edit(_ rel: String, quiet: Bool = false, _ transform: (String) -> String?) {
        let u = url(rel)
        guard let text = try? String(contentsOf: u, encoding: .utf8) else { message = "No se pudo leer \(rel)."; return }
        guard let new = transform(text) else { message = "No encontré dónde cambiar \(rel). No se modificó."; return }
        guard new != text else { return }
        ensureBackup()
        do {
            try new.write(to: u, atomically: true, encoding: .utf8)
            fileCache[rel] = nil
            message = nil
            record(rel, previous: text, written: new, quiet: quiet)
        } catch { message = "No se pudo guardar \(rel): \(error.localizedDescription)" }
        reload()
    }

    /// `quiet` es el autoguardado: no muestra aviso y junta varios guardados seguidos del mismo archivo en un solo paso de deshacer.
    func record(_ rel: String, previous: String?, written: String? = nil, quiet: Bool = false) {
        if quiet, let q = lastQuietWrite, q.rel == rel, Date().timeIntervalSince(q.at) < 120, case .write(let last, let first, _)? = undoStack.last, last == rel {
            lastQuietWrite = (rel, Date())
            undoStack[undoStack.count - 1] = .write(rel: rel, previous: first, written: written)
            return
        }
        push(.write(rel: rel, previous: previous, written: written))
        lastQuietWrite = quiet ? (rel, Date()) : nil
        if !quiet { lastChange = Change(file: rel, undoable: true) }
    }

    func push(_ step: UndoStep) {
        undoStack.append(step)
        if undoStack.count > 40 { undoStack.removeFirst() }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Deshace el último cambio hecho desde la app (restaura el archivo tal como estaba).
    func undo() {
        guard let last = undoStack.popLast() else { return }
        fileCache.removeAll()
        let fm = FileManager.default
        var failed: [String] = []
        func restore(_ rel: String, _ text: String) {
            do { try text.write(to: url(rel), atomically: true, encoding: .utf8) } catch { failed.append(rel) }
        }
        let label: String
        switch last {
        case let .write(rel, previous, written):
            label = rel
            // Si el archivo ya no es lo que escribió la app, otro programa (o iCloud) lo cambió después: no se pisa.
            if let written, let current = readOptional(rel), current != written {
                message = "«\(rel)» cambió fuera de la app después de ese cambio. No se deshizo para no perder lo nuevo."
                reload()
                return
            }
            if let previous { restore(rel, previous) }
            else { do { try fm.trashItem(at: url(rel), resultingItemURL: nil) } catch { failed.append(rel) } }
        case let .trash(rel, trashed, links):
            label = rel
            do {
                try fm.createDirectory(at: url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: trashed, to: url(rel))
            } catch { failed.append(rel) }
            for l in links { restore(l.rel, l.previous) }
        case let .rename(old, new, links):
            label = old
            do { try fm.moveItem(at: url(new), to: url(old)) } catch { failed.append(old) }
            for l in links { restore(l.rel, l.previous) }
            pinned = pinned.map { $0 == new ? old : $0 }
        }
        if failed.isEmpty { lastChange = Change(file: "Deshecho: " + label, undoable: false); message = nil }
        else { message = "No se pudo deshacer del todo: \(failed.joined(separator: ", "))." }
        reload()
    }

    func dismissChange(_ id: UUID) { if lastChange?.id == id { lastChange = nil } }
}
