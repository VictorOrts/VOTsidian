import SwiftUI

/// Reparto de las tareas abiertas por días de una semana (lógica pura, para poder probarla).
struct WeekPlan {
    var start: Date
    var days: [Date]
    var tasks: [String: [TaskItem]]
    var overdue: [TaskItem]
    var undated: [TaskItem]
    var other: [String: [AgendaItem]]

    /// Día de una tarea: su fecha límite o, si no tiene, el día planeado.
    static func day(of t: TaskItem) -> Date? { t.due ?? t.scheduled }

    static func build(tasks all: [TaskItem], agenda: [String: [AgendaItem]], weekStart: Date, today: Date = DayKey.today()) -> WeekPlan {
        let days = (0..<7).map { DayKey.adding(days: $0, to: weekStart) }
        let keys = Set(days.map(DayKey.string))
        func order(_ a: TaskItem, _ b: TaskItem) -> Bool { a.priority != b.priority ? a.priority > b.priority : a.text < b.text }
        var byDay: [String: [TaskItem]] = [:]
        var overdue: [TaskItem] = []
        var undated: [TaskItem] = []
        let limit = min(weekStart, today)
        for t in all where !t.done {
            guard let d = day(of: t) else { undated.append(t); continue }
            if keys.contains(DayKey.string(d)) { byDay[DayKey.string(d), default: []].append(t) }
            else if d < limit { overdue.append(t) }
        }
        for k in byDay.keys { byDay[k]?.sort(by: order) }
        var other: [String: [AgendaItem]] = [:]
        for (k, items) in agenda where keys.contains(k) {
            other[k] = items.filter { $0.task == nil && $0.kind != .diary && $0.kind != .weight && $0.kind != .dose }
        }
        return WeekPlan(start: weekStart, days: days, tasks: byDay,
                        overdue: overdue.sorted { (day(of: $0) ?? .distantPast) < (day(of: $1) ?? .distantPast) },
                        undated: undated.sorted(by: order), other: other)
    }

    /// Un día con más de `limit` tareas se considera cargado.
    static let busyLimit = 5
    func load(_ d: Date) -> Int { tasks[DayKey.string(d)]?.count ?? 0 }
}

extension Store {
    func unschedule(_ t: TaskItem) {
        edit(t.file) { Edit.updateTask($0, task: t, newText: t.text, due: nil) }
    }

    /// Pasa a hoy todo lo vencido (de una sola vez, para poder deshacerlo con un paso).
    func moveOverdueToToday() {
        let today = DayKey.today()
        let overdue = tasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) }
        for (file, group) in Dictionary(grouping: overdue, by: \.file) {
            edit(file) { text in
                var out: String? = text
                for t in group { out = out.flatMap { Edit.updateTask($0, task: t, newText: t.text, due: today) } }
                return out
            }
        }
    }
}

struct PlanificarView: View {
    @Environment(Store.self) private var store
    @State private var offset = 0
    @State private var drafts: [String: String] = [:]
    @State private var editing: TaskItem?
    @State private var message = ""
    @State private var showAllUndated = false
    @State private var hoverDay: String?

    private var weekStart: Date { DayKey.adding(days: offset * 7, to: DayKey.weekStart(Date())) }

    var body: some View {
        let _ = BodyCounter.hit("PlanificarView")
        let end = DayKey.adding(days: 6, to: weekStart)
        let plan = WeekPlan.build(tasks: store.tasks, agenda: store.agenda(from: weekStart, to: end), weekStart: weekStart)
        let total = plan.days.reduce(0) { $0 + plan.load($1) }
        let busy = plan.days.filter { plan.load($0) > WeekPlan.busyLimit }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Anterior") }
                    Text("\(shortDate(weekStart)) – \(shortDate(end))").font(.title3.weight(.semibold)).frame(minWidth: 180)
                    Button { offset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }
                    if offset != 0 { Button("Esta semana") { offset = 0 } }
                    InfoButton(text: "Arrastra una tarea a otro día para cambiarle la fecha, o a «Sin fecha» para quitársela. Pasa el ratón por un día para añadirle una tarea.")
                    Spacer()
                    if total > 0 {
                        Text("\(total) \(total == 1 ? "tarea" : "tareas")" + (busy > 0 ? " · \(busy) \(busy == 1 ? "día cargado" : "días cargados")" : ""))
                            .font(.callout).foregroundStyle(busy > 0 ? Brand.warn : .secondary)
                    }
                }
                if !message.isEmpty { Label(message, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent) }

                // Una fila de lunes a domingo, para que se lea como una semana.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 7), alignment: .leading, spacing: 8) {
                    ForEach(plan.days, id: \.self) { day in dayColumn(day, plan) }
                }

                // Sin vencidas basta una línea; «Sin fecha» usa entonces todo el ancho.
                if plan.overdue.isEmpty {
                    Label("Nada vencido", systemImage: "checkmark.circle").foregroundStyle(Brand.good)
                    undatedCard(plan)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        overdueCard(plan)
                        undatedCard(plan)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Planificar semana")
        .sheet(item: $editing) { TaskSheet(task: $0) }
    }

    // MARK: Columna de un día

    private func dayColumn(_ day: Date, _ plan: WeekPlan) -> some View {
        let key = DayKey.string(day)
        let list = plan.tasks[key] ?? []
        let isToday = day == DayKey.today()
        let busy = list.count > WeekPlan.busyLimit
        let past = day < DayKey.today()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(capitalizedFirst(DayKey.esLong(day, .dateTime.weekday(.abbreviated).day()))).font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? Brand.accent : .primary)
                Spacer()
                if busy { Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Brand.warn).help("Día cargado") }
                if !list.isEmpty { Text("\(list.count)").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(plan.other[key] ?? []) { it in
                HStack(spacing: 6) {
                    Image(systemName: it.kind.icon).font(.caption2).foregroundStyle(it.kind.color)
                    Text(MDParser.inline(it.title)).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
            }
            ForEach(list) { t in taskCard(t, overdue: past) }
            Spacer(minLength: 0)
            // El campo solo se ve al pasar el ratón por el día (o si ya tiene algo escrito): la semana vacía queda limpia.
            TextField("Añadir…", text: Binding(get: { drafts[key] ?? "" }, set: { drafts[key] = $0 }))
                .font(.caption).onSubmit { add(to: day) }
                .opacity(hoverDay == key || !(drafts[key] ?? "").isEmpty ? 1 : 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hoverDay = $0 ? key : (hoverDay == key ? nil : hoverDay) }
        .background(isToday ? Brand.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Brand.radius))
        .overlay(RoundedRectangle(cornerRadius: Brand.radius).stroke(busy ? Brand.warn.opacity(0.7) : (isToday ? Brand.accent.opacity(0.5) : Color.clear), lineWidth: 1.5))
        .dropDestination(for: String.self) { ids, _ in
            guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }) else { return false }
            if WeekPlan.day(of: t) != day { store.reschedule(t, to: day); message = "«\(t.text)» pasa al \(shortDate(day))" }
            return true
        }
    }

    private func taskCard(_ t: TaskItem, overdue: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { store.setTask(t, done: true) } label: { Image(systemName: "circle").accessibilityLabel("Completar") }.buttonStyle(.plain).foregroundStyle(Brand.accent).help("Completar")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if t.priority > 0 { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(t.priority == 3 ? Brand.bad : t.priority == 2 ? Brand.warn : Brand.info) }
                    Text(MDParser.inline(t.text)).font(.callout).lineLimit(3)
                }
                if t.noteName != "Inbox" { Text(t.noteName).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
            if t.recurrence != nil { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Brand.radius))
        .overlay(RoundedRectangle(cornerRadius: Brand.radius).stroke(overdue ? Brand.bad.opacity(0.5) : Color.primary.opacity(0.08)))
        .draggable(t.id)
        .contextMenu {
            Button("Editar…") { editing = t }
            Button("Completar") { store.setTask(t, done: true) }
            Button("Quitar la fecha") { store.unschedule(t) }
        }
        .onTapGesture(count: 2) { editing = t }
    }

    // MARK: Vencidas y sin fecha

    private func overdueCard(_ plan: WeekPlan) -> some View {
        Card(title: "Vencidas (\(plan.overdue.count))", icon: "exclamationmark.triangle") {
            ForEach(plan.overdue) { taskCard($0, overdue: true) }
            if !plan.overdue.isEmpty {
                Button("Pasar todas a hoy") { store.moveOverdueToToday(); message = "Lo vencido pasa a hoy" }.controlSize(.small)
            }
        }
    }

    private func undatedCard(_ plan: WeekPlan) -> some View {
        let shown = showAllUndated ? plan.undated : Array(plan.undated.prefix(8))
        return Card(title: "Sin fecha (\(plan.undated.count))", icon: "tray") {
            if plan.undated.isEmpty { EmptyNote("Todo tiene fecha.", icon: "checkmark.circle") }
            ForEach(shown) { taskCard($0, overdue: false) }
            if plan.undated.count > 8 { Button(showAllUndated ? "Ver menos" : "Ver las \(plan.undated.count)") { showAllUndated.toggle() }.buttonStyle(.accentLink) }
            Text("Suelta aquí una tarea para quitarle la fecha.").font(.caption).foregroundStyle(.tertiary)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }) else { return false }
            if WeekPlan.day(of: t) != nil { store.unschedule(t); message = "«\(t.text)» queda sin fecha" }
            return true
        }
    }

    private func add(to day: Date) {
        let key = DayKey.string(day)
        let raw = (drafts[key] ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let p = NaturalDate.extractTask(raw)
        store.addTask(p.text, due: p.date ?? day, recurrence: p.recurrence, priority: p.priority)
        drafts[key] = ""
    }
}
