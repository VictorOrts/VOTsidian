import AppIntents
import AppKit

// Siri y Atajos. Las acciones usan el `Store` de la app (lo registra `VOTsidianApp` en `AppDependencyManager`) y las mismas
// funciones que ⌘K y la captura rápida: lo que se dice a Siri se apunta igual que lo que se escribe.
// SwiftPM no genera los metadatos que Siri lee (`Metadata.appintents`): los crea `scripts/build-app.sh`. Con `swift run` no hay Siri.

/// Cualquier cosa en una frase, como la captura rápida (⇧⌘N): tarea, cita, gasto, peso, compra…
struct CapturarIntent: AppIntent {
    static let title: LocalizedStringResource = "Apuntar"
    static let description = IntentDescription("Apunta cualquier cosa en una frase, como la captura rápida: «comprar pan el viernes», «peso 101,2», «gasto 22 € cena», «compra leche y huevos».")

    @Parameter(title: "Qué", requestValueDialog: "¿Qué apunto?")
    var texto: String

    @Dependency var store: Store

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let guess = Capture.interpret(texto, categories: store.expenseCategories, people: store.people.map(\.name), learned: store.expenseLearned) else {
            return .result(dialog: "No he entendido «\(texto)».")
        }
        let reply = store.run(guess.command)
        return .result(dialog: "\(guess.command.summary). \(reply)")
    }
}

/// Una tarea en lenguaje natural («llamar al taller el lunes a las 10»): nunca la toma por gasto o compra.
struct AnadirTareaIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir tarea"
    static let description = IntentDescription("Añade una tarea con su fecha, hora, duración y repetición si las dices: «llamar al taller el lunes a las 10».")

    @Parameter(title: "Tarea", requestValueDialog: "¿Qué tarea añado?")
    var texto: String

    @Dependency var store: Store

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let guess = Capture.interpret(texto, tasksOnly: true), case .task(let p) = guess.command else {
            return .result(dialog: "No he entendido la tarea.")
        }
        return .result(dialog: "«\(p.text)». \(store.addTask(p)).")
    }
}

/// Lo que hay hoy en la agenda y lo vencido, leído en voz alta o en un atajo.
struct HoyIntent: AppIntent {
    static let title: LocalizedStringResource = "Qué tengo hoy"
    static let description = IntentDescription("Dice las tareas, citas y avisos de hoy en la agenda, y cuántas tareas están vencidas.")

    @Dependency var store: Store

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let today = DayKey.today()
        let end = DayKey.adding(days: 1, to: today).addingTimeInterval(-1)
        let items = store.agenda(from: today, to: end)[DayKey.string(today)] ?? []
        let overdue = store.tasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) }.count
        let text = SiriText.today(items, overdue: overdue)
        return .result(value: text, dialog: "\(text)")
    }
}

/// Los avisos más urgentes (pagos, caducidades, citas…), los mismos que la pantalla Avisos.
struct AvisosIntent: AppIntent {
    static let title: LocalizedStringResource = "Avisos pendientes"
    static let description = IntentDescription("Dice los avisos más urgentes: pagos, caducidades, citas, medicación…")

    @Dependency var store: Store

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = SiriText.alerts(store.alerts().map(\.text))
        return .result(value: text, dialog: "\(text)")
    }
}

/// Abre la app en una pantalla.
struct AbrirPantallaIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir pantalla"
    static let description = IntentDescription("Abre VOTsidian en una pantalla: Mi día, Calendario, Gastos, Peso…")
    static let openAppWhenRun = true

    @Parameter(title: "Pantalla")
    var pantalla: Screen

    @Dependency var store: Store

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard store.isVisible(pantalla) else { return .result(dialog: "«\(store.title(pantalla))» está oculto en Ajustes → Módulos.") }
        store.go(pantalla)
        NSApplication.shared.activate()
        return .result(dialog: "\(store.title(pantalla))")
    }
}

extension Screen: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pantalla"
    // Literal: los metadatos de Siri se leen al compilar y no admiten valores calculados.
    static let caseDisplayRepresentations: [Screen: DisplayRepresentation] = [
        .inicio: "Inicio", .dia: "Mi día", .tareas: "Tareas", .calendario: "Calendario", .planificar: "Planificar semana",
        .semana: "Revisión semanal", .mes: "Revisión mensual", .proyectos: "Proyectos", .objetivos: "Objetivos",
        .peso: "Peso", .nutricion: "Plan nutricional", .medicacion: "Medicación", .salud: "Salud y médicos", .correlaciones: "Correlaciones",
        .casa: "Casa", .compra: "Compra", .moda: "Moda", .mascota: "Mascota", .vehiculo: "Vehículo", .personas: "Personas",
        .documentos: "Documentos", .finanzas: "Finanzas", .gastos: "Gastos", .suscripciones: "Suscripciones", .prestamos: "Préstamos",
        .lecturas: "Lecturas", .viajes: "Viajes", .tramites: "Trámites y seguros", .notas: "Notas", .bases: "Bases", .grafo: "Grafo",
        .lienzo: "Lienzo", .enlaces: "Enlaces rotos", .avisos: "Avisos", .ajustes: "Ajustes",
    ]
}

/// Frases para Siri. Cada una lleva el nombre de la app; Siri pide después el texto que falte.
struct VOTsidianShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AnadirTareaIntent(), phrases: [
            "Añade una tarea en \(.applicationName)", "Nueva tarea en \(.applicationName)", "Recuérdame algo con \(.applicationName)",
        ], shortTitle: "Añadir tarea", systemImageName: "checklist")
        AppShortcut(intent: CapturarIntent(), phrases: [
            "Apunta en \(.applicationName)", "Anota en \(.applicationName)", "Captura en \(.applicationName)",
        ], shortTitle: "Apuntar", systemImageName: "plus.circle")
        AppShortcut(intent: HoyIntent(), phrases: [
            "Qué tengo hoy en \(.applicationName)", "Mi día en \(.applicationName)", "Agenda de hoy en \(.applicationName)",
        ], shortTitle: "Qué tengo hoy", systemImageName: "sun.max")
        AppShortcut(intent: AvisosIntent(), phrases: [
            "Avisos de \(.applicationName)", "Qué está pendiente en \(.applicationName)",
        ], shortTitle: "Avisos", systemImageName: "bell")
        AppShortcut(intent: AbrirPantallaIntent(), phrases: [
            "Abre \(\.$pantalla) en \(.applicationName)", "Abre \(.applicationName) en \(\.$pantalla)",
        ], shortTitle: "Abrir pantalla", systemImageName: "macwindow")
    }
}

/// Lo que dice Siri, sin depender del `Store` (se prueba en `SiriTests`).
nonisolated enum SiriText {
    /// Hoy, como la agenda: lo de todo el día primero y lo que tiene hora después, en orden; lo hecho no se lee. Hasta `limit` elementos, y cuántos quedan.
    static func today(_ items: [AgendaItem], overdue: Int, limit: Int = 6) -> String {
        let pending = items.filter { $0.kind != .done }
            .sorted { ($0.minutes ?? -1, $0.title) < ($1.minutes ?? -1, $1.title) }
        var parts: [String] = []
        if pending.isEmpty {
            parts.append("Hoy no tienes nada en la agenda.")
        } else {
            let lines = pending.prefix(limit).map { i in i.timeText.map { "\($0), \(i.title)" } ?? i.title }
            let more = pending.count - lines.count
            parts.append("Hoy tienes \(pending.count == 1 ? "una cosa" : "\(pending.count) cosas"): " + lines.joined(separator: "; ")
                         + (more > 0 ? "; y \(more) más." : "."))
        }
        if overdue > 0 { parts.append(overdue == 1 ? "Hay una tarea vencida." : "Hay \(overdue) tareas vencidas.") }
        return parts.joined(separator: " ")
    }

    /// Los avisos ya vienen de más a menos urgente.
    static func alerts(_ texts: [String], limit: Int = 5) -> String {
        guard !texts.isEmpty else { return "No hay avisos pendientes." }
        let more = texts.count - min(texts.count, limit)
        return "\(texts.count == 1 ? "Un aviso" : "\(texts.count) avisos"): " + texts.prefix(limit).joined(separator: "; ")
            + (more > 0 ? "; y \(more) más." : ".")
    }
}
