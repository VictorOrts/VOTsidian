import SwiftUI

/// Lo que la captura entiende de una frase: la orden que se ejecutará, sus datos como etiquetas y la nota donde se escribe.
struct CaptureGuess: Equatable {
    enum Tone: Equatable { case kind, date, amount, place, warn }
    struct Chip: Equatable, Hashable { var label: String; var value: String; var tone: Tone }
    var command: QuickCommand
    var chips: [Chip]
    var destination: String
}

/// Captura de cualquier cosa en una frase. Primero las órdenes de ⌘K («peso 101,2», «compra leche»), luego un importe en euros
/// como gasto, y si no, una tarea con todo lo que se entienda de la frase (fecha, hora, duración, repetición, prioridad).
enum Capture {
    /// `tasksOnly` es para los campos de tareas: ahí «comprar pan el viernes» es una tarea, no la lista de la compra.
    /// `defaultDay` es el día de la pantalla (Mi día, la semana): la tarea va a ese día si la frase no dice otro.
    static func interpret(_ raw: String, defaultDay: Date? = nil, tasksOnly: Bool = false, today: Date = DayKey.today(),
                          categories: [String] = Edit.defaultBudgetLines.map(\.0), people: [String] = [], learned: [String: String] = [:]) -> CaptureGuess? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if !tasksOnly {
            if let c = QuickCommand.parse(text, today: today, categories: categories, people: people, learned: learned) { return guess(c, today: today) }
            if looksLikeMoney(text), let p = ExpenseParser.parse(text, categories: categories, people: people, learned: learned, today: today) {
                return guess(.expense(p), today: today)
            }
        }
        var p = NaturalDate.extractTask(text, today: today)
        guard !p.text.isEmpty else { return nil }
        if p.date == nil, let defaultDay { p.date = defaultDay }
        return guess(.task(p), today: today)
    }

    /// «22 €», «12,50 euros»: sin el símbolo o la palabra, un número suelto es más probable que sea parte de una tarea.
    static func looksLikeMoney(_ text: String) -> Bool {
        text.contains("€") || text.range(of: #"(^|\s)[0-9]+([.,][0-9]+)?\s*(euros?|eur)(\s|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func name(_ rel: String) -> String { ((rel as NSString).lastPathComponent as NSString).deletingPathExtension }

    static func guess(_ c: QuickCommand, today: Date = DayKey.today()) -> CaptureGuess {
        typealias Chip = CaptureGuess.Chip
        func day(_ d: Date) -> String {
            switch DayKey.days(from: today, to: d) {
            case 0: "hoy"
            case 1: "mañana"
            case -1: "ayer"
            default: dayLabel(d)
            }
        }
        func kind(_ s: String) -> Chip { Chip(label: "", value: s, tone: .kind) }
        func when(_ d: Date) -> Chip { Chip(label: "Fecha", value: day(d), tone: .date) }
        switch c {
        case .task(let p):
            // Solo con hora, es para hoy (como en `Store.addTask`).
            let d = p.date ?? (p.time != nil ? today : nil)
            var chips = [kind("Tarea"), d.map(when) ?? Chip(label: "Fecha", value: "sin fecha", tone: .place)]
            if let t = p.time, d != nil { chips.append(Chip(label: "Hora", value: TimeOfDay.text(t), tone: .date)) }
            if let m = p.duration { chips.append(Chip(label: "Dura", value: TaskDuration.human(m), tone: .date)) }
            if let r = p.recurrence { chips.append(Chip(label: "Repite", value: Recurrence.describe(r), tone: .date)) }
            if p.priority > 0 { chips.append(Chip(label: "Prioridad", value: ["", "baja", "media", "alta"][min(max(p.priority, 0), 3)], tone: p.priority == 3 ? .warn : .place)) }
            if p.muted { chips.append(Chip(label: "Aviso", value: "no", tone: .place)) }
            return CaptureGuess(command: c, chips: chips, destination: name(VaultPath.inbox))
        case .appointment(_, let d, let h):
            var chips = [kind("Cita"), when(d)]
            if let h { chips.append(Chip(label: "Hora", value: TimeOfDay.text(h), tone: .date)) }
            return CaptureGuess(command: c, chips: chips, destination: name(VaultPath.medico))
        case .expense(let p):
            var chips = [kind(p.amount < 0 ? "Devolución" : "Gasto"), Chip(label: "Importe", value: Money.exact(abs(p.amount)), tone: .amount),
                         Chip(label: "Partida", value: p.category ?? "Imprevistos", tone: p.category == nil ? .warn : .place), when(p.date)]
            if let who = p.person { chips.append(Chip(label: "Con", value: who, tone: .place)) }
            return CaptureGuess(command: c, chips: chips, destination: "Gastos")
        case .weight(let kg, let d):
            return CaptureGuess(command: c, chips: [kind("Peso"), Chip(label: "", value: MD.formatNumber(kg, comma: true) + " kg", tone: .amount), when(d)], destination: name(VaultPath.peso))
        case .sleep(let h, let d):
            return CaptureGuess(command: c, chips: [kind("Sueño"), Chip(label: "", value: MD.formatNumber(h, comma: true) + " h", tone: .amount), when(d)], destination: "Nota del día")
        case .injection(let d):
            return CaptureGuess(command: c, chips: [kind("Toma o pinchazo"), when(d)], destination: name(VaultPath.medicacion))
        case .idea:
            return CaptureGuess(command: c, chips: [kind("Idea")], destination: name(VaultPath.inbox) + " · Ideas")
        case .diary:
            return CaptureGuess(command: c, chips: [kind("Apunte"), when(today)], destination: "Nota de hoy")
        case .measure(let f, let v, let d):
            return CaptureGuess(command: c, chips: [kind("Medida"), Chip(label: f, value: MD.formatNumber(v, comma: true), tone: .amount), when(d)], destination: name(VaultPath.medidas))
        case .shopping(let items):
            return CaptureGuess(command: c, chips: [kind("Compra")] + items.map { Chip(label: "", value: $0, tone: .place) }, destination: name(VaultPath.compra))
        case .book(let t, let a):
            return CaptureGuess(command: c, chips: [kind("Libro"), Chip(label: "", value: t, tone: .place)] + (a.isEmpty ? [] : [Chip(label: "de", value: a, tone: .place)]), destination: name(VaultPath.lecturas))
        case .finishBook(let t):
            return CaptureGuess(command: c, chips: [kind("Libro terminado"), Chip(label: "", value: t, tone: .place), when(today)], destination: name(VaultPath.lecturas))
        case .loanPayment(let t):
            return CaptureGuess(command: c, chips: [kind("Cuota"), Chip(label: "", value: t, tone: .place)], destination: name(VaultPath.prestamos))
        }
    }
}

/// Las etiquetas de lo que se entendió y la nota donde irá.
struct CaptureChips: View {
    let guess: CaptureGuess

    private func color(_ t: CaptureGuess.Tone) -> Color {
        switch t {
        case .kind: Brand.accent
        case .date: Brand.info
        case .amount: Brand.sky
        case .place: Brand.slate
        case .warn: Brand.warn
        }
    }

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(guess.chips, id: \.self) { c in
                HStack(spacing: 4) {
                    if !c.label.isEmpty { Text(c.label).foregroundStyle(.secondary) }
                    Text(c.value).fontWeight(.medium)
                }
                .font(.caption).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(color(c.tone).opacity(0.15), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
            }
            Label(guess.destination, systemImage: "doc.text").font(.caption).foregroundStyle(.secondary).padding(.vertical, 3)
        }
        .accessibilityElement(children: .combine)
    }
}

/// El campo de añadir que comparten Inicio, Tareas, Mi día, la semana, el panel Hoy, Cerrar el día y la barra de menús.
/// Mientras se escribe enseña lo que va a guardar; al pulsar intro lo guarda con `Store.run` y deja el cursor para la siguiente.
struct CaptureField: View {
    @Environment(Store.self) private var store
    var placeholder = "Añadir tarea… (ej: llamar al dentista el viernes a las 17:30)"
    /// Día de la pantalla: las tareas sin fecha en la frase van a ese día.
    var defaultDay: Date? = nil
    /// Sin botón «Añadir» (columnas estrechas): se guarda con intro.
    var compact = false
    @State private var text = ""
    @State private var feedback = ""
    @FocusState private var focused: Bool

    var body: some View {
        let guess = Capture.interpret(text, defaultDay: defaultDay, tasksOnly: true)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(placeholder, text: $text).focused($focused).onSubmit { save(guess) }
                if !compact { Button("Añadir") { save(guess) }.disabled(guess == nil) }
            }
            if let guess { CaptureChips(guess: guess) }
            else if !feedback.isEmpty { Label(feedback, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Brand.accent) }
        }
        // El «Añadido…» se va solo: si no, seguía en el panel horas después.
        .task(id: feedback) {
            guard !feedback.isEmpty else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { feedback = "" }
        }
    }

    private func save(_ guess: CaptureGuess?) {
        guard let guess else { return }
        feedback = store.run(guess.command)
        text = ""
        focused = true
    }
}
