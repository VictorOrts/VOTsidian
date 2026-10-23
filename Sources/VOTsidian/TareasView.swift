import SwiftUI

struct TareasView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case todas = "Todas", hoy = "Hoy", semana = "7 días", vencidas = "Vencidas", sinFecha = "Sin fecha"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @State private var text = ""
    @State private var hasDue = false
    @State private var due = Date()
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
        let open = store.tasks.filter { !$0.done && matches($0) }
        let done = store.tasks.filter(\.done).sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
        let overdue = store.tasks.filter { !$0.done && ($0.due.map { $0 < DayKey.today() } ?? false) }.count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Card(title: "Nueva tarea (va al Inbox)", icon: "plus.circle") {
                    HStack {
                        TextField("Qué hay que hacer", text: $text).onSubmit(add)
                        Toggle("Fecha", isOn: $hasDue).toggleStyle(.checkbox)
                        DatePicker("", selection: $due, displayedComponents: .date).labelsHidden().disabled(!hasDue)
                        Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                HStack {
                    Picker("", selection: $filter) { ForEach(Filter.allCases) { Text($0 == .vencidas && overdue > 0 ? "Vencidas (\(overdue))" : $0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 420)
                    TextField("Buscar tarea o nota", text: $search).frame(width: 220)
                    Toggle("Agrupar por nota", isOn: $byNote).toggleStyle(.checkbox)
                    InfoButton(text: "Se leen de todas tus notas (líneas “- [ ] texto 📅 fecha”). Pasa el ratón por una tarea para aplazarla o editarla; el nombre de la nota abre esa nota.")
                }
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
                    if open.isEmpty { EmptyNote("Ninguna tarea en este filtro.", icon: "checkmark.circle") }
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

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTask(t, due: hasDue ? DayKey.calendar().startOfDay(for: due) : nil)
        text = ""; hasDue = false
    }

    private func section(_ title: String, _ items: [TaskItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text("\(title) (\(items.count))").font(.headline).foregroundStyle(title == "Vencidas" ? Brand.bad : .primary)
            ForEach(items) { TaskRow(task: $0) }
        }
    }
}
