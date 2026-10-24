import SwiftUI

// MARK: - Columna de horas (Mi día y la semana del Calendario)

/// Altura de una hora en la agenda.
private let hourHeight: CGFloat = 52

private func yOffset(_ minutes: Int) -> CGFloat { CGFloat(minutes) / 60 * hourHeight }

/// Las horas a la izquierda de la agenda. Cada una lleva su `id` («h9») para llevar el scroll a ella.
struct HourLabels: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(String(format: "%02d:00", h)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 42, height: hourHeight, alignment: .topTrailing).offset(y: -6).id("h\(h)")
            }
        }
    }
}

/// Un día de 0 a 24 h con sus bloques. Soltar una tarea encima le pone esa hora (en franjas de 15 minutos); los bloques de
/// tareas se arrastran a otra hora y se estiran por el borde de abajo. Un clic selecciona un bloque (`onSelect`, que abre su
/// ficha); el doble clic, además, lleva el cursor al texto; un clic en un hueco quita la selección.
struct TimelineColumn: View {
    @Environment(Store.self) private var store
    let day: Date
    let blocks: [TimeBlock]
    var compact = false
    var selected: String? = nil
    /// El bloque pulsado (`nil` en un hueco) y si fue doble clic.
    var onSelect: (TimeBlock?, Bool) -> Void = { _, _ in }
    @State private var targeted = false
    /// Duración mientras se estira un bloque, antes de soltar.
    @State private var stretching: (id: String, minutes: Int)?

    var body: some View {
        let cols = DayPlan.columns(blocks)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(0..<24, id: \.self) { h in
                    Rectangle().fill(Color.primary.opacity(h % 6 == 0 ? 0.12 : 0.06)).frame(height: 1).offset(y: yOffset(h * 60))
                }
                ForEach(blocks) { b in
                    let c = cols[b.id] ?? (0, 1)
                    let w = (geo.size.width - 4) / CGFloat(c.of)
                    let minutes = stretching?.id == b.id ? stretching!.minutes : b.duration
                    block(b, minutes: minutes)
                        .frame(width: max(10, w - 2), height: max(compact ? 16 : 20, yOffset(minutes) - 2))
                        .offset(x: 2 + CGFloat(c.column) * w, y: yOffset(b.start) + 1)
                }
                if day == DayKey.today() {
                    let now = TimeOfDay.minutes(of: Date())
                    HStack(spacing: 0) { Circle().fill(Brand.bad).frame(width: 7, height: 7); Rectangle().fill(Brand.bad).frame(height: 1.5) }
                        .offset(y: yOffset(now) - 3.5).allowsHitTesting(false)
                }
            }
        }
        .frame(height: hourHeight * 24)
        .background(targeted ? Brand.accent.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if selected != nil { onSelect(nil, false) } }
        .dropDestination(for: String.self) { ids, location in
            guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }) else { return false }
            store.schedule(t, on: day, at: DayPlan.snap(Double(location.y) / hourHeight * 60))
            return true
        } isTargeted: { targeted = $0 }
    }

    @ViewBuilder private func block(_ b: TimeBlock, minutes: Int) -> some View {
        let tall = yOffset(minutes) >= 34
        let shape = RoundedRectangle(cornerRadius: 5)
        let content = VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let t = b.task, !compact {
                    Button { store.setTask(t, done: !t.done) } label: { Image(systemName: b.done ? "checkmark.circle.fill" : "circle") }
                        .buttonStyle(.plain).foregroundStyle(b.kind.color).accessibilityLabel(b.done ? "Marcar como pendiente" : "Completar")
                } else if !compact {
                    Image(systemName: b.kind.icon).font(.caption).foregroundStyle(b.kind.color)
                }
                if compact {
                    // En la semana las columnas son estrechas: la hora encima del título si cabe; si no, solo el título.
                    VStack(alignment: .leading, spacing: 0) {
                        if tall { Text(TimeOfDay.text(b.start)).foregroundStyle(.secondary) }
                        Text(b.title).lineLimit(tall ? 2 : 1).strikethrough(b.done).foregroundStyle(b.done ? .secondary : .primary)
                    }.font(.caption2)
                } else {
                    Text((tall ? "" : TimeOfDay.text(b.start) + " ") + b.title)
                        .font(.callout).lineLimit(1).strikethrough(b.done)
                        .foregroundStyle(b.done ? .secondary : .primary)
                }
            }
            if tall, !compact {
                Text("\(TimeOfDay.text(b.start))–\(TimeOfDay.text(b.start + minutes))" + (b.detail.isEmpty ? "" : " · \(b.detail)"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 4 : 7).padding(.vertical, compact ? 2 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(b.kind.color.opacity(b.done ? 0.08 : 0.18), in: shape)
        .overlay(alignment: .leading) { Rectangle().fill(b.kind.color).frame(width: 3).clipShape(shape) }
        .clipShape(shape)
        .overlay { if selected == b.id { shape.stroke(Brand.accent, lineWidth: 2) } }
        .help(b.title + (b.detail.isEmpty ? "" : " · \(b.detail)"))
        // El clic simple selecciona al momento (sin esperar a ver si es doble); el doble, además, lleva al texto.
        let tappable = content
            .onTapGesture(count: 2) { onSelect(b, true) }
            .simultaneousGesture(TapGesture().onEnded { onSelect(b, false) })
        if let t = b.task, b.movable {
            tappable
                .overlay(alignment: .bottom) { stretchHandle(b, task: t) }
                .draggable(t.id)
                .contextMenu { taskMenu(t, block: b) }
        } else {
            tappable
                .contextMenu { if let t = b.task { taskMenu(t, block: b) } }
        }
    }

    /// Borde de abajo: arrastrarlo cambia lo que dura, en pasos de 15 minutos.
    private func stretchHandle(_ b: TimeBlock, task t: TaskItem) -> some View {
        Rectangle().fill(Color.clear).frame(height: 7).contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in stretching = (b.id, max(15, DayPlan.snap(Double(b.duration) + Double(v.translation.height) / hourHeight * 60))) }
                    .onEnded { _ in
                        if let s = stretching, s.minutes != b.duration { store.setDuration(t, s.minutes) }
                        stretching = nil
                    }
            )
    }

    @ViewBuilder private func taskMenu(_ t: TaskItem, block b: TimeBlock) -> some View {
        Button(t.done ? "Marcar como pendiente" : "Completar") { store.setTask(t, done: !t.done) }
        if !t.done {
            Button("Quitar la hora") { store.schedule(t, on: day, at: nil) }
            Menu("Dura") {
                ForEach(TaskDuration.presets(including: t.duration ?? 0), id: \.self) { m in
                    Button(TaskDuration.human(m) + (t.duration == m ? " ✓" : "")) { store.setDuration(t, m) }
                }
                if t.duration != nil { Divider(); Button("Sin calcular") { store.setDuration(t, nil) } }
            }
        }
        Button("Editar…") { onSelect(b, true) }
        Button("Abrir la nota \(t.noteName)") { store.pendingNote = t.file }
    }
}

// MARK: - Mi día

struct MiDiaView: View {
    @Environment(Store.self) private var store
    @State private var day = DayKey.today()
    /// Horas que se quieren dedicar al día (tareas y citas).
    @AppStorage("dayCapacity") private var capacity = 8.0
    /// Desde y hasta qué hora reparte «Repartir en los huecos».
    @AppStorage("dayStart") private var dayStart = 9
    @AppStorage("dayEnd") private var dayEnd = 20
    @State private var quick = ""
    @State private var feedback = ""
    @State private var targeted = false
    /// Bloque o elemento de todo el día seleccionado: su ficha sustituye a «Sin hora» mientras está abierta.
    @State private var selectedEvent: String?
    @State private var focusToken = 0
    @FocusState private var focused: Bool

    var body: some View {
        let _ = BodyCounter.hit("MiDiaView")
        let agenda = store.agenda(from: day, to: day)[DayKey.string(day)] ?? []
        let plan = store.dayPlan(day, agenda: agenda)
        let allDay = agenda.filter { $0.minutes == nil && $0.task == nil && $0.kind != .diary && $0.kind != .done }
        HStack(spacing: 0) {
            side(plan, event: selectedEvent.flatMap { EventRef.find($0, day: day, blocks: plan.blocks, agenda: agenda) })
                .frame(width: 340)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                if !allDay.isEmpty {
                    FlowChips(items: allDay, selected: selectedEvent) { select($0.id) }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider()
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        HStack(alignment: .top, spacing: 6) {
                            HourLabels()
                            TimelineColumn(day: day, blocks: plan.blocks, selected: selectedEvent) { b, focus in select(b?.id, focus: focus) }
                        }
                        .padding(.vertical, 12).padding(.trailing, 16)
                    }
                    .onAppear { scroll(proxy, plan) }
                    .onChange(of: day) { scroll(proxy, plan) }
                }
            }
        }
        .navigationTitle("Mi día")
        .onAppear(perform: takePending)
        .onChange(of: store.pendingPlanDay) { takePending() }
    }

    // MARK: Panel de la izquierda

    private func side(_ plan: DayPlan, event: EventRef?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").accessibilityLabel("Día anterior") }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(capitalizedFirst(DayKey.esLong(day, .dateTime.weekday(.wide).day().month(.wide)))).font(.title3.weight(.semibold))
                        Text(relativeDays(DayKey.days(from: DayKey.today(), to: day))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").accessibilityLabel("Día siguiente") }
                    if day != DayKey.today() { Button("Hoy") { day = DayKey.today(); feedback = ""; selectedEvent = nil } }
                }
                capacityBar(plan)
                HStack {
                    if day == DayKey.today() { Button { store.showEmpezar = true } label: { Label("Empezar el día", systemImage: "sunrise") } }
                    Button { distribute(plan) } label: { Label("Repartir", systemImage: "wand.and.stars") }
                        .disabled(plan.unscheduled.isEmpty)
                        .help("Coloca las tareas sin hora en los huecos libres, de \(dayStart):00 a \(dayEnd):00 (se deshace de una vez con ⌥⌘Z).")
                }.controlSize(.small)
                if !feedback.isEmpty { Label(feedback, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent) }
                Divider()
                if let event {
                    EventPanel(event: event, focusToken: focusToken) { select(nil) }
                } else {
                    unscheduledList(plan)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder private func unscheduledList(_ plan: DayPlan) -> some View {
        Text(plan.unscheduled.isEmpty ? "Sin hora" : "Sin hora (\(plan.unscheduled.count))").font(.headline)
        VStack(alignment: .leading, spacing: 6) {
            if plan.unscheduled.isEmpty {
                Text("Todo lo de este día tiene hora.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(plan.unscheduled) { t in UnscheduledRow(task: t, day: day) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .background(targeted ? Brand.accent.opacity(0.1) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Brand.radius))
        .dropDestination(for: String.self) { ids, _ in
            guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }), t.time != nil else { return false }
            store.schedule(t, on: day, at: nil)
            return true
        } isTargeted: { targeted = $0 }
        Text("Arrastra una tarea a una hora. Para quitarle la hora, tráela aquí.").font(.caption).foregroundStyle(.secondary)
        HStack {
            TextField("Añadir a este día (ej: llamar a Ana a las 18:00 durante 30 min)", text: $quick).focused($focused).onSubmit(add)
            Button("Añadir", action: add).disabled(quick.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func capacityBar(_ plan: DayPlan) -> some View {
        let planned = plan.plannedMinutes, limit = Int(capacity * 60)
        let over = planned - limit
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(planned == 0 ? "Nada planificado" : "Planificado \(TaskDuration.human(planned))").font(.callout.weight(.medium))
                Spacer()
                Menu("de \(Int(capacity)) h") {
                    ForEach([4.0, 5, 6, 7, 8, 9, 10], id: \.self) { h in Button("\(Int(h)) h" + (h == capacity ? " ✓" : "")) { capacity = h } }
                }.menuStyle(.borderlessButton).fixedSize().help("Horas que quieres dedicar al día a tareas y citas")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(over > 0 ? Brand.bad : Brand.accent).frame(width: g.size.width * min(1, Double(planned) / Double(max(limit, 1))))
                }
            }.frame(height: 7)
            if over > 0 { Text("Te pasas \(TaskDuration.human(over)). Mueve algo a otro día.").font(.caption).foregroundStyle(Brand.bad) }
            if plan.unestimated > 0 {
                Text(plan.unestimated == 1 ? "1 tarea sin hora ni duración no cuenta: elige cuánto dura en «¿cuánto?»." : "\(plan.unestimated) tareas sin hora ni duración no cuentan: elige cuánto duran en «¿cuánto?».").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Acciones

    private func move(_ days: Int) { day = DayKey.adding(days: days, to: day); feedback = ""; selectedEvent = nil }

    private func select(_ id: String?, focus: Bool = false) {
        selectedEvent = id
        if focus { focusToken += 1 }
    }

    private func takePending() {
        guard let d = store.pendingPlanDay else { return }
        if d != day { selectedEvent = nil }
        day = d
        store.pendingPlanDay = nil
    }

    /// Al abrir, la agenda enseña la hora actual (si es hoy) o el primer bloque.
    private func scroll(_ proxy: ScrollViewProxy, _ plan: DayPlan) {
        let hour = day == DayKey.today() ? TimeOfDay.minutes(of: Date()) / 60 - 1 : (plan.blocks.first.map { $0.start / 60 } ?? dayStart) - 1
        proxy.scrollTo("h\(min(18, max(0, hour)))", anchor: .top)
    }

    private func distribute(_ plan: DayPlan) {
        let now = day == DayKey.today() ? TimeOfDay.minutes(of: Date()) : 0
        let n = store.autoSchedule(plan, from: max(dayStart * 60, now), until: dayEnd * 60)
        let left = plan.unscheduled.count - n
        feedback = n == 0 ? "No queda hueco libre hasta las \(dayEnd):00." : "Repartidas \(n)" + (left > 0 ? "; \(left) no caben" : "") + ". ⌥⌘Z lo deshace."
    }

    private func add() {
        let raw = quick.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        feedback = store.addTask(NaturalDate.extractTask(raw), defaultDue: day)
        quick = ""
        focused = true
    }
}

/// Una tarea sin hora: se arrastra a la agenda; el menú pone lo que dura o la aplaza.
private struct UnscheduledRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    let day: Date

    var body: some View {
        HStack(spacing: 7) {
            Button { store.setTask(task, done: true) } label: { Image(systemName: "circle") }.buttonStyle(.plain).foregroundStyle(Brand.accent).accessibilityLabel("Completar")
            if task.priority > 0 { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(task.priority == 3 ? Brand.bad : Brand.warn) }
            VStack(alignment: .leading, spacing: 1) {
                Text(MDParser.inline(task.text)).lineLimit(2)
                if let d = task.due, d < day { Text("vencida \(dayLabel(d))").font(.caption2).foregroundStyle(Brand.bad) }
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(TaskDuration.presets(including: task.duration ?? 0), id: \.self) { m in Button(TaskDuration.human(m)) { store.setDuration(task, m) } }
                Divider()
                Button("Mañana") { store.reschedule(task, to: DayKey.adding(days: 1, to: day)) }
                Button("En una semana") { store.reschedule(task, to: DayKey.adding(days: 7, to: day)) }
            } label: { Text(task.duration.map(TaskDuration.human) ?? "¿cuánto?").font(.caption).foregroundStyle(task.duration == nil ? .secondary : .primary) }
                .menuStyle(.borderlessButton).fixedSize().help("Cuánto dura, o aplazarla")
        }
        .padding(6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .draggable(task.id)
    }
}

/// Lo de todo el día (cumpleaños, renovaciones, caducidades…), en fichas encima de la agenda.
private struct FlowChips: View {
    let items: [AgendaItem]
    var selected: String?
    let onSelect: (AgendaItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Todo el día").font(.caption).foregroundStyle(.secondary)
                ForEach(items) { it in
                    Button { onSelect(it) } label: {
                        Label(it.title, systemImage: it.kind.icon).font(.caption).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(it.kind.color.opacity(0.15), in: Capsule())
                            .overlay { if selected == it.id { Capsule().stroke(Brand.accent, lineWidth: 1.5) } }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Empezar el día

/// Repaso de la mañana, pareja de «Cerrar el día»: lo que quedó de ayer, lo de hoy y lo que viene, y a repartirlo en las horas.
struct EmpezarSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dayCapacity") private var capacity = 8.0

    var body: some View {
        let today = DayKey.today()
        let open = store.tasks.filter { !$0.done && $0.due != nil }
        let overdue = open.filter { $0.due! < today }.sorted { ($0.due!, -$0.priority) < ($1.due!, -$1.priority) }
        let todays = open.filter { $0.due == today }.sorted { ($0.time ?? 9999, -$0.priority) < ($1.time ?? 9999, -$1.priority) }
        let soon = open.filter { $0.due! > today && $0.due! <= DayKey.adding(days: 3, to: today) }.sorted { $0.due! < $1.due! }
        let plan = store.dayPlan(today)
        VStack(alignment: .leading, spacing: 14) {
            Text("Empezar el día").font(.title2.weight(.semibold))
            Text(summary(plan)).foregroundStyle(plan.plannedMinutes > Int(capacity * 60) ? Brand.bad : .secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("1. Lo que quedó pendiente", overdue, empty: "Nada vencido: buen comienzo.") { t in
                        Button("Hoy") { store.reschedule(t, to: today) }
                        Button("Mañana") { store.reschedule(t, to: DayKey.adding(days: 1, to: today)) }
                        Button("Hecha") { store.setTask(t, done: true) }
                    }
                    section("2. Para hoy", todays, empty: "Nada con fecha de hoy todavía.") { t in
                        if let m = t.time { Text(TimeOfDay.text(m)).monospacedDigit().foregroundStyle(.secondary) }
                        Menu(t.duration.map(TaskDuration.human) ?? "¿cuánto?") {
                            ForEach(TaskDuration.presets(including: t.duration ?? 0), id: \.self) { m in Button(TaskDuration.human(m)) { store.setDuration(t, m) } }
                        }.menuStyle(.borderlessButton).fixedSize()
                        Button("Mañana") { store.reschedule(t, to: DayKey.adding(days: 1, to: today)) }
                    }
                    section("3. Lo que viene (3 días)", soon, empty: "Nada en los próximos días.") { t in
                        Text(dayLabel(t.due!)).font(.caption).foregroundStyle(.secondary)
                        Button("Adelantar a hoy") { store.reschedule(t, to: today) }
                    }
                }
            }.frame(maxHeight: 380)
            HStack {
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { store.pendingPlanDay = today; store.screen = .dia; dismiss() } label: { Label("Repartir en las horas", systemImage: "calendar.day.timeline.left") }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 660)
    }

    private func summary(_ plan: DayPlan) -> String {
        let planned = plan.plannedMinutes, limit = Int(capacity * 60)
        let base = planned == 0 ? "Aún no hay nada planificado con duración." : "Tienes \(TaskDuration.human(planned)) planificadas de \(Int(capacity)) h."
        return planned > limit ? base + " Te pasas \(TaskDuration.human(planned - limit)): aplaza algo." : base
    }

    private func section<Actions: View>(_ title: String, _ tasks: [TaskItem], empty: String, @ViewBuilder actions: @escaping (TaskItem) -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tasks.isEmpty ? title : "\(title) (\(tasks.count))").font(.headline)
            if tasks.isEmpty { Text(empty).font(.callout).foregroundStyle(.secondary) }
            ForEach(tasks.prefix(12)) { t in
                HStack(spacing: 8) {
                    if t.priority > 0 { Image(systemName: "flag.fill").font(.caption).foregroundStyle(t.priority == 3 ? Brand.bad : Brand.warn) }
                    Text(MDParser.inline(t.text)).lineLimit(2)
                    if let d = t.due, d < DayKey.today() { Text("vencida \(dayLabel(d))").font(.caption).foregroundStyle(Brand.bad) }
                    Spacer()
                    actions(t)
                }.controlSize(.small)
            }
            if tasks.count > 12 { Text("y \(tasks.count - 12) más en Tareas").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
