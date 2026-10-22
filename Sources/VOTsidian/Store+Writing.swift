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
        if !autoBackupExists(day) { Store.makeBackup(from: root, to: autoBackupURL(day), password: backupPassword) }
        pruneAutoBackups()
    }

    /// Hace la copia de hoy en segundo plano nada más abrir, para que el primer cambio no espere a copiar toda la carpeta.
    /// Se llama al abrir, al volver a la app y cada pocos minutos: si cambió el día con la app abierta, la copia se hace
    /// en cuanto toca y no en el primer cambio de la mañana. Solo actúa una vez al día.
    func startDailyBackup() {
        let day = Store.stamp("yyyy-MM-dd")
        guard dailyBackupDay != day else { return }
        dailyBackupDay = day
        let dest = autoBackupURL(day)
        guard !autoBackupExists(day) else { lastBackupDay = day; return }
        // Los archivos que iCloud no tiene en este Mac solo se copiarían como marcadores vacíos: se piden ya,
        // y lo que no haya llegado queda avisado en Avisos («no entran en las copias»).
        for rel in pendingDownloads { try? FileManager.default.startDownloadingUbiquitousItem(at: url(rel)) }
        let src = root
        let password = backupPassword
        let job = backupJob
        job.enter()
        DispatchQueue.global(qos: .utility).async {
            Store.makeBackup(from: src, to: dest, password: password)
            job.leave()
        }
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
    @discardableResult
    nonisolated static func makeBackup(from src: URL, to dest: URL, password: String?) -> Bool {
        guard let password else { copyVault(from: src, to: dest); return FileManager.default.fileExists(atPath: dest.path) }
        let fm = FileManager.default
        let staging = stagingURL(for: dest)
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: dest.path), !fm.fileExists(atPath: staging.path) else { return false }
        do { try fm.copyItem(at: src, to: staging) } catch { try? fm.removeItem(at: staging); return false }
        DispatchQueue.global(qos: .utility).async {
            _ = EncryptedBackup.create(from: staging, to: dest, password: password)
            try? FileManager.default.removeItem(at: staging)
        }
        return true
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

    /// Las copias automáticas se llaman `<vault>-auto-AAAA-MM-DD` (más `.dmg` si van cifradas); las manuales y cualquier otra carpeta no se tocan.
    func autoBackups() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.range(of: #"-auto-\d{4}-\d{2}-\d{2}(\.dmg)?$"#, options: .regularExpression) != nil }
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
            message = nil
            record(rel, previous: text, written: new, quiet: quiet)
        } catch { message = "No se pudo guardar \(rel): \(error.localizedDescription)" }
        reload(changed: [rel])
    }

    func dismissChange(_ id: UUID) { if lastChange?.id == id { lastChange = nil } }
}
