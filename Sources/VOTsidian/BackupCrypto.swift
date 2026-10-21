import Foundation
import Security

/// Contraseña de las copias cifradas, guardada en el Llavero de macOS.
enum BackupKeychain {
    private static let service = "VOTsidian.copias"
    private static let account = "contraseña"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// Copias cifradas: imagen de disco `.dmg` con AES-256 (hdiutil). Se abre con doble clic en Finder y la contraseña, sin necesitar la app.
enum EncryptedBackup {
    static let ext = "dmg"

    /// Crea la imagen en un archivo temporal y la renombra al final, como `copyVault`.
    nonisolated static func create(from src: URL, to dest: URL, password: String) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: dest.path) else { return true }
        let partial = dest.deletingLastPathComponent().appendingPathComponent(".\(dest.deletingPathExtension().lastPathComponent).partial.\(ext)")
        try? fm.removeItem(at: partial)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["create", "-srcfolder", src.path, "-volname", "VOTsidian", "-encryption", "AES-256", "-stdinpass", "-format", "UDZO", "-ov", partial.path]
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            input.fileHandleForWriting.write(Data(password.utf8))
            try input.fileHandleForWriting.close()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { try? fm.removeItem(at: partial); return false }
            try fm.moveItem(at: partial, to: dest)
            return true
        } catch { try? fm.removeItem(at: partial); return false }
    }
}
