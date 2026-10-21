import SwiftUI

func fmt(_ v: Double?, _ digits: Int = 1, unit: String = "") -> String {
    guard let v else { return "–" }
    return String(format: "%.\(digits)f", v) + unit
}

func fmtDelta(_ v: Double?, unit: String = " kg") -> String {
    guard let v else { return "–" }
    return String(format: "%+.1f", v) + unit
}

func shortDate(_ d: Date) -> String { DayKey.esLong(d, .dateTime.day().month(.abbreviated)) }
func longDate(_ d: Date) -> String { DayKey.esLong(d, .dateTime.weekday(.wide).day().month(.wide)) }

func relativeDays(_ n: Int) -> String {
    switch n {
    case 0: "hoy"
    case 1: "mañana"
    case -1: "ayer"
    case let x where x > 0: "en \(x) días"
    default: "hace \(-n) días"
    }
}

struct Tile: View {
    let title: String
    let value: String
    var note: String? = nil
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint ?? .primary).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Card<Content: View>: View {
    let title: String
    var icon: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon ?? "circle").labelStyle(.titleAndIcon).font(.headline)
                Spacer()
                if let actionTitle, let action {
                    Button(action: action) { Text(actionTitle) + Text(" ›") }.buttonStyle(.link).font(.callout)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}

struct Ring<Content: View>: View {
    var progress: Double
    var color: Color = Brand.accent
    var line: CGFloat = 12
    var size: CGFloat = 112
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: size, height: size)
        .padding(line / 2)
    }
}

func capitalizedFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

struct TaskRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Button { store.setTask(task, done: !task.done) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(.plain).accessibilityLabel(task.done ? "Marcar como pendiente" : "Marcar como hecha").foregroundStyle(task.done ? Color.green : Color.accentColor)
            if task.priority > 0 && !task.done { Image(systemName: "flag.fill").font(.caption).foregroundStyle(task.priority == 3 ? Brand.bad : task.priority == 2 ? Brand.warn : Color.blue).help(["", "Prioridad baja", "Prioridad media", "Prioridad alta"][task.priority]).accessibilityLabel(["", "Prioridad baja", "Prioridad media", "Prioridad alta"][task.priority]) }
            Text(MDParser.inline(task.text)).strikethrough(task.done).foregroundStyle(task.done ? .secondary : .primary).lineLimit(2)
            if let r = task.recurrence { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary).help(Recurrence.describe(r)).accessibilityLabel(Recurrence.describe(r)) }
            Spacer(minLength: 8)
            if let due = task.due {
                let n = DayKey.days(from: DayKey.today(), to: due)
                Text(n < 0 && !task.done ? "vencida \(shortDate(due))" : shortDate(due))
                    .font(.caption).foregroundStyle(n < 0 && !task.done ? Color.red : .secondary)
            }
            Button(task.noteName) { store.pendingNote = task.file }
                .buttonStyle(.link).font(.caption)
            if !task.done {
                Menu {
                    Button("Hoy") { store.reschedule(task, to: DayKey.today()) }
                    Button("Mañana") { store.reschedule(task, to: DayKey.adding(days: 1, to: DayKey.today())) }
                    Button("En una semana") { store.reschedule(task, to: DayKey.adding(days: 7, to: DayKey.today())) }
                    Button("El lunes") {
                        let wd = DayKey.calendar().component(.weekday, from: DayKey.today())
                        store.reschedule(task, to: DayKey.adding(days: (9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7, to: DayKey.today()))
                    }
                } label: { Image(systemName: "clock.arrow.circlepath").accessibilityLabel("Aplazar") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).help("Aplazar")
            }
            EditButton { editing = true }
        }
        .sheet(isPresented: $editing) { TaskSheet(task: task) }
    }
}

enum Brand {
    static let accent = Color(red: 0.16, green: 0.62, blue: 0.50)
    static let warn = Color.orange
    static let bad = Color(red: 0.88, green: 0.28, blue: 0.25)
}


// MARK: - Edición de filas y tareas

struct RowSpec: Identifiable {
    enum Mode { case edit(line: Int), add(afterLine: Int, headerLine: Int) }
    let id = UUID()
    var file: String
    var mode: Mode
    var title: String = "Fila"
    var prefill: [String]? = nil
}

struct RowSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let spec: RowSpec
    @State private var header: [String] = []
    @State private var cells: [String] = []
    @State private var first = ""
    @State private var confirmDelete = false

    private var isEdit: Bool { if case .edit = spec.mode { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEdit ? "Editar \(spec.title)" : "Añadir a \(spec.title)").font(.title3.weight(.semibold))
            if header.isEmpty {
                Text("No encuentro la tabla. Puede haber cambiado en otro sitio.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(header.indices, id: \.self) { i in
                        GridRow {
                            Text(header[i]).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            TextField("", text: Binding(get: { i < cells.count ? cells[i] : "" }, set: { if i < cells.count { cells[i] = $0 } }))
                                .frame(minWidth: 320)
                        }
                    }
                }
            }
            HStack {
                if isEdit {
                    if confirmDelete {
                        Button("Confirmar eliminar", role: .destructive) { delete() }
                    } else {
                        Button("Eliminar", role: .destructive) { confirmDelete = true }
                    }
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(header.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 520)
        .onAppear(perform: load)
    }

    private func load() {
        switch spec.mode {
        case .edit(let line):
            guard let r = store.rowCells(file: spec.file, line: line) else { return }
            header = r.header; cells = r.cells; first = r.cells.first ?? ""
            while cells.count < header.count { cells.append("") }
        case .add(_, let headerLine):
            header = store.tableHeader(file: spec.file, headerLine: headerLine)
            cells = [String](repeating: "", count: header.count)
            if let p = spec.prefill { for (i, v) in p.enumerated() where i < cells.count { cells[i] = v } }
        }
    }

    private func save() {
        switch spec.mode {
        case .edit(let line): store.updateRow(file: spec.file, line: line, expectFirst: first, cells: cells)
        case .add(let after, _): store.insertRow(file: spec.file, afterLine: after, cells: cells)
        }
        dismiss()
    }

    private func delete() {
        if case .edit(let line) = spec.mode { store.deleteRow(file: spec.file, line: line, expectFirst: first) }
        dismiss()
    }
}

struct TaskSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var text = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var priority = 0
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Editar tarea").font(.title3.weight(.semibold))
            TextField("Texto", text: $text).frame(minWidth: 420)
            Picker("Prioridad", selection: $priority) { Text("Ninguna").tag(0); Text("Baja").tag(1); Text("Media").tag(2); Text("Alta").tag(3) }.pickerStyle(.segmented).frame(width: 360)
            HStack {
                Toggle("Fecha límite", isOn: $hasDue).toggleStyle(.checkbox)
                DatePicker("", selection: $due, displayedComponents: .date).labelsHidden().disabled(!hasDue)
            }
            Text("Está en la nota \(task.noteName).").font(.caption).foregroundStyle(.secondary)
            HStack {
                if confirmDelete { Button("Confirmar eliminar", role: .destructive) { store.deleteTask(task); dismiss() } }
                else { Button("Eliminar", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    store.updateTask(task, text: text, due: hasDue ? DayKey.calendar().startOfDay(for: due) : nil, priority: priority)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .onAppear { text = task.text; hasDue = task.due != nil; due = task.due ?? Date(); priority = task.priority }
    }
}

struct EditButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "pencil").accessibilityLabel("Editar") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Editar")
    }
}

// MARK: - Tablas genéricas editables

/// Muestra las tablas de una nota (opcionalmente solo algunas) con botón de editar por fila y de añadir.
struct NoteTables: View {
    @Environment(Store.self) private var store
    let file: String
    var icon = "tablecells"
    var include: (NamedTable) -> Bool = { _ in true }
    var titleOverride: String? = nil
    @State private var spec: RowSpec?

    var body: some View {
        let tables = Parse.tables(store.read(file)).filter(include)
        VStack(alignment: .leading, spacing: 16) {
            ForEach(tables) { t in
                Card(title: titleOverride ?? (t.title.isEmpty ? "Tabla" : t.title), icon: icon) {
                    let rows = t.rows.filter { r in r.cells.contains { !$0.isEmpty } }
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                            GridRow {
                                ForEach(Array(t.header.enumerated()), id: \.offset) { _, h in Text(h) }
                                Color.clear.frame(width: 18, height: 1)
                            }.font(.caption).foregroundStyle(.secondary)
                            Divider()
                            ForEach(rows) { r in
                                GridRow {
                                    ForEach(0..<t.header.count, id: \.self) { i in Text(MDParser.inline(i < r.cells.count ? r.cells[i] : "")).lineLimit(4).frame(maxWidth: 340, alignment: .leading) }
                                    EditButton { spec = RowSpec(file: file, mode: .edit(line: r.line), title: "fila") }
                                }
                            }
                        }
                    }
                    if rows.isEmpty { Text("Sin filas.").foregroundStyle(.secondary) }
                    Button { spec = RowSpec(file: file, mode: .add(afterLine: t.lastLine, headerLine: t.headerLine), title: t.title.isEmpty ? "tabla" : t.title) } label: {
                        Label("Añadir fila", systemImage: "plus")
                    }.buttonStyle(.borderless).font(.callout)
                }
            }
        }
        .sheet(item: $spec) { RowSheet(spec: $0) }
        .environment(\.openURL, OpenURLAction { url in store.open(link: url) })
    }
}

/// Campo de propiedad (frontmatter) que se guarda al pulsar intro.
struct PropertyField: View {
    @Environment(Store.self) private var store
    let file: String
    let key: String
    var label: String? = nil
    var width: CGFloat? = nil
    @State private var text = ""
    @State private var seen = ""

    private var current: String { MD.frontmatter(store.read(file))[key] ?? "" }

    var body: some View {
        HStack {
            if let label { Text(label).foregroundStyle(.secondary) }
            TextField("", text: $text).frame(width: width)
                .onSubmit { if text != current { store.setProperty(file, key: key, value: text) } }
        }
        .autosave(on: text, delay: 2) { if text != current { store.setProperty(file, key: key, value: text, quiet: true) } }
        .onAppear { text = current; seen = current }
        .onChange(of: store.revision) {
            // Solo se actualiza si no estás escribiendo algo distinto.
            if text == seen { text = current }
            seen = current
        }
    }
}

/// Menú de opciones con texto legible en modo claro y oscuro.
struct ChoiceMenu: View {
    let options: [String]
    let current: String
    var width: CGFloat = 130
    var capitalize = false
    var emptyLabel = "—"
    let set: (String) -> Void

    private func label(_ o: String) -> String { o.isEmpty ? emptyLabel : (capitalize ? o.capitalized : o) }

    var body: some View {
        let opts = options.contains(current) ? options : options + [current]
        Menu {
            ForEach(opts, id: \.self) { o in
                Button { set(o) } label: {
                    if o == current { Label(label(o), systemImage: "checkmark") } else { Text(label(o)) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label(current)).foregroundStyle(Color.primary).lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(width: width)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// Selector que escribe una propiedad (frontmatter) de una nota.
struct PropertyPicker: View {
    @Environment(Store.self) private var store
    let file: String
    let key: String
    let options: [String]
    var width: CGFloat = 130

    var body: some View {
        ChoiceMenu(options: options, current: store.noteMeta[file]?[key] ?? "", width: width, capitalize: true) {
            store.setProperty(file, key: key, value: $0)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "Sistema"; case .light: "Claro"; case .dark: "Oscuro" } }
    var icon: String { switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max"; case .dark: "moon" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

struct AppearancePicker: View {
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    var body: some View {
        Picker("", selection: $appearance) {
            ForEach(Appearance.allCases) { Image(systemName: $0.icon).help($0.title).tag($0.rawValue) }
        }.pickerStyle(.segmented).labelsHidden()
    }
}

/// Lista de puntos `- texto` de una sección, con añadir y quitar.
struct ListCard: View {
    @Environment(Store.self) private var store
    let file: String
    let section: String
    let title: String
    var icon = "list.bullet"
    var placeholder = "Añadir"
    @State private var new = ""

    var body: some View {
        let items = Parse.listItems(store.read(file), section: section)
        Card(title: title, icon: icon) {
            if items.isEmpty { Text("Sin elementos.").foregroundStyle(.secondary) }
            ForEach(items) { it in
                HStack(alignment: .firstTextBaseline) {
                    Text("•").foregroundStyle(.secondary)
                    Text(MDParser.inline(it.text))
                    Spacer()
                    Button { store.edit(file) { Edit.deleteLine($0, raw: it.raw, hint: it.line) } } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Quitar")
                }
            }
            HStack {
                TextField(placeholder, text: $new).onSubmit(add)
                Button("Añadir", action: add).disabled(new.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let t = new.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.edit(file) { Edit.appendToSection($0, section: section, line: "- \(t)") }
        new = ""
    }
}


/// Muestra una línea con sus enlaces [[...]] pulsables, solo si los tiene.
struct LinkPreview: View {
    let text: String
    var body: some View {
        if text.contains("[[") {
            Text(MDParser.inline(text)).font(.callout).foregroundStyle(.secondary)
        }
    }
}


extension View {
    /// Ejecuta `action` cuando `value` lleva `delay` segundos sin cambiar (autoguardado). Se cancela si cambia antes.
    func autosave<V: Equatable>(on value: V, delay: Double = 1.5, _ action: @escaping () -> Void) -> some View {
        task(id: value) {
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled { action() }
        }
    }
}

/// Cinco círculos de 1 (mal) a 5 (genial). Pulsar el mismo valor otra vez lo quita.
struct MoodPicker: View {
    let value: Double?
    let set: (Double?) -> Void
    private let labels = ["Mal", "Regular", "Normal", "Bien", "Genial"]
    private let colors: [Color] = [Brand.bad, Brand.warn, .yellow, .mint, Brand.accent]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { n in
                let on = value.map { Int($0) == n } ?? false
                Button { set(on ? nil : Double(n)) } label: {
                    Text("\(n)").font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? colors[n - 1] : colors[n - 1].opacity(0.18), in: Circle())
                }.buttonStyle(.plain).help(labels[n - 1])
            }
        }
    }
}

/// Campo numérico que guarda su valor a los 1,5 s de dejar de escribir.
struct DiaryNumberField: View {
    @Environment(Store.self) private var store
    let day: Date
    let key: String
    let placeholder: String
    @State private var text = ""
    @State private var seen = ""

    private var current: String { store.diaryValue(day, key).map { MD.formatNumber($0) } ?? "" }

    var body: some View {
        TextField(placeholder, text: $text).frame(width: 60)
            .onAppear { text = current; seen = current }
            .onChange(of: day) { text = current; seen = current }
            .onChange(of: store.revision) { if text == seen { text = current }; seen = current }
            .onSubmit(save)
            .autosave(on: text) { if text != current { save() } }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { store.setDiaryValue(day, key, nil) } else if let v = MD.number(t) { store.setDiaryValue(day, key, v) }
    }
}
