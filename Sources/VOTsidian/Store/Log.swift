import Foundation
import os

// MARK: - Registro del sistema
//
// Para diagnosticar lo que no se ve en pantalla (iCloud que no baja un archivo, una copia que falla de madrugada, Calendar que
// rechaza un evento). Se lee en Consola.app filtrando por el subsistema, o en Terminal:
//
//     log stream --predicate 'subsystem == "com.votsidian.app"' --level info
//
// Nunca se escribe el contenido de las notas. Rutas y nombres van como privados (macOS los oculta salvo que se pidan);
// errores, cuentas y tiempos, públicos.

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.votsidian.app"
    /// Leer y escribir notas, cambios desde fuera de la app.
    static let notes = Logger(subsystem: subsystem, category: "notas")
    /// Archivos que iCloud aún no ha bajado a este Mac y copias en conflicto.
    static let icloud = Logger(subsystem: subsystem, category: "icloud")
    static let backups = Logger(subsystem: subsystem, category: "copias")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let notifications = Logger(subsystem: subsystem, category: "notificaciones")
}
