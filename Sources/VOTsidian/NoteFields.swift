import SwiftUI

// MARK: - Tablas genéricas editables

/// Muestra las tablas de una nota (opcionalmente solo algunas) con botón de editar por fila y de añadir.
struct NoteTables: View {
    @Environment(Store.self) private var store
    let file: String
    var icon = "tablecells"
    var include: (NamedTable) -> Bool = { _ in true }
    var titleOverride: String? = nil
    @State private var spec: RowSpec?
    /// Tablas (por su línea de cabecera) en las que se ven todas las filas, no solo las últimas.
    @State private var expanded: Set<Int> = []
    static let rowLimit = 40

    var body: some View {
        let _ = BodyCounter.hit("NoteTables")
        let tables = Parse.tables(store.read(file)).filter(include)
        VStack(alignment: .leading, spacing: 16) {
            ForEach(tables) { t in
                Card(title: titleOverride ?? (t.title.isEmpty ? "Tabla" : t.title), icon: icon) {
                    let all = t.rows.filter { r in r.cells.contains { !$0.isEmpty } }
                    // Las filas nuevas suelen ir al final: por defecto, las últimas.
                    let rows = expanded.contains(t.id) ? all : Array(all.suffix(Self.rowLimit))
                    Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                        GridRow {
                            ForEach(Array(t.header.enumerated()), id: \.offset) { _, h in Text(h) }
                            Color.clear.frame(width: 18, height: 1)
                        }.font(.caption).foregroundStyle(.secondary)
                        Divider()
                        ForEach(rows) { r in
                            GridRow {
                                // Sin scroll horizontal: dentro de uno la altura se medía con el texto en una línea y, al partirse,
                                // la segunda se cortaba. La última columna (resultado, notas…) suele ser la larga y tiene más sitio.
                                ForEach(0..<t.header.count, id: \.self) { i in
                                    let cell = i < r.cells.count ? r.cells[i] : ""
                                    Text(MDParser.inline(cell)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: i == t.header.count - 1 ? 520 : 340, alignment: .leading).help(cell)
                                }
                                EditButton { spec = RowSpec(file: file, mode: .edit(line: r.line), title: "fila") }
                            }
                        }
                    }
                    if rows.isEmpty { EmptyNote("Sin filas.") }
                    ShowAllButton(total: all.count, limit: Self.rowLimit, showAll: Binding(get: { expanded.contains(t.id) }, set: { if $0 { expanded.insert(t.id) } else { expanded.remove(t.id) } }))
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

/// Propiedad de fecha (`AAAA-MM-DD`) con selector en vez de texto libre. La cruz la deja vacía.
struct PropertyDateField: View {
    @Environment(Store.self) private var store
    let file: String
    let key: String

    private var current: Date? { store.noteMeta[file]?[key].flatMap(DayKey.date) }

    var body: some View {
        let _ = BodyCounter.hit("PropertyDateField")
        HStack(spacing: 4) {
            if let d = current {
                // Cada clic del selector guarda en silencio: los cambios seguidos se deshacen de una vez.
                DatePicker("", selection: Binding(get: { d }, set: { store.setProperty(file, key: key, value: DayKey.string($0), quiet: true) }),
                           displayedComponents: .date).labelsHidden().fixedSize()
                Button { store.setProperty(file, key: key, value: "") } label: { Image(systemName: "xmark.circle.fill").accessibilityLabel("Quitar fecha") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary).help("Quitar fecha")
            } else {
                Button("Poner fecha") { store.setProperty(file, key: key, value: DayKey.string(DayKey.today())) }.controlSize(.small)
            }
        }
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
        let _ = BodyCounter.hit("PropertyField")
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
            .background(Color.primary.opacity(0.07), in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
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
            if items.isEmpty { EmptyNote("Sin elementos.") }
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
                Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(new.trimmingCharacters(in: .whitespaces).isEmpty)
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
    /// Si la vista desaparece (cambias de pantalla) o la app se cierra antes de que pase el plazo, se guarda igualmente (`PendingSaves`).
    func autosave<V: Equatable>(on value: V, delay: Double = 1.5, _ action: @escaping () -> Void) -> some View {
        modifier(Autosave(value: value, delay: delay, action: action))
    }
}

private struct Autosave<V: Equatable>: ViewModifier {
    let value: V
    let delay: Double
    let action: () -> Void
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { PendingSaves.actions[id] = action }
            .task(id: value) {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                PendingSaves.actions[id] = nil
                action()
            }
            .onDisappear { PendingSaves.actions.removeValue(forKey: id)?() }
    }
}

/// Autoguardados que aún esperan su plazo. Al cerrar la app se ejecutan todos, para no perder lo último que se escribió.
@MainActor
enum PendingSaves {
    static var actions: [UUID: () -> Void] = [:]

    static func flush() {
        let pending = actions
        actions = [:]
        for action in pending.values { action() }
    }
}
