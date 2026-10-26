import SwiftUI

// MARK: - Editar una tarea (hoja de Tareas y ficha del Calendario y Mi día)

/// Lo que se está editando de una tarea, antes de guardarlo. Puro: `apply` da el texto nuevo de la nota.
struct TaskDraft: Equatable {
    var text = ""
    var hasDue = false
    var due = DayKey.today()
    var hasTime = false
    /// Minutos desde medianoche.
    var time = 10 * 60
    /// 0 = sin calcular.
    var duration = 0
    var priority = 0
    var muted = false

    init(_ t: TaskItem) {
        text = t.text; hasDue = t.due != nil; due = t.due ?? DayKey.today()
        hasTime = t.time != nil; time = t.time ?? 10 * 60
        duration = t.duration ?? 0; priority = t.priority; muted = t.muted
    }

    var isValid: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// La tarea cambió mientras se editaba (se arrastró a otra hora): lo que no se ha tocado en el formulario toma el valor
    /// nuevo; lo que sí, se queda como lo dejó quien edita.
    func rebased(from base: TaskDraft, onto new: TaskDraft) -> TaskDraft {
        var d = self
        if text == base.text { d.text = new.text }
        if hasDue == base.hasDue { d.hasDue = new.hasDue }
        if due == base.due { d.due = new.due }
        if hasTime == base.hasTime { d.hasTime = new.hasTime }
        if time == base.time { d.time = new.time }
        if duration == base.duration { d.duration = new.duration }
        if priority == base.priority { d.priority = new.priority }
        if muted == base.muted { d.muted = new.muted }
        return d
    }

    /// El texto de la nota con la tarea cambiada (`nil` si la línea ya no está). La hora solo va con fecha.
    func apply(_ note: String, task: TaskItem) -> String? {
        Edit.updateTask(note, task: task, newText: text, due: hasDue ? due : nil, priority: priority,
                        time: .some(hasDue && hasTime ? time : nil), muted: muted, duration: .some(duration > 0 ? duration : nil))
    }
}

extension Store {
    func save(_ draft: TaskDraft, for t: TaskItem) {
        edit(t.file) { draft.apply($0, task: t) }
    }
}

/// El formulario de una tarea. `focusToken`: cada vez que cambia, el cursor va al texto (doble clic en un bloque).
struct TaskEditor: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    var focusToken = 0
    /// Al guardar, cancelar o eliminar.
    var onClose: () -> Void
    @State private var draft: TaskDraft
    @State private var base: TaskDraft
    /// La tarea sobre la que se guarda: la de cuando se empezó a editar, puesta al día solo si sigue siendo la misma.
    @State private var origin: TaskItem
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    init(task: TaskItem, focusToken: Int = 0, onClose: @escaping () -> Void) {
        self.task = task
        self.focusToken = focusToken
        self.onClose = onClose
        _draft = State(initialValue: TaskDraft(task))
        _base = State(initialValue: TaskDraft(task))
        _origin = State(initialValue: task)
    }

    private var priorityPicker: some View {
        Picker("Prioridad", selection: $draft.priority) { Text("Ninguna").tag(0); Text("Baja").tag(1); Text("Media").tag(2); Text("Alta").tag(3) }
            .labelsHidden()
    }

    private var dirty: Bool { draft != base }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Texto", text: $draft.text).focused($focused).onSubmit(save)
            HStack {
                Toggle("Día", isOn: $draft.hasDue).toggleStyle(.checkbox)
                DatePicker("", selection: Binding(get: { draft.due }, set: { draft.due = DayKey.calendar().startOfDay(for: $0) }), displayedComponents: .date)
                    .labelsHidden().disabled(!draft.hasDue).fixedSize()
            }
            HStack {
                Toggle("A las", isOn: $draft.hasTime).toggleStyle(.checkbox).disabled(!draft.hasDue)
                DatePicker("Hora", selection: Binding(get: { TimeOfDay.date(draft.time) }, set: { draft.time = TimeOfDay.minutes(of: $0) }), displayedComponents: .hourAndMinute)
                    .labelsHidden().disabled(!draft.hasDue || !draft.hasTime).fixedSize()
                Picker("Dura", selection: $draft.duration) {
                    Text("Sin calcular").tag(0)
                    ForEach(TaskDuration.presets(including: draft.duration), id: \.self) { Text(TaskDuration.human($0)).tag($0) }
                }.fixedSize().help("Altura del bloque en Mi día y duración del evento en Calendar (⏱ en la nota).")
            }
            // En el panel (300 pt) las cuatro pestañas no caben desde macOS 27 (cada una mide lo que «Ninguna»): ahí, menú.
            ViewThatFits(in: .horizontal) {
                priorityPicker.pickerStyle(.segmented).fixedSize()
                priorityPicker.pickerStyle(.menu).fixedSize()
            }
            Toggle("Sin aviso en Calendar ni notificaciones", isOn: $draft.muted).toggleStyle(.checkbox)
                .help("Sigue en Tareas y en el Calendario de la app; solo deja de ir a Calendar de macOS y a las notificaciones (🔕 en la nota).")
            HStack(spacing: 6) {
                if let r = origin.recurrence { Label(Recurrence.describe(r), systemImage: "repeat").font(.caption).foregroundStyle(.secondary) }
                Button("En la nota \(origin.noteName)") { store.pendingNote = origin.file }.buttonStyle(.accentLink).font(.caption)
            }
            HStack {
                Button(origin.done ? "Pendiente" : "Completar") { store.setTask(origin, done: !origin.done); onClose() }
                if confirmDelete { Button("Confirmar", role: .destructive) { store.deleteTask(origin); onClose() } }
                else { Button("Eliminar", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("Cancelar", action: onClose).keyboardShortcut(.cancelAction)
                Button("Guardar", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!dirty || !draft.isValid)
            }.controlSize(.small)
        }
        .onAppear { if focusToken > 0 { focused = true } }
        .onChange(of: focusToken) { focused = true }
        // La tarea cambió por otro lado. Si es la misma (mismo texto y nota: se arrastró a otra hora), la ficha se pone al día
        // sin perder lo que se está escribiendo. Si es otra (la nota cambió fuera y otra tarea ocupa esa línea), se sigue
        // guardando sobre la de antes, que se busca por su línea exacta: si ya no está, no se toca nada.
        .onChange(of: task) {
            guard task.file == origin.file, task.text == origin.text || !dirty else { return }
            let new = TaskDraft(task)
            draft = dirty ? draft.rebased(from: base, onto: new) : new
            base = new
            origin = task
        }
    }

    private func save() {
        guard draft.isValid else { return }
        if dirty { store.save(draft, for: origin) }
        onClose()
    }
}

// MARK: - Lo que se ha seleccionado en el Calendario o en Mi día

/// Lo seleccionado: el id y el título de cuando se pulsó. Los ids de tarea son «nota:línea»; si la nota cambia fuera de la app
/// y otra tarea pasa a esa línea, el título ya no coincide y la ficha se cierra en vez de enseñar otra tarea.
struct EventSelection: Equatable {
    var id: String
    var title: String

    func resolve(day: Date, blocks: [TimeBlock], agenda: [AgendaItem]) -> EventRef? {
        EventRef.find(id, day: day, blocks: blocks, agenda: agenda).flatMap { $0.title == title ? $0 : nil }
    }

    func matches(_ b: TimeBlock) -> Bool { b.id == id && b.title == title }
}

/// Un elemento de la agenda (bloque con hora o elemento de todo el día), con lo necesario para la ficha.
struct EventRef: Equatable {
    var id: String
    var title: String
    var detail = ""
    var kind: AgendaItem.Kind
    var date: Date
    var minutes: Int?
    var duration: Int?
    var task: TaskItem?
    var screen: Screen?
    var path: String?

    static func == (a: EventRef, b: EventRef) -> Bool { a.id == b.id && a.title == b.title && a.minutes == b.minutes && a.date == b.date && a.task == b.task }

    /// Busca `id` entre los bloques del día y lo de todo el día. `nil` si ya no está (se borró o cambió fuera de la app).
    static func find(_ id: String, day: Date, blocks: [TimeBlock], agenda: [AgendaItem]) -> EventRef? {
        if let b = blocks.first(where: { $0.id == id }) {
            return EventRef(id: b.id, title: b.title, detail: b.detail, kind: b.kind, date: day, minutes: b.start, duration: b.duration,
                            task: b.task, screen: b.screen, path: b.path)
        }
        if let i = agenda.first(where: { $0.id == id }) {
            return EventRef(id: i.id, title: i.title, detail: i.detail, kind: i.kind, date: i.date, minutes: i.minutes, task: i.task, screen: i.screen, path: i.path)
        }
        return nil
    }
}

/// La ficha del elemento seleccionado: las tareas se editan; las citas de una nota de visita, su fecha y hora; el resto
/// (medicación, cumpleaños, renovaciones…) se ve y lleva a su pantalla, porque su dato vive en la tabla de otro módulo.
struct EventPanel: View {
    @Environment(Store.self) private var store
    let event: EventRef
    var focusToken = 0
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: event.kind.icon).foregroundStyle(event.kind.color)
                Text(MDParser.inline(event.title)).font(.headline).lineLimit(2)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").accessibilityLabel("Cerrar") }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            if let t = event.task {
                TaskEditor(task: t, focusToken: focusToken, onClose: onClose).id(t.id)
            } else if let p = event.path, store.noteMeta[p]?["tipo"] == "cita_medica" {
                VisitEditor(path: p, onClose: onClose).id(p)
            } else {
                Text(when).foregroundStyle(.secondary)
                if !event.detail.isEmpty { Text(event.detail).font(.callout) }
                HStack {
                    if let s = event.screen { Button("Ir a \(store.title(s))") { store.screen = s } }
                    else if let p = event.path { Button("Abrir la nota") { store.pendingNote = p } }
                    Spacer()
                    Button("Cerrar", action: onClose).keyboardShortcut(.cancelAction)
                }.controlSize(.small)
                Text("Se cambia en su pantalla: aquí solo se ve.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(event.kind.color.opacity(0.07), in: RoundedRectangle(cornerRadius: Brand.radius))
        .overlay(RoundedRectangle(cornerRadius: Brand.radius).stroke(event.kind.color.opacity(0.35)))
    }

    private var when: String {
        capitalizedFirst(DayKey.esLong(event.date, .dateTime.weekday(.wide).day().month(.wide)))
            + (event.minutes.map { m in " · " + TimeOfDay.text(m) + (event.duration.map { d in "–" + TimeOfDay.text(m + d) } ?? "") } ?? "")
    }
}

/// Fecha y hora de una cita guardada como nota propia (`fecha:` y `hora:` en su encabezado).
private struct VisitEditor: View {
    @Environment(Store.self) private var store
    let path: String
    let onClose: () -> Void
    @State private var date = DayKey.today()
    @State private var hasTime = false
    @State private var time = 10 * 60
    @State private var base: (Date, Bool, Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Día")
                DatePicker("", selection: Binding(get: { date }, set: { date = DayKey.calendar().startOfDay(for: $0) }), displayedComponents: .date).labelsHidden().fixedSize()
                Toggle("A las", isOn: $hasTime).toggleStyle(.checkbox)
                DatePicker("Hora", selection: Binding(get: { TimeOfDay.date(time) }, set: { time = TimeOfDay.minutes(of: $0) }), displayedComponents: .hourAndMinute)
                    .labelsHidden().disabled(!hasTime).fixedSize()
            }
            HStack {
                Button("Abrir la nota") { store.pendingNote = path }
                Spacer()
                Button("Cancelar", action: onClose).keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    store.saveVisit(path, date: date, time: hasTime ? time : nil)
                    onClose()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(base.map { $0 == (date, hasTime, time) } ?? false)
            }.controlSize(.small)
        }
        .onAppear {
            let m = store.noteMeta[path] ?? [:]
            date = m["fecha"].flatMap(DayKey.date) ?? DayKey.today()
            let t = m["hora"].flatMap(TimeOfDay.parse)
            hasTime = t != nil; time = t ?? 10 * 60
            base = (date, hasTime, time)
        }
    }
}

extension Store {
    /// Cambia `fecha:` y `hora:` de una nota de visita en un solo deshacer. Sin hora, la quita.
    func saveVisit(_ path: String, date: Date, time: Int?) {
        grouped {
            setProperty(path, key: "fecha", value: DayKey.string(date))
            if let time { setProperty(path, key: "hora", value: TimeOfDay.text(time)) }
            else if noteMeta[path]?["hora"] != nil { setProperty(path, key: "hora", value: "") }
        }
    }
}
