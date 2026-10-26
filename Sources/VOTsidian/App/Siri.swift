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

/// Lo que hay un día en la agenda («qué tengo el miércoles»), hoy si no se dice otro; hoy, también lo vencido.
struct HoyIntent: AppIntent {
    static let title: LocalizedStringResource = "Qué tengo"
    static let description = IntentDescription("Dice las tareas, citas y avisos de un día en la agenda (hoy si no dices otro) y, si es hoy, cuántas tareas están vencidas.")
    static var parameterSummary: some ParameterSummary { Summary("Qué tengo \(\.$fecha)") }

    @Parameter(title: "Día", description: "El día que quieres consultar. Sin él, hoy.")
    var fecha: Date?

    @Dependency var store: Store

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let today = DayKey.today()
        let day = fecha.map { DayKey.calendar().startOfDay(for: $0) } ?? today
        let end = DayKey.adding(days: 1, to: day).addingTimeInterval(-1)
        let items = store.agenda(from: day, to: end)[DayKey.string(day)] ?? []
        let overdue = day == today ? store.tasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) }.count : 0
        let text = SiriText.day(items, label: SiriText.label(day, today: today), overdue: overdue)
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
            "Qué tengo en \(.applicationName)", "Mi agenda en \(.applicationName)",
        ], shortTitle: "Qué tengo", systemImageName: "sun.max")
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
    /// «Hoy», «Mañana», «Ayer» o «El miércoles 28 de octubre».
    static func label(_ day: Date, today: Date) -> String {
        switch DayKey.days(from: today, to: day) {
        case 0: return "Hoy"
        case 1: return "Mañana"
        case -1: return "Ayer"
        default: return "El " + DayKey.esLong(day, .dateTime.weekday(.wide).day().month(.wide)).replacingOccurrences(of: ",", with: "")
        }
    }

    /// Un día, como la agenda: lo de todo el día primero y lo que tiene hora después, en orden; lo hecho no se lee. Hasta `limit`
    /// elementos, y cuántos quedan.
    static func day(_ items: [AgendaItem], label: String = "Hoy", overdue: Int, limit: Int = 6) -> String {
        let pending = items.filter { $0.kind != .done }
            .sorted { ($0.minutes ?? -1, $0.title) < ($1.minutes ?? -1, $1.title) }
        var parts: [String] = []
        if pending.isEmpty {
            parts.append("\(label) no tienes nada en la agenda.")
        } else {
            let lines = pending.prefix(limit).map { i in i.timeText.map { "\($0), \(i.title)" } ?? i.title }
            let more = pending.count - lines.count
            parts.append("\(label) tienes \(pending.count == 1 ? "una cosa" : "\(pending.count) cosas"): " + lines.joined(separator: "; ")
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
