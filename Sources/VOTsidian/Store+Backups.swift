import Foundation

/// Una copia de seguridad guardada: carpeta o imagen cifrada `.dmg`.
struct BackupEntry: Identifiable, Hashable, Sendable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var encrypted: Bool { url.pathExtension == EncryptedBackup.ext }
    var isAuto: Bool { name.contains("-auto-") }
    var beforeRestore: Bool { name.contains("antes-de-restaurar") }
    var hasTime: Bool { name.firstMatch(of: /\d{4}-\d{2}-\d{2}-\d{4}/) != nil }

    /// Fecha (y hora en las manuales) sacada del nombre: `…-auto-2026-10-21`, `…-manual-2026-10-21-1430`.
    var date: Date? {
        guard let m = name.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})(?:-(\d{2})(\d{2}))?/),
              let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3), let day = DayKey.make(y, mo, d) else { return nil }
        guard let h = m.4.flatMap({ Int($0) }), let min = m.5.flatMap({ Int($0) }) else { return day }
        return DayKey.calendar().date(bySettingHour: h, minute: min, second: 0, of: day)
    }

    var label: String {
        let kind = isAuto ? "Automática" : beforeRestore ? "Antes de restaurar" : "Manual"
        guard let d = date else { return "\(kind) · \(name)" }
        let style: Date.FormatStyle = hasTime ? .dateTime.day().month(.abbreviated).year().hour().minute() : .dateTime.day().month(.abbreviated).year()
        return "\(kind) · \(DayKey.esLong(d, style))"
    }
}

/// Una copia abierta para leerla. Las cifradas se montan en solo lectura y `close()` las desmonta.
struct OpenedBackup: Sendable {
    let root: URL
    let mounted: Bool
    func close() { if mounted { EncryptedBackup.detach(root) } }
}

// Leer y restaurar copias: historial de una nota y vuelta atrás de toda la carpeta.
extension Store {
    struct NoteVersion: Identifiable, Sendable {
        let backup: BackupEntry
        let text: String
        var id: String { backup.id }
    }

    /// Copias de la más nueva a la más vieja (por la fecha del nombre, no por el nombre: «manual» va antes que «auto»).
    func backupEntries() -> [BackupEntry] {
        allBackups().map(BackupEntry.init).sorted { ($0.date ?? .distantPast, $0.name) > ($1.date ?? .distantPast, $1.name) }
    }

    nonisolated static func open(_ b: BackupEntry, password: String?) -> OpenedBackup? {
        guard b.encrypted else { return OpenedBackup(root: b.url, mounted: false) }
        guard let password, let mount = EncryptedBackup.attach(b.url, password: password) else { return nil }
        return OpenedBackup(root: mount, mounted: true)
    }

    /// Versiones de una nota en las copias, de la más nueva a la más vieja, sin repetir textos seguidos iguales.
    /// Las cifradas se abren con la contraseña actual; las que no se pueden abrir se cuentan en `locked`.
    nonisolated static func noteHistory(_ rel: String, in backups: [BackupEntry], password: String?) -> (versions: [NoteVersion], locked: Int) {
        var out: [NoteVersion] = []
        var locked = 0
        for b in backups {
            guard let opened = open(b, password: password) else { locked += 1; continue }
            let text = try? String(contentsOf: opened.root.appendingPathComponent(rel), encoding: .utf8)
            opened.close()
            guard let text, text != out.last?.text else { continue }
            out.append(NoteVersion(backup: b, text: text))
        }
        return (out, locked)
    }

    /// Copia a `dest` los archivos de `src` que faltan o son distintos. Los que solo están en `dest` no se tocan.
    nonisolated static func restoreFiles(from src: URL, to dest: URL) -> (restored: Int, failed: [String]) {
        let fm = FileManager.default
        let base = src.standardizedFileURL.path
        var restored = 0
        var failed: [String] = []
        guard let en = fm.enumerator(at: src, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return (0, []) }
        for case let u as URL in en where !u.hasDirectoryPath {
            let rel = String(u.standardizedFileURL.path.dropFirst(base.count + 1))
            let target = dest.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: u) else { failed.append(rel); continue }
            if (try? Data(contentsOf: target)) == data { continue }
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                restored += 1
            } catch { failed.append(rel) }
        }
        return (restored, failed)
    }

    /// Deja las notas como estaban en la copia. Antes guarda una copia manual «antes de restaurar» del estado actual,
    /// que es la forma de volver atrás. Las notas creadas después de la copia se conservan. Devuelve el mensaje para el usuario.
    func restoreBackup(_ b: BackupEntry) async -> String {
        let (root, password) = (self.root, backupPassword)
        let name = "\(vaultName)-manual-\(Store.stamp("yyyy-MM-dd-HHmmss"))-antes-de-restaurar"
        let safety = backupsFolder.appendingPathComponent(password == nil ? name : "\(name).\(EncryptedBackup.ext)")
        let job = backupJob
        await withCheckedContinuation { c in job.notify(queue: .main) { c.resume() } }   // que no coincida con la copia diaria
        let text: String = await Task.detached(priority: .userInitiated) {
            guard Store.makeBackup(from: root, to: safety, password: password) else {
                return "No se pudo hacer la copia previa. No se restauró nada."
            }
            guard let opened = Store.open(b, password: password) else {
                return "No se pudo abrir la copia (¿se cifró con otra contraseña?). No se restauró nada."
            }
            defer { opened.close() }
            let r = Store.restoreFiles(from: opened.root, to: root)
            var msg = r.restored == 0 ? "Nada que restaurar: las notas ya coincidían con la copia." : "Restaurados \(r.restored) archivos."
            if !r.failed.isEmpty { msg += " No se pudieron restaurar: \(r.failed.prefix(3).joined(separator: ", "))." }
            return msg + " El estado anterior quedó en «\(safety.lastPathComponent)»."
        }.value
        Log.backups.notice("Restaurar \(b.name, privacy: .private): \(text, privacy: .private)")
        fileCache.removeAll()
        reload()
        backupsStamp += 1
        return text
    }
}
