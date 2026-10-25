import SwiftUI

struct TareasView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case todas = "Todas", hoy = "Hoy", semana = "7 días", vencidas = "Vencidas", sinFecha = "Sin fecha"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @State private var filter = Filter.todas
    @State private var search = ""
    @State private var byNote = false

    private func matches(_ t: TaskItem) -> Bool {
        let today = DayKey.today()
        let limit = DayKey.adding(days: 7, to: today)
        let q = MD.fold(search)
        if !q.isEmpty, !MD.fold(t.text).contains(q), !MD.fold(t.noteName).contains(q) { return false }
        switch filter {
        case .todas: return true
        case .hoy: return (t.due ?? t.scheduled).map { $0 <= today } ?? false
        case .semana: return (t.due ?? t.scheduled).map { $0 <= limit } ?? false
        case .vencidas: return t.due.map { $0 < today } ?? false
        case .sinFecha: return t.due == nil && t.scheduled == nil
        }
    }

    var body: some View {
        let _ = BodyCounter.hit("TareasView")
        let _ = store.today   // se rehace al cambiar de día
        let open = store.tasks.filter { !$0.done && matches($0) }
        let done = store.tasks.filter(\.done).sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Card(title: "Nueva tarea", icon: "plus.circle", info: "Sin fecha en la frase va al Inbox. Entiende “mañana”, “el viernes a las 17:30”, “durante 1h”, “cada lunes”, “urgente” y 🔕.") {
                    CaptureField(placeholder: "Qué hay que hacer (ej: llamar al dentista el viernes a las 17:30)")
                }
                // Con el panel Hoy abierto no siempre cabe en una fila: entonces la búsqueda baja a la segunda.
                ViewThatFits(in: .horizontal) {
                    HStack { filterPicker; searchRow }
                    VStack(alignment: .leading, spacing: 10) { filterPicker; searchRow }
                }
                dropTargets
                if byNote {
                    ForEach(Dictionary(grouping: open, by: \.noteName).keys.sorted(), id: \.self) { n in
                        section(n, open.filter { $0.noteName == n }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
                    }
                } else {
                    let today = DayKey.today()
                    // Vence solo la fecha límite; una tarea programada para un día pasado sigue siendo «para hoy».
                    let overdueTasks = open.filter { ($0.due ?? .distantFuture) < today }
                    let rest = open.filter { ($0.due ?? .distantFuture) >= today }
                    let day = { (t: TaskItem) in t.due ?? t.scheduled }
                    let groups: [(String, [TaskItem])] = [
                        ("Vencidas", overdueTasks),
                        ("Hoy", rest.filter { day($0).map { $0 <= today } ?? false }),
                        ("Mañana", rest.filter { day($0) == DayKey.adding(days: 1, to: today) }),
                        ("Esta semana", rest.filter { day($0).map { $0 >= DayKey.adding(days: 2, to: today) && $0 <= DayKey.adding(days: 7, to: today) } ?? false }),
                        ("Más adelante", rest.filter { day($0).map { $0 > DayKey.adding(days: 7, to: today) } ?? false }),
                        ("Sin fecha", rest.filter { day($0) == nil }),
                    ]
                    ForEach(groups.filter { !$0.1.isEmpty }, id: \.0) { g in
                        section(g.0, g.1.sorted { a, b in a.priority != b.priority ? a.priority > b.priority : (a.due ?? .distantFuture) < (b.due ?? .distantFuture) })
                    }
                    if open.isEmpty { EmptyNote(emptyText, icon: "checkmark.circle") }
                }
                if !done.isEmpty {
                    DisclosureGroup("Completadas (\(done.count))") {
                        VStack(alignment: .leading, spacing: 6) { ForEach(done.prefix(30)) { TaskRow(task: $0) } }.padding(.top, 6)
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Tareas")
    }

    private func section(_ title: String, _ items: [TaskItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text("\(title) (\(items.count))").font(.headline).foregroundStyle(title == "Vencidas" ? Brand.bad : .primary)
            ForEach(items) { TaskRow(task: $0).draggable($0.id) }
        }
    }

    private var filterPicker: some View {
        let overdue = store.tasks.filter { !$0.done && ($0.due.map { $0 < DayKey.today() } ?? false) }.count
        return Picker("", selection: $filter) { ForEach(Filter.allCases) { Text($0 == .vencidas && overdue > 0 ? "Vencidas (\(overdue))" : $0.rawValue).tag($0) } }
            .pickerStyle(.segmented).labelsHidden().frame(width: 420)
    }

    private var searchRow: some View {
        HStack {
            TextField("Buscar tarea o nota", text: $search).frame(width: 220)
            Toggle("Agrupar por nota", isOn: $byNote).toggleStyle(.checkbox).fixedSize()
            InfoButton(text: "Se leen de todas tus notas (líneas “- [ ] texto 📅 fecha”). Arrastra una tarea a las etiquetas de fecha para cambiársela. Pasa el ratón por una tarea para aplazarla o editarla; el nombre de la nota abre esa nota.")
        }
    }

    private var emptyText: String {
        if !search.isEmpty { return "Ninguna tarea contiene «\(search)»." }
        switch filter {
        case .todas: return "No hay tareas pendientes. Escribe una arriba o apúntala en cualquier nota como «- [ ] texto»."
        case .hoy: return "Nada para hoy. Arrastra aquí arriba, a «Hoy», lo que quieras hacer."
        case .semana: return "Nada en los próximos 7 días."
        case .vencidas: return "Nada vencido."
        case .sinFecha: return "Todas las tareas tienen fecha."
        }
    }

    /// Arrastrar una tarea a una de estas etiquetas le cambia la fecha (o se la quita).
    private var dropTargets: some View {
        let today = DayKey.today()
        let wd = DayKey.calendar().component(.weekday, from: today)
        let monday = DayKey.adding(days: (9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7, to: today)
        let targets: [(String, Date?)] = [("Hoy", today), ("Mañana", DayKey.adding(days: 1, to: today)), ("El lunes", monday), ("En una semana", DayKey.adding(days: 7, to: today)), ("Sin fecha", nil)]
        return HStack(spacing: 6) {
            Text("Arrastra una tarea a:").font(.caption).foregroundStyle(.secondary)
            ForEach(targets, id: \.0) { DropChip(title: $0.0, day: $0.1) }
        }
    }
}

/// Etiqueta de fecha de Tareas: se ilumina al pasar una tarea por encima y, al soltarla, se la pone (o le quita la fecha).
private struct DropChip: View {
    @Environment(Store.self) private var store
    let title: String
    let day: Date?
    @State private var targeted = false

    var body: some View {
        Text(title).font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(targeted ? Brand.accent.opacity(0.3) : Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(targeted ? Brand.accent : Color.clear))
            .dropDestination(for: String.self) { ids, _ in
                guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }) else { return false }
                if let day { store.reschedule(t, to: day) } else { store.unschedule(t) }
                return true
            } isTargeted: { targeted = $0 }
    }
}
