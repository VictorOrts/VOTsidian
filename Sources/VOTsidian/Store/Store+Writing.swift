import AppKit
import Foundation
import SwiftUI

// Escritura segura: copias de seguridad, edición con deshacer.
extension Store {
    // MARK: Escritura

    static func stamp(_ format: String) -> String {
        let f = DateFormatter()
        // Siempre gregoriano y con cifras occidentales, sea cual sea el calendario del sistema: los nombres de las copias dependen de ello.
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
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
        if !autoBackupExists(day) {
            let started = Store.makeBackup(from: root, to: autoBackupURL(day), password: backupPassword) { [weak self] ok in
                DispatchQueue.main.async { self?.backupFinished(ok: ok, day: day) }
            }
            if !started { backupFinished(ok: false, day: day) }
        }
        pruneAutoBackups()
    }

    /// Al terminar una copia automática: si falló se avisa (Avisos e Inicio); si fue bien se quitan las viejas.
    func backupFinished(ok: Bool, day: String) {
        defer { backupsStamp += 1; refreshPublished() }
        if ok {
            Log.backups.info("Copia automática del \(day, privacy: .public) hecha")
            backupFailure = nil
            pruneAutoBackups()
        } else {
            Log.backups.error("La copia automática del \(day, privacy: .public) no se pudo hacer")
            let when = DayKey.date(day).map(DayKey.dmy) ?? day
            backupFailure = "La copia de seguridad del \(when) no se pudo hacer. Prueba «Hacer copia ahora» en Ajustes."
        }
    }

    /// Días desde la copia más reciente de esta carpeta (automática o manual), o `nil` si no hay ninguna.
    func daysSinceLastBackup(today: Date = DayKey.today()) -> Int? {
        let prefix = "\(vaultName)-"
        let dates = backupEntries().filter { $0.name.hasPrefix(prefix) }.compactMap(\.date)
        return dates.max().map { DayKey.days(from: $0, to: today) }
    }

    /// Hace la copia de hoy en segundo plano nada más abrir, para que el primer cambio no espere a copiar toda la carpeta.
    /// Se llama al abrir, al volver a la app y cada pocos minutos: si cambió el día con la app abierta, la copia se hace
    /// en cuanto toca y no en el primer cambio de la mañana. Solo actúa una vez al día.
    func startDailyBackup() {
        let day = Store.stamp("yyyy-MM-dd")
        guard dailyBackupDay != day else { return }
        dailyBackupDay = day
        let dest = autoBackupURL(day)
        guard !autoBackupExists(day) else { lastBackupDay = day; pruneAutoBackups(); return }
        // Los archivos que iCloud no tiene en este Mac solo se copiarían como marcadores vacíos: se piden ya,
        // y lo que no haya llegado queda avisado en Avisos («no entran en las copias»).
        if !pendingDownloads.isEmpty { Log.icloud.notice("Antes de la copia: \(self.pendingDownloads.count, privacy: .public) archivos sin bajar de iCloud; se piden") }
        for rel in pendingDownloads { try? FileManager.default.startDownloadingUbiquitousItem(at: url(rel)) }
        let src = root
        let password = backupPassword
        let job = backupJob
        job.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let started = Store.makeBackup(from: src, to: dest, password: password) { ok in
                DispatchQueue.main.async { self?.backupFinished(ok: ok, day: day) }
            }
            if !started { DispatchQueue.main.async { self?.backupFinished(ok: false, day: day) } }
            job.leave()
        }
    }

    /// Fuera de Documentos (que puede ir a iCloud con «Escritorio y Documentos»): las copias no ocupan iCloud ni se sincronizan.
    nonisolated static var defaultBackupsFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("VOTsidian/Copias")
    }

    /// Lleva las copias de la carpeta de antes (`Documentos/Copias VOTsidian`) a la de ahora. Las que no se puedan mover se quedan donde estaban.
    func moveOldBackups() {
        let fm = FileManager.default
        let old = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Copias VOTsidian")
        guard old.standardizedFileURL != backupsFolder.standardizedFileURL,
              let items = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil), !items.isEmpty else { return }
        try? fm.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        for u in items where !u.lastPathComponent.hasPrefix(".") {
            let dest = backupsFolder.appendingPathComponent(u.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: u, to: dest) }
        }
        let left = ((try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }
        if left.isEmpty { try? fm.removeItem(at: old) }
    }

    /// Con contraseña la copia es una imagen cifrada `.dmg`; sin ella, una carpeta.
    func autoBackupURL(_ day: String) -> URL {
        let name = "\(vaultName)-auto-\(day)"
        return backupsFolder.appendingPathComponent(backupPassword == nil ? name : "\(name).\(EncryptedBackup.ext)")
    }

    /// Carpeta oculta con el clon de la copia mientras se cifra; marca que la copia de ese día está en marcha.
    nonisolated static func stagingURL(for dest: URL) -> URL {
        dest.deletingLastPathComponent().appendingPathComponent(".\(dest.deletingPathExtension().lastPathComponent).staging")
    }

    /// Cuenta la copia de ese día sea carpeta, imagen cifrada o cifrado en curso, para no duplicarla.
    func autoBackupExists(_ day: String) -> Bool {
        let base = backupsFolder.appendingPathComponent("\(vaultName)-auto-\(day)")
        let dmg = base.appendingPathExtension(EncryptedBackup.ext)
        return [base, dmg, Store.stagingURL(for: dmg)].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Al abrir no puede haber cifrados en curso: lo que quede es de una sesión que se cerró a medias.
    func removeStaleStaging() {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        for u in items where u.lastPathComponent.hasSuffix(".staging") { try? FileManager.default.removeItem(at: u) }
    }

    /// Sin contraseña copia la carpeta. Con contraseña hace primero un clon rápido (APFS) y cifra desde él en segundo plano,
    /// así quien llama solo espera al clon y los cambios posteriores no entran en la copia.
    /// Devuelve si la copia se pudo empezar; `completion` recibe si terminó bien (también tras cifrar), solo si empezó.
    @discardableResult
    nonisolated static func makeBackup(from src: URL, to dest: URL, password: String?, completion: (@Sendable (Bool) -> Void)? = nil) -> Bool {
        guard let password else {
            let ok = copyVault(from: src, to: dest)
            if ok { completion?(true) }
            return ok
        }
        let fm = FileManager.default
        let staging = stagingURL(for: dest)
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: dest.path), !fm.fileExists(atPath: staging.path) else { return false }
        do { try cloneOrCopy(src, to: staging) } catch {
            Log.backups.error("No se pudo clonar la carpeta para cifrarla: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: staging); return false
        }
        DispatchQueue.global(qos: .utility).async {
            let ok = EncryptedBackup.create(from: staging, to: dest, password: password)
            if !ok { Log.backups.error("No se pudo crear la imagen cifrada \(dest.lastPathComponent, privacy: .private)") }
            try? FileManager.default.removeItem(at: staging)
            completion?(ok)
        }
        return true
    }

    /// Clon APFS de toda la carpeta de una vez (`clonefile`: ~15 veces más rápido que copiar nota a nota y sin ocupar espacio
    /// hasta que algo cambia). Si no se puede (otro volumen…) o hay archivos de iCloud sin bajar, copia normal: el clon de un
    /// archivo sin bajar sería solo el marcador, y la copia normal lee su contenido.
    nonisolated static func cloneOrCopy(_ src: URL, to dest: URL) throws {
        if !hasDatalessFiles(src), clonefile(src.path, dest.path, 0) == 0 { return }
        let err = errno
        Log.backups.notice("Sin clon APFS (\(String(cString: strerror(err)), privacy: .public)): se copia nota a nota")
        // Un clon a medias se quita; si el destino ya existía, no es nuestro y no se toca (`copyItem` fallará).
        if err != EEXIST { try? FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: src, to: dest)
    }

    /// ¿Algún archivo de la carpeta está en iCloud sin bajar a este Mac? (`SF_DATALESS`, con `lstat`: sin pedir la descarga.)
    nonisolated static func hasDatalessFiles(_ root: URL) -> Bool {
        guard let walk = FileManager.default.enumerator(atPath: root.path) else { return false }
        var st = stat()
        while let rel = walk.nextObject() as? String {
            if lstat(root.appendingPathComponent(rel).path, &st) == 0, st.st_flags & UInt32(SF_DATALESS) != 0 { return true }
        }
        return false
    }

    /// Copia a una carpeta temporal y la renombra al final, para que una copia a medias no pase por completa.
    /// Devuelve si la copia existe al terminar.
    @discardableResult
    nonisolated static func copyVault(from src: URL, to dest: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: dest.path) else { return true }
        let partial = dest.deletingLastPathComponent().appendingPathComponent(".\(dest.lastPathComponent).partial")
        try? fm.removeItem(at: partial)
        do {
            try cloneOrCopy(src, to: partial)
            try fm.moveItem(at: partial, to: dest)
        } catch {
            Log.backups.error("No se pudo copiar la carpeta: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: partial)
        }
        return fm.fileExists(atPath: dest.path)
    }

    /// Las copias automáticas de esta carpeta se llaman `<vault>-auto-AAAA-MM-DD` (más `.dmg` si van cifradas); las manuales, las de otras carpetas y cualquier otra cosa no se tocan.
    func autoBackups() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        let prefix = "\(vaultName)-auto-"
        return items.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.range(of: #"-auto-[0-9]{4}-[0-9]{2}-[0-9]{2}(\.dmg)?$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func pruneAutoBackups(keep: Int = Store.keepAutoBackups) {
        let all = autoBackups()
        guard all.count > keep else { return }
        for u in all.prefix(all.count - keep) { try? FileManager.default.removeItem(at: u) }
        if all.count > keep { backupsStamp += 1 }
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
    /// Si la nota de un módulo aún no existe, se parte de su plantilla: lo primero que se apunta la crea.
    /// Devuelve `false` si no se pudo (el motivo queda en `message`).
    @discardableResult
    func edit(_ rel: String, quiet: Bool = false, _ transform: (String) -> String?) -> Bool {
        let u = url(rel)
        let onDisk = try? String(contentsOf: u, encoding: .utf8)
        // Solo si de verdad no está: una nota ilegible o pendiente de iCloud no se sustituye por la plantilla.
        let starter = onDisk == nil && !exists(rel) && !pendingDownloads.contains(rel) ? starterText(for: rel) : nil
        guard let text = onDisk ?? starter else {
            Log.notes.error("No se pudo leer \(rel, privacy: .private) para cambiarla (¿pendiente de iCloud: \(self.pendingDownloads.contains(rel), privacy: .public)?)")
            message = "No se pudo leer \(rel)."; return false
        }
        guard let new = transform(text) else {
            Log.notes.notice("No se encontró dónde cambiar \(rel, privacy: .private): la nota no tiene la forma esperada")
            message = "No encontré dónde cambiar \(rel). No se modificó."; return false
        }
        guard new != text || starter != nil else { return true }
        ensureBackup()
        var ok = true
        do {
            if starter != nil { try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true) }
            try new.write(to: u, atomically: true, encoding: .utf8)
            message = nil
            record(rel, previous: onDisk, written: new, quiet: quiet)
        } catch {
            Log.notes.error("No se pudo guardar \(rel, privacy: .private): \(error.localizedDescription, privacy: .public)")
            message = "No se pudo guardar \(rel): \(error.localizedDescription)"; ok = false
        }
        reload(changed: [rel])
        return ok
    }

    func dismissChange(_ id: UUID) { if lastChange?.id == id { lastChange = nil } }
}

extension Store {
    /// Copia un archivo elegido (foto, análisis) a la carpeta de su nota, sin pisar nada: si ya hay uno con ese nombre y es el
    /// mismo, se reutiliza; si es otro, el nuevo se numera («análisis 2.pdf»). Devuelve dónde quedó, o `nil` si no se pudo
    /// (el motivo queda en `message`).
    @discardableResult
    func importFile(_ src: URL, to dir: URL, as name: String? = nil) -> URL? {
        let fm = FileManager.default
        let base = name ?? src.lastPathComponent
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { message = "No se pudo crear la carpeta \(dir.lastPathComponent): \(error.localizedDescription)"; return nil }
        let (stem, ext) = ((base as NSString).deletingPathExtension, (base as NSString).pathExtension)
        var dest = dir.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            if fm.contentsEqual(atPath: src.path, andPath: dest.path) { return dest }
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        do { try fm.copyItem(at: src, to: dest) }
        catch { message = "No se pudo copiar \(base): \(error.localizedDescription)"; return nil }
        return dest
    }
}
